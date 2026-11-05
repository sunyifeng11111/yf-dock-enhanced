import AppKit
import DockCore

private final class ShakeCancellation {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

/// Input state belongs to the main thread; AX state belongs to a serial worker.
/// At most one sample is queued so a slow app cannot build a stale drag backlog.
final class WindowShakeService {
    private final class Drag {
        let cancellation = ShakeCancellation()
        var window: AppWindow?
        var app: NSRunningApplication?
        var gesture = WindowShakeGesture()
    }
    private let queue = DispatchQueue(label: "dev.yifeng.DockEnhanced.window-shake", qos: .userInitiated)
    private let isolation: ShakeWindowIsolation
    private var lifetime = ShakeCancellation()
    private var enabled = false
    private var drag: Drag?
    private var sampling = false
    private var sampleTimer: Timer?
    var onChange: (() -> Void)?

    init(applications: @escaping () -> [NSRunningApplication] = ShakeWindowIsolation.runningApplications) {
        isolation = ShakeWindowIsolation(applications: applications)
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        cancelDrag()
        lifetime.cancel()
        lifetime = ShakeCancellation()
        if !enabled { lifetime.cancel() }
    }

    func cancelDrag() {
        sampleTimer?.invalidate()
        sampleTimer = nil
        drag?.cancellation.cancel()
        drag = nil
        sampling = false
    }

    func interrupt() {
        cancelDrag()
        lifetime.cancel()
        lifetime = ShakeCancellation()
        if !enabled { lifetime.cancel() }
    }

    func observe(type: CGEventType, event: CGEvent) {
        guard enabled else { return }
        let pointer = event.location
        let time = Double(event.timestamp) / 1_000_000_000
        if type == .leftMouseDown || type == .rightMouseDown || type == .keyDown {
            // New intentional input cancels unfinished batch work/focus repair.
            lifetime.cancel()
            lifetime = ShakeCancellation()
        }
        if type == .leftMouseUp || type == .rightMouseDown || type == .keyDown {
            cancelDrag()
            return
        }
        if type == .leftMouseDown {
            cancelDrag()
            guard event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return }
            let request = Drag()
            drag = request
            sampling = true
            queue.async { [weak self] in
                defer { self?.finishSample(request) }
                guard !request.cancellation.isCancelled,
                      let (window, app) = Self.window(at: pointer) else { return }
                request.window = window
                request.app = app
                request.gesture.begin(frame: window.frame, time: time)
            }
        } else if type == .leftMouseDragged, drag != nil, sampleTimer == nil {
            let timer = Timer(timeInterval: 0.025, repeats: true) { [weak self] _ in self?.sample() }
            sampleTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func sample() {
        guard let request = drag, !request.cancellation.isCancelled, !sampling else { return }
        sampling = true
        let lifetime = lifetime
        let time = ProcessInfo.processInfo.systemUptime
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.finishSample(request) }
            guard !request.cancellation.isCancelled, !lifetime.isCancelled,
                  let window = request.window, let app = request.app,
                  let frame = AX.rect(window.element) else { return }
            guard request.gesture.update(frame: frame, time: time),
                  !request.cancellation.isCancelled, !lifetime.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
            request.cancellation.cancel() // one batch action per drag
            self.isolation.toggle(except: window, app: app, continuing: { !lifetime.isCancelled })
            DispatchQueue.main.async { [weak self] in self?.onChange?() }
        }
    }

    private func finishSample(_ request: Drag) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.drag === request else { return }
            if request.cancellation.isCancelled || request.window == nil { self.cancelDrag(); return }
            self.sampling = false
        }
    }

    private static func window(at point: CGPoint) -> (AppWindow, NSRunningApplication)? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.04)
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        for _ in 0..<8 {
            guard let element = hit else { return nil }
            AXUIElementSetMessagingTimeout(element, 0.04)
            if (AX.value(element, kAXRoleAttribute) as String?) == kAXWindowRole {
                var pid: pid_t = 0
                guard AXUIElementGetPid(element, &pid) == .success,
                      let app = NSRunningApplication(processIdentifier: pid), !app.isHidden,
                      app.activationPolicy != .prohibited,
                      (AX.value(element, "AXFullScreen") as Bool?) != true,
                      (AX.value(element, kAXMinimizedAttribute) as Bool?) == false,
                      let frame = AX.rect(element) else { return nil }
                let key = WindowIdentityRegistry.shared.key(for: element, pid: pid)
                return (AppWindow(element: element, key: key, title: "", frame: frame,
                                  state: WindowState(id: key.id)), app)
            }
            hit = AX.value(element, kAXWindowAttribute) ?? AX.value(element, kAXParentAttribute)
        }
        return nil
    }

    deinit { sampleTimer?.invalidate(); lifetime.cancel(); drag?.cancellation.cancel() }
}

