import AppKit
import DockCore

private let replayMarker: Int64 = 0x444F434B454E48

private func dockEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    return Unmanaged<DockService>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
}

final class DockService {
    let controller = WindowController()
    let locator = DockLocator()
    let images = PreviewImages()
    let preview = PreviewPanel()
    private(set) var running = false
    var onStatusChanged: (() -> Void)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var hovered: DockItem?
    private var lastInside = Date.distantPast
    private var lastRefresh = Date.distantPast
    private var lastCapture = Date.distantPast
    private var prepared: [pid_t: [AppWindow]] = [:]
    private var pending: (down: CGEvent, item: DockItem, windows: [AppWindow], action: DockClickAction)?
    private var hoverPolicy = PreviewHoverPolicy()
    private var contextMenuInteraction = false
    private var contextMenuStarted = Date.distantPast

    init() {
        preview.onSelect = { [weak self] window, app in
            self?.controller.reveal(window, app: app)
            self?.hovered = nil
            self?.hoverPolicy.beginInteraction(appID: app.processIdentifier)
            self?.hoverPolicy.endInteraction()
        }
        images.onUpdate = { [weak self] in
            guard let self else { return }
            self.preview.updateImages(self.images)
        }
    }

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        guard AXIsProcessTrusted() else { return false }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .keyDown]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                            options: .defaultTap, eventsOfInterest: mask,
                                            callback: dockEventCallback,
                                            userInfo: Unmanaged.passUnretained(self).toOpaque()),
              let newSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else { return false }
        tap = newTap
        source = newSource
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        running = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in self?.tick() }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        tick()
        onStatusChanged?()
        return true
    }

    func stop() {
        if let pending { repost(pending.down); self.pending = nil }
        timer?.invalidate()
        timer = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        source = nil
        tap = nil
        running = false
        hoverPolicy = PreviewHoverPolicy()
        contextMenuInteraction = false
        hovered = nil
        prepared.removeAll()
        preview.hide()
        images.clear()
        controller.userChangedWindow()
        onStatusChanged?()
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let pending { repost(pending.down); self.pending = nil }
            if !CGEventSource.buttonState(.combinedSessionState, button: .left) &&
               !CGEventSource.buttonState(.combinedSessionState, button: .right) {
                // A release can be lost while the tap is disabled. Retain suppression
                // for the clicked icon, but do not leave hover permanently held.
                hoverPolicy.endInteraction()
            }
            if running, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == replayMarker { return Unmanaged.passUnretained(event) }
        if type == .leftMouseUp || type == .rightMouseUp { hoverPolicy.endInteraction() }
        if type == .leftMouseDown || type == .rightMouseDown {
            controller.cancelDeferredReveal()
            let item = locator.item(at: event.location)
            if let item {
                hoverPolicy.beginInteraction(appID: item.app.processIdentifier)
                preview.hide(animated: false)
                if type == .rightMouseDown || event.flags.contains(.maskControl) {
                    contextMenuInteraction = true
                    contextMenuStarted = Date()
                }
            } else if !(preview.isVisible && preview.panel.frame.contains(appKitPoint(event.location))) {
                hoverPolicy.beginInteraction(appID: hovered?.app.processIdentifier)
                preview.hide(animated: false)
            }
        }
        if type == .keyDown {
            // Observe activity only; never inspect key codes or characters. Working in a
            // different window ends the consecutive Dock-click restore interaction.
            controller.userChangedWindow()
            // Arrow keys can navigate a still-open Dock menu. Only the menu-state
            // check in tick() may release context-menu suppression.
            return Unmanaged.passUnretained(event)
        }
        if type == .leftMouseDragged, let pending {
            if hypot(event.location.x - pending.down.location.x, event.location.y - pending.down.location.y) > 5 {
                // Recreate the original press before the drag, preserving Dock icon reordering.
                repost(pending.down)
                repost(event)
                self.pending = nil
            }
            return nil
        }
        if type == .leftMouseUp, let pending {
            self.pending = nil
            let close = hypot(event.location.x - pending.down.location.x, event.location.y - pending.down.location.y) <= 5
            if close && !hasModifiers(event) && controller.perform(pending.action, app: pending.item.app, windows: pending.windows) {
                // Publish the confirmed command locally, then refresh Accessibility outside
                // the tap callback so a slow application cannot stall mouse delivery.
                let targetID: Int
                let isMinimized: Bool
                switch pending.action {
                case .minimize(let id): targetID = id; isMinimized = true
                case .restore(let id): targetID = id; isMinimized = false
                case .native: targetID = -1; isMinimized = false
                }
                prepared[pending.item.app.processIdentifier] = pending.windows.map { window in
                    guard window.key.id == targetID else { return window }
                    return AppWindow(element: window.element, key: window.key, title: window.title, frame: window.frame,
                                     state: WindowState(id: targetID, minimized: isMinimized, canMinimize: window.state.canMinimize, fullScreen: window.state.fullScreen))
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.running else { return }
                    self.prepared[pending.item.app.processIdentifier] = self.controller.windows(of: pending.item.app)
                }
                preview.hide()
                hovered = nil
                return nil
            }
            repost(pending.down)
            repost(event)
            return nil
        }
        guard type == .leftMouseDown || type == .rightMouseDown else { return Unmanaged.passUnretained(event) }
        guard type == .leftMouseDown, !hasModifiers(event),
              let item = locator.item(at: event.location),
              let windows = prepared[item.app.processIdentifier] else {
            controller.userChangedWindow()
            return Unmanaged.passUnretained(event)
        }
        controller.refreshFocusedWindow(of: item.app)
        let action = controller.action(for: item.app, windows: windows)
        guard action != .native, let down = event.copy() else {
            controller.userChangedWindow()
            return Unmanaged.passUnretained(event)
        }
        pending = (down, item, windows, action)
        preview.hide()
        return nil
    }

    private func hasModifiers(_ event: CGEvent) -> Bool {
        !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }

    private func repost(_ event: CGEvent) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: replayMarker)
        copy.post(tap: .cgSessionEventTap)
    }

    private func tick() {
        guard running, pending == nil else { return }
        guard AXIsProcessTrusted() else { stop(); return }
        let now = Date()
        if now.timeIntervalSince(lastRefresh) > 0.4 {
            lastRefresh = now
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
                let windows = controller.windows(of: app)
                prepared[app.processIdentifier] = windows
                if now.timeIntervalSince(lastCapture) > 2 {
                    lastCapture = now
                    if let recent = controller.recentWindow(of: app, in: windows) { images.refresh([recent]) }
                    controller.forgetTerminatedApps()
                    let live = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
                    prepared = prepared.filter { live.contains($0.key) }
                }
            }
        }
        let pointer = quartzPoint(NSEvent.mouseLocation)
        if contextMenuInteraction && now.timeIntervalSince(contextMenuStarted) > 0.4 && !locator.hasOpenMenu() {
            contextMenuInteraction = false
        }
        if let item = locator.item(at: pointer) {
            hoverPolicy.hover(appID: item.app.processIdentifier, time: now.timeIntervalSinceReferenceDate)
            lastInside = now
            if item.app.processIdentifier != hovered?.app.processIdentifier {
                hovered = item
                preview.hide()
                let windows = controller.windows(of: item.app)
                prepared[item.app.processIdentifier] = windows
                images.refresh(windows)
            }
            if hoverPolicy.allowsPreview(appID: item.app.processIdentifier, time: now.timeIntervalSinceReferenceDate,
                                         delay: PreviewPreferences.hoverDelay, menuOpen: contextMenuInteraction),
               let windows = prepared[item.app.processIdentifier] {
                refreshPreview(item: item, windows: windows)
            }
        } else if preview.containsPointer(pointer) {
            lastInside = now
        } else {
            hoverPolicy.leaveIcon()
            if now.timeIntervalSince(lastInside) > 0.25 {
                hovered = nil
                preview.hide()
            }
        }
        if preview.isVisible, now.timeIntervalSince(lastCapture) > 1, let app = preview.app {
            lastCapture = now
            let windows = controller.windows(of: app)
            prepared[app.processIdentifier] = windows
            if let item = hovered { refreshPreview(item: item, windows: windows) }
            images.refresh(windows)
        }
    }

    private func refreshPreview(item: DockItem, windows: [AppWindow]) {
        if windows.isEmpty { preview.hide() }
        else if !preview.isVisible || preview.windowKeys != windows.map(\.key) {
            preview.show(item: item, windows: windows, images: images)
        } else {
            preview.updateWindows(windows, images: images)
        }
    }
}
