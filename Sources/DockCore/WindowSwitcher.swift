/// Identity belongs to one concrete window, never to its title or application alone.
public struct SwitcherWindowID: Hashable {
    public let pid: Int32
    public let id: Int
    public init(pid: Int32, id: Int) { self.pid = pid; self.id = id }
}

public struct SwitcherWindow {
    public let id: SwitcherWindowID
    public let appName: String
    public let title: String
    public init(id: SwitcherWindowID, appName: String, title: String) {
        self.id = id; self.appName = appName; self.title = title
    }
}

public enum SwitcherDirection { case left, right, up, down }

public struct WindowSwitcherSnapshot: Equatable {
    public let windows: [SwitcherWindowID]
    public let selected: SwitcherWindowID
}

/// Complete selection workflow. Native adapters supply candidates and execute the
/// unique confirmed result; browsing itself has no window-management side effects.
public struct WindowSwitcher {
    public private(set) var snapshot: WindowSwitcherSnapshot?
    public private(set) var isPanelVisible = false
    private var displayDeadline: Double?
    private var history: [SwitcherWindowID] = []
    public init() {}

    /// Report only an observed foreground window, never a selected/requested target.
    public mutating func observeFocus(_ window: SwitcherWindowID) {
        history.removeAll { $0 == window }
        history.insert(window, at: 0)
    }

    public mutating func begin(candidates: [SwitcherWindow], current: SwitcherWindowID?, reverse: Bool = false, time: Double) {
        let sorted = candidates.sorted {
            ($0.appName, $0.title, $0.id.pid, $0.id.id) < ($1.appName, $1.title, $1.id.pid, $1.id.id)
        }
        begin(windows: sorted.map(\.id), current: current, reverse: reverse, time: time)
    }

    public mutating func advanceTime(to time: Double) {
        if snapshot != nil, let displayDeadline, time >= displayDeadline { isPanelVisible = true }
    }

    public mutating func begin(windows: [SwitcherWindowID], current: SwitcherWindowID?, reverse: Bool = false, time: Double = 0) {
        cancel()
        if let current, windows.contains(current) { observeFocus(current) }
        var seen = Set<SwitcherWindowID>()
        let live = Set(windows)
        history.removeAll { !live.contains($0) }
        let unique = (history + windows).filter { live.contains($0) && seen.insert($0).inserted }
        guard !unique.isEmpty, unique != [current].compactMap({ $0 }) else { snapshot = nil; return }
        let start = current.flatMap { unique.firstIndex(of: $0) }
        let index = start.map { ($0 + (reverse ? unique.count - 1 : 1)) % unique.count } ?? (reverse ? unique.count - 1 : 0)
        snapshot = WindowSwitcherSnapshot(windows: unique, selected: unique[index])
        displayDeadline = time + 0.12
    }

    public mutating func advance(reverse: Bool = false) {
        guard let snapshot, let index = snapshot.windows.firstIndex(of: snapshot.selected) else { return }
        let count = snapshot.windows.count
        let next = (index + (reverse ? count - 1 : 1)) % count
        self.snapshot = WindowSwitcherSnapshot(windows: snapshot.windows, selected: snapshot.windows[next])
    }

    public mutating func move(_ direction: SwitcherDirection, columns: Int) {
        guard let snapshot, let index = snapshot.windows.firstIndex(of: snapshot.selected) else { return }
        let columns = max(1, columns)
        let row = index / columns
        let next: Int
        switch direction {
        case .left: next = max(row * columns, index - 1)
        case .right: next = min(snapshot.windows.count - 1, (row + 1) * columns - 1, index + 1)
        case .up: next = row == 0 ? index : index - columns
        case .down: next = (row + 1) * columns >= snapshot.windows.count ? index : min(snapshot.windows.count - 1, index + columns)
        }
        self.snapshot = WindowSwitcherSnapshot(windows: snapshot.windows, selected: snapshot.windows[next])
    }

    public mutating func pointerMoved(over window: SwitcherWindowID) {
        guard let snapshot, snapshot.windows.contains(window) else { return }
        self.snapshot = WindowSwitcherSnapshot(windows: snapshot.windows, selected: window)
    }

    /// A session only shrinks; refreshes cannot reorder or introduce a new target.
    public mutating func updateAvailableWindows(_ windows: [SwitcherWindowID]) {
        let live = Set(windows)
        history.removeAll { !live.contains($0) }
        guard let snapshot else { return }
        let remaining = snapshot.windows.filter { live.contains($0) }
        guard !remaining.isEmpty else { cancel(); return }
        let selected: SwitcherWindowID
        if live.contains(snapshot.selected) { selected = snapshot.selected }
        else {
            let oldIndex = snapshot.windows.firstIndex(of: snapshot.selected) ?? 0
            selected = snapshot.windows.dropFirst(oldIndex + 1).first { live.contains($0) } ?? remaining[0]
        }
        self.snapshot = WindowSwitcherSnapshot(windows: remaining, selected: selected)
    }

    public mutating func commandReleased() -> SwitcherWindowID? {
        let target = snapshot?.selected
        cancel()
        return target
    }

    public mutating func cancel() { snapshot = nil; isPanelVisible = false; displayDeadline = nil }
}
