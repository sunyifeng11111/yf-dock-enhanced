#if DEBUG
import AppKit
import ScreenCaptureKit
import DockCore

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出测试窗口", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApp.mainMenu = menu
        for index in 0..<2 {
            let window = NSWindow(contentRect: CGRect(x: 220 + index * 70, y: 250 + index * 45, width: 540, height: 360),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = index == 0 ? "测试窗口 · 紫色" : "测试窗口 · 绿色"
            let view = NSView(frame: CGRect(x: 0, y: 0, width: 540, height: 360))
            view.wantsLayer = true
            view.layer?.backgroundColor = (index == 0 ? NSColor.systemPurple : NSColor.systemTeal).cgColor
            let label = NSTextField(labelWithString: index == 0 ? "WINDOW A" : "WINDOW B")
            label.font = .systemFont(ofSize: 42, weight: .bold)
            label.textColor = .white
            label.frame = CGRect(x: 120, y: 150, width: 330, height: 70)
            view.addSubview(label)
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class NativeIntegrationCheck {
    let service: DockService
    let fixtureURL: URL

    init(service: DockService, fixtureURL: URL) { self.service = service; self.fixtureURL = fixtureURL }

    func run() {
        Task { @MainActor in
            let previousApp = NSWorkspace.shared.frontmostApplication
            let previousPointer = quartzPoint(NSEvent.mouseLocation)
            var fixture: NSRunningApplication?
            var result: Int32 = 0
            do {
                try require(service.running, "event tap is active")
                try require(CGPreflightScreenCaptureAccess(), "screen capture is authorized")
                for oldFixture in NSWorkspace.shared.runningApplications where oldFixture.bundleIdentifier == "dev.yifeng.DockEnhancedFixture" {
                    oldFixture.terminate()
                }
                await pause(0.6)
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = ["--fixture"]
                configuration.createsNewApplicationInstance = true
                configuration.activates = true
                fixture = try await NSWorkspace.shared.openApplication(at: fixtureURL, configuration: configuration)
                await pause(1.5)
                guard let app = fixture else { throw failure("fixture failed to launch") }
                let windows = service.controller.windows(of: app)
                try require(windows.count == 2, "two real windows are exposed through Accessibility")
                move(to: center(windows[0].frame))
                click(at: center(windows[0].frame))
                _ = AX.set(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute, true)
                await pause(0.5)
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "fixture is foreground before hovering")
                guard let initialItem = service.locator.item(for: app) else { throw failure("fixture Dock icon not found") }
                move(to: center(initialItem.frame))
                await pause(1.5)
                guard let item = service.locator.item(for: app) else { throw failure("Dock icon disappeared") }
                let point = center(item.frame)
                move(to: point)
                await pause(1)
                try require(service.locator.item(at: point)?.app.processIdentifier == app.processIdentifier, "Dock icon belongs to the fixture instance")
                try require(service.preview.isVisible && service.preview.windowKeys.count == 2, "hover shows both window previews")
                try require(windows.allSatisfy { service.images.cache[$0.key] != nil }, "both thumbnails contain captured window images")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "hover does not steal keyboard focus")
                try await savePreview()

                let target = service.preview.windowKeys[1]
                let panel = service.preview.panel.frame
                let clickInPanel = CGPoint(x: panel.minX + 12 + 244 + 117, y: panel.minY + 100)
                click(at: quartzPoint(clickInPanel))
                await pause(0.5)
                let owner = AXUIElementCreateApplication(app.processIdentifier)
                let focused: AXUIElement? = AX.value(owner, kAXFocusedWindowAttribute)
                try require(focused.map { Int(CFHash($0)) } == target.id, "clicking a preview focuses its exact window")

                move(to: point)
                await pause(0.5)
                click(at: point)
                await pause(0.7)
                let minimized = service.controller.windows(of: app)
                try require(minimized.filter(\.state.minimized).map(\.key) == [target], "Dock click minimizes only the selected recent window")
                try require(service.preview.isVisible && service.preview.windowKeys.contains(target) && service.images.cache[target] != nil,
                            "minimized window remains selectable with its cached preview")
                move(to: point)
                await pause(0.5)
                click(at: point)
                await pause(0.7)
                let restored = service.controller.windows(of: app)
                try require(restored.count == 2 && restored.allSatisfy { !$0.state.minimized }, "next Dock click restores the same window")
                print("PASS: native integration checks complete; preview image: /tmp/dock-enhanced-preview.png")
            } catch {
                print("FAIL: \(error.localizedDescription)")
                result = 1
            }
            service.stop()
            fixture?.terminate()
            previousApp?.activate(options: [])
            move(to: previousPointer)
            exit(result)
        }
    }

    @MainActor private func savePreview() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.windowID == CGWindowID(service.preview.panel.windowNumber) }) else { return }
        let config = SCStreamConfiguration()
        config.width = Int(service.preview.panel.frame.width * 2)
        config.height = Int(service.preview.panel.frame.height * 2)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/dock-enhanced-preview.png"))
    }

    private func require(_ condition: Bool, _ text: String) throws {
        guard condition else { throw failure(text) }
        print("PASS: \(text)")
    }
    private func failure(_ text: String) -> NSError { NSError(domain: "DockIntegration", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
    private func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    private func quartzPoint(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y) }
    private func move(to point: CGPoint) {
        CGWarpMouseCursorPosition(point)
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    private func click(at point: CGPoint) {
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }
    }
}
#endif
