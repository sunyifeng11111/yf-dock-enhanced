import CoreGraphics

/// Recognizes movement of the window itself, once per mouse drag.
public struct WindowShakeGesture {
    private var size: CGSize?
    private var horizontal = AxisShake()
    private var vertical = AxisShake()
    private var triggered = false

    public init() {}

    public mutating func begin(frame: CGRect, time: Double) {
        size = frame.size
        horizontal = AxisShake(position: frame.minX, time: time)
        vertical = AxisShake(position: frame.minY, time: time)
        triggered = false
    }

    public mutating func update(frame: CGRect, time: Double) -> Bool {
        guard let size, !triggered else { return false }
        // A resize or a system snap ends recognition until the next drag.
        guard abs(frame.width - size.width) <= 1, abs(frame.height - size.height) <= 1 else {
            self.size = nil
            return false
        }
        let x = horizontal.update(position: frame.minX, time: time)
        let y = vertical.update(position: frame.minY, time: time)
        triggered = x || y
        return triggered
    }
}

private struct AxisShake {
    private var extreme: Double
    private var lastTime: Double
    private var direction = 0
    private var reversals: [Double] = []

    init(position: Double = 0, time: Double = 0) { extreme = position; lastTime = time }

    mutating func update(position: Double, time: Double) -> Bool {
        // Require three quick reversals, each after substantial window travel.
        if time < lastTime { self = AxisShake(position: position, time: time); return false }
        lastTime = time
        reversals.removeAll { time < $0 || time - $0 > 0.75 }
        let delta = position - extreme
        if direction == 0 {
            guard abs(delta) >= 24 else { return false }
            direction = delta > 0 ? 1 : -1
            extreme = position
        } else if delta * Double(direction) > 0 {
            extreme = position
        } else if abs(delta) >= 24 {
            reversals.append(time)
            direction = -direction
            extreme = position
        }
        return reversals.count >= 3
    }
}
