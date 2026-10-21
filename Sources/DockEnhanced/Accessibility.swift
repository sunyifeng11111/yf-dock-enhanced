import AppKit
import ApplicationServices
import DockCore

enum AX {
    static func value<T>(_ element: AXUIElement, _ name: String) -> T? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result as? T
    }

    static func rect(_ element: AXUIElement) -> CGRect? {
        guard let position: AXValue = value(element, kAXPositionAttribute),
              let size: AXValue = value(element, kAXSizeAttribute),
              AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &point), AXValueGetValue(size, .cgSize, &dimensions) else { return nil }
        return CGRect(origin: point, size: dimensions)
    }

    static func set(_ element: AXUIElement, _ name: String, _ value: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, name as CFString, value ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }
}

struct WindowKey: Hashable {
    let pid: pid_t
    let id: Int
}

/// AX elements provide equality, not a globally unique hash. Allocate process-local
/// identities so equal titles, hash collisions and refreshed wrappers stay distinct.
final class WindowIdentityRegistry {
    static let shared = WindowIdentityRegistry()
    private let lock = NSLock()
    private var entries: [pid_t: [(AXUIElement, Int)]] = [:]
    private var next = 0

    func key(for element: AXUIElement, pid: pid_t) -> WindowKey {
        lock.lock()
        defer { lock.unlock() }
        if let entry = entries[pid]?.first(where: { CFEqual($0.0, element) }) {
            return WindowKey(pid: pid, id: entry.1)
        }
        next += 1
        entries[pid, default: []].append((element, next))
        return WindowKey(pid: pid, id: next)
    }

    func knownElements(for pid: pid_t) -> [AXUIElement] {
        lock.lock()
        defer { lock.unlock() }
        return entries[pid, default: []].map(\.0)
    }

    /// Absence from AXWindows and failed/timed-out queries are not proof of
    /// closure. Only a definitive invalid element retires this exact identity.
    func forgetInvalidElement(_ element: AXUIElement, pid: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        entries[pid]?.removeAll { CFEqual($0.0, element) }
    }

    func forgetTerminatedApps(_ live: Set<pid_t>) {
        lock.lock()
        defer { lock.unlock() }
        entries = entries.filter { live.contains($0.key) }
    }
}

struct AppWindow {
    let element: AXUIElement
    let key: WindowKey
    let title: String
    let frame: CGRect
    let state: WindowState
}

struct DockItem {
    let app: NSRunningApplication
    let frame: CGRect  // Quartz coordinates, same as CGEvent.location.
}

final class DockLocator {
    private let system = AXUIElementCreateSystemWide()

    init() { AXUIElementSetMessagingTimeout(system, 0.04) }

    func hasOpenMenu() -> Bool {
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return false }
        let dock = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(dock, 0.03)
        let focused: AXUIElement? = AX.value(dock, kAXFocusedUIElementAttribute)
        if let focused {
            let role: String = AX.value(focused, kAXRoleAttribute) ?? ""
            if role == kAXMenuRole || role == kAXMenuItemRole { return true }
        }
        let children: [AXUIElement] = AX.value(dock, kAXChildrenAttribute) ?? []
        return children.contains { (AX.value($0, kAXRoleAttribute) as String?) == kAXMenuRole }
    }

    func item(at point: CGPoint) -> DockItem? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success else { return nil }
        for _ in 0..<6 {
            guard let node = hit else { return nil }
            let role: String? = AX.value(node, kAXRoleAttribute)
            if role == "AXDockItem" {
                let subrole: String = AX.value(node, kAXSubroleAttribute) ?? ""
                guard !subrole.contains("Minimized"),
                      let url: URL = AX.value(node, kAXURLAttribute), url.pathExtension.lowercased() == "app",
                      let frame = AX.rect(node), frame.contains(point),
                      let app = NSWorkspace.shared.runningApplications.first(where: {
                          $0.bundleURL?.standardizedFileURL == url.standardizedFileURL && !$0.isTerminated
                      }) else { return nil }
                return DockItem(app: app, frame: frame)
            }
            hit = AX.value(node, kAXParentAttribute)
        }
        return nil
    }

    // Used only by the local integration check; no user app names are logged.
    func item(for app: NSRunningApplication) -> DockItem? {
        guard let dock = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.dock" }) else { return nil }
        var queue = [AXUIElementCreateApplication(dock.processIdentifier)]
        for _ in 0..<200 {
            guard !queue.isEmpty else { break }
            let node = queue.removeFirst()
            let role: String? = AX.value(node, kAXRoleAttribute)
            let subrole: String = AX.value(node, kAXSubroleAttribute) ?? ""
            if role == "AXDockItem", !subrole.contains("Minimized"),
               let url: URL = AX.value(node, kAXURLAttribute),
               url.standardizedFileURL == app.bundleURL?.standardizedFileURL,
               let frame = AX.rect(node) { return DockItem(app: app, frame: frame) }
            let children: [AXUIElement] = AX.value(node, kAXChildrenAttribute) ?? []
            queue.append(contentsOf: children)
        }
        return nil
    }
}

