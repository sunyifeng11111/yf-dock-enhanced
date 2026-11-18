#if DEBUG
import AppKit
import ScreenCaptureKit

/// Times each stage between a Command+Tab press and a thumbnail being ready,
/// against the windows currently on screen. Records only counts and times.
@MainActor
func measureCaptureTiming(output: String) async -> Int32 {
    var lines: [String] = []
    func log(_ line: String) { lines.append(line) }
    func clock() -> Double { ProcessInfo.processInfo.systemUptime }
    func ms(_ start: Double) -> String { String(format: "%.1f", (clock() - start) * 1000) }
    func finish(_ code: Int32) -> Int32 {
        try? lines.joined(separator: "\n").appending("\n").write(toFile: output, atomically: true, encoding: .utf8)
        return code
    }
    guard AXIsProcessTrusted(), CGPreflightScreenCaptureAccess() else {
        log("UNAVAILABLE ax=\(AXIsProcessTrusted()) capture=\(CGPreflightScreenCaptureAccess())")
        return finish(2)
    }
    let controller = WindowController()
    let apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() }
    var start = clock()
    let windows = apps.flatMap { app in controller.windows(of: app).map { SwitcherCandidate(window: $0, app: app) } }
    log("inventory apps=\(apps.count) windows=\(windows.count) visible=\(windows.filter { !$0.window.state.minimized }.count) ms=\(ms(start))")
    let visible = windows.map(\.window).filter { !$0.state.minimized }

    let panel = WindowSwitcherPanel()
    for round in 1...3 {
        start = clock()
        panel.prepareContent(candidates: windows, screen: NSScreen.main)
        log("build-cards round=\(round) ms=\(ms(start))")
        panel.hide()
    }
    // A selection's real order: request screenshots, then build cards on the
    // main thread, then wait. Measures when the last image actually lands.
    for round in 1...5 {
        let images = PreviewImages()
        images.setCaptureDemand(active: true)
        var lastPublish: Double?
        images.onUpdate = { _ in lastPublish = clock() }
        let pressed = clock()
        let request = images.refresh(visible)
        panel.prepareContent(candidates: windows, screen: NSScreen.main)
        let built = clock()
        await request?.value
        log("selection round=\(round) cards-built ms=\(String(format: "%.1f", (built - pressed) * 1000)) last-image ms=\(String(format: "%.1f", ((lastPublish ?? pressed) - pressed) * 1000)) images=\(images.cache.count)/\(visible.count)")
        panel.hide()
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    // Same, with the main thread busy for 80 ms (a cold card build).
    for round in 1...5 {
        let images = PreviewImages()
        images.setCaptureDemand(active: true)
        var lastPublish: Double?
        images.onUpdate = { _ in lastPublish = clock() }
        let pressed = clock()
        let request = images.refresh(visible)
        usleep(80_000)
        await request?.value
        log("busy-main round=\(round) last-image ms=\(String(format: "%.1f", ((lastPublish ?? pressed) - pressed) * 1000)) images=\(images.cache.count)/\(visible.count)")
        try? await Task.sleep(nanoseconds: 500_000_000)
    }
    if CommandLine.arguments.contains("--sizes"), let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) {
        let pids = Set(visible.map(\.key.pid))
        let targets = content.windows.filter { pids.contains($0.owningApplication?.processID ?? -1) && $0.frame.width > 100 }
        for (w, h) in [(500.0, 400.0), (440.0, 220.0), (300.0, 160.0), (500.0, 400.0)] {
            var walls: [Double] = []
            for _ in 1...4 {
                let begin = clock()
                await withTaskGroup(of: Void.self) { group in
                    for target in targets {
                        let filter = SCContentFilter(desktopIndependentWindow: target)
                        let size = filter.contentRect.size
                        let scale = min(w / size.width, h / size.height)
                        let configuration = SCStreamConfiguration()
                        configuration.width = max(1, Int((size.width * scale).rounded()))
                        configuration.height = max(1, Int((size.height * scale).rounded()))
                        configuration.showsCursor = false
                        configuration.ignoreShadowsSingleWindow = true
                        group.addTask { _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
                    }
                }
                walls.append((clock() - begin) * 1000)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            log("size \(Int(w))x\(Int(h)) windows=\(targets.count) wall ms=\(walls.map { String(format: "%.0f", $0) }.joined(separator: " "))")
        }
    }
    log("pipeline-on-main-thread=\(PreviewImages.pipelineRanOnMainThread.map(String.init(describing:)) ?? "unknown")")
    if CommandLine.arguments.contains("--selection-only") { return finish(0) }

    for iteration in 1...6 {
        let total = clock()
        start = clock()
        let content = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        log("[\(iteration)] list-onscreen ms=\(ms(start)) windows=\(content?.windows.count ?? -1)")
        start = clock()
        _ = try? await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        log("[\(iteration)] list-all ms=\(ms(start))")
        guard let content else { continue }
        start = clock()
        let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        log("[\(iteration)] cg-list-all ms=\(ms(start)) entries=\(info.count)")
        var axTime = 0.0, cgTime = 0.0, slowestAX = 0.0
        var filters: [SCContentFilter] = []
        for window in visible {
            let a = clock()
            let minimized: Bool? = AX.value(window.element, kAXMinimizedAttribute)
            let axElapsed = clock() - a
            axTime += axElapsed; slowestAX = max(slowestAX, axElapsed)
            let c = clock()
            let match = content.windows.first {
                $0.owningApplication?.processID == window.key.pid &&
                abs($0.frame.minX - window.frame.minX) < 8 && abs($0.frame.minY - window.frame.minY) < 8 &&
                abs($0.frame.width - window.frame.width) < 8 && abs($0.frame.height - window.frame.height) < 8
            }
            if let match { _ = CGWindowListCopyWindowInfo(.optionIncludingWindow, match.windowID) }
            cgTime += clock() - c
            if minimized != true, let match { filters.append(SCContentFilter(desktopIndependentWindow: match)) }
        }
        log("[\(iteration)] match ax-total ms=\(String(format: "%.1f", axTime * 1000)) ax-slowest ms=\(String(format: "%.1f", slowestAX * 1000)) cg-total ms=\(String(format: "%.1f", cgTime * 1000)) matched=\(filters.count)/\(visible.count)")
        start = clock()
        var durations: [Double] = []
        await withTaskGroup(of: Double.self) { group in
            for filter in filters {
                let size = filter.contentRect.size
                let scale = min(500 / max(size.width, 1), 400 / max(size.height, 1))
                let configuration = SCStreamConfiguration()
                configuration.width = max(1, Int((size.width * scale).rounded()))
                configuration.height = max(1, Int((size.height * scale).rounded()))
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let begin = start
                group.addTask {
                    _ = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    return ProcessInfo.processInfo.systemUptime - begin
                }
            }
            for await d in group { durations.append(d) }
        }
        durations.sort()
        let median = durations.isEmpty ? 0 : durations[durations.count / 2]
        log("[\(iteration)] capture-parallel wall ms=\(ms(start)) first ms=\(String(format: "%.1f", (durations.first ?? 0) * 1000)) median ms=\(String(format: "%.1f", median * 1000)) last ms=\(String(format: "%.1f", (durations.last ?? 0) * 1000))")
        if let one = filters.first {
            let configuration = SCStreamConfiguration()
            configuration.width = 400; configuration.height = 300
            start = clock()
            _ = try? await SCScreenshotManager.captureImage(contentFilter: one, configuration: configuration)
            log("[\(iteration)] capture-single ms=\(ms(start))")
        }
        log("[\(iteration)] stages-total ms=\(ms(total))")

        let images = PreviewImages()
        images.setCaptureDemand(active: true)
        var firstPublish: Double?, lastPublish: Double?
        let e2e = clock()
        images.onUpdate = { _ in let now = clock(); if firstPublish == nil { firstPublish = now }; lastPublish = now }
        await images.refresh(visible)?.value
        log("[\(iteration)] pipeline end-to-end ms=\(ms(e2e)) first-image ms=\(String(format: "%.1f", ((firstPublish ?? e2e) - e2e) * 1000)) last-image ms=\(String(format: "%.1f", ((lastPublish ?? e2e) - e2e) * 1000)) images=\(images.cache.count)")
        try? await Task.sleep(nanoseconds: 700_000_000)
    }
    return finish(0)
}
#endif
