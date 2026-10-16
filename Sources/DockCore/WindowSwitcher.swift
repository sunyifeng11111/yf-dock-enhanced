/// Identity belongs to one concrete window, never to its title or application alone.
public struct SwitcherWindowID: Hashable {
    public let pid: Int32
    public let id: Int
    public init(pid: Int32, id: Int) { self.pid = pid; self.id = id }
}

public struct WindowSwitcherSnapshot: Equatable {
    public let windows: [SwitcherWindowID]
    public let selected: SwitcherWindowID
}

/// Complete selection workflow. Native adapters supply candidates and execute the
/// unique confirmed result; browsing itself has no window-management side effects.
public struct WindowSwitcher {
    public private(set) var snapshot: WindowSwitcherSnapshot?
    public init() {}

    public mutating func begin(windows: [SwitcherWindowID], current: SwitcherWindowID?, reverse: Bool = false) {
        var seen = Set<SwitcherWindowID>()
        let unique = windows.filter { seen.insert($0).inserted }
        guard !unique.isEmpty, unique != [current].compactMap({ $0 }) else { snapshot = nil; return }
        let start = current.flatMap { unique.firstIndex(of: $0) }
        let index = start.map { ($0 + (reverse ? unique.count - 1 : 1)) % unique.count } ?? (reverse ? unique.count - 1 : 0)
        snapshot = WindowSwitcherSnapshot(windows: unique, selected: unique[index])
    }

    public mutating func advance(reverse: Bool = false) {
        guard let snapshot, let index = snapshot.windows.firstIndex(of: snapshot.selected) else { return }
        let count = snapshot.windows.count
        let next = (index + (reverse ? count - 1 : 1)) % count
        self.snapshot = WindowSwitcherSnapshot(windows: snapshot.windows, selected: snapshot.windows[next])
    }

    public mutating func commandReleased() -> SwitcherWindowID? {
        let target = snapshot?.selected
        snapshot = nil
        return target
    }

    public mutating func cancel() { snapshot = nil }
}
