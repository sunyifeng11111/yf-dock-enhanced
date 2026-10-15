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
        let elements: [AXUIElement] = AX.value(owner, kAXWindowsAttribute) ?? []
        let focused: AXUIElement? = AX.value(owner, kAXFocusedWindowAttribute)
        var seen: [AXUIElement] = []
        let windows = elements.compactMap { element -> AppWindow? in
            AXUIElementSetMessagingTimeout(element, 0.06)
            let role: String? = AX.value(element, kAXRoleAttribute)
            guard role == kAXWindowRole, let frame = AX.rect(element), frame.width > 1, frame.height > 1 else { return nil }
            guard !seen.contains(where: { CFEqual($0, element) }) else { return nil }
            let rawTitle: String? = AX.value(element, kAXTitleAttribute)
            let title = rawTitle ?? ""
            let subrole: String? = AX.value(element, kAXSubroleAttribute)
            let isFocused = focused.map { CFEqual(element, $0) } ?? false
            // Frameworks can expose untitled backdrop/panel windows in AXWindows.
            // Preserve real untitled standard windows and active custom dialogs.
            if rawTitle?.isEmpty == true, let subrole, subrole != kAXStandardWindowSubrole && subrole != kAXDialogSubrole,
               !isFocused, (AX.value(element, kAXMainAttribute) as Bool?) == false { return nil }
            seen.append(element)
            let id = Int(CFHash(element))
            var writable = DarwinBoolean(false)
            AXUIElementIsAttributeSettable(element, kAXMinimizedAttribute as CFString, &writable)
            let minimized: Bool = AX.value(element, kAXMinimizedAttribute) ?? false
            let fullScreen: Bool = AX.value(element, "AXFullScreen") ?? false
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
            recent[app.processIdentifier] = Int(CFHash(focused))
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

    @discardableResult
    func reveal(_ window: AppWindow, app: NSRunningApplication) -> Bool {
        cancelDeferredReveal()
        let generation = revealGeneration
        let minimized: Bool = AX.value(window.element, kAXMinimizedAttribute) ?? window.state.minimized
        if minimized && !AX.set(window.element, kAXMinimizedAttribute, false) { return false }
        if minimized {
            recent[app.processIdentifier] = window.key.id
            minimizedByClick.removeValue(forKey: app.processIdentifier)
            finishRestore(window, app: app, generation: generation, attempt: 0)
            return true
        }
        let raised = bringForward(window, app: app)
        recent[app.processIdentifier] = window.key.id
        minimizedByClick.removeValue(forKey: app.processIdentifier)
        return raised
    }

    private func finishRestore(_ window: AppWindow, app: NSRunningApplication, generation: Int, attempt: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, generation == self.revealGeneration, !app.isTerminated else { return }
            // A restored window can temporarily disappear from AXWindows while the
            // Dock animation runs. Raising it then may time out even after unminimize
            // succeeded. Refresh the element and retry outside the mouse event tap.
            let current = self.windows(of: app).first { $0.key == window.key && !$0.state.minimized }
            if current != nil, !app.isActive {
                let owner = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(owner, 0.06)
                _ = AX.set(owner, kAXFrontmostAttribute, true)
                app.activate(options: [])
                if attempt < 12 { self.finishRestore(window, app: app, generation: generation, attempt: attempt + 1) }
                return
            }
            if let current, self.bringForward(current, app: app) {
                self.recent[app.processIdentifier] = current.key.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    guard let self, generation == self.revealGeneration, attempt < 12 else { return }
                    if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                        self.finishRestore(window, app: app, generation: generation, attempt: attempt + 1)
                    }
                }
                return
            }
            if attempt < 12 { self.finishRestore(window, app: app, generation: generation, attempt: attempt + 1) }
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
        recent = recent.filter { pids.contains($0.key) }
        minimizedByClick = minimizedByClick.filter { pids.contains($0.key) }
    }
}
