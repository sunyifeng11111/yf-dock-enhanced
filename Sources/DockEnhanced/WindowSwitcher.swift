import AppKit
import DockCore
import QuartzCore

extension WindowKey {
    var switcherID: SwitcherWindowID { SwitcherWindowID(pid: pid, id: id) }
}

struct SwitcherCandidate {
    let window: AppWindow
    let app: NSRunningApplication
    var id: SwitcherWindowID { window.key.switcherID }
    var descriptor: SwitcherWindow { SwitcherWindow(id: id, appName: app.localizedName ?? "", title: window.title) }
}

private func switcherFocusChanged(_ observer: AXObserver, _ element: AXUIElement, _ notification: CFString, _ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    Unmanaged<NativeWindowSwitcher>.fromOpaque(context).takeUnretainedValue().observeActualFocus()
}

/// Translates native input and observed focus into one selection workflow. No
/// enumeration, capture or window restoration runs in the event-tap callback.
final class NativeWindowSwitcher {
    let panel = WindowSwitcherPanel()
    let failureNotice = WindowSwitcherFailureNotice()
    private(set) var workflow = WindowSwitcher()
    private(set) var candidates: [SwitcherCandidate] = []
    var onCandidatesChanged: (([SwitcherCandidate]) -> Void)?
    private var focusedWindows: [pid_t: SwitcherWindowID] = [:]
    private var sessionCandidates: [SwitcherCandidate] = []
    private let scanner = WindowController()
    private let scanQueue = DispatchQueue(label: "dev.yifeng.DockEnhanced.switcher-inventory", qos: .userInitiated)
    private var scanning = false
    private var generation = 0
    private var activationGeneration = 0
    private var sessionGeneration = 0
    private var commandMissingSince: Double?
    private var failureWork: DispatchWorkItem?
    private var swallowedKeys = Set<Int64>()
    private var swallowMouseUp = false
    private var displayWork: DispatchWorkItem?
    private var sessionScreen: NSScreen?
    private var focusObservers: [pid_t: AXObserver] = [:]
    private var workspaceObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let controller: WindowController
    private let applicationFilter: (NSRunningApplication) -> Bool
    private let screenVisibleFrame: (NSScreen?) -> CGRect
    private var observing = false
    private var lastPointer = CGPoint.zero

