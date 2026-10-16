import AppKit
import DockCore
import Carbon

private let replayMarker: Int64 = 0x444F434B454E48

private func dockEventCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, info: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let info else { return Unmanaged.passUnretained(event) }
    return Unmanaged<DockService>.fromOpaque(info).takeUnretainedValue().handle(type: type, event: event)
}

final class DockService {
    let controller = WindowController()
    let locator = DockLocator()
    let images: PreviewImages
    private let captureAccess: () -> Bool
    private let accessibilityAccess: () -> Bool
    let preview = PreviewPanel()
    lazy var switcher = NativeWindowSwitcher(controller: controller)
    private(set) var switcherEnabled = true
    private(set) var switcherAvailable = false
    private(set) var switcherUnavailableReason = "快捷键接管尚未就绪"
    private var keyboardHookVerified = false
    private static let keyboardMask: CGEventMask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(0) { $0 | (1 << $1.rawValue) }
    private var lastSwitcherRefresh = Date.distantPast
    private(set) var running = false
    private(set) var previewsEnabled = true
    private(set) var clickEnabled = true
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

    init(captureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         accessibilityAccess: @escaping () -> Bool = { AXIsProcessTrusted() }, capture: PreviewImages.Capture? = nil) {
        self.captureAccess = captureAccess
        self.accessibilityAccess = accessibilityAccess
        self.images = capture.map { PreviewImages(captureAccess: captureAccess, capture: $0) } ?? PreviewImages(captureAccess: captureAccess)
        preview.onSelect = { [weak self] window, app in
            self?.controller.reveal(window, app: app)
            self?.hovered = nil
            self?.hoverPolicy.beginInteraction(appID: app.processIdentifier)
            self?.hoverPolicy.endInteraction()
        }
        images.onUpdate = { [weak self] key in
            guard let self else { return }
            self.preview.updateImages(self.images)
            if let key { self.switcher.updatePreviewImage(self.images.cache[key], for: key.switcherID) }
            else { self.switcher.clearPreviewImages() }
        }
        switcher.onCandidatesChanged = { [weak self] candidates in
            guard let self, self.running, self.switcherEnabled else { return }
            self.publishSwitcherImages()
            self.images.refresh(candidates.map(\.window))
        }
    }

    private func publishSwitcherImages() {
        if images.cache.isEmpty { switcher.clearPreviewImages(); return }
        for candidate in switcher.candidates {
            switcher.updatePreviewImage(images.cache[candidate.window.key], for: candidate.id)
        }
    }

    private func refreshImageAvailability() {
        images.updateAvailability(hasConsumers: running && (previewsEnabled || switcherEnabled), captureGranted: captureAccess())
    }

