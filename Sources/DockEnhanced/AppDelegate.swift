import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    let service = DockService()
    private var statusItem: NSStatusItem!
    private var stateItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var helpWindow: NSWindow?
    private var accessLabel: NSTextField?
    private var captureLabel: NSTextField?
    private var permissionTimer: Timer?
    private var wantsEnabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Dock Enhanced")
        let menu = NSMenu()
        stateItem = NSMenuItem(title: "Dock Enhanced", action: nil, keyEquivalent: "")
        menu.addItem(stateItem)
        toggleItem = NSMenuItem(title: "启用", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)
        let help = NSMenuItem(title: "权限与帮助…", action: #selector(showHelp), keyEquivalent: "")
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

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        service.stop()
    }

    private func refreshPermissions() {
        if wantsEnabled && AXIsProcessTrusted() && !service.running { service.start() }
        accessLabel?.stringValue = AXIsProcessTrusted() ? "辅助功能：已授权" : "辅助功能：未授权（用于操作窗口）"
        captureLabel?.stringValue = CGPreflightScreenCaptureAccess() ? "屏幕录制：已授权" : "屏幕录制：未授权（用于窗口缩略图）"
        updateStatus()
    }

    private func updateStatus() {
        stateItem?.title = service.running ? "Dock Enhanced · 正在运行" : (wantsEnabled ? "Dock Enhanced · 等待权限" : "Dock Enhanced · 已暂停")
        toggleItem?.state = wantsEnabled ? .on : .off
    }

    @objc private func toggle() {
        wantsEnabled.toggle()
        UserDefaults.standard.set(wantsEnabled, forKey: "enabled")
        if wantsEnabled { refreshPermissions() } else { service.stop(); updateStatus() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc func showHelp() {
        if let helpWindow { helpWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refreshPermissions(); return }
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 490, height: 350),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Dock Enhanced"
        window.isReleasedWhenClosed = false
        window.center()
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 490, height: 350))
        func label(_ text: String, y: CGFloat, height: CGFloat = 20, size: CGFloat = 13) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size)
            field.frame = CGRect(x: 28, y: y, width: 434, height: height)
            content.addSubview(field)
            return field
        }
        let title = label("让 Dock 更顺手", y: 288, height: 32, size: 24)
        title.font = .systemFont(ofSize: 24, weight: .semibold)
        _ = label("点击图标收起或恢复窗口，悬停预览，点击缩略图切换。", y: 247, height: 38)
        accessLabel = label("", y: 214)
        captureLabel = label("", y: 148)
        func button(_ title: String, y: CGFloat, action: Selector) {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded
            button.frame = CGRect(x: 26, y: y, width: 190, height: 30)
            content.addSubview(button)
        }
        button("授权辅助功能", y: 177, action: #selector(requestAccessibility))
        button("授权屏幕录制", y: 111, action: #selector(requestCapture))
        let note = label("最小化的窗口显示缓存画面；没有缓存时显示图标与标题。\n授权后若缩略图仍不可用，请退出并重新打开应用。", y: 36, height: 52, size: 11)
        note.textColor = .secondaryLabelColor
        window.contentView = content
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
