import AppKit
import ScreenCaptureKit

final class PreviewImages {
    private(set) var cache: [WindowKey: NSImage] = [:]
    var onUpdate: (() -> Void)?
    private var busy = false
    private var order: [WindowKey] = []
    private var generation = 0

    func refresh(_ windows: [AppWindow]) {
        guard !busy, CGPreflightScreenCaptureAccess(), windows.contains(where: { !$0.state.minimized }) else { return }
        busy = true
        let requestedGeneration = generation
        Task { @MainActor in
            defer { self.busy = false }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                guard self.generation == requestedGeneration else { return }
                let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                let transparent = Set(windowInfo.compactMap { info -> CGWindowID? in
                    guard (info[kCGWindowAlpha as String] as? Double) == 0 else { return nil }
                    return info[kCGWindowNumber as String] as? CGWindowID
                })
                var used = Set<CGWindowID>()
                for window in windows where !window.state.minimized {
                    let candidates = content.windows.filter {
                        $0.owningApplication?.processID == window.key.pid && !used.contains($0.windowID) && !transparent.contains($0.windowID)
                    }
                    // Geometry plus title disambiguates identical browser titles. Never guess
                    // from title alone when more than one capture candidate matches.
                    let matches = candidates.filter {
                        abs($0.frame.minX - window.frame.minX) < 8 && abs($0.frame.minY - window.frame.minY) < 8 &&
                        abs($0.frame.width - window.frame.width) < 8 && abs($0.frame.height - window.frame.height) < 8
                    }
                    let exact = matches.filter { $0.title == window.title }
                    let appName = NSRunningApplication(processIdentifier: window.key.pid)?.localizedName ?? ""
                    let normalized = matches.filter {
                        !($0.title ?? "").isEmpty && normalizedTitle($0.title ?? "", appName: appName) == normalizedTitle(window.title, appName: appName)
                    }
                    guard let capturedWindow = exact.count == 1 ? exact.first :
                            (normalized.count == 1 ? normalized.first : (matches.count == 1 ? matches.first : nil)) else { continue }
                    used.insert(capturedWindow.windowID)
                    let filter = SCContentFilter(desktopIndependentWindow: capturedWindow)
                    let size = filter.contentRect.size
                    guard size.width > 0, size.height > 0 else { continue }
                    let scale = min(500 / size.width, 400 / size.height)
                    let configuration = SCStreamConfiguration()
                    // Fit both dimensions together. A fixed width with a capped height
                    // leaves a padded canvas around portrait windows in ScreenCaptureKit.
                    configuration.width = max(1, Int((size.width * scale).rounded()))
                    configuration.height = max(1, Int((size.height * scale).rounded()))
                    configuration.showsCursor = false
                    configuration.ignoreShadowsSingleWindow = true
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    guard self.generation == requestedGeneration else { return }
                    self.cache[window.key] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    self.order.removeAll { $0 == window.key }
                    self.order.append(window.key)
                    while self.order.count > 64 {
                        self.cache.removeValue(forKey: self.order.removeFirst())
                    }
                }
                self.onUpdate?()
            } catch {
                // Existing images and title/icon fallbacks remain usable on capture failure.
            }
        }
    }

    func clear() { generation += 1; cache.removeAll(); order.removeAll() }

    private func normalizedTitle(_ title: String, appName: String) -> String {
        var title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        for name in Set([appName, "Google Chrome", "Chrome", "Chromium"]) where !name.isEmpty {
            for separator in [" - ", " — ", " – "] {
                let suffix = separator + name
                if title.hasSuffix(suffix) { title = String(title.dropLast(suffix.count)) }
            }
        }
        return title.precomposedStringWithCanonicalMapping
    }
}
