#if DEBUG
import AppKit
import DockCore
import QuartzCore

/// Real fixture-window thumbnails and compositor output, with an opaque controlled
/// desktop underneath. This check creates no event tap or persisted setting.
final class WindowSwitcherVisualCheck: NSObject, NSApplicationDelegate {
    private let urls: [URL]
    init(urls: [URL]) { self.urls = urls }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            let controller = WindowController()
            let previous = NSWorkspace.shared.frontmostApplication
            let previousWindow = previous.flatMap { controller.focusedWindow(of: $0, in: controller.windows(of: $0)) }
            let glassComparison = CommandLine.arguments.contains("--glass")
            let backdrop = controlledBackdrop()
            if glassComparison {
                // Keep all user windows beneath an opaque, known color pattern.
                // Fixture thumbnails use desktop-independent capture underneath it.
                backdrop.level = .floating
                let pattern = NSView(frame: backdrop.contentView!.bounds)
                pattern.wantsLayer = true
                let gradient = CAGradientLayer()
                gradient.frame = pattern.bounds
                gradient.colors = [NSColor(calibratedRed: 0.20, green: 0.35, blue: 0.47, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 0.65, green: 0.40, blue: 0.46, alpha: 1).cgColor,
                                   NSColor(calibratedRed: 0.38, green: 0.45, blue: 0.36, alpha: 1).cgColor]
                gradient.startPoint = CGPoint(x: 0, y: 0)
                gradient.endPoint = CGPoint(x: 1, y: 1)
                pattern.layer?.addSublayer(gradient)
                for index in 0..<9 {
                    let band = CALayer()
                    band.frame = CGRect(x: CGFloat(index) * pattern.bounds.width / 9, y: pattern.bounds.height * 0.22,
                                        width: pattern.bounds.width / 18, height: pattern.bounds.height * 0.56)
                    band.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
                    pattern.layer?.addSublayer(band)
                }
                backdrop.contentView = pattern
                backdrop.orderFrontRegardless()
            }
            let panel = WindowSwitcherPanel()
            let preview = PreviewPanel()
            let images = PreviewImages()
            let evidencePrefix = glassComparison ? "macos27-" : "command-tab-05-"
            var apps: [NSRunningApplication] = []
            var result: Int32 = 0
            do {
                guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else { print("UNAVAILABLE: actual fixture thumbnails need existing AX/capture access"); exit(2) }
                for url in urls {
                    let config = NSWorkspace.OpenConfiguration()
                    config.arguments = ["--interaction-fixture"]
                    config.createsNewApplicationInstance = true
                    apps.append(try await NSWorkspace.shared.openApplication(at: url, configuration: config))
                }
                await pause(0.8)
                let inventory = {
                    apps.flatMap { app in controller.windows(of: app).map { SwitcherCandidate(window: $0, app: app) } }.sorted {
                        let left = $0.window.frame.width < 400 ? 0 : $0.window.frame.width < 1000 ? 1 : 2
                        let right = $1.window.frame.width < 400 ? 0 : $1.window.frame.width < 1000 ? 1 : 2
                        return (left, $0.id.pid, $0.id.id) < (right, $1.id.pid, $1.id.id)
                    }
                }
                var candidates = inventory()
                let inventoryDeadline = ProcessInfo.processInfo.systemUptime + 4
                while candidates.count != 40, ProcessInfo.processInfo.systemUptime < inventoryDeadline {
                    await pause(0.1)
                    candidates = inventory()
                }
                guard candidates.count == 40 else {
                    throw NSError(domain: "VisualCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "controlled inventory contains \(candidates.count) windows, expected 40"])
                }
                await images.refresh(Array(candidates.prefix(12)).map(\.window))?.value
                guard images.cache.count >= 8 else { throw NSError(domain: "VisualCheck", code: 2, userInfo: [NSLocalizedDescriptionKey: "real thumbnail capture did not produce at least eight fixture images"]) }
                print("PASS: \(images.cache.count) actual controlled thumbnails ready before visual inspection")
                // Preserve an actual last image, then minimize the exact fixture.
                _ = AX.set(candidates[1].window.element, kAXMinimizedAttribute, true)
                await pause(0.6)
                candidates = inventory()
                for candidate in candidates { panel.updatePreviewImage(images.cache[candidate.window.key], for: candidate.id) }
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    panel.panel.appearance = NSAppearance(named: appearance)
                    panel.show(candidates: candidates, selected: candidates[1].id, screen: NSScreen.main)
                    await pause(0.35)
                    try saveControlledCompositor(panel.panel, name: appearance == .aqua ? "grid-light" : "grid-dark", prefix: evidencePrefix)
                    panel.hide()
                    if glassComparison, let screen = NSScreen.main {
                        let app = candidates[0].app
                        let windows = Array(candidates.filter { $0.id.pid == app.processIdentifier }.prefix(2)).map(\.window)
                        let anchor = quartzPoint(CGPoint(x: screen.frame.midX - 24, y: screen.frame.minY + 72))
                        preview.panel.appearance = NSAppearance(named: appearance)
                        preview.show(item: DockItem(app: app, frame: CGRect(origin: anchor, size: CGSize(width: 48, height: 48))), windows: windows, images: images)
                        await pause(0.3)
                        try saveControlledCompositor(preview.panel, name: appearance == .aqua ? "dock-preview-light" : "dock-preview-dark", prefix: evidencePrefix)
                        preview.hide(animated: false)
                    }
                }
                panel.show(candidates: candidates, selected: candidates.last!.id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "grid-scrolled", prefix: evidencePrefix)
                panel.hide()
                panel.panel.appearance = NSAppearance(named: .aqua)
                panel.show(candidates: Array(candidates.prefix(4)), selected: candidates[1].id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "row", prefix: evidencePrefix)
                panel.hide()
                panel.show(candidates: [candidates[0]], selected: candidates[0].id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "single", prefix: evidencePrefix)
                panel.hide()
                if glassComparison, let screen = NSScreen.main {
                    try saveControlledCompositor(backdrop, name: "native-dock", prefix: evidencePrefix,
                                                 crop: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 180))
                    try await captureNativeSwitcher(backdrop: backdrop, prefix: evidencePrefix, screen: screen)
                }
                print("ENVIRONMENT: display scale=\(NSScreen.main?.backingScaleFactor ?? 0), reducedMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
                print("PASS: actual light/dark/grid/scroll/row/single compositor screenshots saved")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            panel.hide(); preview.hide(animated: false); images.clear()
            for app in apps { app.terminate() }
            backdrop.orderOut(nil)
            if let previous, let previousWindow { _ = controller.reveal(previousWindow, app: previous) }
            else { previous?.activate(options: []) }
            await pause(0.3)
            exit(result)
        }
    }
    private func captureNativeSwitcher(backdrop: NSWindow, prefix: String, screen: NSScreen) async throws {
        guard CGPreflightPostEventAccess(), !NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleIdentifier == "dev.yifeng.DockEnhanced" && $0.processIdentifier != getpid()
        }) else { print("UNAVAILABLE: native switcher reference requires input access and the installed enhancement stopped"); return }
        func command(_ down: Bool) {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 55, keyDown: down)!
            event.type = .flagsChanged
            event.flags = down ? .maskCommand : []
            event.post(tap: .cghidEventTap)
        }
        func key(_ code: CGKeyCode) {
            for down in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
                event.flags = .maskCommand
                event.post(tap: .cghidEventTap)
            }
        }
        command(true)
        key(48)
        defer { key(53); command(false) }
        await pause(0.3)
        try saveControlledCompositor(backdrop, name: "native-command-tab", prefix: prefix,
                                     crop: CGRect(x: screen.frame.minX, y: screen.frame.midY - 180, width: screen.frame.width, height: 360))
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
}
#endif
