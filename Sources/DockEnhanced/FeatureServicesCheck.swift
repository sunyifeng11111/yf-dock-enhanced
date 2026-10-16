#if DEBUG
import AppKit
import DockCore

/// Uses the real event tap/service and real settings storage. Screenshot permission
/// and delivery are controlled at the OS boundary; no desktop pixels are captured.
@MainActor
func checkFeatureServices() async -> Int32 {
    guard AXIsProcessTrusted() else {
        print("UNAVAILABLE: Accessibility is required for the native service check; no permission changed")
        return 2
    }
    var failed = false
    var checks = 0
    func require(_ value: Bool, _ message: String) {
        checks += 1
        print("\(value ? "PASS" : "FAIL"): \(message)")
        if !value { failed = true }
    }
    var recording = true
    let picture = NSImage(size: NSSize(width: 40, height: 30))
    let service = DockService(captureAccess: { recording }, capture: { windows, current, publish in
        for window in windows where current() { publish(window.key, picture) }
    })
    defer { service.stop() }
    let window = AppWindow(element: AXUIElementCreateApplication(getpid()), key: WindowKey(pid: getpid(), id: 9001),
                           title: "Controlled image", frame: CGRect(x: 0, y: 0, width: 400, height: 300),
                           state: WindowState(id: 9001, minimized: false, canMinimize: true, fullScreen: false))
    let suite = "dev.yifeng.DockEnhanced.services.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsModel(defaults: defaults)
    for (hover, click, switcher) in [(false,false,false), (false,false,true), (false,true,false), (false,true,true),
                                   (true,false,false), (true,false,true), (true,true,false), (true,true,true)] {
        settings.previewEnabled = hover
        settings.clickEnabled = click
        settings.switcherEnabled = switcher
        let reopened = SettingsModel(defaults: defaults)
        service.configure(previewsEnabled: reopened.previewEnabled, clickEnabled: reopened.clickEnabled, switcherEnabled: reopened.switcherEnabled)
        let name = "hover=\(hover) click=\(click) switcher=\(switcher)"
        require(reopened.previewEnabled == hover && reopened.clickEnabled == click && reopened.switcherEnabled == switcher,
                name + " retains all choices after reopening settings")
        require(service.running == (hover || click || switcher), name + " has the expected service availability")
        require(service.switcherAvailable == switcher, name + " reports actual keyboard capability independently")
        await service.images.refresh([window])?.value
        require((service.images.cache[window.key] != nil) == (hover || switcher), name + " enables only required image consumers")
    }
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
    require(service.images.cache[window.key] === picture, "disabling hover preserves images still consumed by the switcher")
    service.configure(previewsEnabled: true, clickEnabled: false, switcherEnabled: false)
    require(service.images.cache[window.key] === picture, "disabling switcher preserves images still consumed by hover")
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
    service.images.clear()
    service.switcher.panel.show(candidates: [SwitcherCandidate(window: window, app: NSRunningApplication.current)], selected: window.key.switcherID, screen: NSScreen.main)
    func containsPicture(_ view: NSView?) -> Bool {
        guard let view else { return false }
        if let imageView = view as? NSImageView, imageView.image === picture { return true }
        return view.subviews.contains { containsPicture($0) }
    }
    require(!containsPicture(service.switcher.panel.panel.contentView), "the actual card is usable with its title and icon before capture completes")
    await service.images.refresh([window])?.value
    require(containsPicture(service.switcher.panel.panel.contentView), "async imagery reaches an actual visible native card")
    recording = false
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
    require(service.switcherAvailable && service.images.cache.isEmpty && !containsPicture(service.switcher.panel.panel.contentView) &&
            service.switcher.panel.windowIDs == [window.key.switcherID] && service.switcher.panel.panel.isVisible,
            "recording revocation clears visible card imagery and cache while keyboard switching remains available")
    service.switcher.panel.hide()
    service.configure(previewsEnabled: false, clickEnabled: true, switcherEnabled: false)
    require(service.running && !service.switcherAvailable && service.images.cache.isEmpty,
            "click-only mode runs without recording or keyboard enhancement")
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false)
    require(!service.running && !service.preview.isVisible && !service.switcher.isSelecting && service.images.cache.isEmpty,
            "all features disabled leaves no panel, selection or imagery")
    print("\(checks) native feature-service checks, \(failed ? "failed" : "passed")")
    return failed ? 1 : 0
}
#endif