    init(controller: WindowController, applicationFilter: @escaping (NSRunningApplication) -> Bool = { _ in true }, screenVisibleFrame: @escaping (NSScreen?) -> CGRect = { $0?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700) }) {
        self.controller = controller
        self.applicationFilter = applicationFilter
        self.screenVisibleFrame = screenVisibleFrame
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in self?.observeActualFocus() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, let screen = self.sessionScreen else { return }
            guard let currentScreen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber }) else { self.cancel(); return }
            self.sessionScreen = currentScreen
            self.panel.prepare(candidates: self.sessionCandidates, screen: currentScreen, availableFrame: self.screenVisibleFrame(currentScreen))
            self.render()
        }
    }

    deinit {
        if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in focusObservers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
    }

    var isSelecting: Bool { workflow.snapshot != nil }

    func refreshCandidates() {
        guard !scanning else { return }
        scanning = true
        observing = true
        let scanGeneration = generation
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid() && applicationFilter($0)
        }
        updateFocusObservers(apps)
        scanQueue.async { [weak self] in
            guard let self else { return }
            var focused: [pid_t: SwitcherWindowID] = [:]
            let result = apps.flatMap { app in
                let windows = self.scanner.windows(of: app)
                if let window = self.scanner.focusedWindow(of: app, in: windows) { focused[app.processIdentifier] = window.key.switcherID }
                return windows.map { SwitcherCandidate(window: $0, app: app) }
            }
            let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanning = false
                guard self.generation == scanGeneration else { return }
                self.focusedWindows = focused
                self.candidates = result
                // Only an actual foreground observation records use. Background
                // focused attributes and accepted activation requests do not.
                if foregroundPID == NSWorkspace.shared.frontmostApplication?.processIdentifier,
                   let pid = foregroundPID, let focused = focused[pid] { self.workflow.observeFocus(focused) }
                self.workflow.updateAvailableWindows(result.map(\.id))
                if let snapshot = self.workflow.snapshot {
                    let byID = Dictionary(result.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    self.sessionCandidates = snapshot.windows.compactMap { byID[$0] }
                } else { self.sessionCandidates = [] }
                self.onCandidatesChanged?(result)
                self.render()
            }
        }
    }

    fileprivate func observeActualFocus() {
        guard observing, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid(), applicationFilter(app) else { return }
        let observationGeneration = generation
        scanQueue.async { [weak self] in
            guard let self else { return }
            let windows = self.scanner.windows(of: app)
            let focused = self.scanner.focusedWindow(of: app, in: windows)?.key.switcherID
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == observationGeneration,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                      let focused else { return }
                self.focusedWindows[app.processIdentifier] = focused
                self.workflow.observeFocus(focused)
            }
        }
    }

    private func updateFocusObservers(_ apps: [NSRunningApplication]) {
        let pids = Set(apps.map(\.processIdentifier))
        for pid in Array(focusObservers.keys) where !pids.contains(pid) {
            if let observer = focusObservers.removeValue(forKey: pid) { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        }
        for app in apps where focusObservers[app.processIdentifier] == nil {
            var observer: AXObserver?
            guard AXObserverCreate(app.processIdentifier, switcherFocusChanged, &observer) == .success, let observer else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            guard AXObserverAddNotification(observer, element, kAXFocusedWindowChangedNotification as CFString, Unmanaged.passUnretained(self).toOpaque()) == .success else { continue }
            focusObservers[app.processIdentifier] = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
    }

    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeys.remove(code) != nil { return true }
        if type == .leftMouseUp, swallowMouseUp { swallowMouseUp = false; return true }
        if type == .flagsChanged, isSelecting, !event.flags.contains(.maskCommand) { confirm(); return false }
        if type == .mouseMoved, isSelecting, workflow.isPanelVisible {
            let point = appKitPoint(event.location)
            if point != lastPointer {
                lastPointer = point
                if let target = panel.window(at: point) { workflow.pointerMoved(over: target); render() }
            }
            return false
        }
        if type == .leftMouseDown || type == .rightMouseDown {
            if isSelecting {
                if type == .leftMouseDown, workflow.isPanelVisible, panel.panel.frame.contains(appKitPoint(event.location)) {
                    if let target = panel.window(at: appKitPoint(event.location)) { workflow.pointerMoved(over: target); confirm() }
                    swallowMouseUp = true
                    return true
                }
                cancel()
            } else { cancel() }
            return false
        }
        guard type == .keyDown else { return false }
        if code == 48, event.flags.contains(.maskCommand), event.flags.intersection([.maskControl, .maskAlternate]).isEmpty {
            if !isSelecting {
                guard !candidates.isEmpty else {
                    cancel()
                    swallowedKeys.insert(code)
                    return true
                }
                controller.userChangedWindow()
                activationGeneration += 1
                sessionGeneration += 1
                let selectionGeneration = sessionGeneration
                commandMissingSince = nil
                hideFailure()
                lastPointer = NSEvent.mouseLocation
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let current = pid.flatMap { focusedWindows[$0] }
                workflow.begin(candidates: candidates.map(\.descriptor), current: current, reverse: event.flags.contains(.maskShift), time: ProcessInfo.processInfo.systemUptime)
                if let snapshot = workflow.snapshot {
                    let byID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                    sessionCandidates = snapshot.windows.compactMap { byID[$0] }
                    sessionScreen = screenForCurrentWindow(current)
                    panel.prepare(candidates: sessionCandidates, screen: sessionScreen, availableFrame: screenVisibleFrame(sessionScreen))
                    // Build native views after returning the input callback, while
                    // the no-flash interval is still running.
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.sessionGeneration == selectionGeneration, self.isSelecting else { return }
                        self.panel.prepareContent(candidates: self.sessionCandidates, screen: self.sessionScreen, availableFrame: self.screenVisibleFrame(self.sessionScreen))
                    }
                    let work = DispatchWorkItem { [weak self] in
                        guard let self, self.sessionGeneration == selectionGeneration, self.isSelecting else { return }
                        self.workflow.advanceTime(to: ProcessInfo.processInfo.systemUptime)
                        self.render()
                    }
                    displayWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
                    onCandidatesChanged?(sessionCandidates)
                }
            } else { workflow.advance(reverse: event.flags.contains(.maskShift)) }
            swallowedKeys.insert(code)
            render()
            return true
        }
        if isSelecting {
            if code == 53 { swallowedKeys.insert(code); cancel(); return true }
            if code == 36 || code == 76 { swallowedKeys.insert(code); confirm(); return true }
            let directions: [Int64: SwitcherDirection] = [123: .left, 124: .right, 125: .down, 126: .up]
            if let direction = directions[code] {
                swallowedKeys.insert(code)
                workflow.move(direction, columns: panel.columns)
                render()
                return true
            }
            cancel()
        } else { cancel() }
        return false
    }

    func updatePreviewImage(_ image: NSImage?, for windowID: SwitcherWindowID) { panel.updatePreviewImage(image, for: windowID) }
    func clearPreviewImages() { panel.clearPreviewImages() }

    /// Polling discovers a missed release; uncertainty cancels rather than confirms.
    func checkCommandState(commandIsDown: Bool, time: Double = ProcessInfo.processInfo.systemUptime) {
        guard isSelecting, !commandIsDown else { commandMissingSince = nil; return }
        // Combined flags can change before the queued release callback arrives.
        // Give that event a full heartbeat before treating its absence as a fault.
        guard let missingSince = commandMissingSince else { commandMissingSince = time; return }
        if time - missingSince >= 0.10 { cancel() }
    }

    func interrupt() {
        cancel()
        swallowedKeys.removeAll()
        swallowMouseUp = false
    }

    func cancel() {
        activationGeneration += 1
        controller.cancelDeferredReveal()
        hideFailure()
        workflow.cancel()
        endPresentation()
    }

    func stop() {
        generation += 1
        observing = false
        cancel()
        candidates = []
        focusedWindows = [:]
        workflow = WindowSwitcher()
        swallowedKeys.removeAll()
        swallowMouseUp = false
        for observer in focusObservers.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        focusObservers = [:]
        clearPreviewImages()
        controller.cancelDeferredReveal()
    }

    private func confirm() {
        activationGeneration += 1
        let confirmationGeneration = activationGeneration
        let target = workflow.commandReleased()
        let candidate = sessionCandidates.first { $0.id == target }
        let screen = sessionScreen
        endPresentation()
        guard let candidate else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activationGeneration == confirmationGeneration else { return }
            _ = self.controller.reveal(candidate.window, app: candidate.app) { [weak self] success in
                guard let self, self.activationGeneration == confirmationGeneration, !success else { return }
                self.failureNotice.show(screen: screen)
                let dismiss = DispatchWorkItem { [weak self] in
                    guard let self, self.activationGeneration == confirmationGeneration else { return }
                    self.hideFailure()
                }
                self.failureWork = dismiss
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: dismiss)
            }
        }
    }

    private func hideFailure() {
        failureWork?.cancel(); failureWork = nil
        failureNotice.panel.orderOut(nil)
    }

    private func endPresentation() {
        sessionGeneration += 1
        commandMissingSince = nil
        displayWork?.cancel(); displayWork = nil
        sessionCandidates = []
        sessionScreen = nil
        panel.hide()
    }

    private func screenForCurrentWindow(_ current: SwitcherWindowID?) -> NSScreen? {
        if let window = candidates.first(where: { $0.id == current })?.window {
            let center = appKitPoint(CGPoint(x: window.frame.midX, y: window.frame.midY))
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func render() {
        guard let snapshot = workflow.snapshot, workflow.isPanelVisible else {
            if !isSelecting { endPresentation() }
            return
        }
        panel.show(candidates: sessionCandidates, selected: snapshot.selected, screen: sessionScreen, availableFrame: screenVisibleFrame(sessionScreen))
    }
}

private final class SwitcherGridView: NSView { override var isFlipped: Bool { true } }

private final class SwitcherCard: NSView {
    override var isFlipped: Bool { true }
    private(set) var candidate: SwitcherCandidate
    private let thumbnail = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let appName = NSTextField(labelWithString: "")
    private let minimizedBadge = NSTextField(labelWithString: "已最小化")
    private let appIcon = NSImageView()
    private var hasPreview = false
    init(candidate: SwitcherCandidate, frame: CGRect) {
        self.candidate = candidate
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        thumbnail.frame = CGRect(x: 8, y: 8, width: frame.width - 16, height: 126)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.imageAlignment = .alignCenter
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.masksToBounds = true
        addSubview(thumbnail)
        title.frame = CGRect(x: 10, y: 143, width: frame.width - 20, height: 20)
        title.font = .systemFont(ofSize: 13)
        title.alignment = .center
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
        appIcon.frame = CGRect(x: 12, y: 166, width: 16, height: 16)
        appIcon.imageScaling = .scaleProportionallyUpOrDown
        addSubview(appIcon)
        appName.font = .systemFont(ofSize: 11)
        appName.textColor = .secondaryLabelColor
        appName.lineBreakMode = .byTruncatingTail
        addSubview(appName)
        minimizedBadge.frame = CGRect(x: frame.width - 66, y: 166, width: 58, height: 16)
        minimizedBadge.font = .systemFont(ofSize: 10)
        minimizedBadge.textColor = .secondaryLabelColor
        minimizedBadge.alignment = .right
        addSubview(minimizedBadge)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        update(candidate: candidate)
        update(image: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func update(candidate: SwitcherCandidate) {
        self.candidate = candidate
        title.stringValue = candidate.window.title.isEmpty ? "无标题窗口" : candidate.window.title
        appName.stringValue = candidate.app.localizedName ?? "应用"
        appIcon.image = candidate.app.icon
        let minimized = candidate.window.state.minimized
        minimizedBadge.isHidden = !minimized
        appName.frame = CGRect(x: 34, y: 165, width: frame.width - (minimized ? 108 : 46), height: 18)
        setAccessibilityLabel("\(appName.stringValue) · \(title.stringValue)\(minimized ? " · 已最小化" : "")")
        setAccessibilityHelp(minimized && hasPreview ? "已最小化 · 缓存画面" : "选择并切换此窗口")
    }
    func update(image: NSImage?) {
        hasPreview = image != nil
        thumbnail.image = image ?? candidate.app.icon
        thumbnail.frame = image == nil ? CGRect(x: (frame.width - 64) / 2, y: 39, width: 64, height: 64) : CGRect(x: 8, y: 8, width: frame.width - 16, height: 126)
        setAccessibilityHelp(candidate.window.state.minimized && image != nil ? "已最小化 · 缓存画面" : "选择并切换此窗口")
    }
    func select(_ selected: Bool) {
        guard let layer else { return }
        var color = NSColor.clear.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance { color = (selected ? NSColor.labelColor.withAlphaComponent(0.12) : NSColor.clear).cgColor }
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        animation.toValue = color
        animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
        layer.add(animation, forKey: "selection")
        layer.backgroundColor = color
        setAccessibilityValue(selected ? "已选中" : "")
    }
}

private func makeSwitcherPanel(title: String, ignoresMouseEvents: Bool = false) -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.hidesOnDeactivate = false
    panel.isReleasedWhenClosed = false
    panel.ignoresMouseEvents = ignoresMouseEvents
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    panel.setAccessibilityTitle(title)
    return panel
}

final class WindowSwitcherPanel {
    let panel = makeSwitcherPanel(title: "窗口切换")
    private var cards: [SwitcherWindowID: SwitcherCard] = [:]
    private var images: [SwitcherWindowID: NSImage] = [:]
    private var scroll: NSScrollView?
    private(set) var columns = 1
    private(set) var windowIDs: [SwitcherWindowID] = []
    private var selected: SwitcherWindowID?
    private var layoutFrame: CGRect?

    func prepare(candidates: [SwitcherCandidate], screen: NSScreen?, availableFrame: CGRect? = nil) {
        let available = availableFrame ?? screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        columns = max(1, min(candidates.count, Int((available.width - 48) / 244)))
    }

    func prepareContent(candidates: [SwitcherCandidate], screen: NSScreen?, availableFrame: CGRect? = nil) {
        guard !candidates.isEmpty else { return }
        windowIDs = candidates.map(\.id)
        prepare(candidates: candidates, screen: screen, availableFrame: availableFrame)
        let available = availableFrame ?? screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        layoutFrame = available
        let rows = (candidates.count + columns - 1) / columns
        let documentHeight = CGFloat(rows) * 200 - 10
        let size = CGSize(width: CGFloat(columns) * 244 + 14, height: min(available.height - 64, documentHeight + 24))
        panel.setFrame(CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height), display: false)
        let content = NSView(frame: CGRect(origin: .zero, size: size))
        let scrolling = NSScrollView(frame: content.bounds.insetBy(dx: 12, dy: 12))
        scrolling.drawsBackground = false
        scrolling.hasVerticalScroller = true
        scrolling.scrollerStyle = .overlay
        scrolling.autohidesScrollers = true
        let document = SwitcherGridView(frame: CGRect(x: 0, y: 0, width: size.width - 24, height: documentHeight))
        cards = [:]
        for (index, candidate) in candidates.enumerated() {
            let card = SwitcherCard(candidate: candidate, frame: CGRect(x: CGFloat(index % columns) * 244, y: CGFloat(index / columns) * 200, width: 234, height: 190))
            card.update(image: images[candidate.id])
            document.addSubview(card)
            cards[candidate.id] = card
        }
        scrolling.documentView = document
        content.addSubview(scrolling)
        scroll = scrolling
        panel.contentView = makeWindowPreviewBackground(content: content)
    }

    func show(candidates: [SwitcherCandidate], selected: SwitcherWindowID, screen: NSScreen?, availableFrame: CGRect? = nil) {
        guard !candidates.isEmpty else { hide(); return }
        let wasVisible = panel.isVisible
        let available = availableFrame ?? screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        let rebuilt = windowIDs != candidates.map(\.id) || layoutFrame != available
        if rebuilt { prepareContent(candidates: candidates, screen: screen, availableFrame: availableFrame) }
        for candidate in candidates { cards[candidate.id]?.update(candidate: candidate) }
        for (id, card) in cards { card.select(id == selected) }
        if self.selected != selected || !wasVisible || rebuilt, let card = cards[selected] { card.scrollToVisible(card.bounds) }
        self.selected = selected
        if !wasVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    func window(at screenPoint: CGPoint) -> SwitcherWindowID? {
        guard panel.isVisible, panel.frame.contains(screenPoint), let scroll else { return nil }
        // convertFromScreen is needed before converting into the scrolled document.
        let inWindow = panel.convertPoint(fromScreen: screenPoint)
        let inScroll = scroll.convert(inWindow, from: nil)
        guard scroll.bounds.contains(inScroll) else { return nil }
        return cards.first { _, card in card.bounds.contains(card.convert(inWindow, from: nil)) }?.key
    }

    func updatePreviewImage(_ image: NSImage?, for windowID: SwitcherWindowID) {
        images[windowID] = image
        cards[windowID]?.update(image: image)
    }
    func clearPreviewImages() {
        images = [:]
        for card in cards.values { card.update(image: nil) }
    }
    func hide() { panel.orderOut(nil); windowIDs = []; cards = [:]; scroll = nil; selected = nil; layoutFrame = nil }
}

/// Nonactivating, bounded feedback that never substitutes another window.
final class WindowSwitcherFailureNotice {
    let panel = makeSwitcherPanel(title: "无法切换到此窗口，请重试", ignoresMouseEvents: true)
    init() {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 58))
        let label = NSTextField(labelWithString: "无法切换到此窗口，请重试")
        label.font = .systemFont(ofSize: 13)
        label.alignment = .center
        label.frame = CGRect(x: 16, y: 20, width: 268, height: 18)
        content.addSubview(label)
        panel.contentView = makeWindowPreviewBackground(content: content)
    }
    func show(screen: NSScreen?) {
        let available = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
        panel.setFrame(CGRect(x: available.midX - 150, y: available.midY - 29, width: 300, height: 58), display: false)
        panel.orderFrontRegardless()
    }
}
