import AppKit
import ScreenCaptureKit

/// Shared, memory-only image delivery for Dock hover and the window switcher.
/// The injectable boundary is the operating system's async screenshot operation.
final class PreviewImages {
    typealias Capture = ([AppWindow], @escaping () -> Bool, @escaping (WindowKey, NSImage) -> Void) async throws -> Void
    private(set) var cache: [WindowKey: NSImage] = [:]
    var onUpdate: ((WindowKey?) -> Void)?
    private let captureAccess: () -> Bool
    private let capture: Capture
    private var activeCapture: UUID?
    private var order: [WindowKey] = []
    private var generation = 0
    private var hasConsumers = true
    private var permissionGranted = true

    init(captureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         capture: @escaping Capture = PreviewImages.captureWindows) {
        self.captureAccess = captureAccess
        self.capture = capture
    }

    /// A consumer leaving must not erase imagery still used by the other one.
    func updateAvailability(hasConsumers: Bool, captureGranted: Bool) {
        self.hasConsumers = hasConsumers
        permissionGranted = captureGranted
        if (!hasConsumers || !captureGranted) && (activeCapture != nil || !cache.isEmpty) { clear() }
    }

    @discardableResult
    func refresh(_ windows: [AppWindow]) -> Task<Void, Never>? {
        guard hasConsumers, permissionGranted, captureAccess() else {
            clear()
            return nil
        }
        let visible = windows.filter { !$0.state.minimized }
        guard activeCapture == nil, !visible.isEmpty else { return nil }
        let token = UUID()
        activeCapture = token
        let requestedGeneration = generation
        return Task { @MainActor in
            defer { if self.activeCapture == token { self.activeCapture = nil } }
            let current = { self.generation == requestedGeneration && self.hasConsumers && self.permissionGranted && self.captureAccess() }
            do {
                try await self.capture(visible, current) { key, image in
                    guard current() else { return }
                    self.cache[key] = image
                    self.order.removeAll { $0 == key }
                    self.order.append(key)
                    while self.order.count > 64 {
                        let evicted = self.order.removeFirst()
                        self.cache.removeValue(forKey: evicted)
                        self.onUpdate?(evicted)
                    }
                    self.onUpdate?(key)
                }
            } catch {
                // Titles, icons and previous images remain usable on capture failure.
            }
            // A permission change during capture also clears existing images.
            if self.hasConsumers && self.permissionGranted && !self.captureAccess() { self.clear() }
        }
    }

    func clear() {
        generation += 1
        activeCapture = nil
        cache.removeAll()
        order.removeAll()
        onUpdate?(nil)
    }

    private static func captureWindows(_ windows: [AppWindow], isCurrent: @escaping () -> Bool,
                                       publish: @escaping (WindowKey, NSImage) -> Void) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard isCurrent() else { return }
        let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let transparent = Set(windowInfo.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowAlpha as String] as? Double) == 0 else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        })
        var used = Set<CGWindowID>()
        for window in windows {
            guard isCurrent(), CGPreflightScreenCaptureAccess() else { return }
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
                !($0.title ?? "").isEmpty && Self.normalizedTitle($0.title ?? "", appName: appName) == Self.normalizedTitle(window.title, appName: appName)
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
            guard isCurrent() else { return }
            publish(window.key, NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
        }
    }

    private static func normalizedTitle(_ title: String, appName: String) -> String {
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
