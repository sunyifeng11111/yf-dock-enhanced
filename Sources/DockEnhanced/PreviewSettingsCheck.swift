#if DEBUG
import AppKit
import DockCore

/// Exercises real preference storage and image delivery at the OS capture boundary.
/// No user window is read, moved, captured or activated by this check.
@MainActor
func checkPreviewSettings() async -> Int32 {
    var failures = 0
    var checks = 0
    func require(_ value: Bool, _ message: String) {
        checks += 1
        if !value { failures += 1 }
        print("\(value ? "PASS" : "FAIL"): \(message)")
    }
    let suite = "dev.yifeng.DockEnhanced.check.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let fresh = SettingsModel(defaults: defaults)
    require(fresh.switcherEnabled && fresh.previewEnabled && fresh.clickEnabled, "new installations enable all three independent features")
    defaults.set(false, forKey: "enabled")
    defaults.set(true, forKey: "previewEnabled")
    let settings = SettingsModel(defaults: defaults)
    require(settings.switcherEnabled && settings.previewEnabled && !settings.clickEnabled,
            "upgrade enables the new switcher while preserving explicit and legacy Dock choices")
    settings.switcherEnabled = false
    settings.previewEnabled = false
    settings.clickEnabled = true
    let reopened = SettingsModel(defaults: defaults)
    require(!reopened.switcherEnabled && !reopened.previewEnabled && reopened.clickEnabled,
            "explicit feature choices survive reopening settings")
    defaults.synchronize()
    let restartedProcess = Process()
    restartedProcess.executableURL = Bundle.main.executableURL
    restartedProcess.arguments = ["--check-preference-restart", suite, "false", "true", "false"]
    do {
        try restartedProcess.run()
        restartedProcess.waitUntilExit()
        require(restartedProcess.terminationStatus == 0, "a separate application process retains the explicit disabled switcher and Dock choices")
    } catch { require(false, "a separate application process could verify saved feature choices") }
    reopened.switcherEnabled = true
    reopened.running = true
    require(reopened.switcherStatus == "需要辅助功能权限 · 系统 Command+Tab 仍可用", "a running Dock service does not imply switcher control permission")
    reopened.accessibilityGranted = true
    reopened.switcherAvailable = true
    require(reopened.switcherStatus == "增强可用 · 图标和标题可用（未授权屏幕录制）", "missing image permission leaves window switching available")
    reopened.captureGranted = true
    require(reopened.switcherStatus == "增强可用 · 窗口缩略图已启用", "settings distinguishes full enhancement from icon-only switching")
    let sample = AppWindow(element: AXUIElementCreateApplication(getpid()), key: WindowKey(pid: getpid(), id: 501),
                           title: "Controlled image", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           state: WindowState(id: 501, minimized: false, canMinimize: true, fullScreen: false))
    let picture = NSImage(size: NSSize(width: 40, height: 30))
    let images = PreviewImages(captureAccess: { true }, capture: { windows, _, publish in
        for window in windows { publish(window.key, picture) }
    })
    let pendingImage = images.refresh([sample])
    require(images.cache.isEmpty, "selection can begin with title and icon before capture finishes")
    await pendingImage?.value
    require(images.cache[sample.key] === picture, "completed capture makes the image available without rebuilding a window")
    let minimized = AppWindow(element: sample.element, key: sample.key, title: sample.title, frame: sample.frame,
                              state: WindowState(id: 501, minimized: true, canMinimize: true, fullScreen: false))
    await images.refresh([minimized])?.value
    require(images.cache[minimized.key] === picture, "minimized windows retain the last available image")
    var captureAllowed = true
    let gate = ControlledImageCapture()
    let revocable = PreviewImages(captureAccess: { captureAllowed }, capture: gate.capture)
    let oldRequest = revocable.refresh([sample])
    await gate.waitUntilRequested()
    captureAllowed = false
    revocable.updateAvailability(hasConsumers: true, captureGranted: false)
    gate.finish(key: sample.key, image: picture)
    await oldRequest?.value
    require(revocable.cache.isEmpty, "permission revocation discards an in-flight image instead of retaining it")
    let blocked = revocable.refresh([sample])
    require(blocked == nil && revocable.cache.isEmpty, "without recording permission switching has only icon and title imagery")
    captureAllowed = true
    revocable.updateAvailability(hasConsumers: true, captureGranted: true)
    let newRequest = revocable.refresh([sample])
    await gate.waitUntilRequested()
    gate.finish(key: sample.key, image: picture)
    await newRequest?.value
    require(revocable.cache[sample.key] === picture, "granting image access again permits fresh async imagery")
    captureAllowed = false
    revocable.updateAvailability(hasConsumers: true, captureGranted: false)
    require(revocable.cache.isEmpty, "revocation clears already displayed cache immediately")
    let many = (1...80).map { index in
        AppWindow(element: sample.element, key: WindowKey(pid: getpid(), id: index), title: "Controlled", frame: sample.frame,
                  state: WindowState(id: index, minimized: false, canMinimize: true, fullScreen: false))
    }
    await images.refresh(many)?.value
    require(images.cache.count == 64 && images.cache[many.last!.key] === picture && images.cache[many.first!.key] == nil,
            "many windows keep recent images within the 64-image memory bound")
    images.updateAvailability(hasConsumers: false, captureGranted: true)
    require(images.cache.isEmpty && images.refresh([sample]) == nil, "no image consumers clears retained imagery and prevents new capture")
    print("\(checks) preview/settings checks, \(failures) failures")
    return failures == 0 ? 0 : 1
}
/// A deterministic stand-in for the external screenshot operation. Only completion
/// timing is controlled; the image store, generation handling and preferences are real.
@MainActor
private final class ControlledImageCapture {
    private var publisher: (@MainActor (WindowKey, NSImage) -> Void)?
    private var completion: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func capture(_ windows: [AppWindow], current: @escaping @MainActor () -> Bool,
                 publish: @escaping @MainActor (WindowKey, NSImage) -> Void) async throws {
        publisher = publish
        await withCheckedContinuation { continuation in
            completion = continuation
            started?.resume()
            started = nil
        }
    }
    func waitUntilRequested() async {
        if completion != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func finish(key: WindowKey, image: NSImage) {
        publisher?(key, image)
        publisher = nil
        completion?.resume()
        completion = nil
    }
}
#endif
