import AppKit
import QuartzCore

func appKitPoint(_ quartzPoint: CGPoint) -> CGPoint {
    CGPoint(x: quartzPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - quartzPoint.y)
}

func quartzPoint(_ appKitPoint: CGPoint) -> CGPoint {
    CGPoint(x: appKitPoint.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - appKitPoint.y)
}

final class PreviewCard: NSButton {
    private(set) var snapshot: AppWindow
    private let thumbnail = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    var selected: ((AppWindow) -> Void)?
    private var hoverTracking: NSTrackingArea?
    private var highlightedByPointer = false

    init(window: AppWindow, frame: CGRect) {
        self.snapshot = window
        super.init(frame: frame)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65).cgColor
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.clear.cgColor
        thumbnail.frame = CGRect(x: 8, y: 32, width: frame.width - 16, height: 126)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 6
        thumbnail.layer?.masksToBounds = true
        addSubview(thumbnail)
        name.stringValue = window.title
        name.frame = CGRect(x: 10, y: 8, width: frame.width - 20, height: 18)
        name.font = .systemFont(ofSize: 12, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        addSubview(name)
        detail.frame = CGRect(x: 10, y: 161, width: frame.width - 20, height: 16)
        detail.font = .systemFont(ofSize: 10)
        detail.textColor = .secondaryLabelColor
        addSubview(detail)
        target = self
        action = #selector(selectWindow)
        setAccessibilityLabel(window.title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { highlightedByPointer = true; updateHighlight() }
    override func mouseExited(with event: NSEvent) { highlightedByPointer = false; updateHighlight() }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateHighlight() }

    private func updateHighlight() {
        guard let layer else { return }
        let color = highlightedByPointer ? NSColor.systemIndigo.withAlphaComponent(0.14) : NSColor.controlBackgroundColor.withAlphaComponent(0.65)
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        animation.toValue = color.cgColor
        animation.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
        layer.add(animation, forKey: "pointerHighlight")
        layer.backgroundColor = color.cgColor
        layer.borderColor = highlightedByPointer ? NSColor.systemIndigo.withAlphaComponent(0.65).cgColor : NSColor.clear.cgColor
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    func update(image: NSImage?, icon: NSImage?) {
        thumbnail.image = image ?? icon
        detail.stringValue = snapshot.state.minimized ? (image == nil ? "已最小化 · 点击恢复" : "已最小化 · 缓存画面") : (image == nil ? "点击切换窗口" : "点击切换")
        setAccessibilityHelp(detail.stringValue)
    }

    func update(snapshot: AppWindow, image: NSImage?, icon: NSImage?) {
        self.snapshot = snapshot
        name.stringValue = snapshot.title
        setAccessibilityLabel(snapshot.title)
        update(image: image, icon: icon)
    }

    @objc private func selectWindow() { selected?(snapshot) }
}

final class PreviewPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var cards: [PreviewCard] = []
    private(set) var app: NSRunningApplication?
    private(set) var windowKeys: [WindowKey] = []
    private var anchor = CGRect.zero
    private var presented = false
    private var transitionGeneration = 0
    var onSelect: ((AppWindow, NSRunningApplication) -> Void)?

    init() {
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.setAccessibilityTitle("Dock 窗口预览")
    }

    var isVisible: Bool { presented }

    func show(item: DockItem, windows: [AppWindow], images: PreviewImages) {
        guard !windows.isEmpty else { hide(); return }
        let wasPresented = presented
        transitionGeneration += 1
        presented = true
        app = item.app
        windowKeys = windows.map(\.key)
        let origin = appKitPoint(CGPoint(x: item.frame.minX, y: item.frame.maxY))
        anchor = CGRect(origin: origin, size: item.frame.size)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? NSScreen.main
        let available = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let width = min(CGFloat(windows.count) * 244 + 24, available.width - 24)
        let size = CGSize(width: max(180, width), height: 228)
        var position = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 10)
        let full = screen?.frame ?? available
        if anchor.midX - full.minX < 100 {
            position = CGPoint(x: anchor.maxX + 10, y: anchor.midY - size.height / 2)
        } else if full.maxX - anchor.midX < 100 {
            position = CGPoint(x: anchor.minX - size.width - 10, y: anchor.midY - size.height / 2)
        }
        position.x = min(max(position.x, available.minX + 8), available.maxX - size.width - 8)
        position.y = min(max(position.y, available.minY + 8), available.maxY - size.height - 8)
        panel.setFrame(CGRect(origin: position, size: size), display: false)
        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: size))
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        let header = NSTextField(labelWithString: "\(item.app.localizedName ?? "应用") · \(windows.count) 个窗口")
        header.font = .systemFont(ofSize: 12, weight: .semibold)
        header.frame = CGRect(x: 16, y: 202, width: size.width - 32, height: 18)
        background.addSubview(header)
        let scroll = NSScrollView(frame: CGRect(x: 12, y: 10, width: size.width - 24, height: 184))
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = CGFloat(windows.count) * 244 > scroll.frame.width
        scroll.autohidesScrollers = true
        let document = NSView(frame: CGRect(x: 0, y: 0, width: CGFloat(windows.count) * 244, height: 180))
        cards = windows.enumerated().map { index, window in
            let card = PreviewCard(window: window, frame: CGRect(x: CGFloat(index) * 244, y: 0, width: 234, height: 180))
            card.selected = { [weak self] selectedWindow in
                self?.onSelect?(selectedWindow, item.app)
                self?.hide()
            }
            card.update(image: images.cache[window.key], icon: item.app.icon)
            document.addSubview(card)
            return card
        }
        scroll.documentView = document
        background.addSubview(scroll)
        panel.contentView = background
        let finalFrame = panel.frame
        if !wasPresented {
            panel.alphaValue = 0
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                panel.setFrame(finalFrame.offsetBy(dx: 0, dy: -6), display: false)
            }
        }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }
    }

    func updateImages(_ images: PreviewImages) {
        for card in cards { card.update(image: images.cache[card.snapshot.key], icon: app?.icon) }
    }

    func updateWindows(_ windows: [AppWindow], images: PreviewImages) {
        let current = Dictionary(uniqueKeysWithValues: windows.map { ($0.key, $0) })
        for card in cards {
            guard let snapshot = current[card.snapshot.key] else { continue }
            card.update(snapshot: snapshot, image: images.cache[snapshot.key], icon: app?.icon)
        }
    }

    func containsPointer(_ point: CGPoint) -> Bool {
        presented && panel.frame.union(anchor).insetBy(dx: -8, dy: -8).contains(appKitPoint(point))
    }

    func hide(animated: Bool = true) {
        guard presented || !animated else { return }
        presented = false
        transitionGeneration += 1
        let generation = transitionGeneration
        cards.removeAll()
        windowKeys = []
        app = nil
        if !animated {
            panel.orderOut(nil)
            panel.alphaValue = 0
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.08 : 0.13
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.transitionGeneration == generation, !self.presented else { return }
            self.panel.orderOut(nil)
        }
    }
}
