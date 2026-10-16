import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = DockService()
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var previewItem: NSMenuItem!
    private var clickItem: NSMenuItem!
    private var switcherItem: NSMenuItem!
    private var helpWindow: NSWindow?
    let preferences = SettingsModel()
    let loginItem = LoginItem()
    let updates = ApplicationUpdates()
    private var permissionTimer: Timer?
    private var languageObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchReason = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        let backgroundLaunch = launchEvent?.eventID == kAEOpenApplication &&
            (launchReason == keyAELaunchedAsLogInItem || launchReason == keyAELaunchedAsServiceItem)
        NSApp.setActivationPolicy(.accessory)
        preferences.onFeaturesChange = { [weak self] in self?.refreshPermissions() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Dock Enhanced")
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Dock Enhanced", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        previewItem = NSMenuItem(title: L("悬停预览"), action: #selector(togglePreview), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)
        clickItem = NSMenuItem(title: L("点击收起 / 恢复"), action: #selector(toggleClick), keyEquivalent: "")
        clickItem.target = self
        menu.addItem(clickItem)
        switcherItem = NSMenuItem(title: L("Command+Tab 增强"), action: #selector(toggleSwitcher), keyEquivalent: "")
        switcherItem.target = self
        menu.addItem(switcherItem)
        let help = NSMenuItem(title: L("设置…"), action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        let update = NSMenuItem(title: L("检查更新…"), action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("退出 Dock Enhanced"), action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        languageObserver = NotificationCenter.default.addObserver(forName: Localization.didChange, object: Localization.shared, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.updateStatus()
            self.helpWindow?.title = L("Dock Enhanced · 设置")
            self.service.preview.hide(animated: false)
            self.service.switcher.interrupt()
        }
        statusItem.isVisible = !preferences.hideMenuBarIcon
        preferences.onMenuBarVisibilityChange = { [weak self] hidden in self?.statusItem.isVisible = !hidden }
        service.onStatusChanged = { [weak self] in self?.updateStatus() }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--integration-check"), CommandLine.arguments.count > index + 1 {
            service.configure(previewsEnabled: true, clickEnabled: true, switcherEnabled: false)
            NativeIntegrationCheck(service: service, fixtureURL: URL(fileURLWithPath: CommandLine.arguments[index + 1]),
                                   sourceFixtureURL: CommandLine.arguments.count > index + 2 ? URL(fileURLWithPath: CommandLine.arguments[index + 2]) : nil).run()
            return
        }
        #endif
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        refreshPermissions()
        updates.start()
        let needsPermissions = preferences.anyFeatureEnabled &&
            (!AXIsProcessTrusted() || (preferences.previewEnabled && !CGPreflightScreenCaptureAccess()))
        // Manual launches always provide a settings entry, including with no status
        // icon. Login launches stay quiet once the necessary permissions are granted.
        if !backgroundLaunch || needsPermissions { showHelp() }
    }

    func applicationDidBecomeActive(_ notification: Notification) { refreshPermissions() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHelp()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        if let languageObserver { NotificationCenter.default.removeObserver(languageObserver) }
        service.stop()
    }

    private func refreshPermissions() {
        loginItem.refresh()
        service.configure(previewsEnabled: preferences.previewEnabled, clickEnabled: preferences.clickEnabled, switcherEnabled: preferences.switcherEnabled)
        preferences.accessibilityGranted = AXIsProcessTrusted()
        preferences.captureGranted = CGPreflightScreenCaptureAccess()
        updateStatus()
    }

    private func updateStatus() {
        previewItem?.title = L("悬停预览")
        clickItem?.title = L("点击收起 / 恢复")
        switcherItem?.title = L("Command+Tab 增强")
        for item in statusItem?.menu?.items ?? [] {
            if item.action == #selector(showHelp) { item.title = L("设置…") }
            if item.action == #selector(checkForUpdates) { item.title = L("检查更新…") }
            if item.action == #selector(quit) { item.title = L("退出 Dock Enhanced") }
        }
        preferences.switcherAvailable = service.switcherAvailable
        preferences.switcherUnavailableReason = service.switcherUnavailableReason
        preferences.running = service.running
        stateItem?.title = "Dock Enhanced · " + preferences.serviceStatus
        previewItem?.state = preferences.previewEnabled ? .on : .off
        clickItem?.state = preferences.clickEnabled ? .on : .off
        switcherItem?.state = preferences.switcherEnabled ? .on : .off
    }

    @objc private func togglePreview() { preferences.previewEnabled.toggle() }
    @objc private func toggleSwitcher() { preferences.switcherEnabled.toggle() }
    @objc private func toggleClick() { preferences.clickEnabled.toggle() }

    @objc private func checkForUpdates() { updates.checkNow() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func showHelp() {
        if let helpWindow { helpWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshPermissions(); return }
        let height = min(560, (NSScreen.main?.visibleFrame.height ?? 624) - 64)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: height),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.contentMinSize = NSSize(width: 760, height: 500)
        window.title = L("Dock Enhanced · 设置")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: preferences, loginItem: loginItem, updates: updates,
            requestAccessibility: { [weak self] in self?.requestAccessibility() },
            requestCapture: { [weak self] in self?.requestCapture() }))
        helpWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refreshPermissions()
    }

    @objc private func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    @objc private func requestCapture() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }
}
