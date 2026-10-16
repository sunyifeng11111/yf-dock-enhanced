#if DEBUG
import AppKit
import DockCore

/// Uses real AX windows and posted OS input. Filtering the application inventory
/// confines screenshots to controlled fixtures, rather than recording user data.
final class WindowSwitcherInteractionCheck: NSObject, NSApplicationDelegate {
    private let service = DockService()
    private let urls: [URL]
    init(urls: [URL]) { self.urls = urls }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let previousApp = NSWorkspace.shared.frontmostApplication
            let previousWindow = previousApp.flatMap { service.controller.focusedWindow(of: $0, in: service.controller.windows(of: $0)) }
            let previousPointer = NSEvent.mouseLocation
            var fixtures: [NSRunningApplication] = []
            var result: Int32 = 0
            do {
                guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
                    print("UNAVAILABLE: Accessibility/event posting required; no permissions changed")
                    exit(2)
                }
                for url in urls {
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = ["--interaction-fixture"]
                    config.createsNewApplicationInstance = true
                    fixtures.append(try await NSWorkspace.shared.openApplication(at: url, configuration: config))
                }
                await pause(1)
                let pids = Set(fixtures.map(\.processIdentifier))
                service.switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { pids.contains($0.processIdentifier) })
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
                try require(service.switcherAvailable, "real active keyboard hook is available")
                let a = service.controller.windows(of: fixtures[0])
                let b = service.controller.windows(of: fixtures[1])
                try require(a.count == 20 && b.count == 20, "40 controlled native windows are enumerated")
                let source = a[0], previous = b[0]
                _ = service.controller.reveal(previous, app: fixtures[1])
                await pause(0.5)
                await refresh()
                _ = service.controller.reveal(source, app: fixtures[0])
                await pause(0.5)
                await refresh()
                command(true); tab(); command(false)
                await pause(0.6)
                try require(!service.switcher.panel.panel.isVisible && service.controller.isFocused(previous, app: fixtures[1]), "quick Command+Tab returns to actual previous exact window without panel")
                command(true); tab(); command(false)
                await pause(0.6)
                try require(service.controller.isFocused(source, app: fixtures[0]), "actual focus observation enables two-window quick return")
                await refresh()
                let started = ProcessInfo.processInfo.systemUptime
                command(true); tab()
                await pause(0.06)
                try require(!service.switcher.panel.panel.isVisible && service.controller.isFocused(source, app: fixtures[0]), "panel stays hidden and source stays focused at 60ms")
                while !service.switcher.panel.panel.isVisible && ProcessInfo.processInfo.systemUptime - started < 1 { await pause(0.005) }
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                try require(service.switcher.panel.panel.isVisible && elapsed >= 0.115 && elapsed < 0.5, "held gesture presents the panel after the 120ms target")
                print("MEASURED: native panel visible after \(Int(elapsed * 1000))ms (5ms observation resolution)")
                try require(service.controller.isFocused(source, app: fixtures[0]), "displaying the nonactivating panel preserves exact source focus")
                let selected = service.switcher.workflow.snapshot!.selected
                await pause(0.15)
                try require(service.switcher.workflow.snapshot?.selected == selected, "stationary pointer does not change initial keyboard selection")
                let panel = service.switcher.panel.panel
                try require(abs(panel.frame.midX - NSScreen.main!.visibleFrame.midX) < 2, "panel centered on current work-window display")
                let scrolling = descendants(panel.contentView!).compactMap { $0 as? NSScrollView }.first!
                try require(scrolling.hasVerticalScroller && scrolling.documentView!.frame.height > scrolling.contentView.bounds.height, "many windows form multiple rows with vertical overflow")
                for _ in 0..<35 { tab(); await pause(0.006) }
                let selectedCard = descendants(panel.contentView!).first { $0.accessibilityValue() as? String == "已选中" }!
                let frame = selectedCard.convert(selectedCard.bounds, to: scrolling.documentView)
                try require(scrolling.documentVisibleRect.contains(frame), "keyboard selection automatically scrolls the actual card into view")
                let afterScroll = service.switcher.workflow.snapshot!.selected
                await pause(0.08)
                try require(service.switcher.workflow.snapshot?.selected == afterScroll, "keyboard scrolling beneath a stationary pointer does not steal selection")
                let beforeArrow = service.switcher.workflow.snapshot!.selected
                key(126); await pause(0.04)
                try require(service.switcher.workflow.snapshot?.selected != beforeArrow, "real Up arrow moves selection geometrically in the grid")
                await pause(0.15)
                if !CommandLine.arguments.contains("--skip-compositor-capture") { try capture(panel: panel) }
                let enterTarget = service.switcher.workflow.snapshot!.selected
                key(36); command(false); await pause(0.6)
                try require(focused(enterTarget, fixtures), "Enter confirms the selected exact window and later Command release does not repeat")

                command(true); tab(); await pause(0.2)
                let clickScroll = descendants(panel.contentView!).compactMap { $0 as? NSScrollView }.first!
                guard let clickCard = descendants(panel.contentView!).first(where: { view in
                    view.isAccessibilityElement() && view.accessibilityRole() == .button && view.accessibilityValue() as? String != "已选中" && clickScroll.documentVisibleRect.contains(view.convert(view.bounds, to: clickScroll.documentView))
                }) else { throw NSError(domain: "SwitcherInteractionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "no visible card available for actual pointer selection"]) }
                let point = panel.convertPoint(toScreen: clickCard.convert(CGPoint(x: clickCard.bounds.midX, y: clickCard.bounds.midY), to: nil))
                let oldTarget = service.switcher.workflow.snapshot!.selected
                move(point); await pause(0.05)
                let clickTarget = service.switcher.workflow.snapshot!.selected
                try require(clickTarget != oldTarget, "real pointer movement selects another visible card")
                click(point); command(false); await pause(0.6)
                try require(focused(clickTarget, fixtures), "real mouse click confirms the exact selected card")
                command(true); tab(); await pause(0.2)
                let outside = CGPoint(x: panel.frame.minX - 20, y: panel.frame.midY)
                click(outside); command(false); await pause(0.2)
                try require(!service.switcher.isSelecting && !panel.isVisible, "outside click cancels the active chooser")
                print("PASS: native timing, MRU, grid, Enter, pointer click and outside cancellation")
                if NSScreen.screens.count < 2 { print("UNAVAILABLE: second-display placement/removal and scaling require a second display") }
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            command(false)
            service.stop()
            for fixture in fixtures { fixture.terminate() }
            move(previousPointer)
            if let previousWindow, let previousApp { _ = service.controller.reveal(previousWindow, app: previousApp) }
            else { previousApp?.activate(options: []) }
            await pause(0.4)
            exit(result)
        }
    }
    @MainActor private func refresh() async { service.switcher.refreshCandidates(); await pause(1) }
    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    private func focused(_ id: SwitcherWindowID, _ apps: [NSRunningApplication]) -> Bool {
        guard let app = apps.first(where: { $0.processIdentifier == id.pid }), let window = service.controller.windows(of: app).first(where: { $0.key.switcherID == id }) else { return false }
        return service.controller.isFocused(window, app: app)
    }
    private func capture(panel: NSPanel) throws {
        guard CGPreflightScreenCaptureAccess() else { print("UNAVAILABLE: composed panel screenshot requires Screen Recording permission"); return }
        let rect = CGRect(x: panel.frame.minX - 8, y: (NSScreen.screens.first?.frame.maxY ?? 0) - panel.frame.maxY - 8, width: panel.frame.width + 16, height: panel.frame.height + 16)
        guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]) else { print("UNAVAILABLE: compositor did not supply panel image"); return }
        let bitmap = NSBitmapImageRep(cgImage: image)
        let path = "/tmp/dock-switcher-03-composed.png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
        print("SCREENSHOT: \(path)")
    }
    private func command(_ down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: down)!
        event.type = .flagsChanged; event.flags = down ? .maskCommand : []; event.post(tap: .cghidEventTap)
    }
    private func tab() { key(48) }
    private func key(_ code: CGKeyCode) {
        for down in [true, false] { let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!; event.flags = .maskCommand; event.post(tap: .cghidEventTap) }
    }
    private func move(_ point: CGPoint) { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: quartzPoint(point), mouseButton: .left)?.post(tap: .cghidEventTap) }
    private func click(_ point: CGPoint) {
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] { let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartzPoint(point), mouseButton: .left)!; event.flags = .maskCommand; event.post(tap: .cghidEventTap) }
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func require(_ value: Bool, _ text: String) throws {
        guard value else { throw NSError(domain: "SwitcherInteractionCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        print("PASS: \(text)"); fflush(stdout)
    }
}

final class SwitcherInteractionFixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        for index in 0..<20 {
            let rect = index == 0 ? CGRect(x: 120, y: 160, width: 260, height: 500) : index == 1 ? CGRect(x: 180, y: 200, width: 720, height: 320) : NSScreen.main!.visibleFrame
            let window = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = index == 0 ? "Controlled portrait window with a deliberately long title for truncation" : "Controlled window \(index + 1)"
            let content = NSView(frame: window.contentView!.bounds)
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor(calibratedRed: CGFloat(index % 3) * 0.12 + 0.18, green: 0.26, blue: 0.34, alpha: 1).cgColor
            let label = NSTextField(labelWithString: "Controlled switcher fixture · \(index + 1)")
            label.font = .systemFont(ofSize: 36, weight: .medium)
            label.textColor = .white
            label.frame = CGRect(x: 60, y: 80, width: 900, height: 60)
            content.addSubview(label)
            window.contentView = content
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
