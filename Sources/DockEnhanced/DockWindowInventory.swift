import AppKit

/// The Dock reads completed snapshots; AX enumeration belongs to this worker.
/// Request state and delivery are confined to the main executor.
final class DockWindowInventory {
    struct Observation {
        let windows: [AppWindow]
        let recentID: Int?
    }
    typealias Scan = (NSRunningApplication) -> Observation

    private final class Request {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    }

    var onUpdate: ((NSRunningApplication, Observation) -> Void)?
    private let queue = DispatchQueue(label: "dev.yifeng.DockEnhanced.dock-inventory", qos: .userInitiated)
    private let scan: Scan
    private var requests: [pid_t: Request] = [:]

    init(scan: Scan? = nil) {
        let scanner = WindowController()
        self.scan = scan ?? { app in
            let windows = scanner.windows(of: app)
            return Observation(windows: windows, recentID: scanner.recentWindow(of: app, in: windows)?.key.id)
        }
    }

    @discardableResult
    func refresh(_ app: NSRunningApplication) -> Bool {
        let pid = app.processIdentifier
        guard !app.isTerminated, requests[pid] == nil else { return false }
        let request = Request()
        requests[pid] = request
        queue.async { [weak self, scan] in
            guard !request.isCancelled else { return }
            let observation = scan(app)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.requests[pid] === request else { return }
                self.requests.removeValue(forKey: pid)
                guard !request.isCancelled, !app.isTerminated else { return }
                self.onUpdate?(app, observation)
            }
        }
        return true
    }

    /// A newer window command must not be overwritten by an older AX snapshot.
    func invalidate(_ pid: pid_t) { requests.removeValue(forKey: pid)?.cancel() }

    func invalidateAll() {
        for request in requests.values { request.cancel() }
        requests.removeAll()
    }

    deinit { for request in requests.values { request.cancel() } }
}
