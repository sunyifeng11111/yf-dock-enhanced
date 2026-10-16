#if DEBUG
import AppKit
import DockCore

/// Real posted keyboard input, independent fixture processes and exact AX focus.
/// Inventory/workflow observation identifies a displayed target, never substitutes
/// for delivering the shortcut through the system event tap.
final class WindowSwitcherCheck: NSObject, NSApplicationDelegate {
    let service = DockService()
    private let urls: [URL]
    private let fixtureStateDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("dock-switcher-check-" + UUID().uuidString)
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
                try FileManager.default.createDirectory(at: fixtureStateDirectory, withIntermediateDirectories: true)
                for (index, url) in urls.enumerated() {
                    let configuration = NSWorkspace.OpenConfiguration()
                    configuration.arguments = ["--fixture", "--fixture-state", fixtureStateDirectory.appendingPathComponent("\(index).json").path]
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
                _ = service.controller.reveal(source, app: fixtures[0])
                await pause(0.5)
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

                // Hiding belongs to the application; minimizing belongs to one
                // window. Browsing/canceling must preserve both independently.
                command(down: true)
                key(4, down: true, flags: .maskCommand)
                key(4, down: false, flags: .maskCommand)
                command(down: false)
                await pause(0.5)
                try require(fixtures[1].isHidden, "real Command+H hides the controlled application")
                _ = service.controller.reveal(source, app: fixtures[0])
                await pause(0.5)
                await refresh()
                try await select(target.windowID, source: source, sourceApp: fixtures[0])
                try require(fixtures[1].isHidden, "browsing does not unhide the target application")
                key(53, down: true, flags: .maskCommand)
                key(53, down: false, flags: .maskCommand)
                command(down: false)
                await pause(0.3)
                try require(fixtures[1].isHidden && service.controller.isFocused(source, app: fixtures[0]),
                            "cancel preserves the hidden application and exact source focus")
                await refresh()
                try await select(target.windowID, source: source, sourceApp: fixtures[0])
                command(down: false)
                await pause(1)
                try require(service.controller.isFocused(target, app: fixtures[1]) && isVisibleOnActiveSpace(target),
                            "confirmation unhides the exact ordinary target with actual visible focus")
                command(down: true)
                key(4, down: true, flags: .maskCommand)
                key(4, down: false, flags: .maskCommand)
                command(down: false)
                await pause(0.5)
                try require(fixtures[1].isHidden, "application hidden again for the independent minimized case")
                _ = service.controller.reveal(source, app: fixtures[0])
                await pause(0.5)
                try require(AX.set(target.element, kAXMinimizedAttribute, true), "hidden target independently minimized")
                await refresh()
                try await select(target.windowID, source: source, sourceApp: fixtures[0], verifyMinimized: target)
                try require(fixtures[1].isHidden, "browsing a hidden minimized target preserves application hiding")
                command(down: false)
                await pause(2)
                try require(service.controller.isFocused(target, app: fixtures[1]) && isVisibleOnActiveSpace(target),
                            "confirmation unhides and restores the exact hidden minimized window with actual visibility")
                var confirmedExactFocus: Bool?
                _ = service.controller.reveal(sameAppTarget, app: fixtures[1]) { success in
                    confirmedExactFocus = success && self.service.controller.isFocused(sameAppTarget, app: fixtures[1])
                }
                await pause(2)
                try require(confirmedExactFocus == true, "restoration completion verifies exact target focus rather than an activation request")

                if CommandLine.arguments.contains("--reachability") {
                    try await checkReachability(app: fixtures[1], ordinary: sameAppTarget, fullScreen: target)
                    _ = service.controller.reveal(sameAppTarget, app: fixtures[1])
                    await pause(0.5)
                }
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
                let remaining = service.controller.windows(of: fixtures[1])
                guard let staleTarget = remaining.first,
                      let close: AXUIElement = AX.value(staleTarget.element, kAXCloseButtonAttribute) else {
                    throw failure("controlled stale-target fixture has no close button")
                }
                try require(AXUIElementPerformAction(close, kAXPressAction as CFString) == .success,
                            "controlled target closed after inventory was captured")
                await pause(0.4)
                var staleResult: Bool?
                let accepted = service.controller.reveal(staleTarget, app: fixtures[1]) { staleResult = $0 }
                await pause(0.3)
                try require(!accepted && staleResult == false && service.controller.isFocused(source, app: fixtures[0]),
                            "a vanished target fails without activating another window in its application")
                print("PASS: real shortcut/minimized/hidden/same-app/cancel/exact-completion checks complete")
            } catch {
                print("FAIL: \(error.localizedDescription)")
                result = 1
            }
            command(down: false)
            service.stop()
            for fixture in fixtures {
                for window in service.controller.windows(of: fixture) where (AX.value(window.element, "AXFullScreen") as Bool?) == true {
                    _ = AX.set(window.element, "AXFullScreen", false)
                }
            }
            await pause(1.2)
            for fixture in fixtures { fixture.terminate() }
            try? FileManager.default.removeItem(at: fixtureStateDirectory)
            if let previousWindow, let previousApp { _ = service.controller.reveal(previousWindow, app: previousApp) }
            else { previousApp?.activate(options: []) }
            await pause(0.3)
            exit(result)
        }
    }

    @MainActor private func checkReachability(app: NSRunningApplication, ordinary: AppWindow, fullScreen: AppWindow) async throws {
        let fullScreenIdentifier: String? = AX.value(fullScreen.element, kAXIdentifierAttribute)
        let ordinaryIdentifier: String? = AX.value(ordinary.element, kAXIdentifierAttribute)
        _ = service.controller.reveal(fullScreen, app: app)
        await pause(0.5)
        try require(AX.set(fullScreen.element, "AXFullScreen", true), "controlled target enters a separate full-screen Space")
        await pause(2)
        try require(fixtureState(fullScreen)?["fullScreen"] as? Bool == true && isVisibleOnActiveSpace(fullScreen),
                    "fixture reports full-screen target actually visible on the active Space")
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        let children: [AXUIElement] = AX.value(owner, kAXChildrenAttribute) ?? []
        print("DIAGNOSTIC: app children roles=\(children.map { (AX.value($0, kAXRoleAttribute) as String?) ?? "none" }); known ordinary role=\((AX.value(ordinary.element, kAXRoleAttribute) as String?) ?? "none") frame=\(String(describing: AX.rect(ordinary.element)))")
        let raw: [AXUIElement] = AX.value(owner, kAXWindowsAttribute) ?? []
        print("DIAGNOSTIC: raw fixture AX windows=\(raw.map { [(AX.value($0, kAXIdentifierAttribute) as String?) ?? "none", (AX.value($0, kAXRoleAttribute) as String?) ?? "none", (AX.value($0, kAXSubroleAttribute) as String?) ?? "none", String(describing: AX.rect($0))] })")
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        probe.arguments = ["--probe-fixture-inventory", String(app.processIdentifier)]
        let output = Pipe()
        probe.standardOutput = output
        try probe.run()
        for _ in 0..<30 { if !probe.isRunning { break }; await pause(0.1) }
        if probe.isRunning { probe.terminate(); throw failure("cold fixture inventory probe exceeded its bounded deadline") }
        let evidence = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print(evidence.trimmingCharacters(in: .whitespacesAndNewlines))
        if probe.terminationStatus != 0 { print("LIMITATION: a fresh utility process cannot enumerate both fixture windows while this app is full screen") }
        let windows = service.controller.windows(of: app)
        print("DIAGNOSTIC: fixture after full-screen entries=\(windows.map { [$0.key.id.description, (AX.value($0.element, kAXIdentifierAttribute) as String?) ?? "none", $0.state.fullScreen.description] }), old ordinary=\(ordinary.key.id) fullscreen=\(fullScreen.key.id)")
        // Only the controlled fixture supplies independently known identifiers.
        // Production never substitutes a different window by title or geometry.
        guard let refreshedFullScreen = windows.first(where: { (AX.value($0.element, kAXIdentifierAttribute) as String?) == fullScreenIdentifier }),
              let refreshedOrdinary = windows.first(where: { (AX.value($0.element, kAXIdentifierAttribute) as String?) == ordinaryIdentifier }),
              refreshedFullScreen.key != refreshedOrdinary.key else {
            throw failure("fresh inventory must include the fixture's two known ordinary/full-screen windows")
        }
        try require(refreshedFullScreen.state.fullScreen && !refreshedOrdinary.state.fullScreen,
                    "same-app ordinary and full-screen windows on different Spaces are both freshly enumerated")
        try require(service.controller.action(for: app, windows: [refreshedFullScreen]) == .native,
                    "original Dock full-screen click retains native fallback")
        await refresh()
        try await select(refreshedOrdinary.windowID, source: refreshedFullScreen, sourceApp: app)
        command(down: false)
        await pause(2.5)
        print("EVIDENCE: full-screen → ordinary exactFocus=\(service.controller.isFocused(refreshedOrdinary, app: app)) visibleOnActiveSpace=\(isVisibleOnActiveSpace(refreshedOrdinary))")
        try require(service.controller.isFocused(refreshedOrdinary, app: app) && isVisibleOnActiveSpace(refreshedOrdinary),
                    "full-screen to same-app ordinary window switches active Space and exact visible focus")
        await refresh()
        try await select(refreshedFullScreen.windowID, source: refreshedOrdinary, sourceApp: app)
        command(down: false)
        await pause(2.5)
        print("EVIDENCE: ordinary → full-screen exactFocus=\(service.controller.isFocused(refreshedFullScreen, app: app)) visibleOnActiveSpace=\(isVisibleOnActiveSpace(refreshedFullScreen))")
        try require(service.controller.isFocused(refreshedFullScreen, app: app) && isVisibleOnActiveSpace(refreshedFullScreen),
                    "ordinary to same-app full-screen window switches active Space and exact visible focus")
        _ = AX.set(refreshedFullScreen.element, "AXFullScreen", false)
        await pause(1.5)
        if NSScreen.screens.count < 2 { print("UNAVAILABLE: physical multi-display selection requires a second display; host has one") }
        print("UNVERIFIED: same-app windows on two ordinary desktops require a separate controlled desktop fixture; full-screen Space coverage is recorded separately")
    }

    private func fixtureState(_ window: AppWindow) -> [String: Any]? {
        guard let identifier: String = AX.value(window.element, kAXIdentifierAttribute) else { return nil }
        for index in urls.indices {
            guard let data = try? Data(contentsOf: fixtureStateDirectory.appendingPathComponent("\(index).json")),
                  let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let state = entries.first(where: { $0["identifier"] as? String == identifier }) else { continue }
            // Identifiers repeat between fixture apps, so match the owning PID.
            if state["pid"] as? Int == Int(window.key.pid) { return state }
        }
        return nil
    }

    private func isVisibleOnActiveSpace(_ window: AppWindow) -> Bool {
        guard let state = fixtureState(window), state["onActiveSpace"] as? Bool == true,
              state["visible"] as? Bool == true, let number = state["number"] as? Int else { return false }
        let visible = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        return visible.contains { ($0[kCGWindowNumber as String] as? Int) == number }
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
