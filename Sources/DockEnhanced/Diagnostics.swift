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
            let size = index == 0 ? CGSize(width: 540, height: 360) : CGSize(width: 240, height: 420)
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 220 + index * 70, y: 250 + index * 45), size: size),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = index == 0 ? "" : "测试窗口 · 绿色"
            let view = NSView(frame: CGRect(origin: .zero, size: size))
            view.wantsLayer = true
            view.layer?.backgroundColor = (index == 0 ? NSColor.systemPurple : NSColor.systemTeal).cgColor
            let label = NSTextField(labelWithString: index == 0 ? "WINDOW A" : "WINDOW B")
            label.font = .systemFont(ofSize: index == 0 ? 42 : 28, weight: .bold)
            label.textColor = .white
            label.alignment = .center
            label.frame = CGRect(x: 0, y: (size.height - 70) / 2, width: size.width, height: 70)
            view.addSubview(label)
            window.contentView = view
            window.isReleasedWhenClosed = false
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        let helper = NSPanel(contentRect: windows[0].frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        helper.isOpaque = false
        helper.backgroundColor = .clear
        helper.alphaValue = 0
        helper.ignoresMouseEvents = true
        helper.isReleasedWhenClosed = false
        helper.orderFront(nil)
        windows.append(helper)
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class NativeIntegrationCheck {
    let service: DockService
    let fixtureURL: URL

    init(service: DockService, fixtureURL: URL) { self.service = service; self.fixtureURL = fixtureURL }

    func run() {
        Task { @MainActor in
            let foreground = NSWorkspace.shared.frontmostApplication
            let previousApp = foreground?.bundleIdentifier == "dev.yifeng.DockEnhancedFixture"
                ? NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.finder" }
                : foreground
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
                let raw: [AXUIElement] = AX.value(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute) ?? []
                print("DIAGNOSTIC: fixture raw windows=\(raw.count), subroles=\(raw.map { (AX.value($0, kAXSubroleAttribute) as String?) ?? "?" })")
                try require(raw.count == 3, "fixture exposes an internal auxiliary window alongside two real windows")
                let windows = service.controller.windows(of: app)
                try require(windows.count == 2, "two real windows are exposed through Accessibility")
                try require(windows.contains { (AX.value($0.element, kAXTitleAttribute) as String?) == "" },
                            "a real untitled standard window remains available")
                move(to: center(windows[0].frame))
                click(at: center(windows[0].frame))
                let madeFrontmost = service.controller.reveal(windows[0], app: app)
                await pause(0.5)
                let axFrontmost: Bool = AX.value(AXUIElementCreateApplication(app.processIdentifier), kAXFrontmostAttribute) ?? false
                print("DIAGNOSTIC: activationAccepted=\(madeFrontmost), accessibleFrontmost=\(axFrontmost), workspaceFrontmost=\(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier)")
                fflush(stdout)
                try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier, "fixture is foreground before hovering")
                let point = try await hover(app)
                try require(service.locator.item(at: point)?.app.processIdentifier == app.processIdentifier, "Dock icon belongs to the fixture instance")
                try require(service.preview.isVisible && service.preview.windowKeys.count == 2, "hover shows both window previews")
                try require(windows.allSatisfy { service.images.cache[$0.key] != nil }, "both thumbnails contain captured window images")
                try require(windows.allSatisfy { window in
                    guard let image = service.images.cache[window.key] else { return false }
                    return abs(image.size.width / image.size.height - window.frame.width / window.frame.height) < 0.01
                }, "wide and portrait thumbnails preserve their window aspect ratios")
                try checkPreviewMargins(service.preview.panel)
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
                try await savePreview(service.preview.panel, path: "/tmp/dock-enhanced-preview.png")
                if let portrait = windows.first(where: { $0.frame.height > $0.frame.width }),
                   let item = service.locator.item(for: app) {
                    service.preview.hide(animated: false)
                    let single = PreviewPanel()
                    single.show(item: item, windows: [portrait], images: service.images)
                    try checkPreviewMargins(single.panel)
                    move(to: quartzPoint(CGPoint(x: single.panel.frame.midX, y: single.panel.frame.midY)))
                    await pause(0.3)
                    try await savePreview(single.panel, path: "/tmp/dock-enhanced-portrait-preview.png")
                    single.hide(animated: false)
                    _ = try await hover(app)
                }

                if let previousApp, previousApp.processIdentifier != app.processIdentifier,
                   previousApp.processIdentifier != getpid() {
                    _ = AX.set(AXUIElementCreateApplication(previousApp.processIdentifier), kAXFrontmostAttribute, true)
                    previousApp.activate(options: [])
                    await pause(0.5)
                    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp.processIdentifier,
                                "another application is foreground before preview selection")
                    _ = try await hover(app)
                }

                guard let target = service.preview.windowKeys.dropFirst().first else { throw failure("preview closed before selection") }
                var selectedKey: WindowKey?
                let originalSelection = service.preview.onSelect
                service.preview.onSelect = { window, selectedApp in
                    selectedKey = window.key
                    originalSelection?(window, selectedApp)
                }
                let panel = service.preview.panel.frame
                let clickInPanel = CGPoint(x: panel.minX + 12 + 244 + 117, y: panel.minY + 100)
                click(at: quartzPoint(clickInPanel))
                await pause(0.5)
                let owner = AXUIElementCreateApplication(app.processIdentifier)
                let focused: AXUIElement? = AX.value(owner, kAXFocusedWindowAttribute)
                try require(selectedKey == target, "the clicked preview selects its displayed window")
                try require(focused.map { service.controller.windowKey(for: $0, pid: app.processIdentifier) } == target, "clicking a preview focuses its exact window")
                var stayedFrontmost = true
                for _ in 0..<10 {
                    stayedFrontmost = stayedFrontmost && NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
                    await pause(0.1)
                }
                try require(stayedFrontmost, "selected application stays foreground after preview dismissal")

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
                if let previousApp, previousApp.processIdentifier != app.processIdentifier,
                   let restoring = afterKeyboard.first {
                    _ = AX.set(AXUIElementCreateApplication(previousApp.processIdentifier), kAXFrontmostAttribute, true)
                    previousApp.activate(options: [])
                    await pause(0.5)
                    try require(service.controller.reveal(restoring, app: app), "minimized-window restoration is accepted")
                    service.controller.userChangedWindow()
                    await pause(1.5)
                    try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp.processIdentifier,
                                "new user activity cancels deferred foreground activation")
                    if service.locator.item(for: previousApp) != nil {
                        let original = service.controller.windows(of: previousApp)
                        _ = AX.set(restoring.element, kAXMinimizedAttribute, true)
                        await pause(0.6)
                        try require(service.controller.reveal(restoring, app: app), "another minimized restore is accepted before a new Dock press")
                        guard let current = service.locator.item(for: previousApp) else { throw failure("source Dock icon disappeared") }
                        let point = center(current.frame)
                        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)!
                        let intercepted = service.handle(type: .leftMouseDown, event: down) == nil
                        await pause(1.5)
                        let keptForeground = NSWorkspace.shared.frontmostApplication?.processIdentifier == previousApp.processIdentifier
                        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)!
                        _ = service.handle(type: .leftMouseUp, event: up)
                        await pause(0.6)
                        for window in original where !window.state.minimized {
                            _ = service.controller.reveal(window, app: previousApp)
                        }
                        await pause(1.5)
                        try require(intercepted && keptForeground, "a held intercepted Dock press cancels earlier deferred activation immediately")
                    }
                }
                try await checkFeatureSwitches(app)
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

    @MainActor private func checkFeatureSwitches(_ app: NSRunningApplication) async throws {
        for window in service.controller.windows(of: app) { _ = AX.set(window.element, kAXMinimizedAttribute, false) }
        await pause(0.8)
        guard let window = service.controller.windows(of: app).first else { throw failure("fixture window disappeared") }
        _ = service.controller.reveal(window, app: app)
        await pause(0.5)

        service.configure(previewsEnabled: true, clickEnabled: false, switcherEnabled: false)
        _ = try await hover(app)
        try require(service.preview.isVisible, "previews work with click control disabled")
        try await dockClick(app)
        await pause(0.7)
        try require(service.controller.windows(of: app).allSatisfy { !$0.state.minimized },
                    "Dock click retains native behavior when click control is disabled")
        _ = try await hover(app)
        guard let selected = service.preview.windowKeys.first else { throw failure("preview-only mode has no selectable windows") }
        let panel = service.preview.panel.frame
        click(at: quartzPoint(CGPoint(x: panel.minX + 12 + 117, y: panel.minY + 100)))
        await pause(0.7)
        let focused: AXUIElement? = AX.value(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedWindowAttribute)
        try require(focused.map { service.controller.windowKey(for: $0, pid: app.processIdentifier) } == selected, "preview selection works with click control disabled")

        service.configure(previewsEnabled: false, clickEnabled: true, switcherEnabled: false)
        try require(!service.preview.isVisible && service.images.cache.isEmpty, "turning previews off dismisses the panel and clears thumbnails")
        move(to: center(window.frame))
        await pause(0.4)
        guard let item = service.locator.item(for: app) else { throw failure("fixture Dock icon disappeared") }
        move(to: center(item.frame))
        await pause(1.7)
        try require(!service.preview.isVisible && service.images.cache.isEmpty, "hovering with previews off does not show or capture thumbnails")
        try await dockClick(app)
        await pause(0.7)
        try require(service.controller.windows(of: app).filter(\.state.minimized).count == 1,
                    "click control minimizes a window with previews disabled")
        try await dockClick(app)
        await pause(0.8)
        try require(service.controller.windows(of: app).allSatisfy { !$0.state.minimized },
                    "click control restores a window with previews disabled")

        service.configure(previewsEnabled: false, clickEnabled: false, switcherEnabled: false)
        try require(!service.running && !service.preview.isVisible && service.images.cache.isEmpty, "both features off stops the service")
        try await dockClick(app)
        await pause(0.5)
        try require(service.controller.windows(of: app).allSatisfy { !$0.state.minimized }, "both features off leaves native Dock behavior intact")
        service.configure(previewsEnabled: true, clickEnabled: true, switcherEnabled: false)
        _ = try await hover(app)
        try require(service.running && service.preview.isVisible, "enabling both features restarts previews and click handling")
    }

    @MainActor private func savePreview(_ panel: NSPanel, path: String) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        let panelFrame = panel.frame
        let captureFrame = CGRect(origin: quartzPoint(CGPoint(x: panelFrame.minX, y: panelFrame.maxY)), size: panelFrame.size)
        guard let display = content.displays.first(where: { $0.frame.contains(CGPoint(x: captureFrame.midX, y: captureFrame.midY)) }) else { return }
        let config = SCStreamConfiguration()
        config.width = Int(panelFrame.width * 2)
        config.height = Int(panelFrame.height * 2)
        config.sourceRect = captureFrame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
        config.showsCursor = false
        // Capture only the displayed panel bounds so native glass includes its actual
        // composited backdrop; isolated-window captures flatten the glass to gray.
        let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    private func checkPreviewMargins(_ panel: NSPanel) throws {
        guard let content = panel.contentView else { throw failure("missing preview content") }
        func cards(in view: NSView) -> [PreviewCard] {
            view.subviews.flatMap { child in
                if let card = child as? PreviewCard { return [card] }
                return cards(in: child)
            }
        }
        let frames = cards(in: content).map { $0.convert($0.bounds, to: content) }
        guard let left = frames.map(\.minX).min(), let right = frames.map(\.maxX).max() else { throw failure("missing preview cards") }
        try require(abs(left - (content.bounds.width - right)) < 0.5, "preview cards have equal left and right outer margins (\(frames.count) windows)")
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
        move(to: point)
        for type: CGEventType in [.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.flags = []
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            event?.post(tap: .cghidEventTap)
        }
    }
}
#endif
