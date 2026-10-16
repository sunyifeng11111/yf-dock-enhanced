import AppKit
import DockCore

extension WindowKey {
    var switcherID: SwitcherWindowID { SwitcherWindowID(pid: pid, id: id) }
}

struct SwitcherCandidate {
    let window: AppWindow
    let app: NSRunningApplication
    var id: SwitcherWindowID { window.key.switcherID }
}

/// Owns the native boundary. Scans are prepared off the input callback; browsing
/// updates a nonactivating panel, and only a confirmed result reaches the controller.
final class NativeWindowSwitcher {
    let panel = WindowSwitcherPanel()
    private(set) var workflow = WindowSwitcher()
    private(set) var candidates: [SwitcherCandidate] = []
    private var focusedWindows: [pid_t: SwitcherWindowID] = [:]
    private var sessionCandidates: [SwitcherCandidate] = []
    private let scanner = WindowController()
    private let scanQueue = DispatchQueue(label: "dev.yifeng.DockEnhanced.switcher-inventory", qos: .userInitiated)
    private var scanning = false
    private var generation = 0
    private var activationGeneration = 0
    private var swallowedKeys = Set<Int64>()
    private let controller: WindowController

    init(controller: WindowController) { self.controller = controller }
    var isSelecting: Bool { workflow.snapshot != nil }

    func refreshCandidates() {
        guard !scanning else { return }
        scanning = true
        let scanGeneration = generation
        let apps = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && !$0.isTerminated && $0.processIdentifier != getpid()
        }
        scanQueue.async { [weak self] in
            guard let self else { return }
            var focused: [pid_t: SwitcherWindowID] = [:]
            let result = apps.flatMap { app in
                let windows = self.scanner.windows(of: app)
                if let window = self.scanner.focusedWindow(of: app, in: windows) { focused[app.processIdentifier] = window.key.switcherID }
                return windows.map { SwitcherCandidate(window: $0, app: app) }
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scanning = false
                guard self.generation == scanGeneration else { return }
                self.focusedWindows = focused
                self.candidates = result.sorted {
                    let left = ($0.app.localizedName ?? "", $0.window.title, $0.window.key.id)
                    let right = ($1.app.localizedName ?? "", $1.window.title, $1.window.key.id)
                    return left < right
                }
            }
        }
    }

    /// Returns true only for events owned by this feature; other input retains its
    /// ordinary system meaning. No Accessibility enumeration runs in this callback.
    func handle(type: CGEventType, event: CGEvent) -> Bool {
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp, swallowedKeys.remove(code) != nil { return true }
        if type == .flagsChanged, isSelecting, !event.flags.contains(.maskCommand) {
            confirm()
            return false
        }
        guard type == .keyDown else { return false }
        if code == 48, event.flags.contains(.maskCommand),
           event.flags.intersection([.maskControl, .maskAlternate]).isEmpty {
            if !isSelecting {
                guard !candidates.isEmpty else { return false }
                controller.userChangedWindow()
                sessionCandidates = candidates
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                let current = pid.flatMap { focusedWindows[$0] }
                workflow.begin(windows: sessionCandidates.map(\.id), current: current,
                               reverse: event.flags.contains(.maskShift))
            } else {
                workflow.advance(reverse: event.flags.contains(.maskShift))
            }
            swallowedKeys.insert(code)
            render()
            return true
        }
        if isSelecting, code == 53 { swallowedKeys.insert(code); cancel(); return true }
        return false
    }

    func cancel() {
        activationGeneration += 1
        workflow.cancel()
        sessionCandidates = []
        panel.hide()
    }

    func stop() {
        generation += 1
        cancel()
        candidates = []
        swallowedKeys.removeAll()
        controller.cancelDeferredReveal()
    }

    private func confirm() {
        activationGeneration += 1
        let confirmationGeneration = activationGeneration
        let target = workflow.commandReleased()
        let candidate = sessionCandidates.first { $0.id == target }
        panel.hide()
        sessionCandidates = []
        guard let candidate else { return }
        // The confirming flagsChanged must finish before deferred restoration starts.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.activationGeneration == confirmationGeneration else { return }
            _ = self.controller.reveal(candidate.window, app: candidate.app)
        }
    }

    private func render() {
        guard let snapshot = workflow.snapshot else { panel.hide(); return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.workflow.snapshot == snapshot else { return }
            self.panel.show(candidates: self.sessionCandidates, selected: snapshot.selected)
        }
    }
}

