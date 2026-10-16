public struct WindowState: Equatable {
    public let id: Int
    public let minimized: Bool
    public let canMinimize: Bool
    public let fullScreen: Bool

    public init(id: Int, minimized: Bool = false, canMinimize: Bool = true, fullScreen: Bool = false) {
        self.id = id
        self.minimized = minimized
        self.canMinimize = canMinimize
        self.fullScreen = fullScreen
    }
}

public enum DockClickAction: Equatable {
    case native
    case minimize(Int)
    case restore(Int)
}

public struct DockClickPolicy {
    public init() {}

    public func action(windows: [WindowState], isFrontmost: Bool, recentID: Int?, lastMinimizedID: Int?) -> DockClickAction {
        if let window = windows.first(where: { $0.id == lastMinimizedID && $0.minimized && $0.canMinimize && !$0.fullScreen }) {
            return .restore(window.id)
        }
        guard let window = windows.first(where: { $0.id == recentID }) else { return .native }
        guard window.canMinimize, !window.fullScreen else { return .native }
        if window.minimized { return .restore(window.id) }
        guard isFrontmost else { return .native }
        return .minimize(window.id)
    }
}