final class WindowController {
    private var recent: [pid_t: Int] = [:]
    private var minimizedByClick: [pid_t: Int] = [:]
    private var revealGeneration = 0
    private let policy = DockClickPolicy()

    func windows(of app: NSRunningApplication) -> [AppWindow] {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.06)
        var reportedValue: CFTypeRef?
        // A timed-out owner is not a successful empty/full-screen inventory.
        // Avoid multiplying its messaging timeout across every retained element.
        guard AXUIElementCopyAttributeValue(owner, kAXWindowsAttribute as CFString, &reportedValue) == .success,
              let reported = reportedValue as? [AXUIElement] else { return [] }
        // AppKit can omit ordinary windows from AXWindows while that application
        // is full screen. Keep previously identified exact elements discoverable;
        // every retained element still has to pass live role/frame/state reads.
        let elements = reported + WindowIdentityRegistry.shared.knownElements(for: app.processIdentifier)
        let focused: AXUIElement? = AX.value(owner, kAXFocusedWindowAttribute)
        var seen: [AXUIElement] = []
        var compositorWindows: [[String: Any]]?
        let windows = elements.compactMap { element -> AppWindow? in
            AXUIElementSetMessagingTimeout(element, 0.06)
            var roleValue: CFTypeRef?
            let roleResult = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue)
            if roleResult == .invalidUIElement {
                WindowIdentityRegistry.shared.forgetInvalidElement(element, pid: app.processIdentifier)
            }
            guard roleResult == .success, roleValue as? String == kAXWindowRole,
                  let frame = AX.rect(element), frame.width > 1, frame.height > 1 else { return nil }
            guard !seen.contains(where: { CFEqual($0, element) }) else { return nil }
            let rawTitle: String? = AX.value(element, kAXTitleAttribute)
            let title = rawTitle ?? ""
            let subrole: String? = AX.value(element, kAXSubroleAttribute)
            let isFocused = focused.map { CFEqual(element, $0) } ?? false
            // Frameworks can expose untitled backdrop/panel windows in AXWindows.
            // Preserve real untitled standard windows and active custom dialogs.
            if title.isEmpty, let subrole, subrole != kAXStandardWindowSubrole && subrole != kAXDialogSubrole,
               !isFocused, (AX.value(element, kAXMainAttribute) as Bool?) == false { return nil }
            let minimized: Bool = AX.value(element, kAXMinimizedAttribute) ?? false
            let fullScreen: Bool = AX.value(element, "AXFullScreen") ?? false
            // Some apps expose invisible floating helpers as focused AXDialogs.
            // Focus alone is not evidence that such a window has visible content.
            // Require positive compositor evidence; absence/ambiguous geometry
            // must not hide real dialogs, minimized windows or other Spaces.
            if title.isEmpty, subrole == kAXDialogSubrole, !minimized, !fullScreen,
               (AX.value(element, kAXMainAttribute) as Bool?) == false {
                if compositorWindows == nil {
                    compositorWindows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
                }
                let matches = (compositorWindows ?? []).filter { info in
                    guard (info[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier,
                          let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                          let bounds = CGRect(dictionaryRepresentation: bounds) else { return false }
                    return bounds == frame
                }
                if !matches.isEmpty, matches.allSatisfy({ info in
                    (info[kCGWindowAlpha as String] as? Double) == 0 &&
                    (info[kCGWindowLayer as String] as? Int).map { $0 > 0 } == true
                }) { return nil }
            }
            seen.append(element)
            let id = windowKey(for: element, pid: app.processIdentifier).id
            var writable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &writable)
            if isFocused, !minimized { recent[app.processIdentifier] = id }
            return AppWindow(element: element, key: WindowKey(pid: app.processIdentifier, id: id),
                             title: title.isEmpty ? "窗口 \(seen.count)" : title, frame: frame,
                             state: WindowState(id: id, minimized: minimized, canMinimize: writable.boolValue, fullScreen: fullScreen))
        }
        if !windows.contains(where: { $0.key.id == recent[app.processIdentifier] }) {
            recent[app.processIdentifier] = windows.first?.key.id
        }
        return windows
    }

    func windowKey(for element: AXUIElement, pid: pid_t) -> WindowKey {
        WindowIdentityRegistry.shared.key(for: element, pid: pid)
    }

    func focusedWindow(of app: NSRunningApplication, in windows: [AppWindow]) -> AppWindow? {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.04)
        guard let focused: AXUIElement = AX.value(owner, kAXFocusedWindowAttribute) else { return nil }
        return windows.first { CFEqual($0.element, focused) }
    }

    func isFocused(_ window: AppWindow, app: NSRunningApplication) -> Bool {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
              !app.isHidden,
              (AX.value(window.element, kAXMinimizedAttribute) as Bool?) == false else { return false }
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.04)
        guard let focused: AXUIElement = AX.value(owner, kAXFocusedWindowAttribute) else { return false }
        return CFEqual(focused, window.element)
    }

    func action(for app: NSRunningApplication, windows: [AppWindow]) -> DockClickAction {
        policy.action(windows: windows.map(\.state),
                      isFrontmost: NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier,
                      recentID: recent[app.processIdentifier], lastMinimizedID: minimizedByClick[app.processIdentifier])
    }

    func recentWindow(of app: NSRunningApplication, in windows: [AppWindow]) -> AppWindow? {
        windows.first(where: { $0.key.id == recent[app.processIdentifier] }) ?? windows.first
    }

    func refreshFocusedWindow(of app: NSRunningApplication) {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.04)
        if let focused: AXUIElement = AX.value(owner, kAXFocusedWindowAttribute) {
            recent[app.processIdentifier] = windowKey(for: focused, pid: app.processIdentifier).id
        }
    }

    func perform(_ action: DockClickAction, app: NSRunningApplication, windows: [AppWindow]) -> Bool {
        switch action {
        case .native: return false
        case .minimize(let id):
            cancelDeferredReveal()
            guard let window = windows.first(where: { $0.key.id == id }),
                  (AX.value(window.element, "AXFullScreen") as Bool?) != true,
                  AX.set(window.element, kAXMinimizedAttribute, true) else { return false }
            minimizedByClick[app.processIdentifier] = id
            return true
        case .restore(let id):
            guard let window = windows.first(where: { $0.key.id == id }) else { return false }
            return reveal(window, app: app)
        }
    }

    /// Returns whether an exact-target request was accepted. Completion reports
    /// observed exact focus, never just AXRaise/app-activation request success.
    /// Cancellation invalidates deferred work and intentionally omits completion.
    @discardableResult
    func reveal(_ window: AppWindow, app: NSRunningApplication, completion: ((Bool) -> Void)? = nil) -> Bool {
        cancelDeferredReveal()
        let generation = revealGeneration
        var ownerPID: pid_t = 0
        guard !app.isTerminated,
              AXUIElementGetPid(window.element, &ownerPID) == .success, ownerPID == app.processIdentifier,
              (AX.value(window.element, kAXRoleAttribute) as String?) == kAXWindowRole,
              let frame = AX.rect(window.element), frame.width > 1, frame.height > 1 else {
            completion?(false)
            return false
        }
        // The Dock also uses this entry point from its mouse callback. Validate
        // only the exact supplied element here; full inventory refresh/retries
        // run in the deferred completion path rather than scanning inside a tap.
        let current = window
        // Hiding is application-wide; it is independent of a window's minimized
        // state. Public activation often unhides implicitly, but request both
        // operations explicitly rather than relying on that incidental behavior.
        if app.isHidden {
            app.unhide()
            let owner = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(owner, 0.06)
            _ = AX.set(owner, kAXHiddenAttribute, false)
        }
        let minimized: Bool = AX.value(current.element, kAXMinimizedAttribute) ?? current.state.minimized
        if minimized && !AX.set(current.element, kAXMinimizedAttribute, false) {
            completion?(false)
            return false
        }
        minimizedByClick.removeValue(forKey: app.processIdentifier)
        // Restoring can complete asynchronously. Keep the first foreground
        // request deferred so newer input can cancel it before it steals focus.
        if !minimized { _ = bringForward(current, app: app) }
        finishRestore(current, app: app, generation: generation, attempt: 0, completion: completion)
        return true
    }

    private func finishRestore(_ window: AppWindow, app: NSRunningApplication, generation: Int,
                               attempt: Int, completion: ((Bool) -> Void)?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, generation == self.revealGeneration else { return }
            guard !app.isTerminated else { completion?(false); return }
            // Full-screen/Space changes and restore animations are asynchronous.
            // Refresh by exact AX identity and bound retries for every window,
            // including already-unminimized windows of the current application.
            let current = self.windows(of: app).first { $0.key == window.key }
            if let current, self.isFocused(current, app: app) {
                self.recent[app.processIdentifier] = current.key.id
                completion?(true)
                return
            }
            guard attempt < 20 else { completion?(false); return }
            if let current {
                if app.isHidden { app.unhide() }
                _ = self.bringForward(current, app: app)
            }
            self.finishRestore(window, app: app, generation: generation, attempt: attempt + 1, completion: completion)
        }
    }

    private func bringForward(_ window: AppWindow, app: NSRunningApplication) -> Bool {
        let owner = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(owner, 0.06)
        if !AX.set(owner, kAXFrontmostAttribute, true) { app.activate(options: []) }
        let raised = AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
        _ = AX.set(window.element, kAXMainAttribute, true)
        _ = AX.set(window.element, kAXFocusedAttribute, true)
        return raised
    }

    func cancelDeferredReveal() { revealGeneration += 1 }

    func userChangedWindow() { minimizedByClick.removeAll(); cancelDeferredReveal() }

    func forgetTerminatedApps() {
        let pids = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        WindowIdentityRegistry.shared.forgetTerminatedApps(pids)
        recent = recent.filter { pids.contains($0.key) }
        minimizedByClick = minimizedByClick.filter { pids.contains($0.key) }
    }
}
