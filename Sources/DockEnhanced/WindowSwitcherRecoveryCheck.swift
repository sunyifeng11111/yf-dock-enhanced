#if DEBUG
import AppKit
import DockCore
import Carbon

/// Native workflow checks. Only modifier/capability observations are injected at
/// OS boundaries; selection, event routing, AX windows and focus remain real.
final class WindowSwitcherRecoveryCheck: NSObject, NSApplicationDelegate {
    private let urls: [URL]
    private var controlAccess = true
    private lazy var service = DockService(captureAccess: { false }, accessibilityAccess: { [weak self] in self?.controlAccess == true && AXIsProcessTrusted() })
    private let stateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("dock-recovery-" + UUID().uuidString)
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
                guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else { print("UNAVAILABLE: recovery requires existing Accessibility/event-posting access"); exit(2) }
                try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
                for (index, url) in urls.enumerated() {
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = ["--fixture", "--fixture-state", stateDirectory.appendingPathComponent("\(index).json").path]
                    config.createsNewApplicationInstance = true
                    apps.append(try await NSWorkspace.shared.openApplication(at: url, configuration: config))
                }
                await pause(1)
                let pids = Set(apps.map(\.processIdentifier))
                service.switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { pids.contains($0.processIdentifier) })
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
                let source = service.controller.windows(of: apps[0])[0]
                let target = service.controller.windows(of: apps[1])[0]
                _ = service.controller.reveal(source, app: apps[0])
                await pause(0.5)
                await refresh()
                try await select(target.key.switcherID)
                let missingTime = ProcessInfo.processInfo.systemUptime
                service.switcher.checkCommandState(commandIsDown: false, time: missingTime)
                try require(service.switcher.isSelecting, "a single missing modifier observation allows its queued release event to arrive")
                service.switcher.checkCommandState(commandIsDown: false, time: missingTime + 0.11)
                await pause(0.2)
                try require(!service.switcher.isSelecting && !service.switcher.panel.panel.isVisible && service.controller.isFocused(source, app: apps[0]),
                            "lost Command release cancels without confirming or leaving a panel")
                command(false)
                await pause(0.2)
                try await select(target.key.switcherID)
                command(false)
                await pause(0.7)
                try require(service.controller.isFocused(target, app: apps[1]), "fresh complete gesture works after lost-release cancellation")
                // Both system-disable notifications invalidate the old session.
                for fault in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
                    try await select(source.key.switcherID)
                    _ = service.handle(type: fault, event: CGEvent(source: nil)!)
                    command(false)
                    await pause(0.3)
                    try require(!service.switcher.isSelecting && service.controller.isFocused(target, app: apps[1]), "tap interruption cancels without activating its selected target")
                    try require(service.switcherAvailable, "keyboard capability is revalidated after tap recovery")
                }
                try await select(source.key.switcherID)
                controlAccess = false
                service.refreshSwitcherCapability()
                command(false)
                try require(!service.switcherAvailable && !service.switcher.isSelecting && service.switcherUnavailableReason.contains("辅助功能"), "injected control-access loss cancels with an accurate unavailable reason")
                await pause(0.2)
                controlAccess = true
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
                await refresh()
                try await select(source.key.switcherID)
                command(false); await pause(0.6)
                try require(service.controller.isFocused(source, app: apps[0]), "fresh shortcut recovers after injected control access returns")

                try await select(target.key.switcherID)
                try fixtureCommand("secure-on", index: 1)
                await pause(0.4)
                command(false)
                try require(IsSecureEventInputEnabled() && !service.switcherAvailable && !service.switcher.isSelecting, "real secure input owned by a controlled fixture cancels the session")
                command(true); key(48); command(false); await pause(0.5)
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == apps[1].processIdentifier && !service.switcher.isSelecting, "native Command+Tab remains active during real secure input")
                try fixtureCommand("secure-off", index: 1)
                await pause(0.4)
                try require(!IsSecureEventInputEnabled() && service.switcherAvailable, "secure-input exit restores enhancement for a fresh gesture")
                _ = service.controller.reveal(source, app: apps[0]); await pause(0.5); await refresh()
                for confirmation in ["release", "enter", "mouse"] {
                    _ = service.controller.reveal(source, app: apps[0]); await pause(0.4)
                    _ = AX.set(target.element, kAXMinimizedAttribute, true); await pause(0.5); await refresh()
                    try await select(target.key.switcherID)
                    confirm(confirmation)
                    await pause(0.8)
                    command(false)
                    try require(service.controller.isFocused(target, app: apps[1]), "\(confirmation) confirmation restores the exact minimized target without canceling itself")
                    _ = service.controller.reveal(source, app: apps[0]); await pause(0.4)
                    _ = AX.set(target.element, kAXMinimizedAttribute, true); await pause(0.5); await refresh()
                    try await select(target.key.switcherID)
                    confirm(confirmation)
                    // A new unrelated key is a later intent, not part of confirm.
                    let activity = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: true)!
                    activity.flags = []; activity.post(tap: .cghidEventTap)
                    command(false)
                    await pause(2.4)
                    try require(service.controller.isFocused(source, app: apps[0]) && !service.switcher.failureNotice.panel.isVisible, "new activity after \(confirmation) invalidates deferred restore and stale feedback")
                }
                try await checkSlowEnumeration(app: apps[1], source: source, sourceApp: apps[0])
                await refresh()
                try await select(target.key.switcherID)
                let frozen = service.switcher.workflow.snapshot!.windows
                try fixtureCommand("new", index: 1)
                await refresh()
                let added = Set(service.switcher.candidates.map(\.id)).subtracting(frozen)
                try require(added.count == 1 && service.switcher.workflow.snapshot?.windows == frozen, "real newly created window is deferred while the existing session order stays frozen")
                let close: AXUIElement = AX.value(target.element, kAXCloseButtonAttribute)!
                _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
                await refresh()
                try require(service.switcher.workflow.snapshot?.windows == frozen.filter { $0 != target.key.switcherID } && service.switcher.workflow.snapshot?.selected != target.key.switcherID, "closing the selected native window removes it and advances without reordering survivors")
                key(53); command(false); await pause(0.2)
                command(true); key(48); await pause(0.2)
                try require(added.isSubset(of: Set(service.switcher.workflow.snapshot?.windows ?? [])), "the next real selection includes the newly created window")
                key(53); command(false); await pause(0.2)

                let stale = service.switcher.candidates.first { $0.id.pid == apps[1].processIdentifier }!
                try await select(stale.id)
                let staleClose: AXUIElement = AX.value(stale.window.element, kAXCloseButtonAttribute)!
                _ = AXUIElementPerformAction(staleClose, kAXPressAction as CFString)
                // Confirm the displayed exact identity before the next scan.
                command(false); await pause(0.35)
                try require(service.switcher.failureNotice.panel.isVisible && service.controller.isFocused(source, app: apps[0]), "failed exact restoration shows nonactivating feedback without selecting another window")
                await pause(1.7)
                try require(!service.switcher.failureNotice.panel.isVisible, "failure feedback dismisses without blocking input")
                print("PASS: recovery workflow complete")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            command(false)
            service.stop()
            try? fixtureCommand("secure-off", index: 1)
            await pause(0.2)
            for app in apps { app.terminate() }
            CGWarpMouseCursorPosition(quartzPoint(priorPointer))
            if let prior, let priorWindow { _ = service.controller.reveal(priorWindow, app: prior) }
            else { prior?.activate(options: []) }
            await pause(0.3)
            try? FileManager.default.removeItem(at: stateDirectory)
            exit(result)
        }
    }

    @MainActor private func refresh() async { service.switcher.refreshCandidates(); await pause(0.9) }
    @MainActor private func select(_ id: SwitcherWindowID) async throws {
        command(true); key(48)
        await pause(0.25)
        for _ in 0..<service.switcher.candidates.count {
            if service.switcher.workflow.snapshot?.selected == id { break }
            key(48); await pause(0.03)
        }
        try require(service.switcher.workflow.snapshot?.selected == id, "real shortcut selects the exact recovery target")
    }
    private func confirm(_ method: String) {
        if method == "release" { command(false) }
        else if method == "enter" { key(36) }
        else if let snapshot = service.switcher.workflow.snapshot, let index = snapshot.windows.firstIndex(of: snapshot.selected) {
            let frame = service.switcher.panel.panel.frame
            let columns = service.switcher.panel.columns
            let point = CGPoint(x: frame.minX + 12 + CGFloat(index % columns) * 244 + 117, y: frame.maxY - 12 - CGFloat(index / columns) * 200 - 95)
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartzPoint(point), mouseButton: .left)?.post(tap: .cghidEventTap)
            }
        }
    }

    @MainActor private func checkSlowEnumeration(app: NSRunningApplication, source: AppWindow, sourceApp: NSRunningApplication) async throws {
        guard app.bundleIdentifier?.hasPrefix("dev.yifeng.DockEnhancedSwitcherFixture") == true else { return }
        _ = service.controller.reveal(source, app: sourceApp); await pause(0.3)
        // Suspend only our disposable fixture. Always resume it before unwinding.
        kill(app.processIdentifier, SIGSTOP)
        defer { kill(app.processIdentifier, SIGCONT) }
        let start = ProcessInfo.processInfo.systemUptime
        _ = service.controller.windows(of: app)
        let scanTime = ProcessInfo.processInfo.systemUptime - start
        print("TIMING: unresponsive fixture inventory \(String(format: "%.3f", scanTime))s")
        try require(scanTime < 0.35, "a timed-out AX owner does not multiply delay across retained windows")
        service.switcher.refreshCandidates()
        let pressed = ProcessInfo.processInfo.systemUptime
        command(true); key(48)
        while !service.switcher.panel.panel.isVisible && ProcessInfo.processInfo.systemUptime - pressed < 0.7 { await pause(0.005) }
        let shown = ProcessInfo.processInfo.systemUptime - pressed
        print("TIMING: no-image panel while fixture suspended \(String(format: "%.3f", shown))s")
        try require(service.switcher.panel.panel.isVisible && shown < 0.5, "cached selection remains responsive during a real slow AX inventory")
        key(53); command(false); await pause(0.15)
    }

    private func fixtureCommand(_ command: String, index: Int) throws {
        try command.write(to: stateDirectory.appendingPathComponent("\(index).json.command"), atomically: true, encoding: .utf8)
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
    private func require(_ condition: Bool, _ text: String) throws {
        guard condition else { throw NSError(domain: "RecoveryCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        print("PASS: \(text)"); fflush(stdout)
    }
}
#endif
