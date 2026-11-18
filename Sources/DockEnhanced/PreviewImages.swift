import AppKit
import ScreenCaptureKit

/// Shared, memory-only image delivery for Dock hover and the window switcher.
/// The injectable boundary is the operating system's async screenshot operation.
final class PreviewImages {
    // The async capture and its callbacks share the UI executor. An enclosing
    // MainActor task alone does not isolate an async nonisolated callee.
    typealias Capture = @MainActor ([AppWindow], @escaping @MainActor () -> Bool,
                                   @escaping @MainActor (WindowKey, NSImage) -> Void) async throws -> Void
    private(set) var cache: [WindowKey: NSImage] = [:]
    var onUpdate: ((WindowKey?) -> Void)?
    private let captureAccess: () -> Bool
    private let sessionAvailable: () -> Bool
    /// Starts a capture and returns its work; the default starts off the main
    /// actor at once, so screenshots need no free main thread to begin.
    private let startCapture: ([AppWindow], @escaping @MainActor () -> Bool,
                                          @escaping @MainActor (WindowKey, NSImage) -> Void) -> Task<Void, Never>
    private let now: () -> TimeInterval
    private struct Observation {
        let minimized: Bool
        let revision: UUID
        let readyAfter: TimeInterval
    }
    private var observations: [WindowKey: Observation] = [:]
    // Request time of the newest completed screenshot attempt per window,
    // whether or not it produced an image.
    private var attempted: [WindowKey: TimeInterval] = [:]
    private var queued: [AppWindow] = []
    private var activeCapture: UUID?
    private var captureTask: Task<Void, Never>?
    private static let windowCache = CaptureWindowCache()
    #if DEBUG
    nonisolated(unsafe) static var pipelineRanOnMainThread: Bool?
    #endif
    private var order: [WindowKey] = []
    private var generation = 0
    private var hasConsumers = true
    private var permissionGranted = true
    private var captureDemand = true

    init(captureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         sessionAvailable: @escaping () -> Bool = PreviewImages.isSessionAvailable,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         capture: Capture? = nil) {
        self.captureAccess = captureAccess
        self.sessionAvailable = sessionAvailable
        self.now = now
        if let capture {
            startCapture = { windows, isCurrent, publish in
                Task { @MainActor in
                    guard isCurrent() else { return }
                    try? await capture(windows, isCurrent, publish)
                }
            }
        } else {
            startCapture = { windows, isCurrent, publish in
                Task.detached(priority: .userInitiated) { await PreviewImages.captureOffMain(windows, isCurrent: isCurrent, publish: publish) }
            }
        }
    }

    var currentTime: TimeInterval { now() }

    /// True once every capturable window has had a screenshot attempt requested
    /// at or after `since`, so a presentation opened then will not swap in a
    /// newer image moments later.
    func hasFreshImages(for windows: [AppWindow], since: TimeInterval) -> Bool {
        guard sessionAvailable(), hasConsumers, permissionGranted, captureDemand, captureAccess() else { return true }
        let time = now()
        return windows.allSatisfy { window in
            if window.state.minimized { return true }
            guard let observation = observations[window.key], !observation.minimized else { return false }
            if observation.readyAfter > time { return true }
            return (attempted[window.key] ?? -.infinity) >= since
        }
    }

    static func isSessionAvailable() -> Bool {
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        return session["CGSSessionScreenIsLocked"] as? Bool != true &&
            session[kCGSessionOnConsoleKey as String] as? Bool == true
    }

    /// A consumer leaving must not erase imagery still used by the other one.
    func updateAvailability(hasConsumers: Bool, captureGranted: Bool) {
        self.hasConsumers = hasConsumers
        if hasConsumers && !sessionAvailable() {
            suspendCapture()
            return
        }
        permissionGranted = captureGranted
        if (!hasConsumers || !captureGranted) && (activeCapture != nil || !cache.isEmpty) { clear() }
    }

    /// Closing a panel stops new screenshots and retires pending callbacks,
    /// while retaining memory-only thumbnails for the next presentation.
    func setCaptureDemand(active: Bool) {
        captureDemand = active
        if !active { suspendCapture() }
    }

