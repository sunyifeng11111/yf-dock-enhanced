#if DEBUG
import AppKit
import DockCore

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
            let backdrop = controlledBackdrop()
            let panel = WindowSwitcherPanel()
            let images = PreviewImages()
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
                guard candidates.count == 40 else { throw NSError(domain: "VisualCheck", code: 1) }
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
                    try saveControlledCompositor(panel.panel, name: appearance == .aqua ? "grid-light" : "grid-dark")
                    panel.hide()
                }
                panel.show(candidates: candidates, selected: candidates.last!.id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "grid-scrolled")
                panel.hide()
                panel.panel.appearance = NSAppearance(named: .aqua)
                panel.show(candidates: Array(candidates.prefix(4)), selected: candidates[1].id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "row")
                panel.hide()
                panel.show(candidates: [candidates[0]], selected: candidates[0].id, screen: NSScreen.main)
                await pause(0.3)
                try saveControlledCompositor(panel.panel, name: "single")
                panel.hide()
                print("ENVIRONMENT: display scale=\(NSScreen.main?.backingScaleFactor ?? 0), reducedMotion=\(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)")
                print("PASS: actual light/dark/grid/scroll/row/single compositor screenshots saved")
            } catch { print("FAIL: \(error.localizedDescription)"); result = 1 }
            panel.hide(); images.clear()
            for app in apps { app.terminate() }
            backdrop.orderOut(nil)
            if let previous, let previousWindow { _ = controller.reveal(previousWindow, app: previous) }
            else { previous?.activate(options: []) }
            await pause(0.3)
            exit(result)
        }
    }
    private func pause(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }
}
#endif
