import Foundation
import DockCore

var failures = 0
var checks = 0
func expect(_ actual: DockClickAction, _ expected: DockClickAction, _ description: String) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL: \(description): expected \(expected), got \(actual)")
    }
}

let policy = DockClickPolicy()
expect(policy.action(windows: [WindowState(id: 10), WindowState(id: 20)],
                     isFrontmost: true, recentID: 20, lastMinimizedID: nil),
       .minimize(20), "foreground click minimizes only the recent window")
expect(policy.action(windows: [WindowState(id: 10, minimized: true), WindowState(id: 20)],
                     isFrontmost: true, recentID: 20, lastMinimizedID: 10),
       .restore(10), "next click restores the same window even when another window became focused")
expect(policy.action(windows: [WindowState(id: 10, fullScreen: true)],
                     isFrontmost: true, recentID: 10, lastMinimizedID: nil),
       .native, "full-screen windows retain the native click behavior")
expect(policy.action(windows: [WindowState(id: 10, canMinimize: false)],
                     isFrontmost: true, recentID: 10, lastMinimizedID: nil),
       .native, "unsupported windows retain the native click behavior")
expect(policy.action(windows: [WindowState(id: 10, minimized: true)],
                     isFrontmost: false, recentID: 10, lastMinimizedID: nil),
       .restore(10), "a previously minimized recent window is restored")
expect(policy.action(windows: [WindowState(id: 10)],
                     isFrontmost: false, recentID: 10, lastMinimizedID: nil),
       .native, "background applications are activated by the native Dock")
expect(policy.action(windows: [], isFrontmost: true, recentID: 10, lastMinimizedID: 10),
       .native, "closed windows cannot be targeted")
expect(policy.action(windows: [WindowState(id: 20)],
                     isFrontmost: true, recentID: 20, lastMinimizedID: 10),
       .minimize(20), "a stale minimized-window reference does not block the current window")
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
