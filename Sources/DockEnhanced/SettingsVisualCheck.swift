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
            let localization = Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
            let model = SettingsModel(defaults: defaults, localization: localization)
            model.accessibilityGranted = true
            model.captureGranted = false
            model.running = true
            model.switcherAvailable = true
            let backdrop = controlledBackdrop()
            windows.append(backdrop)
            var result: Int32 = 0
            do {
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
                window.title = "Dock Enhanced · 设置（受控检查）"
                SettingsWindowStyle.apply(to: window)
                window.appearance = NSAppearance(named: .aqua)
                window.contentMinSize = NSSize(width: 760, height: 500)
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: SettingsView(model: model, loginItem: LoginItem(), updates: ApplicationUpdates(defaults: defaults), requestAccessibility: {}, requestCapture: {}))
                window.center(); window.makeKeyAndOrderFront(nil)
                windows.append(window)
                NSApp.activate(ignoringOtherApps: true)
                await pause(0.4)
                try checkWindowButtons(window)
                try await checkDrag(window, x: 145, fromTop: 24)
                try await checkDrag(window, x: 650, fromTop: 32)
                window.standardWindowButton(.miniaturizeButton)?.performClick(nil)
                await pause(0.4)
                try require(window.isMiniaturized, "native yellow button still minimizes the integrated window")
                window.deminiaturize(nil)
                window.makeKeyAndOrderFront(nil)
                await pause(0.4)
                try saveControlledCompositor(window, name: "dock-light", prefix: "settings-ocean-")
                click(window: window, x: 710, fromTop: 158)
                await pause(0.2)
                try require(!model.previewEnabled && model.delay == 0.4, "hiding the preview delay retains its saved value")
                try saveControlledCompositor(window, name: "dock-preview-off", prefix: "settings-ocean-")
                click(window: window, x: 710, fromTop: 142)
                await pause(0.2)
                try require(model.previewEnabled && model.delay == 0.4, "preview re-enables with the same delay")
                click(window: window, x: 88, fromTop: 180)
                await pause(0.4)
                try saveControlledCompositor(window, name: "switcher-light", prefix: "settings-ocean-")
                click(window: window, x: 710, fromTop: 142)
                await pause(0.2)
                try require(!model.switcherEnabled && !SettingsModel(defaults: defaults).switcherEnabled, "actual settings toggle disables enhancement and persists in an isolated domain")
                click(window: window, x: 710, fromTop: 142)
                await pause(0.2)
                try require(model.switcherEnabled && model.switcherStatus == localization.text("增强可用 · 图标和标题可用（未授权屏幕录制）"), "actual settings toggle restores icon/title switching with capture unavailable")
                window.appearance = NSAppearance(named: .darkAqua)
                await pause(0.3)
                try saveControlledCompositor(window, name: "switcher-dark", prefix: "settings-ocean-")
                click(window: window, x: 88, fromTop: 228)
                await pause(0.3)
                try saveControlledCompositor(window, name: "general-dark", prefix: "settings-ocean-")
                window.appearance = NSAppearance(named: .aqua)
                await pause(0.3)
                try saveControlledCompositor(window, name: "general-light", prefix: "settings-ocean-")
                localization.language = .english
                await pause(0.3)
                try require(Localization(defaults: defaults, preferredLanguages: ["zh-Hans"]).language == .english,
                            "language choice persists in the isolated domain")
                try saveControlledCompositor(window, name: "general-en", prefix: "settings-ocean-")
                click(window: window, x: 88, fromTop: 180)
                await pause(0.3)
                try saveControlledCompositor(window, name: "switcher-en", prefix: "settings-ocean-")
                click(window: window, x: 88, fromTop: 136)
                await pause(0.3)
                try saveControlledCompositor(window, name: "dock-en", prefix: "settings-ocean-")
                window.setContentSize(NSSize(width: 760, height: 500))
                await pause(0.3)
                try saveControlledCompositor(window, name: "dock-en-minimum", prefix: "settings-ocean-")
                click(window: window, x: 88, fromTop: 228)
                await pause(0.3)
                try saveControlledCompositor(window, name: "general-en-minimum", prefix: "settings-ocean-")
                try scrollToBottom(window.contentView!)
                await pause(0.3)
                try saveControlledCompositor(window, name: "general-en-updates", prefix: "settings-ocean-")
                window.standardWindowButton(.closeButton)?.performClick(nil)
                await pause(0.2)
                try require(!window.isVisible, "native red button closes the integrated settings window")
                window.makeKeyAndOrderFront(nil)
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
    private func checkWindowButtons(_ window: NSWindow) throws {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(kind) else {
                try require(false, "native traffic light exists")
                return
            }
            let rect = button.convert(button.bounds, to: nil)
            try require(button.isEnabled && rect.maxX < 200 && rect.minY > window.frame.height - 48,
                        "native traffic light is enabled and contained in the sidebar header")
        }
    }
    @MainActor private func checkDrag(_ window: NSWindow, x: CGFloat, fromTop: CGFloat) async throws {
        let frame = window.frame
        let start = window.convertPoint(toScreen: CGPoint(x: x, y: window.contentView!.bounds.height - fromTop))
        let end = CGPoint(x: start.x + 40, y: start.y - 20)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint(start), mouseButton: .left)?.post(tap: .cghidEventTap)
        await pause(0.1)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseDragged, mouseCursorPosition: quartzPoint(end), mouseButton: .left)?.post(tap: .cghidEventTap)
        await pause(0.1)
        CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint(end), mouseButton: .left)?.post(tap: .cghidEventTap)
        await pause(0.2)
        let moved = abs(window.frame.minX - frame.minX) > 8
        window.setFrame(frame, display: true)
        try require(moved, "integrated header drags the window at x=\(x)")
    }
    private func scrollToBottom(_ view: NSView) throws {
        func findScrollView(_ candidate: NSView) -> NSScrollView? {
            if let scroll = candidate as? NSScrollView { return scroll }
            return candidate.subviews.lazy.compactMap { findScrollView($0) }.first
        }
        guard let scroll = findScrollView(view), let document = scroll.documentView else {
            throw NSError(domain: "SettingsVisualCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "Settings scroll view is unavailable"])
        }
        let y = document.isFlipped ? max(0, document.bounds.height - scroll.contentSize.height) : 0
        scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
        scroll.reflectScrolledClipView(scroll.contentView)
        try require(scroll.contentView.bounds.height < document.bounds.height, "minimum-height General scrolls to reach update controls")
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

func saveControlledCompositor(_ window: NSWindow, name: String, prefix: String = "command-tab-05-", crop: CGRect? = nil) throws {
    guard CGPreflightScreenCaptureAccess() else { print("UNAVAILABLE: compositor screenshot requires existing Screen Recording access"); return }
    let frame = crop ?? window.frame.insetBy(dx: -8, dy: -8)
    let rect = CGRect(x: frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - frame.maxY, width: frame.width, height: frame.height)
    guard let image = CGWindowListCreateImage(rect, .optionOnScreenOnly, kCGNullWindowID, [.bestResolution]),
          let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("docs/images")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(prefix + name + ".png")
    try data.write(to: url)
    print("SCREENSHOT: \(url.path)")
}
#endif