final class WindowSwitcherPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var cards: [SwitcherWindowID: NSView] = [:]
    private var scroll: NSScrollView?
    private(set) var windowIDs: [SwitcherWindowID] = []

    init() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.setAccessibilityTitle("窗口切换")
    }

    func show(candidates: [SwitcherCandidate], selected: SwitcherWindowID) {
        guard !candidates.isEmpty else { hide(); return }
        let ids = candidates.map(\.id)
        if windowIDs != ids || !panel.isVisible {
            windowIDs = ids
            let available = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 700)
            let width = min(available.width - 48, CGFloat(candidates.count) * 244 + 14)
            let size = CGSize(width: max(250, width), height: 206)
            panel.setFrame(CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2, width: size.width, height: size.height), display: false)
            let content = NSView(frame: CGRect(origin: .zero, size: size))
            let scrolling = NSScrollView(frame: content.bounds.insetBy(dx: 12, dy: 12))
            scrolling.drawsBackground = false
            scrolling.hasHorizontalScroller = true
            scrolling.autohidesScrollers = true
            let document = NSView(frame: CGRect(x: 0, y: 0, width: CGFloat(candidates.count) * 244 - 10, height: 170))
            cards = [:]
            for (index, candidate) in candidates.enumerated() {
                let card = NSView(frame: CGRect(x: CGFloat(index) * 244, y: 0, width: 234, height: 170))
                card.wantsLayer = true
                card.layer?.cornerRadius = 16
                let icon = NSImageView(frame: CGRect(x: 85, y: 72, width: 64, height: 64))
                icon.image = candidate.app.icon
                icon.imageScaling = .scaleProportionallyUpOrDown
                card.addSubview(icon)
                let title = NSTextField(labelWithString: candidate.window.title)
                title.frame = CGRect(x: 10, y: 40, width: 214, height: 20)
                title.font = .systemFont(ofSize: 13)
                title.alignment = .center
                title.lineBreakMode = .byTruncatingTail
                card.addSubview(title)
                let appName = NSTextField(labelWithString: candidate.app.localizedName ?? "应用")
                appName.frame = CGRect(x: 10, y: 18, width: 214, height: 18)
                appName.font = .systemFont(ofSize: 11)
                appName.textColor = .secondaryLabelColor
                appName.alignment = .center
                appName.lineBreakMode = .byTruncatingTail
                card.addSubview(appName)
                card.setAccessibilityElement(true)
                card.setAccessibilityLabel("\(candidate.app.localizedName ?? "应用") · \(candidate.window.title)")
                document.addSubview(card)
                cards[candidate.id] = card
            }
            scrolling.documentView = document
            content.addSubview(scrolling)
            scroll = scrolling
            panel.contentView = makeWindowPreviewBackground(content: content)
        }
        for (id, card) in cards {
            card.effectiveAppearance.performAsCurrentDrawingAppearance {
                card.layer?.backgroundColor = (id == selected ? NSColor.labelColor.withAlphaComponent(0.12) : NSColor.clear).cgColor
            }
            card.setAccessibilityValue(id == selected ? "已选中" : "")
        }
        if let card = cards[selected] { card.scrollToVisible(card.bounds) }
        panel.orderFrontRegardless()
    }

    func hide() { panel.orderOut(nil); windowIDs = []; cards = [:]; scroll = nil }
}