/// Confined to the shake worker. Restores exact elements without activation.
final class ShakeWindowIsolation {
    private struct Entry { let window: AppWindow; let app: NSRunningApplication }
    private let applications: () -> [NSRunningApplication]
    private let controller = WindowController()
    private var batch: [Entry] = []
    private var focusCancellation = ShakeCancellation()

    static func runningApplications() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { $0.activationPolicy != .prohibited }
    }

    init(applications: @escaping () -> [NSRunningApplication] = ShakeWindowIsolation.runningApplications) {
        self.applications = applications
    }

    func toggle(except kept: AppWindow, app: NSRunningApplication, continuing: @escaping () -> Bool = { true }) {
        focusCancellation.cancel()
        focusCancellation = ShakeCancellation()
        guard continuing(), !app.isTerminated, !app.isHidden,
              (AX.value(kept.element, kAXMinimizedAttribute) as Bool?) == false,
              (AX.value(kept.element, "AXFullScreen") as Bool?) != true else { return }
        if !batch.isEmpty {
            var remaining: [Entry] = []
            for entry in batch {
                guard continuing() else { remaining.append(entry); continue }
                guard !entry.app.isTerminated, !entry.app.isHidden,
                      (AX.value(entry.window.element, "AXFullScreen") as Bool?) != true else { continue }
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(entry.window.element, kAXMinimizedAttribute as CFString, &value)
                if result == .invalidUIElement { continue }
                guard result == .success, let minimized = value as? Bool else { remaining.append(entry); continue }
                guard minimized else { continue }
                guard eligible(entry.window, app: entry.app), continuing() else { remaining.append(entry); continue }
                if !AX.set(entry.window.element, kAXMinimizedAttribute, false, ifAllowed: continuing) { remaining.append(entry) }
            }
            batch = remaining
            // AppKit may focus a deminiaturized sibling. Reassert only within
            // the still-foreground app; never activate an app over newer input.
            let cancellation = focusCancellation
            let restoreFocus = {
                guard !cancellation.isCancelled, continuing(), !app.isTerminated, !app.isHidden,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                let allowed = { !cancellation.isCancelled && continuing() }
                _ = AX.perform(kAXRaiseAction, on: kept.element, ifAllowed: allowed)
                guard !cancellation.isCancelled, continuing() else { return }
                _ = AX.set(kept.element, kAXMainAttribute, true, ifAllowed: allowed)
                guard !cancellation.isCancelled, continuing() else { return }
                _ = AX.set(kept.element, kAXFocusedAttribute, true, ifAllowed: allowed)
            }
            restoreFocus()
            // AppKit changes key windows again when deminiaturization finishes.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.55, execute: restoreFocus)
            return
        }
        for owner in applications() where !owner.isTerminated && !owner.isHidden {
            guard continuing() else { break }
            // AXWindows includes discoverable ordinary Spaces and all displays.
            for window in controller.windows(of: owner) where window.key != kept.key {
                guard continuing() else { return }
                guard eligible(window, app: owner),
                      (AX.value(window.element, kAXMinimizedAttribute) as Bool?) == false else { continue }
                if AX.set(window.element, kAXMinimizedAttribute, true, ifAllowed: continuing) { batch.append(Entry(window: window, app: owner)) }
            }
        }
    }

    private func eligible(_ window: AppWindow, app: NSRunningApplication) -> Bool {
        var pid: pid_t = 0
        var writable = DarwinBoolean(false)
        return !app.isTerminated && !app.isHidden &&
            AXUIElementGetPid(window.element, &pid) == .success && pid == app.processIdentifier &&
            (AX.value(window.element, kAXRoleAttribute) as String?) == kAXWindowRole &&
            (AX.value(window.element, "AXFullScreen") as Bool?) != true &&
            AXUIElementIsAttributeSettable(window.element, kAXMinimizedAttribute as CFString, &writable) == .success && writable.boolValue
    }

    deinit { focusCancellation.cancel() }
}