    @discardableResult
    func refresh(_ windows: [AppWindow]) -> Task<Void, Never>? {
        guard sessionAvailable() else {
            suspendCapture()
            return nil
        }
        guard hasConsumers, permissionGranted, captureAccess() else {
            clear()
            return nil
        }
        guard captureDemand else { return nil }
        // Observe transitions even while another screenshot is suspended. A
        // visible -> minimized -> visible cycle must also retire the old request.
        let time = now()
        for window in windows {
            let previous = observations[window.key]
            if previous == nil || previous?.minimized != window.state.minimized {
                observations[window.key] = Observation(minimized: window.state.minimized, revision: UUID(),
                    readyAfter: previous?.minimized == true && !window.state.minimized ? time + 0.6 : time)
            }
        }
        let visible = windows.filter {
            !$0.state.minimized && time >= (observations[$0.key]?.readyAfter ?? .infinity)
        }
        guard !visible.isEmpty else { return nil }
        guard activeCapture == nil else {
            // An in-flight screenshot may predate the presentation asking now;
            // run this request as soon as it finishes instead of dropping it.
            let keys = Set(visible.map(\.key))
            queued = queued.filter { !keys.contains($0.key) } + visible
            return nil
        }
        let token = UUID()
        activeCapture = token
        let requestedGeneration = generation
        let revisions = Dictionary(visible.map { ($0.key, observations[$0.key]!.revision) }, uniquingKeysWith: { first, _ in first })
        let current: @MainActor () -> Bool = { self.sessionAvailable() && self.generation == requestedGeneration && self.hasConsumers && self.captureDemand && self.permissionGranted && self.captureAccess() }
        let work = startCapture(visible, current) { key, image in
            guard current(), let revision = revisions[key],
                  self.observations[key]?.revision == revision,
                  self.observations[key]?.minimized == false else { return }
            self.cache[key] = image
            self.attempted[key] = max(self.attempted[key] ?? -.infinity, time)
            self.order.removeAll { $0 == key }
            self.order.append(key)
            while self.order.count > 64 {
                let evicted = self.order.removeFirst()
                self.cache.removeValue(forKey: evicted)
                self.onUpdate?(evicted)
            }
            self.onUpdate?(key)
        }
        captureTask = work
        return Task { @MainActor in
            defer {
                if self.activeCapture == token {
                    self.activeCapture = nil
                    self.captureTask = nil
                    let next = self.queued
                    self.queued = []
                    if !next.isEmpty { self.refresh(next) }
                }
            }
            // Titles, icons and previous images remain usable on capture failure.
            await work.value
            if current() {
                for key in revisions.keys { self.attempted[key] = max(self.attempted[key] ?? -.infinity, time) }
            }
            // A permission change during capture also clears existing images.
            if self.sessionAvailable() && self.hasConsumers && self.permissionGranted && !self.captureAccess() { self.clear() }
        }
    }

    // Retire callbacks from captures interrupted by locking, without losing the
    // last usable image (minimized windows cannot be recaptured after unlocking).
    private func suspendCapture() {
        queued.removeAll()
        if activeCapture != nil {
            generation += 1
            activeCapture = nil
            captureTask?.cancel()
            captureTask = nil
        }
    }

    func clear() {
        generation += 1
        activeCapture = nil
        captureTask?.cancel()
        captureTask = nil
        Self.windowCache.removeAll()
        cache.removeAll()
        observations.removeAll()
        attempted.removeAll()
        queued.removeAll()
        order.removeAll()
        onUpdate?(nil)
    }

