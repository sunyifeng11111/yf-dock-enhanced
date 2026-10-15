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
func expectVisibility(_ actual: Bool, _ expected: Bool, _ description: String) {
    checks += 1
    if actual != expected { failures += 1; print("FAIL: \(description)") }
}
var hover = PreviewHoverPolicy()
hover.hover(appID: 100, time: 0)
expectVisibility(hover.allowsPreview(appID: 100, time: 0.3, delay: 0.85, menuOpen: false), false, "quick click approach does not show previews")
expectVisibility(hover.allowsPreview(appID: 100, time: 1, delay: 0.85, menuOpen: false), true, "deliberate hover shows previews")
hover.beginInteraction(appID: 100)
expectVisibility(hover.allowsPreview(appID: 100, time: 5, delay: 0.85, menuOpen: false), false, "holding a mouse button suppresses previews")
hover.endInteraction()
expectVisibility(hover.allowsPreview(appID: 100, time: 10, delay: 0.85, menuOpen: false), false, "releasing a click does not reopen previews on the same icon")
hover.leaveIcon()
hover.hover(appID: 100, time: 11)
expectVisibility(hover.allowsPreview(appID: 100, time: 12, delay: 0.85, menuOpen: false), true, "leaving and reentering re-arms previews")
expectVisibility(hover.allowsPreview(appID: 100, time: 12, delay: 0.85, menuOpen: true), false, "native context menu suppresses previews")
var quickClick = PreviewHoverPolicy()
quickClick.beginInteraction(appID: 200)
quickClick.endInteraction()
quickClick.hover(appID: 200, time: 0)
expectVisibility(quickClick.allowsPreview(appID: 200, time: 3, delay: 0.85, menuOpen: false), false, "a click before the first hover tick still suppresses that icon")
hover.beginInteraction(appID: 100)
hover.endInteraction()
hover.hover(appID: 200, time: 20)
hover.hover(appID: 100, time: 21)
expectVisibility(hover.allowsPreview(appID: 100, time: 23, delay: 0.85, menuOpen: false), true, "visiting a different icon re-arms the previous icon")
print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
