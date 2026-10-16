#if DEBUG
import AppKit
import DockCore

/// Real posted keyboard input, independent fixture processes and exact AX focus.
/// Inventory/workflow observation identifies a displayed target, never substitutes
/// for delivering the shortcut through the system event tap.
final class WindowSwitcherCheck: NSObject, NSApplicationDelegate {
    let service = DockService()
    private let urls: [URL]
    init(urls: [URL]) { self.urls = urls }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let previousApp = NSWorkspace.shared.frontmostApplication
            let previousWindow = previousApp.flatMap { app in
                service.controller.focusedWindow(of: app, in: service.controller.windows(of: app))
            }
            var fixtures: [NSRunningApplication] = []
            var result: Int32 = 0
            do {
                guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
                    print("UNAVAILABLE: Accessibility and event posting are required; no permissions changed")
                    exit(2)
                }
                for url in urls {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.arguments = ["--fixture"]
                    configuration.createsNewApplicationInstance = true
                    fixtures.append(try await NSWorkspace.shared.openApplication(at: url, configuration: configuration))
                }
                await pause(1.2)
                try require(fixtures.count == 2, "two controlled application processes launched")
                let first = service.controller.windows(of: fixtures[0])
                let second = service.controller.windows(of: fixtures[1])
                try require(first.count == 2 && second.count == 2, "normal untitled windows retained and internal panels excluded")
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
                try require(service.switcherAvailable, "only-switcher mode starts the active event tap")
                guard let source = first.first, let target = second.last else { throw failure("fixture windows missing") }
                _ = service.controller.reveal(source, app: fixtures[0])
                await pause(0.5)
                try require(service.controller.isFocused(source, app: fixtures[0]), "exact source window focused before the gesture")
                try require(AX.set(target.element, kAXMinimizedAttribute, true), "controlled cross-application target minimized")
                await pause(0.6)
                await refresh()
                try await select(target.windowID, source: source, sourceApp: fixtures[0], verifyMinimized: target)
                command(down: false)
                await pause(1.8)
                try require(service.controller.isFocused(target, app: fixtures[1]), "real Command release restores and focuses the exact minimized window")
                await pause(0.4)
                try require(service.controller.isFocused(target, app: fixtures[1]), "the selected window remains focused after restoration")

                let sameAppTarget = second.first { $0.key != target.key }!
                await refresh()
                try await select(sameAppTarget.windowID, source: target, sourceApp: fixtures[1])
                command(down: false)
                await pause(0.7)
                try require(service.controller.isFocused(sameAppTarget, app: fixtures[1]), "same-application windows remain individually selectable")

                await refresh()
                command(down: true)
                tab()
                await pause(0.2)
                key(53, down: true, flags: .maskCommand)
                key(53, down: false, flags: .maskCommand)
                command(down: false)
                await pause(0.5)
                try require(!service.switcher.isSelecting && service.controller.isFocused(sameAppTarget, app: fixtures[1]), "Escape cancels without moving focus")
                service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false)
                try require(!service.running && !service.switcher.isSelecting, "all features disabled removes the event tap and active selection")
                command(down: true)
                tab()
                command(down: false)
                await pause(0.8)
                try require(service.controller.isFocused(source, app: fixtures[0]) && !service.switcher.isSelecting,
                            "the next real Command+Tab uses native app switching after enhancement is disabled")
                print("PASS: real shortcut/minimized/same-app/cancel checks complete; screenshots and cross-Space checks are separate")
            } catch {
                print("FAIL: \(error.localizedDescription)")
                result = 1
            }
            command(down: false)
            service.stop()
            for fixture in fixtures { fixture.terminate() }
            if let previousWindow, let previousApp { _ = service.controller.reveal(previousWindow, app: previousApp) }
            else { previousApp?.activate(options: []) }
            await pause(0.3)
            exit(result)
        }
    }

    @MainActor private func refresh() async {
        service.switcher.refreshCandidates()
        await pause(1)
    }

    @MainActor private func select(_ target: SwitcherWindowID, source: AppWindow, sourceApp: NSRunningApplication, verifyMinimized: AppWindow? = nil) async throws {
        try require(service.switcher.candidates.contains { $0.id == target }, "controlled target is present in the actual inventory")
        command(down: true)
        tab()
        await pause(0.25)
        try require(service.switcher.isSelecting, "posted Command+Tab is intercepted by the enhanced switcher")
        let count = service.switcher.workflow.snapshot?.windows.count ?? 0
        for _ in 0..<count {
            if service.switcher.workflow.snapshot?.selected == target { break }
            tab()
            await pause(0.04)
        }
        try require(service.switcher.workflow.snapshot?.selected == target, "Tab navigation selects the requested concrete card")
        try require(service.switcher.panel.windowIDs.contains(target), "the selected concrete window is represented in the visible panel")
        try require(service.controller.isFocused(source, app: sourceApp), "browsing leaves the original exact window focused")
        if let verifyMinimized {
            try require((AX.value(verifyMinimized.element, kAXMinimizedAttribute) as Bool?) == true, "browsing does not restore the minimized target")
        }
    }

    private func command(down: Bool) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: down)
        event?.type = .flagsChanged
        event?.flags = down ? .maskCommand : []
        event?.post(tap: .cghidEventTap)
    }
    private func tab() { key(48, down: true, flags: .maskCommand); key(48, down: false, flags: .maskCommand) }
    private func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func failure(_ text: String) -> NSError { NSError(domain: "WindowSwitcherCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func require(_ condition: Bool, _ text: String) throws {
        guard condition else { throw failure(text) }
        print("PASS: \(text)")
        fflush(stdout)
    }
}

private extension AppWindow {
    var windowID: SwitcherWindowID { key.switcherID }
}
#endif
