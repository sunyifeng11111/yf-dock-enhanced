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
                let madeFrontmost = AX.set(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute, true)
                await pause(0.5)
                let axFrontmost: Bool = AX.value(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute) ?? false
                print("DIAGNOSTIC: activationAccepted=\(madeFrontmost), accessibleFrontmost=\(axFrontmost), workspaceFrontmost=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier)")
                fflush(stdout)
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "fixture is foreground before hovering")
                let point = try await hover(app)
                try require(service.locator.item(at: point)?.app.processIdentifier == app.processIdentifier, "Dock icon belongs to the fixture instance")
                try require(service.preview.isVisible && service.preview.windowKeys.count == 2, "hover shows both window previews")
                try require(windows.allSatisfy { service.images.cache[$0.key] != nil }, "both thumbnails contain captured window images")
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "hover does not steal keyboard focus")
                if let rightDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
                    _ = service.handle(type: .rightMouseDown, event: rightDown)
                    try require(!service.preview.isVisible, "right click hides a visible preview immediately")
                    await pause(1)
                    try require(!service.preview.isVisible, "holding right mouse button does not reopen the preview")
                    if let rightUp = CGEvent(mouseEventSource: nil, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right) {
                        _ = service.handle(type: .rightMouseUp, event: rightUp)
                    }
                    await pause(1)
                    try require(!service.preview.isVisible, "released right click stays suppressed until the pointer leaves the icon")
                    _ = try await hover(app)
                }
                if let rightDown = CGEvent(mouseEventSource: nil, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right) {
                    _ = service.handle(type: .rightMouseDown, event: rightDown)
                    // Model a release missed while the event tap was disabled. The physical
                    // buttons are up; recovery must retain click suppression but end the hold.
                    _ = service.handle(type: .tapDisabledByTimeout, event: rightDown)
                    _ = try await hover(app)
                    try require(service.preview.isVisible, "event-tap recovery restores hover after a missed button release")
                }
                for type: CGEventType in [.rightMouseDown, .rightMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .right)?.post(tap: .cghidEventTap)
                }
                await pause(0.6)
                try require(service.locator.hasOpenMenu(), "native Dock context menu is detected")
                move(to: center(windows[0].frame))
                await pause(0.3)
                move(to: point)
                for isDown in [true, false] {
                    CGEvent(keyboardEventSource: nil, virtualKey: 125, keyDown: isDown)?.post(tap: .cghidEventTap)
                }
                await pause(1.2)
                let menuRemainedOpen = service.locator.hasOpenMenu()
                let previewStayedHidden = !service.preview.isVisible
                for isDown in [true, false] {
                    CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: isDown)?.post(tap: .cghidEventTap)
                }
                await pause(0.5)
                try require(menuRemainedOpen && previewStayedHidden, "keyboard navigation in an open Dock menu keeps previews suppressed")
                _ = try await hover(app)
                try require(service.preview.isVisible, "hover resumes after the native Dock menu closes")
                let previewFrame = service.preview.panel.frame
                move(to: quartzPoint(CGPoint(x: previewFrame.minX + 12 + 244 + 117, y: previewFrame.minY + 100)))
                await pause(0.25)
                try await savePreview()

                guard let target = service.preview.windowKeys.dropFirst().first else { throw failure("preview closed before selection") }
                let panel = service.preview.panel.frame
                let clickInPanel = CGPoint(x: panel.minX + 12 + 244 + 117, y: panel.minY + 100)
                click(at: quartzPoint(clickInPanel))
                await pause(0.5)
                let owner = AXUIElementCreateApplication(app.processIdentifier)
                let focused: AXUIElement? = AX.value(owner, kAXFocusedWindowAttribute)
                try require(focused.map { Int(CFHash($0)) } == target.id, "clicking a preview focuses its exact window")

                try await dockClick(app)
                await pause(0.7)
                let minimized = service.controller.windows(of: app)
                try require(minimized.filter(\.state.minimized).map(\.key) == [target], "Dock click minimizes only the selected recent window")
                await pause(1)
                try require(!service.preview.isVisible, "minimize click does not reopen the preview while the pointer remains on the icon")
                _ = try await hover(app)
                try require(service.preview.isVisible && service.preview.windowKeys.contains(target) && service.images.cache[target] != nil,
                            "minimized window remains selectable with its cached preview")
                try await dockClick(app)
                await pause(0.7)
                let restored = service.controller.windows(of: app)
                try require(restored.count == 2 && restored.allSatisfy { !$0.state.minimized }, "next Dock click restores the same window")

                try await dockClick(app)
                await pause(0.5)
                for isDown in [true, false] {
                    let keyboard = CGEvent(keyboardEventSource: nil, virtualKey: 124, keyDown: isDown)
                    keyboard?.flags = []
                    keyboard?.post(tap: .cghidEventTap)
                }
                await pause(0.2)
                try await dockClick(app)
                await pause(0.5)
                let afterKeyboard = service.controller.windows(of: app)
                try require(afterKeyboard.count == 2 && afterKeyboard.allSatisfy(\.state.minimized),
                            "keyboard activity makes the next Dock click target the current window, not restore the previous one")
                print("PASS: native integration checks complete; preview image: /tmp/dock-enhanced-preview.png")
            } catch {
                print("FAIL: \(error.localizedDescription)")
                result = 1
            }
            service.stop()
            fixture?.terminate()
            if let previousApp {
                _ = AX.set(AXUIElementCreateApplication(previousApp.processIdentifier), kAXFrontmostAttribute, true)
                previousApp.activate(options: [])
            }
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
        fflush(stdout)
    }
    private func dockClick(_ app: NSRunningApplication) async throws {
        guard let item = service.locator.item(for: app) else { throw failure("fixture Dock icon not found") }
        move(to: center(item.frame))
        await pause(0.4)
        guard let current = service.locator.item(for: app) else { throw failure("fixture Dock icon disappeared") }
        let point = center(current.frame)
        move(to: point)
        click(at: point)
    }
    private func hover(_ app: NSRunningApplication) async throws -> CGPoint {
        if let window = service.controller.windows(of: app).first {
            move(to: center(window.frame))
            await pause(0.4)
        }
        var point = CGPoint.zero
        for _ in 0..<10 {
            guard let item = service.locator.item(for: app) else { throw failure("fixture Dock icon not found") }
            point = center(item.frame)
            move(to: point)
            await pause(0.5)
            if service.preview.isVisible && service.preview.windowKeys.count == 2 { break }
        }
        return point
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
