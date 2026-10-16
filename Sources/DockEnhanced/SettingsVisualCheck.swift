#if DEBUG
import AppKit
import SwiftUI

/// Actual settings UI with an isolated preference domain. No control service,
/// permission prompt, image consumer or login-item mutation is started.
final class SettingsVisualCheck: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let previous = NSWorkspace.shared.frontmostApplication
            let controller = WindowController()
            let previousWindow = previous.flatMap { controller.focusedWindow(of: $0, in: controller.windows(of: $0)) }
            let pointer = NSEvent.mouseLocation
            let suite = "dev.yifeng.DockEnhanced.settings-visual." + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            NSApp.applicationIconImage = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/assets/AppIcon.icns")
            let model = SettingsModel(defaults: defaults)
            model.accessibilityGranted = true
            model.captureGranted = false
            model.running = true
            model.switcherAvailable = true
            let backdrop = controlledBackdrop()
            windows.append(backdrop)
            var result: Int32 = 0
            do {
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Dock Enhanced · 设置（受控检查）"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: SettingsView(model: model, loginItem: LoginItem(), requestAccessibility: {}, requestCapture: {}))
                window.center(); window.makeKeyAndOrderFront(nil)
                windows.append(window)
                NSApp.activate(ignoringOtherApps: true)
                await pause(0.4)
                try saveControlledCompositor(window, name: "settings-dock-light")
                click(window: window, x: 88, fromTop: 131)
                await pause(0.4)
                try saveControlledCompositor(window, name: "settings-switcher-light")
                click(window: window, x: 710, fromTop: 129)
                await pause(0.2)
                try require(!model.switcherEnabled && !SettingsModel(defaults: defaults).switcherEnabled, "actual settings toggle disables enhancement and persists in an isolated domain")
                click(window: window, x: 710, fromTop: 129)
                await pause(0.2)
                try require(model.switcherEnabled && model.switcherStatus.contains("图标和标题"), "actual settings toggle restores icon/title switching with capture unavailable")
                window.appearance = NSAppearance(named: .darkAqua)
                await pause(0.3)
                try saveControlledCompositor(window, name: "settings-switcher-dark")
                click(window: window, x: 88, fromTop: 171)
                await pause(0.3)
                try saveControlledCompositor(window, name: "settings-general-dark")
                window.close(); window.makeKeyAndOrderFront(nil)
                await pause(0.2)
                try require(window.isVisible && model.switcherEnabled, "settings window reopens with its saved feature choice")
                print("PASS: actual settings UI checks; no login registration or real permission change")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            for window in windows { window.orderOut(nil) }
            defaults.removePersistentDomain(forName: suite)
            CGWarpMouseCursorPosition(quartzPoint(pointer))
            if let previous, let previousWindow { _ = controller.reveal(previousWindow, app: previous) }
            else { previous?.activate(options: []) }
            await pause(0.3)
            exit(result)
        }
    }
    private func click(window: NSWindow, x: CGFloat, fromTop: CGFloat) {
        let point = window.convertPoint(toScreen: CGPoint(x: x, y: window.contentView!.bounds.height - fromTop))
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: quartzPoint(point), mouseButton: .left)?.post(tap: .cghidEventTap)
        }
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func require(_ condition: Bool, _ text: String) throws {
        guard condition else { throw NSError(domain: "SettingsVisualCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
        print("PASS: \(text)")
    }
}

func controlledBackdrop() -> NSWindow {
    let window = NSWindow(contentRect: NSScreen.main!.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.backgroundColor = NSColor(calibratedRed: 0.18, green: 0.23, blue: 0.29, alpha: 1)
    window.isReleasedWhenClosed = false
    window.ignoresMouseEvents = true
    window.orderFrontRegardless()
    return window
}

func saveControlledCompositor(_ window: NSWindow, name: String) throws {
    guard CGPreflightScreenCaptureAccess() else { print("UNAVAILABLE: compositor screenshot requires existing Screen Recording access"); return }
    let rect = CGRect(x: window.frame.minX - 8, y: (NSScreen.screens.first?.frame.maxY ?? 0) - window.frame.maxY - 8, width: window.frame.width + 16, height: window.frame.height + 16)
    guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/images")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("command-tab-05-" + name + ".png")
    try data.write(to: url)
    print("SCREENSHOT: \(url.path)")
}
#endif
