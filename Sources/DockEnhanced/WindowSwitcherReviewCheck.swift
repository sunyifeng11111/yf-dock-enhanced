#if DEBUG
import AppKit
import DockCore

/// Review regressions at the agreed native event/window boundaries. Display
/// usable-frame observations are injected; no real display setting is changed.
final class WindowSwitcherReviewCheck: NSObject, NSApplicationDelegate {
    private let urls: [URL]
    private let service = DockService(captureAccess: { false })
    private let directory = FileManager.default.temporaryDirectory.appendingPathComponent("dock-review-" + UUID().uuidString)
    init(urls: [URL]) { self.urls = urls }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let priorPointer = NSEvent.mouseLocation
            let prior = NSWorkspace.shared.frontmostApplication
            let priorWindow = prior.flatMap { service.controller.focusedWindow(of: $0, in: service.controller.windows(of: $0)) }
            var apps: [NSRunningApplication] = []
            var result: Int32 = 0
            do {
                guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { print("UNAVAILABLE: existing Accessibility/event posting required"); exit(2) }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for (index, url) in urls.enumerated() {
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = ["--fixture", "--fixture-state", directory.appendingPathComponent("\(index).json").path]
                    config.createsNewApplicationInstance = true
                    apps.append(try await NSWorkspace.shared.openApplication(at: url, configuration: config))
                }
                await pause(0.8)
                let sourceWindows = service.controller.windows(of: apps[0])
                try require(sourceWindows.count == 2, "source fixture supplies two real windows")
                let source = sourceWindows[0]
                _ = service.controller.reveal(source, app: apps[0]); await pause(0.4)
                try await checkEmpty(source: source, app: apps[0])
                try await checkGeometry(apps: apps, source: source)
                try await checkRegistry(app: apps[1])
                print("PASS: review regressions complete")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            service.stop()
            for app in apps {
                for window in service.controller.windows(of: app) where window.state.fullScreen { _ = AX.set(window.element, "AXFullScreen", false) }
            }
            await pause(0.8)
            for app in apps { app.terminate() }
            CGWarpMouseCursorPosition(quartzPoint(priorPointer))
            if let prior, let priorWindow { _ = service.controller.reveal(priorWindow, app: prior) }
            else { prior?.activate(options: []) }
            await pause(0.3)
            try? FileManager.default.removeItem(at: directory)
            exit(result)
        }
    }

    @MainActor private func checkEmpty(source: AppWindow, app: NSRunningApplication) async throws {
        service.switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { _ in false })
        service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
        await pause(0.3)
        try require(service.switcherAvailable && service.switcher.candidates.isEmpty, "healthy native adapter has an empty eligible inventory")
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: down)!
            event.flags = .maskCommand
            try require(service.handle(type: down ? .keyDown : .keyUp, event: event) == nil,
                        "empty healthy enhancement consumes Tab \(down ? "press" : "release")")
        }
        await pause(0.2)
        try require(!service.switcher.isSelecting && !service.switcher.panel.panel.isVisible && service.controller.isFocused(source, app: app),
                    "empty enhancement leaves exact source focused without an empty panel")
        service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false)
        let native = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        native.flags = .maskCommand
        try require(service.handle(type: .keyDown, event: native) != nil, "unavailable enhancement still passes native Command+Tab through")
    }

    @MainActor private func checkGeometry(apps: [NSRunningApplication], source: AppWindow) async throws {
        service.stop()
        let pids = Set(apps.map(\.processIdentifier))
        var available = CGRect(x: 40, y: 80, width: 1000, height: 700)
        var hostNumbers = Set<NSNumber>()
        let switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { pids.contains($0.processIdentifier) }, screenVisibleFrame: { screen in
            if let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber { hostNumbers.insert(number) }
            return available
        })
        defer { switcher.stop() }
        switcher.refreshCandidates(); await pause(0.5)
        let tab = CGEvent(keyboardEventSource: nil, virtualKey: 48, keyDown: true)!
        tab.flags = .maskCommand
        _ = switcher.handle(type: .keyDown, event: tab)
        await pause(0.2)
        for _ in 0..<2 { _ = switcher.handle(type: .keyDown, event: tab) }
        try require(switcher.workflow.snapshot != nil, "native geometry gesture starts a selection")
        let snapshot = switcher.workflow.snapshot!
        let panel = switcher.panel.panel
        try require(panel.isVisible && switcher.panel.columns == 3 && available.contains(panel.frame), "initial native chooser uses the supplied usable display geometry")
        available = CGRect(x: 100, y: 120, width: 600, height: 300)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
        await pause(0.05)
        try require(switcher.panel.columns == 2 && available.contains(panel.frame) && abs(panel.frame.midX - 400) < 1 && abs(panel.frame.midY - 270) < 1,
                    "same connected display configuration change recenters and bounds the panel with a new grid")
        try require(switcher.workflow.snapshot?.windows == snapshot.windows && switcher.workflow.snapshot?.selected == snapshot.selected && hostNumbers.count == 1 && service.controller.isFocused(source, app: apps[0]),
                    "display relayout preserves host display, frozen candidates, selected identity and exact source focus")
        let views = descendants(panel.contentView!)
        let scrolling = views.compactMap { $0 as? NSScrollView }.first!
        let selected = views.first { $0.accessibilityValue() as? String == "已选中" }!
        try require(scrolling.documentView!.frame.height > scrolling.contentView.bounds.height && scrolling.documentVisibleRect.contains(selected.convert(selected.bounds, to: scrolling.documentView)),
                    "reflowed native grid keeps the selected card scrolled into view")
    }

    @MainActor private func checkRegistry(app: NSRunningApplication) async throws {
        let initial = service.controller.windows(of: app)
        let registry = WindowIdentityRegistry.shared
        try require(initial.count == 2, "registry fixture supplies two stable real windows")
        let baseline = registry.knownElements(for: app.processIdentifier).count
        let duringTimeout: [AppWindow] = {
            kill(app.processIdentifier, SIGSTOP)
            defer { kill(app.processIdentifier, SIGCONT) }
            return service.controller.windows(of: app)
        }()
        try require(duringTimeout.isEmpty && registry.knownElements(for: app.processIdentifier).count == baseline,
                    "transient owner timeout preserves known exact window identities")
        var retired = Set<WindowKey>()
        for cycle in 0..<8 {
            try "new".write(to: directory.appendingPathComponent("1.json.command"), atomically: true, encoding: .utf8)
            await pause(0.25)
            let windows = service.controller.windows(of: app)
            guard let added = windows.first(where: { window in !initial.contains { $0.key == window.key } }) else {
                throw NSError(domain: "SwitcherReviewCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "fixture did not create a new window"])
            }
            try require(!retired.contains(added.key), "create/close cycle \(cycle + 1) allocates a fresh identity")
            retired.insert(added.key)
            let close: AXUIElement = AX.value(added.element, kAXCloseButtonAttribute)!
            _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
            await pause(0.2)
            let survivors = service.controller.windows(of: app)
            try require(survivors.count == initial.count && registry.knownElements(for: app.processIdentifier).count == baseline,
                        "create/close cycle \(cycle + 1) prunes the closed AX handle and returns inventory work to baseline")
        }
        print("EVIDENCE: 8 create/close cycles; retained baseline=\(baseline), final=\(registry.knownElements(for: app.processIdentifier).count), retired unique IDs=\(retired.count)")
        let ordinary = initial[0], fullScreen = initial[1]
        _ = service.controller.reveal(fullScreen, app: app); await pause(0.4)
        try require(AX.set(fullScreen.element, "AXFullScreen", true), "controlled registry fixture enters full screen")
        await pause(2)
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        var reported: CFTypeRef?
        let query = AXUIElementCopyAttributeValue(owner, kAXWindowsAttribute as CFString, &reported)
        let raw = reported as? [AXUIElement]
        try require(query == .success && raw != nil && !raw!.contains { CFEqual($0, ordinary.element) }, "successful full-screen AXWindows query omits the known ordinary window")
        let retained = service.controller.windows(of: app)
        try require(retained.contains { $0.key == ordinary.key } && retained.contains { $0.key == fullScreen.key && $0.state.fullScreen },
                    "full-screen omission keeps both valid exact identities discoverable after pruning")
        _ = AX.set(fullScreen.element, "AXFullScreen", false); await pause(1.8)
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }

    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func require(_ condition: Bool, _ text: String) throws {
        guard condition else { throw NSError(domain: "SwitcherReviewCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        print("PASS: \(text)"); fflush(stdout)
    }
}
#endif