    /// Listing, matching and screenshot submission run off the main actor, so a
    /// busy main thread (building cards) cannot push screenshots past the reveal.
    /// Only delivering a finished image returns to the main actor.
    @concurrent private static func captureOffMain(_ windows: [AppWindow], isCurrent: @escaping @MainActor () -> Bool,
                                                   publish: @escaping @MainActor (WindowKey, NSImage) -> Void) async {
        #if DEBUG
        pipelineRanOnMainThread = pthread_main_np() != 0
        #endif
        // A window matched before is reused while its live geometry is
        // unchanged, which skips listing every shareable window.
        var known: [(AppWindow, SCWindow)] = []
        var unresolved: [AppWindow] = []
        for window in windows {
            if let scWindow = windowCache.window(for: window.key), isReusable(scWindow, for: window) {
                known.append((window, scWindow))
            } else { unresolved.append(window) }
        }
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess() else { return }
        enum Step { case listed(SCShareableContent?), captured(AppWindow, CGWindowID, CGImage?) }
        let pending = unresolved
        await withTaskGroup(of: Step.self) { group in
            // Listing runs alongside screenshots of already known windows.
            if !pending.isEmpty {
                group.addTask { .listed(try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)) }
            }
            func submit(_ window: AppWindow, _ scWindow: SCWindow) {
                let filter = SCContentFilter(desktopIndependentWindow: scWindow)
                let size = filter.contentRect.size
                guard size.width > 0, size.height > 0 else { return }
                let scale = min(500 / size.width, 400 / size.height)
                let configuration = SCStreamConfiguration()
                // Fit both dimensions together. A fixed width with a capped height
                // leaves a padded canvas around portrait windows in ScreenCaptureKit.
                configuration.width = max(1, Int((size.width * scale).rounded()))
                configuration.height = max(1, Int((size.height * scale).rounded()))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let id = scWindow.windowID
                group.addTask { .captured(window, id, try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)) }
            }
            for (window, scWindow) in known { submit(window, scWindow) }
            while let step = await group.next() {
                guard !Task.isCancelled else { group.cancelAll(); return }
                guard case let .captured(window, id, image) = step else {
                    if case let .listed(content?) = step {
                        for (window, scWindow) in match(pending, in: content) {
                            windowCache.store(scWindow, for: window.key)
                            submit(window, scWindow)
                        }
                    }
                    continue
                }
                // The inventory and SCWindow are snapshots. Re-read live state after
                // the await so a minimize animation cannot overwrite the good image.
                guard let image, isStableOnScreen(window, id: id) else { continue }
                let picture = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                guard await deliver(window.key, picture, isCurrent: isCurrent, publish: publish) else { group.cancelAll(); return }
            }
        }
    }

    @MainActor private static func deliver(_ key: WindowKey, _ image: NSImage, isCurrent: @MainActor () -> Bool,
                                           publish: @MainActor (WindowKey, NSImage) -> Void) -> Bool {
        guard isCurrent() else { return false }
        publish(key, image)
        return true
    }

    private static func isReusable(_ scWindow: SCWindow, for window: AppWindow) -> Bool {
        scWindow.owningApplication?.processID == window.key.pid &&
            abs(scWindow.frame.minX - window.frame.minX) < 8 && abs(scWindow.frame.minY - window.frame.minY) < 8 &&
            abs(scWindow.frame.width - window.frame.width) < 8 && abs(scWindow.frame.height - window.frame.height) < 8 &&
            isStableOnScreen(window, id: scWindow.windowID)
    }

    private static func match(_ windows: [AppWindow], in content: SCShareableContent) -> [(AppWindow, SCWindow)] {
        let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let transparent = Set(windowInfo.compactMap { info -> CGWindowID? in
            guard (info[kCGWindowAlpha as String] as? Double) == 0 else { return nil }
            return info[kCGWindowNumber as String] as? CGWindowID
        })
        var used = Set<CGWindowID>()
        var result: [(AppWindow, SCWindow)] = []
        for window in windows {
            let candidates = content.windows.filter {
                $0.owningApplication?.processID == window.key.pid && !used.contains($0.windowID) && !transparent.contains($0.windowID)
            }
            // Offscreen records can retain the same title and frame as a live
            // window. Remove those before deciding whether a match is unique.
            let matches = candidates.filter {
                abs($0.frame.minX - window.frame.minX) < 8 && abs($0.frame.minY - window.frame.minY) < 8 &&
                abs($0.frame.width - window.frame.width) < 8 && abs($0.frame.height - window.frame.height) < 8 &&
                isStableOnScreen(window, id: $0.windowID)
            }
            let exact = matches.filter { $0.title == window.title }
            let appName = NSRunningApplication(processIdentifier: window.key.pid)?.localizedName ?? ""
            let normalized = matches.filter {
                !($0.title ?? "").isEmpty && normalizedTitle($0.title ?? "", appName: appName) == normalizedTitle(window.title, appName: appName)
            }
            guard let capturedWindow = exact.count == 1 ? exact.first :
                    (normalized.count == 1 ? normalized.first : (matches.count == 1 ? matches.first : nil)) else { continue }
            used.insert(capturedWindow.windowID)
            result.append((window, capturedWindow))
        }
        return result
    }

    private static func isStableOnScreen(_ window: AppWindow, id: CGWindowID) -> Bool {
        guard (AX.value(window.element, kAXMinimizedAttribute) as Bool?) != true,
              let info = (CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: bounds) else { return false }
        return abs(frame.minX - window.frame.minX) < 8 && abs(frame.minY - window.frame.minY) < 8 &&
            abs(frame.width - window.frame.width) < 8 && abs(frame.height - window.frame.height) < 8
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

/// Window identities resolved by an earlier listing. Accessed from concurrent
/// capture tasks, so guarded by a lock.
private final class CaptureWindowCache: @unchecked Sendable {
    private let lock = NSLock()
    private var windows: [WindowKey: SCWindow] = [:]
    func window(for key: WindowKey) -> SCWindow? { lock.withLock { windows[key] } }
    func store(_ window: SCWindow, for key: WindowKey) {
        lock.withLock {
            windows[key] = window
            if windows.count > 256 { windows.removeAll() }
        }
    }
    func removeAll() { lock.withLock { windows.removeAll() } }
}
