public struct PreviewHoverPolicy {
    private var target: Int32?
    private var started = 0.0
    private var blocked: Int32?
    private var buttonDown = false
    public init() {}
    public mutating func hover(appID: Int32, time: Double) {
        if target != appID { target = appID; started = time; blocked = nil }
    }
    public mutating func leaveIcon() { target = nil; blocked = nil }
    public mutating func beginInteraction(appID: Int32?) {
        if let appID { target = appID }
        blocked = appID ?? target
        buttonDown = true
    }
    public mutating func endInteraction() { buttonDown = false }
    public func allowsPreview(appID: Int32, time: Double, delay: Double, menuOpen: Bool) -> Bool {
        target == appID && blocked != appID && !buttonDown && !menuOpen && time - started >= delay
    }
}
