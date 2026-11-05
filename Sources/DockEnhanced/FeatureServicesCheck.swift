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
    var captures = 0
    let picture = NSImage(size: NSSize(width: 40, height: 30))
    let service = DockService(captureAccess: { recording }, capture: { windows, current, publish in
        captures += 1
        for window in windows where current() { publish(window.key, picture) }
    }, inventoryScan: { _ in DockWindowInventory.Observation(windows: [], recentID: nil) })
    // This check supplies its own cards. Keep background scans confined to an
    // empty controlled inventory rather than depending on the user's apps.
    service.switcher = NativeWindowSwitcher(controller: service.controller, applicationFilter: { _ in false })
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
        for shake in [false, true] {
            settings.shakeEnabled = shake
            settings.previewEnabled = hover
            settings.clickEnabled = click
            settings.switcherEnabled = switcher
            let reopened = SettingsModel(defaults: defaults)
            service.configure(previewsEnabled: reopened.previewEnabled, clickEnabled: reopened.clickEnabled, switcherEnabled: reopened.switcherEnabled, shakeEnabled: reopened.shakeEnabled)
            // Let the initial inventory render finish before manually presenting a
            // controlled panel outside the keyboard selection workflow.
            try? await Task.sleep(nanoseconds: 30_000_000)
            let name = "hover=\(hover) click=\(click) switcher=\(switcher) shake=\(shake)"
            require(reopened.previewEnabled == hover && reopened.clickEnabled == click && reopened.switcherEnabled == switcher && reopened.shakeEnabled == shake,
                    name + " retains all choices after reopening settings")
            require(service.running == (hover || click || switcher || shake), name + " has the expected service availability")
            require(service.switcherAvailable == switcher, name + " reports actual keyboard capability independently")
            let idleRequest = service.images.refresh([window])
            require(idleRequest == nil, name + " never captures while both panels are hidden")
            if hover || switcher {
                if hover {
                    service.preview.show(item: DockItem(app: .current, frame: window.frame), windows: [window], images: service.images)
                } else {
                    service.switcher.panel.show(candidates: [SwitcherCandidate(window: window, app: .current)], selected: window.key.switcherID, screen: NSScreen.main)
                }
                await service.images.refresh([window])?.value
                require(service.images.cache[window.key] === picture, name + " permits capture with a visible consumer")
                service.preview.hide(animated: false)
                service.switcher.panel.hide()
                require(service.preview.panel.contentView == nil && service.switcher.panel.panel.contentView == nil,
                        name + " releases hidden card views instead of retaining their screenshots")
                require(service.images.refresh([window]) == nil && service.images.cache[window.key] === picture,
                        name + " stops capture on close and preserves cached imagery")
            } else { require(service.images.cache.isEmpty, name + " has no retained image consumers") }
        }
    }
    let beforeIdle = captures
    service.switcher.onCandidatesChanged?([SwitcherCandidate(window: window, app: .current)])
    try? await Task.sleep(nanoseconds: 2_300_000_000)
    require(captures == beforeIdle, "background inventory and foreground polling perform zero screenshots while idle")
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
    // These manually supplied cards have no keyboard selection session. An
    // inventory render may dismiss them during the await; reopen from the image
    // store rather than inspecting a dismissed panel's old content view.
    service.switcher.panel.show(candidates: [SwitcherCandidate(window: window, app: .current)], selected: window.key.switcherID, screen: NSScreen.main)
    require(containsPicture(service.switcher.panel.panel.contentView), "completed imagery is available on the next native card presentation")
    service.preview.show(item: DockItem(app: .current, frame: window.frame), windows: [window], images: service.images)
    service.switcher.panel.hide()
    // The hover feature is disabled, so a manually shown hover panel cannot
    // keep the switcher's capture demand alive.
    require(service.images.refresh([window]) == nil, "a disabled hover consumer cannot keep screenshot demand active")
    service.preview.hide(animated: false)
    service.configure(previewsEnabled: true, clickEnabled: false, switcherEnabled: true)
    service.preview.show(item: DockItem(app: .current, frame: window.frame), windows: [window], images: service.images)
    service.switcher.panel.show(candidates: [SwitcherCandidate(window: window, app: .current)], selected: window.key.switcherID, screen: NSScreen.main)
    service.preview.hide(animated: false)
    await service.images.refresh([window])?.value
    require(containsPicture(service.switcher.panel.panel.contentView), "closing one consumer leaves the other visible consumer able to refresh")
    recording = false
    service.switcher.panel.show(candidates: [SwitcherCandidate(window: window, app: .current)], selected: window.key.switcherID, screen: NSScreen.main)
    service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: true)
    require(service.switcherAvailable && service.images.cache.isEmpty && !containsPicture(service.switcher.panel.panel.contentView) &&
            service.switcher.panel.windowIDs == [window.key.switcherID] && service.switcher.panel.panel.isVisible,
            "recording revocation clears visible card imagery and cache while keyboard switching remains available")
    service.switcher.panel.hide()
    recording = true
    service.configure(previewsEnabled: true, clickEnabled: false, switcherEnabled: false)
    service.preview.show(item: DockItem(app: .current, frame: window.frame), windows: [window], images: service.images)
    await service.images.refresh([window])?.value
    require(containsPicture(service.preview.panel.contentView), "the controlled Dock preview holds a fresh thumbnail")
    service.preview.hide()
    recording = false
    service.configure(previewsEnabled: true, clickEnabled: false, switcherEnabled: false)
    require(service.images.cache.isEmpty && !containsPicture(service.preview.panel.contentView),
            "revocation releases a fading Dock preview's image before its dismissal animation finishes")
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
