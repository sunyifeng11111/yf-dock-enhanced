import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = DockService()
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var previewItem: NSMenuItem!
    private var clickItem: NSMenuItem!
    private var helpWindow: NSWindow?
    let preferences = SettingsModel()
    let loginItem = LoginItem()
    private var permissionTimer: Timer?

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
        previewItem = NSMenuItem(title: "悬停预览", action: #selector(togglePreview), keyEquivalent: "")
        previewItem.target = self
        menu.addItem(previewItem)
        clickItem = NSMenuItem(title: "点击收起 / 恢复", action: #selector(toggleClick), keyEquivalent: "")
        clickItem.target = self
        menu.addItem(clickItem)
        let help = NSMenuItem(title: "设置…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Dock Enhanced", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.isVisible = !preferences.hideMenuBarIcon
        preferences.onMenuBarVisibilityChange = { [weak self] hidden in self?.statusItem.isVisible = !hidden }
        service.onStatusChanged = { [weak self] in self?.updateStatus() }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--integration-check"), CommandLine.arguments.count > index + 1 {
            service.configure(previewsEnabled: true, clickEnabled: true)
            NativeIntegrationCheck(service: service, fixtureURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])).run()
            return
        }
        #endif
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        refreshPermissions()
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
        service.stop()
    }

    private func refreshPermissions() {
        loginItem.refresh()
        service.configure(previewsEnabled: preferences.previewEnabled, clickEnabled: preferences.clickEnabled)
        preferences.accessibilityGranted = AXIsProcessTrusted()
        preferences.captureGranted = CGPreflightScreenCaptureAccess()
        updateStatus()
    }

    private func updateStatus() {
        stateItem?.title = service.running ? "Dock Enhanced · 正在运行" : (preferences.anyFeatureEnabled ? "Dock Enhanced · 等待权限" : "Dock Enhanced · 已暂停")
        previewItem?.state = preferences.previewEnabled ? .on : .off
        clickItem?.state = preferences.clickEnabled ? .on : .off
        preferences.running = service.running
    }

    @objc private func togglePreview() { preferences.previewEnabled.toggle() }
    @objc private func toggleClick() { preferences.clickEnabled.toggle() }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func showHelp() {
        if let helpWindow { helpWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshPermissions(); return }
        let height = min(744, (NSScreen.main?.visibleFrame.height ?? 808) - 64)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 624, height: height),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Dock Enhanced · 设置"
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView(model: preferences, loginItem: loginItem,
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
