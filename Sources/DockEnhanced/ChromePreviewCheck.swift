#if DEBUG
import AppKit

final class ChromePreviewCheck: NSObject, NSApplicationDelegate {
    private let images = PreviewImages()
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Task { @MainActor in
            guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess(),
                  let chrome = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) else {
                print("CHECK unavailable: Chrome and current-process permissions are required")
                exit(2)
            }
            let windows = WindowController().windows(of: chrome).filter { !$0.state.minimized }
            guard !windows.isEmpty else { print("CHECK unavailable: no visible Chrome windows"); exit(2) }
            self.images.refresh(windows)
            for _ in 0..<60 {
                if windows.allSatisfy({ self.images.cache[$0.key] != nil }) { break }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            let captured = windows.filter { self.images.cache[$0.key] != nil }.count
            print("Chrome thumbnail check: \(captured)/\(windows.count) actual images")
            exit(captured == windows.count ? 0 : 1)
        }
    }
}
#endif
