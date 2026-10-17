#if DEBUG
import AppKit
import DockCore

/// Exercises minimize -> actual Command+Tab restoration -> next chooser against
/// disposable native app windows, including real ScreenCaptureKit delivery.
final class WindowSwitcherThumbnailRecoveryCheck: NSObject, NSApplicationDelegate {
    private let urls: [URL]
    private let service = DockService()
    init(urls: [URL]) { self.urls = urls }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let previous = NSWorkspace.shared.frontmostApplication
            let previousWindow = previous.flatMap { service.controller.focusedWindow(of: $0, in: service.controller.windows(of: $0)) }
            let pointer = NSEvent.mouseLocation
            var apps: [NSRunningApplication] = []
            var result: Int32 = 0
            do {
                guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess(), CGPreflightPostEventAccess() else {
                    print("UNAVAILABLE: existing Accessibility, screen capture and event posting access required"); exit(2)
                }
                for url in urls {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.arguments = ["--fixture"]
                    configuration.createsNewApplicationInstance = true
                    apps.append(try await NSWorkspace.shared.openApplication(at: url, configuration: configuration))
                }
                await pause(0.7)
                let singleWindow = CommandLine.arguments.contains("--single-window")
                if singleWindow {
                    for app in apps {
                        for window in service.controller.windows(of: app).dropFirst() {
                            if let close: AXUIElement = AX.value(window.element, kAXCloseButtonAttribute) { _ = AXUIElementPerformAction(close, kAXPressAction as CFString) }
                        }
                    }
                    await pause(0.3)
                }
                let pids = Set(apps.map(\.processIdentifier))
                let delivery = service.switcher.onCandidatesChanged
                service.switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { pids.contains($0.processIdentifier) })
                service.switcher.onCandidatesChanged = delivery
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
                try require(service.switcherAvailable, "native shortcut interception is available")
                let original = apps.flatMap { app in service.controller.windows(of: app).map { SwitcherCandidate(window: $0, app: app) } }
                try require(original.count == apps.count * (singleWindow ? 1 : 2), "disposable applications expose the expected real windows")
                for _ in 0..<30 {
                    if original.allSatisfy({ service.images.cache[$0.window.key] != nil }) { break }
                    service.images.refresh(original.map(\.window))
                    await pause(0.1)
                }
                try require(original.allSatisfy { service.images.cache[$0.window.key] != nil }, "all windows have real thumbnails before minimizing")
                try await checkUnavailableOwner(apps[0], expected: original)
                let cycles = CommandLine.arguments.contains("--stress") ? 10 : 1
                for cycle in 1...cycles {
                    for _ in 0..<10 {
                        let visible = apps.flatMap { service.controller.windows(of: $0) }.filter { !$0.state.minimized }
                        if visible.isEmpty { break }
                        for window in visible {
                            _ = AX.set(window.element, kAXMinimizedAttribute, true)
                            await pause(0.35)
                        }
                    }
                    await pause(0.9)
                    service.switcher.refreshCandidates()
                    await pause(0.2)
                    try require(service.switcher.candidates.count == original.count && service.switcher.candidates.allSatisfy { $0.window.state.minimized }, "cycle \(cycle): all fixture windows are minimized and discoverable")
                    for (index, target) in original.enumerated() {
                        try await openChooser()
                        try verifyImages(original, context: "cycle \(cycle), before restore \(index + 1)")
                        for _ in 0..<original.count {
                            if service.switcher.workflow.snapshot?.selected == target.id { break }
                            key(48); await pause(0.02)
                        }
                        try require(service.switcher.workflow.snapshot?.selected == target.id, "select exact minimized window \(index + 1)")
                        command(false)
                        for _ in 0..<100 {
                            if service.controller.isFocused(target.window, app: target.app) { break }
                            await pause(0.02)
                        }
                        try require(service.controller.isFocused(target.window, app: target.app), "window \(index + 1) restored and focused")
                        // Reopen promptly as well as after the next inventory/capture.
                        try await openChooser()
                        try verifyImages(original, context: "cycle \(cycle), immediately after restore \(index + 1)")
                        await pause(1)
                        try verifyImages(original, context: "cycle \(cycle), settled after restore \(index + 1)")
                        key(53); command(false); await pause(0.1)
                    }
                }
                let closed = original[0]
                if let close: AXUIElement = AX.value(closed.window.element, kAXCloseButtonAttribute) {
                    _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
                }
                await pause(1)
                service.switcher.refreshCandidates(); await pause(0.3)
                try require(!service.switcher.candidates.contains { $0.id == closed.id }, "a genuinely closed window is still removed")
                apps.last?.terminate()
                await pause(0.8)
                service.switcher.refreshCandidates(); await pause(0.3)
                try require(!service.switcher.candidates.contains { $0.id.pid == apps.last?.processIdentifier }, "a terminated application is still removed")
                print("PASS: \(cycles) cycles preserve all \(original.count) native thumbnails across minimize/restore and the next Command+Tab")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            command(false)
            service.stop()
            for app in apps { app.terminate() }
            CGWarpMouseCursorPosition(quartzPoint(pointer))
            if let previous, let previousWindow { _ = service.controller.reveal(previousWindow, app: previous) }
            else { previous?.activate(options: []) }
            await pause(0.3)
            fflush(stdout); exit(result)
        }
    }

    @MainActor private func checkUnavailableOwner(_ app: NSRunningApplication, expected: [SwitcherCandidate]) async throws {
        guard app.bundleIdentifier?.hasPrefix("dev.yifeng.DockEnhancedSwitcherFixture") == true else { throw failure("only controlled fixtures may be suspended") }
        let baseline = service.controller.windows(of: app)
        kill(app.processIdentifier, SIGSTOP)
        defer { kill(app.processIdentifier, SIGCONT) }
        let retained = service.controller.windows(of: app, retaining: baseline)
        try require(Set(retained.map(\.key)) == Set(baseline.map(\.key)), "a temporary AX timeout preserves the last exact window identities")
        service.switcher.refreshCandidates(); await pause(0.3)
        try await openChooser()
        try verifyImages(expected, context: "temporarily unavailable owner")
        key(53); command(false); await pause(0.1)
    }

    @MainActor private func openChooser() async throws {
        command(true); key(48); await pause(0.24)
        try require(service.switcher.isSelecting && service.switcher.panel.panel.isVisible, "actual Command+Tab opens the chooser")
    }
    private func verifyImages(_ expected: [SwitcherCandidate], context: String) throws {
        let ids = Set(service.switcher.panel.windowIDs)
        for (index, candidate) in expected.enumerated() {
            try require(ids.contains(candidate.id), "\(context): card \(index + 1) is present")
            guard let image = service.images.cache[candidate.window.key] else { throw failure("\(context): cached thumbnail \(index + 1) disappeared") }
            try require(contains(image, in: service.switcher.panel.panel.contentView), "\(context): thumbnail \(index + 1) is displayed")
        }
    }
    private func contains(_ image: NSImage, in view: NSView?) -> Bool {
        guard let view else { return false }
        return (view as? NSImageView)?.image === image || view.subviews.contains { contains(image, in: $0) }
    }
    private func command(_ down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: down)!
        event.type = .flagsChanged; event.flags = down ? .maskCommand : []; event.post(tap: .cghidEventTap)
    }
    private func key(_ code: CGKeyCode) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = .maskCommand; event.post(tap: .cghidEventTap)
        }
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func failure(_ text: String) -> NSError { NSError(domain: "ThumbnailRecoveryCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func require(_ value: Bool, _ message: String) throws {
        guard value else { throw failure(message) }
        print("PASS: \(message)"); fflush(stdout)
    }
}
#endif
