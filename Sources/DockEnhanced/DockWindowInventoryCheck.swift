#if DEBUG
import AppKit
import DockCore

/// A blocked AX boundary must leave the UI responsive. No user windows are read.
@MainActor
func checkDockWindowInventory() async -> Int32 {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    var failures = 0, checks = 0
    func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { failures += 1 }
        print("\(value ? "PASS" : "FAIL"): \(message)")
    }
    func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return predicate()
    }
    let app = NSRunningApplication.current
    let windows = (101...102).map { id in
        AppWindow(element: AXUIElementCreateApplication(getpid()), key: WindowKey(pid: getpid(), id: id),
                  title: "Controlled inventory", frame: CGRect(x: 0, y: 0, width: 400, height: 300), state: WindowState(id: id))
    }
    let observation = DockWindowInventory.Observation(windows: windows, recentID: windows.last!.key.id)
    let gate = InventoryScanGate()
    defer { gate.finish(); gate.finish(); gate.finish() }
    let inventory = DockWindowInventory(scan: { _ in gate.scan(); return observation })
    var delivered: [DockWindowInventory.Observation] = []
    var deliveryOnMain = true
    inventory.onUpdate = { _, value in deliveryOnMain = deliveryOnMain && Thread.isMainThread; delivered.append(value) }
    require(inventory.refresh(app) && !inventory.refresh(app), "repeated polling coalesces an application's unfinished scan")
    require(await waitUntil { gate.count == 1 }, "the worker reaches the controlled AX boundary")
    var heartbeat = false
    DispatchQueue.main.async { heartbeat = true }
    require(await waitUntil { heartbeat } && delivered.isEmpty && !gate.calledOnMain,
            "the main queue processes input work while AX enumeration is blocked")
    gate.finish()
    require(await waitUntil { delivered.count == 1 } && deliveryOnMain && delivered.first?.windows.map(\.key) == windows.map(\.key),
            "a finished background scan delivers its complete snapshot on the main executor")
    let controller = WindowController()
    controller.observeWindows(observation.windows, of: app, recentID: observation.recentID)
    require(controller.recentWindow(of: app, in: windows)?.key == windows.last?.key,
            "background snapshots preserve the recent concrete window used by Dock clicks")
    controller.observeWindows([windows[0]], of: app, recentID: observation.recentID)
    require(controller.recentWindow(of: app, in: [windows[0]])?.key == windows[0].key,
            "a removed recent window falls back to an available window")

    inventory.refresh(app)
    require(await waitUntil { gate.count == 2 }, "a later scan may begin after delivery")
    inventory.invalidate(app.processIdentifier)
    require(inventory.refresh(app), "a new window command can request a replacement snapshot")
    gate.finish()
    require(await waitUntil { gate.count == 3 } && delivered.count == 1,
            "the pre-command result cannot overwrite a newer window state")
    gate.finish()
    require(await waitUntil { delivered.count == 2 }, "the replacement snapshot is delivered normally")

    inventory.refresh(app)
    require(await waitUntil { gate.count == 4 }, "shutdown can interrupt a scan in progress")
    inventory.invalidateAll()
    require(inventory.refresh(app), "restarting can request a fresh scan after invalidation")
    gate.finish()
    require(await waitUntil { gate.count == 5 } && delivered.count == 2,
            "a stopped service's pending result cannot repopulate the restarted inventory")
    gate.finish()
    require(await waitUntil { delivered.count == 3 }, "restarted inventory delivers only its new result")
    inventory.invalidateAll()
    print("\(checks) Dock inventory checks, \(failures) failures")
    return failures == 0 ? 0 : 1
}

private final class InventoryScanGate {
    private let lock = NSLock()
    private let completion = DispatchSemaphore(value: 0)
    private var started = 0
    private var mainThread = false
    var count: Int { lock.lock(); defer { lock.unlock() }; return started }
    var calledOnMain: Bool { lock.lock(); defer { lock.unlock() }; return mainThread }
    func scan() {
        lock.lock()
        started += 1
        mainThread = mainThread || Thread.isMainThread
        lock.unlock()
        _ = completion.wait(timeout: .now() + 1)
    }
    func finish() { completion.signal() }
}
#endif
