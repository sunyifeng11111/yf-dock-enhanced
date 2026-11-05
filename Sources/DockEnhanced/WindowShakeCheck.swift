#if DEBUG
import AppKit

/// An own kept window and a remote batch window, using the real shake worker
/// execution context. The parent script owns and cleans up the fixture process.
@MainActor
func checkSelfWindowShake(fixturePID: pid_t) async -> Int32 {
    guard AXIsProcessTrusted() else {
        print("UNAVAILABLE: Accessibility is required for the self-shake check")
        return 2
    }
    var launched: NSRunningApplication?
    for _ in 0..<40 {
        launched = NSRunningApplication(processIdentifier: fixturePID)
        if launched?.bundleIdentifier == "dev.yifeng.DockEnhancedSelfShakeFixture" { break }
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
    guard let fixture = launched, fixture.bundleIdentifier == "dev.yifeng.DockEnhancedSelfShakeFixture" else {
        print("UNAVAILABLE: the isolated self-shake fixture did not register")
        return 2
    }
    let previous = NSWorkspace.shared.frontmostApplication
    let sibling = NSWindow(contentRect: CGRect(x: 280, y: 340, width: 420, height: 280),
                           styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
    sibling.title = "Own sibling regression"
    sibling.isReleasedWhenClosed = false
    sibling.orderFront(nil)
    let window = NSWindow(contentRect: CGRect(x: 240, y: 300, width: 520, height: 320),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.title = "Dock Enhanced own-window regression"
    window.isReleasedWhenClosed = false
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    defer { sibling.close(); window.close(); previous?.activate(options: []) }
    try? await Task.sleep(nanoseconds: 400_000_000)
    let controller = WindowController()
    var ownWindows: [AppWindow] = [], remoteWindows: [AppWindow] = []
    for _ in 0..<40 {
        ownWindows = controller.windows(of: .current)
        remoteWindows = controller.windows(of: fixture)
        if ownWindows.contains(where: { $0.title == window.title }),
           remoteWindows.contains(where: { $0.title == "Shake fixture 1" }) { break }
        try? await Task.sleep(nanoseconds: 75_000_000)
    }
    guard let kept = ownWindows.first(where: { $0.title == window.title }),
          let other = remoteWindows.first(where: { $0.title == "Shake fixture 1" }) else {
        print("FAIL: native regression windows are not ready (own=\(ownWindows.count), fixture=\(remoteWindows.count))")
        return 1
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    try? await Task.sleep(nanoseconds: 300_000_000)
    let isolation = ShakeWindowIsolation(applications: { [fixture, .current] })
    let worker = DispatchQueue(label: "dev.yifeng.DockEnhanced.self-shake-regression")
    func toggle() async {
        await withCheckedContinuation { (completion: CheckedContinuation<Void, Never>) in
            let work = DispatchWorkItem {
                isolation.toggle(except: kept, app: .current)
                completion.resume()
            }
            worker.async(execute: work)
        }
    }
    func waitForRemote(minimized: Bool) async -> Bool {
        for _ in 0..<40 {
            if (AX.value(other.element, kAXMinimizedAttribute) as Bool?) == minimized { return true }
            try? await Task.sleep(nanoseconds: 75_000_000)
        }
        return false
    }
    for cycle in 1...3 {
        await toggle()
        let minimized = await waitForRemote(minimized: true)
        guard minimized, sibling.isMiniaturized, !window.isMiniaturized else {
            print("FAIL: own-window cycle \(cycle) did not isolate the remote window")
            return 1
        }
        print("PASS: own-window cycle \(cycle) minimized the remote window")
        fflush(stdout)
        await toggle()
        let restored = await waitForRemote(minimized: false)
        try? await Task.sleep(nanoseconds: 700_000_000)
        guard restored,
              !sibling.isMiniaturized, !window.isMiniaturized, window.isKeyWindow else {
            print("FAIL: own-window cycle \(cycle) did not restore with own-window focus")
            return 1
        }
        print("PASS: own-window cycle \(cycle) restored without an AppKit thread violation")
    }
    let service = DockService(inventoryScan: { _ in DockWindowInventory.Observation(windows: [], recentID: nil) })
    service.shake = WindowShakeService(applications: { [fixture, .current] })
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false, shakeEnabled: true)
    defer { service.stop() }
    let pointer = quartzPoint(NSEvent.mouseLocation)
    defer { CGWarpMouseCursorPosition(pointer) }
    await shakeFixtureWindow(kept)
    let draggedMinimized = await waitForRemote(minimized: true)
    guard draggedMinimized, sibling.isMiniaturized, !window.isMiniaturized else {
        print("FAIL: actual own-window dragging did not isolate the batch")
        return 1
    }
    await shakeFixtureWindow(kept)
    let draggedRestored = await waitForRemote(minimized: false)
    guard draggedRestored, !sibling.isMiniaturized, window.isKeyWindow else {
        print("FAIL: actual own-window dragging did not restore the batch and own-window focus")
        return 1
    }
    print("PASS: actual own-window dragging minimized and restored the batch without crashing")
    return 0
}

@MainActor
private func shakeFixtureWindow(_ kept: AppWindow, titleBar: Bool = true) async {
    var postedPoint: CGPoint?
    func drag(_ type: CGEventType, _ point: CGPoint) {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        if let previous = postedPoint, type == .leftMouseDragged {
            event?.setDoubleValueField(.mouseEventDeltaX, value: point.x - previous.x)
            event?.setDoubleValueField(.mouseEventDeltaY, value: point.y - previous.y)
        }
        postedPoint = point
        event?.post(tap: .cghidEventTap)
    }
    guard let frame = AX.rect(kept.element) else { return }
    let point = CGPoint(x: frame.midX, y: titleBar ? frame.minY + 12 : frame.midY)
    drag(.mouseMoved, point)
    drag(.leftMouseDown, point)
    try? await Task.sleep(nanoseconds: 100_000_000)
    var previous = 0.0
    for offset in [70.0, 0, 70, 0, 70, 0] {
        for step in 1...10 {
            let x = previous + (offset - previous) * Double(step) / 10
            drag(.leftMouseDragged, CGPoint(x: point.x + x, y: point.y))
            try? await Task.sleep(nanoseconds: 12_000_000)
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        previous = offset
    }
    drag(.leftMouseUp, point)
    try? await Task.sleep(nanoseconds: 900_000_000)
}

final class WindowShakeFixture: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        for index in 0..<4 {
            var style: NSWindow.StyleMask = [.titled, .closable, .resizable]
            if index != 3 { style.insert(.miniaturizable) }
            let window = NSWindow(contentRect: CGRect(x: 180 + index * 80, y: 200 + index * 35, width: 440, height: 280),
                                  styleMask: style, backing: .buffered, defer: false)
            window.title = "Shake fixture \(index)"
            window.setAccessibilityIdentifier("shake-fixture-\(index)")
            window.isReleasedWhenClosed = false
            window.contentView = NSTextField(labelWithString: "Controlled shake fixture \(index)")
            window.orderFront(nil)
            windows.append(window)
        }
        windows[2].miniaturize(nil)
        windows[0].makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
func checkWindowShake(fixtureURLs: [URL]) async -> Int32 {
    guard AXIsProcessTrusted(), fixtureURLs.count == 2 else {
        print("UNAVAILABLE: Accessibility and two isolated fixture bundles are required")
        return 2
    }
    let originalApp = NSWorkspace.shared.frontmostApplication
    var fixtures: [NSRunningApplication] = []
    var failures = 0
    var checks = 0
    func require(_ condition: Bool, _ name: String) {
        checks += 1
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL"): \(name)")
    }
    func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 75_000_000)
        }
        return condition()
    }
    defer {
        for fixture in fixtures { kill(fixture.processIdentifier, SIGCONT); fixture.terminate() }
        originalApp?.activate(options: [])
    }
    do {
        for url in fixtureURLs {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = ["--shake-fixture"]
            config.createsNewApplicationInstance = true
            fixtures.append(try await NSWorkspace.shared.openApplication(at: url, configuration: config))
        }
    } catch {
        print("FAIL: could not launch isolated fixtures: \(error)")
        return 1
    }
    let scanner = WindowController()
    let app = fixtures[0], hiddenApp = fixtures[1]
    try? await Task.sleep(nanoseconds: 800_000_000)
    let windows = scanner.windows(of: app)
    func named(_ index: Int) -> AppWindow? { windows.first { $0.title == "Shake fixture \(index)" } }
    guard let kept = named(0), let other = named(1), let preminimized = named(2), let unsupported = named(3) else {
        print("FAIL: native fixtures did not expose their four exact windows")
        return 1
    }
    hiddenApp.hide()
    _ = scanner.reveal(kept, app: app)
    try? await Task.sleep(nanoseconds: 500_000_000)
    require(scanner.isFocused(kept, app: app), "fixture current window is focused before isolation")
    let isolation = ShakeWindowIsolation(applications: { fixtures })
    isolation.toggle(except: kept, app: app)
    try? await Task.sleep(nanoseconds: 700_000_000)
    func minimized(_ window: AppWindow) -> Bool { AX.value(window.element, kAXMinimizedAttribute) ?? false }
    require(!minimized(kept) && minimized(other), "a shake keeps the exact current window and minimizes another window of the same app")
    require(minimized(preminimized) && !minimized(unsupported), "pre-minimized and non-minimizable windows retain their state")
    require(hiddenApp.isHidden && scanner.windows(of: hiddenApp).filter { !$0.state.minimized }.count == 3,
            "hidden applications are left untouched")
    isolation.toggle(except: kept, app: app)
    try? await Task.sleep(nanoseconds: 700_000_000)
    require(!minimized(other) && minimized(preminimized), "the second shake restores only this feature's batch")
    require(scanner.isFocused(kept, app: app), "batch restoration preserves the kept window's focus")
    let service = DockService(inventoryScan: { _ in DockWindowInventory.Observation(windows: [], recentID: nil) })
    service.shake = WindowShakeService(applications: { fixtures })
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false, shakeEnabled: true)
    defer { service.stop() }
    require(service.running, "shake-only mode keeps the mouse event service running")
    let originalPointer = quartzPoint(NSEvent.mouseLocation)
    defer { CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: originalPointer, mouseButton: .left)?.post(tap: .cghidEventTap) }
    await shakeFixtureWindow(kept, titleBar: false)
    require(!minimized(other), "shaking the pointer over window content never minimizes other windows")
    await shakeFixtureWindow(kept)
    require(!minimized(kept) && minimized(other), "real title-bar dragging reaches the detector through the event tap")
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false, shakeEnabled: false)
    require(!service.running, "disabling shake while isolated stops monitoring")
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false, shakeEnabled: true)
    await shakeFixtureWindow(kept)
    require(!minimized(other) && minimized(preminimized), "another real drag restores the remembered batch")
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false, shakeEnabled: false)
    require(!service.running, "turning off the last feature stops input monitoring")
    isolation.toggle(except: kept, app: app)
    try? await Task.sleep(nanoseconds: 500_000_000)
    if let close: AXUIElement = AX.value(other.element, kAXCloseButtonAttribute) {
        _ = AXUIElementPerformAction(close, kAXPressAction as CFString)
    }
    isolation.toggle(except: kept, app: app)
    require(!minimized(kept) && minimized(preminimized), "closing a batch window before restoration never targets a replacement")
    hiddenApp.unhide()
    _ = scanner.reveal(kept, app: app)
    try? await Task.sleep(nanoseconds: 600_000_000)
    guard let formerlyHidden = scanner.windows(of: hiddenApp).first(where: { $0.title == "Shake fixture 0" }) else {
        require(false, "unhidden fixture exposes its exact window")
        return 1
    }
    isolation.toggle(except: kept, app: app)
    try? await Task.sleep(nanoseconds: 700_000_000)
    let crossMinimized = await waitUntil { (AX.value(formerlyHidden.element, kAXMinimizedAttribute) as Bool?) == true }
    require(crossMinimized && !minimized(kept), "isolation includes ordinary windows belonging to other visible apps")
    // Force a real AX timeout in a fixture, then retry after it responds again.
    kill(hiddenApp.processIdentifier, SIGSTOP)
    isolation.toggle(except: kept, app: app)
    kill(hiddenApp.processIdentifier, SIGCONT)
    try? await Task.sleep(nanoseconds: 500_000_000)
    isolation.toggle(except: kept, app: app)
    let crossRestored = await waitUntil { (AX.value(formerlyHidden.element, kAXMinimizedAttribute) as Bool?) == false }
    try? await Task.sleep(nanoseconds: 700_000_000)
    require(crossRestored && scanner.isFocused(kept, app: app), "restoration survives an AX timeout and leaves the kept window in front")
    print("\(checks) native shake checks, \(failures) failures")
    return failures == 0 ? 0 : 1
}
#endif
