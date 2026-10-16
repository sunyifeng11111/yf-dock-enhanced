import AppKit
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = DockService()
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var helpWindow: NSWindow?
    let preferences = SettingsModel()
    let loginItem = LoginItem()
    private var permissionTimer: Timer?
    private var wantsEnabled: Bool { preferences.enabled }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        preferences.onEnabledChange = { [weak self] enabled in
            guard let self else { return }
            if enabled { self.refreshPermissions() } else { self.service.stop(); self.updateStatus() }
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Dock Enhanced")
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Dock Enhanced", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        toggleItem = NSMenuItem(title: "启用", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let help = NSMenuItem(title: "设置…", action: #selector(showHelp), keyEquivalent: "")
        help.target = self
        menu.addItem(help)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Dock Enhanced", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        service.onStatusChanged = { [weak self] in self?.updateStatus() }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshPermissions() }
        refreshPermissions()
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--integration-check"), CommandLine.arguments.count > index + 1 {
            NativeIntegrationCheck(service: service, fixtureURL: URL(fileURLWithPath: CommandLine.arguments[index + 1])).run()
            return
        }
        #endif
        if !AXIsProcessTrusted() || !CGPreflightScreenCaptureAccess() { showHelp() }
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
        if wantsEnabled && AXIsProcessTrusted() && !service.running { service.start() }
        preferences.accessibilityGranted = AXIsProcessTrusted()
        preferences.captureGranted = CGPreflightScreenCaptureAccess()
        updateStatus()
    }

    private func updateStatus() {
        stateItem?.title = service.running ? "Dock Enhanced · 正在运行" : (wantsEnabled ? "Dock Enhanced · 等待权限" : "Dock Enhanced · 已暂停")
        toggleItem?.state = wantsEnabled ? .on : .off
        preferences.running = service.running
    }

    @objc private func toggle() { preferences.enabled.toggle() }

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
