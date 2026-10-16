#if DEBUG
import AppKit
import DockCore

/// Real ScreenCaptureKit completion -> shared store -> visible switcher card.
/// Captures only this process's disposable window, without an event tap or prefs.
final class ThumbnailDeliveryCheck: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            guard CGPreflightScreenCaptureAccess() else {
                print("UNAVAILABLE: existing screen capture permission required")
                fflush(stdout)
                exit(2)
            }
            let fixture = NSWindow(contentRect: CGRect(x: 80, y: 160, width: 420, height: 280),
                                   styleMask: [.titled], backing: .buffered, defer: false)
            fixture.title = "Controlled thumbnail delivery"
            fixture.isReleasedWhenClosed = false
            fixture.contentView?.wantsLayer = true
            fixture.contentView?.layer?.backgroundColor = NSColor.systemTeal.cgColor
            fixture.orderFront(nil)
            try? await Task.sleep(nanoseconds: 100_000_000)
            let service = DockService()
            let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(fixture.windowNumber)) as? [[String: Any]])?.first
            guard let bounds = info?[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else {
                print("UNAVAILABLE: controlled fixture window geometry not reported")
                fflush(stdout)
                exit(2)
            }
            let window = AppWindow(element: AXUIElementCreateApplication(getpid()), key: WindowKey(pid: getpid(), id: 7001),
                                   title: fixture.title, frame: frame,
                                   state: WindowState(id: 7001, minimized: false, canMinimize: false, fullScreen: false))
            let candidate = SwitcherCandidate(window: window, app: .current)
            let deliverToViews = service.images.onUpdate
            var deliveries = 0
            service.images.onUpdate = { key in
                guard Thread.isMainThread else {
                    print("FAIL: actual screenshot completion reached switcher UI on a background thread")
                    fflush(stdout)
                    exit(1)
                }
                if key == window.key { deliveries += 1 }
                deliverToViews?(key)
            }
            let iterations = CommandLine.arguments.contains("--stress") ? 50 : 1
            var result: Int32 = 0
            for iteration in 1...iterations {
                service.switcher.panel.show(candidates: [candidate], selected: candidate.id, screen: NSScreen.main)
                service.switcher.panel.panel.contentView?.layoutSubtreeIfNeeded()
                await service.images.refresh([window])?.value
                guard deliveries == iteration, let image = service.images.cache[window.key],
                      Self.contains(image, in: service.switcher.panel.panel.contentView) else {
                    print("FAIL: real screenshot did not reach the visible switcher card")
                    result = 1
                    break
                }
                service.switcher.panel.hide()
                service.images.clear()
            }
            service.stop()
            fixture.close()
            if result == 0 { print("PASS: \(deliveries) actual screenshots updated visible cards on the main thread") }
            fflush(stdout)
            exit(result)
        }
    }

    private static func contains(_ image: NSImage, in view: NSView?) -> Bool {
        guard let view else { return false }
        if let imageView = view as? NSImageView, imageView.image === image { return true }
        return view.subviews.contains { contains(image, in: $0) }
    }
}
#endif