    func configure(previewsEnabled: Bool, clickEnabled: Bool, switcherEnabled: Bool = true) {
        if self.switcherEnabled != switcherEnabled {
            switcher.stop()
            lastSwitcherRefresh = .distantPast
        }
        self.switcherEnabled = switcherEnabled
        if self.clickEnabled != clickEnabled {
            if let pending { repost(pending.down); self.pending = nil }
            controller.userChangedWindow()
        }
        if self.previewsEnabled != previewsEnabled {
            hovered = nil
            hoverPolicy = PreviewHoverPolicy()
            preview.hide(animated: false)
            lastCapture = .distantPast
        }
        self.previewsEnabled = previewsEnabled
        self.clickEnabled = clickEnabled
        if previewsEnabled || clickEnabled || switcherEnabled { start() }
        else { stop() }
        refreshImageAvailability()
        refreshSwitcherCapability()
    }

    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        guard accessibilityAccess() else { return false }
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .keyDown, .keyUp, .flagsChanged]
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
        keyboardHookVerified = hasKeyboardEventDelivery()
        refreshImageAvailability()
        refreshSwitcherCapability()
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
        keyboardHookVerified = false
        invalidateSwitcherCapability(reason: "快捷键接管尚未就绪")
        switcher.stop()
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
            invalidateSwitcherCapability(reason: "系统暂停了快捷键监听")
            if let pending { repost(pending.down); self.pending = nil }
            if !CGEventSource.buttonState(.combinedSessionState, button: .left) &&
               !CGEventSource.buttonState(.combinedSessionState, button: .right) {
                // A release can be lost while the tap is disabled. Retain suppression
                // for the clicked icon, but do not leave hover permanently held.
                hoverPolicy.endInteraction()
            }
            if running, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            DispatchQueue.main.async { [weak self] in self?.refreshSwitcherCapability() }
            return Unmanaged.passUnretained(event)
        }
        if !accessibilityAccess() { invalidateSwitcherCapability(reason: "需要辅助功能权限") }
        if event.getIntegerValueField(.eventSourceUserData) == replayMarker { return Unmanaged.passUnretained(event) }
        if switcherAvailable, accessibilityAccess(), switcher.handle(type: type, event: event) {
            preview.hide(animated: false)
            return nil
        }
        if type == .leftMouseUp || type == .rightMouseUp { hoverPolicy.endInteraction() }
        if type == .leftMouseDown || type == .rightMouseDown {
            if switcher.isSelecting { switcher.cancel() }
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
            // Switcher navigation was handled above using physical key codes only.
            // Other keyboard activity cancels deferred Dock/window restoration.
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
        guard clickEnabled, type == .leftMouseDown, !hasModifiers(event),
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

    /// One capability path shared by settings, input routing and fault recovery.
    /// A mouse-capable tap alone is insufficient evidence of keyboard interception.
    func refreshSwitcherCapability() {
        keyboardHookVerified = running && hasKeyboardEventDelivery()
        let reason: String?
        if !switcherEnabled { reason = "增强已关闭" }
        else if !accessibilityAccess() { reason = "需要辅助功能权限" }
        else if !running || tap == nil { reason = "无法创建快捷键监听" }
        else if let tap, !CGEvent.tapIsEnabled(tap: tap) { reason = "系统暂停了快捷键监听" }
        else if !keyboardHookVerified { reason = "系统未开放完整的键盘事件" }
        else if IsSecureEventInputEnabled() { reason = "安全输入期间暂不可用" }
        else { reason = nil }
        if let reason { invalidateSwitcherCapability(reason: reason) }
        else if !switcherAvailable {
            switcherAvailable = true
            switcherUnavailableReason = ""
            onStatusChanged?()
        }
    }

    private func invalidateSwitcherCapability(reason: String) {
        let changed = switcherAvailable || switcherUnavailableReason != reason
        switcherAvailable = false
        switcherUnavailableReason = reason
        if switcher.isSelecting || changed {
            switcher.interrupt()
        }
        if changed { onStatusChanged?() }
    }

    private func hasKeyboardEventDelivery() -> Bool {
        var count: UInt32 = 0
        guard CGGetEventTapList(0, nil, &count) == .success, count > 0 else { return false }
        var info = [CGEventTapInformation](repeating: CGEventTapInformation(), count: Int(count))
        guard CGGetEventTapList(count, &info, &count) == .success else { return false }
        return info.prefix(Int(count)).contains {
            $0.tappingProcess == getpid() && $0.options == .defaultTap && $0.enabled && $0.tapPoint == .cgSessionEventTap &&
                $0.eventsOfInterest & Self.keyboardMask == Self.keyboardMask
        }
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
        guard running else { return }
        refreshImageAvailability()
        guard accessibilityAccess() else { stop(); return }
        refreshSwitcherCapability()
        switcher.checkCommandState(commandIsDown: CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand))
        guard pending == nil else { return }
        let now = Date()
        if switcherAvailable, now.timeIntervalSince(lastSwitcherRefresh) > 0.8 {
            lastSwitcherRefresh = now
            switcher.refreshCandidates()
        }
        if switcher.isSelecting { preview.hide(animated: false); return }
        if now.timeIntervalSince(lastRefresh) > 0.4 {
            lastRefresh = now
            if let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() {
                let windows = controller.windows(of: app)
                prepared[app.processIdentifier] = windows
                if now.timeIntervalSince(lastCapture) > 2 {
                    lastCapture = now
                    if previewsEnabled, let recent = controller.recentWindow(of: app, in: windows) { images.refresh([recent]) }
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
                if previewsEnabled { images.refresh(windows) }
            }
            if previewsEnabled, hoverPolicy.allowsPreview(appID: item.app.processIdentifier, time: now.timeIntervalSinceReferenceDate,
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
        if previewsEnabled, preview.isVisible, now.timeIntervalSince(lastCapture) > 1, let app = preview.app {
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
