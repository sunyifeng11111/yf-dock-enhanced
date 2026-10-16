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
// The public workflow models what a user sees and confirms, without native windows.
let current = SwitcherWindowID(pid: 1, id: 10)
let minimizedTarget = SwitcherWindowID(pid: 1, id: 20)
let otherApp = SwitcherWindowID(pid: 2, id: 10)
var switcher = WindowSwitcher()
let candidates = [current, minimizedTarget, otherApp]
switcher.begin(windows: candidates, current: current)
expectVisibility(switcher.snapshot?.selected == minimizedTarget, true, "first Tab selects a different exact window, including a minimized target")
expectVisibility(switcher.commandReleased() == minimizedTarget, true, "Command release confirms that exact target")
expectVisibility(switcher.commandReleased() == nil && switcher.snapshot == nil, true, "a completed gesture cannot confirm twice")
switcher.begin(windows: candidates, current: current, reverse: true)
expectVisibility(switcher.snapshot?.selected == otherApp, true, "Shift+Tab starts at the preceding window with wrapping")
switcher.advance()
expectVisibility(switcher.snapshot?.selected == current, true, "forward navigation wraps back to the current window")
switcher.advance(reverse: true)
expectVisibility(switcher.snapshot?.selected == otherApp, true, "reverse navigation wraps independently")
switcher.cancel()
expectVisibility(switcher.commandReleased() == nil, true, "Escape cancellation never activates a browsed window")
switcher.begin(windows: [current, current, minimizedTarget], current: current)
expectVisibility(switcher.snapshot?.windows == [current, minimizedTarget], true, "duplicate identities are displayed once without collapsing same-app windows")
switcher.cancel()
switcher.begin(windows: [], current: current)
expectVisibility(switcher.commandReleased() == nil, true, "empty inventory has no confirmation")
switcher.begin(windows: [current], current: current)
expectVisibility(switcher.commandReleased() == nil, true, "only the current window leaves focus unchanged")
// Actual focus, rather than a request or browsing, establishes recent-window order.
var recent = WindowSwitcher()
recent.observeFocus(otherApp)
recent.observeFocus(minimizedTarget)
recent.observeFocus(current)
recent.begin(windows: [current, otherApp, minimizedTarget], current: current)
expectVisibility(recent.snapshot?.windows == [current, minimizedTarget, otherApp], true, "actual use ranks individual windows across applications")
recent.advance()
_ = recent.commandReleased()
recent.begin(windows: [otherApp, current, minimizedTarget], current: current)
expectVisibility(recent.snapshot?.selected == minimizedTarget, true, "browsing and confirming a request do not rewrite usage history")
recent.cancel()
recent.observeFocus(minimizedTarget)
recent.begin(windows: [current, otherApp, minimizedTarget], current: minimizedTarget)
expectVisibility(recent.commandReleased() == current, true, "observed focus enables quick two-window return")
var cold = WindowSwitcher()
let named = [SwitcherWindow(id: otherApp, appName: "Zeta", title: "Work"),
             SwitcherWindow(id: minimizedTarget, appName: "Alpha", title: "Work"),
             SwitcherWindow(id: current, appName: "Zeta", title: "Current")]
cold.begin(candidates: named, current: current, time: 10)
expectVisibility(cold.snapshot?.windows == [current, minimizedTarget, otherApp], true, "cold start places current first and unknown windows in stable name order")
expectVisibility(cold.isPanelVisible, false, "a quick gesture starts without a panel")
cold.advanceTime(to: 10.119)
expectVisibility(cold.isPanelVisible, false, "panel remains hidden before the display threshold")
cold.advanceTime(to: 10.121)
expectVisibility(cold.isPanelVisible, true, "held gesture shows a panel after 120ms without waiting for images")
cold.cancel()
cold.advanceTime(to: 30)
expectVisibility(cold.isPanelVisible, false, "an obsolete display time cannot reopen a canceled panel")
cold.begin(candidates: named, current: current, time: 40)
_ = cold.commandReleased()
cold.advanceTime(to: 41)
expectVisibility(cold.isPanelVisible, false, "a quick confirmation never flashes a panel later")
let fourth = SwitcherWindowID(pid: 3, id: 40)
let fifth = SwitcherWindowID(pid: 3, id: 50)
var grid = WindowSwitcher()
grid.begin(windows: [current, minimizedTarget, otherApp, fourth, fifth], current: current)
grid.move(.down, columns: 3)
expectVisibility(grid.snapshot?.selected == fifth, true, "Down selects the geometric card below, including a short final row")
grid.move(.right, columns: 3)
expectVisibility(grid.snapshot?.selected == fifth, true, "Right does not jump across a row boundary")
grid.move(.up, columns: 3)
expectVisibility(grid.snapshot?.selected == minimizedTarget, true, "Up returns to the column above")
grid.pointerMoved(over: fourth)
expectVisibility(grid.snapshot?.selected == fourth, true, "actual pointer movement shares the keyboard selection")
grid.updateAvailableWindows([current, minimizedTarget, fifth, SwitcherWindowID(pid: 9, id: 99)])
expectVisibility(grid.snapshot?.windows == [current, minimizedTarget, fifth] && grid.snapshot?.selected == fifth, true, "closed selected window advances in frozen order and new windows wait for next session")
grid.updateAvailableWindows([])
expectVisibility(grid.commandReleased() == nil, true, "closing the last candidate cancels without activation")
var renamed = WindowSwitcher()
renamed.observeFocus(minimizedTarget)
renamed.observeFocus(current)
renamed.begin(candidates: [SwitcherWindow(id: current, appName: "App", title: "Same"), SwitcherWindow(id: minimizedTarget, appName: "App", title: "Renamed")], current: current, time: 0)
expectVisibility(renamed.snapshot?.selected == minimizedTarget, true, "renaming a window preserves its own recent-use identity")
renamed.cancel()
renamed.begin(candidates: [SwitcherWindow(id: current, appName: "App", title: "Same"), SwitcherWindow(id: minimizedTarget, appName: "App", title: "Same")], current: current, time: 1)
expectVisibility(renamed.snapshot?.windows == [current, minimizedTarget], true, "same application and title still represent separate windows")
var restarted = WindowSwitcher()
restarted.begin(candidates: named, current: nil, time: 0)
expectVisibility(restarted.snapshot?.selected == minimizedTarget, true, "a new utility run has only stable cold ordering and no old history")
renamed.updateAvailableWindows([minimizedTarget])
expectVisibility(renamed.snapshot?.selected == minimizedTarget, true, "closing an unselected window preserves the selected target")
renamed.updateAvailableWindows([])
renamed.advanceTime(to: 100)
expectVisibility(!renamed.isPanelVisible && renamed.commandReleased() == nil, true, "an empty session invalidates its pending presentation and confirmation")
// Native inventories may drop several targets and add others between scans.
var changing = WindowSwitcher()
changing.begin(windows: [current, minimizedTarget, otherApp], current: current)
changing.updateAvailableWindows([current, minimizedTarget, fourth])
expectVisibility(changing.snapshot?.windows == [current, minimizedTarget] && changing.snapshot?.selected == minimizedTarget, true, "closing an unselected window preserves the selected target and order")
changing.cancel()
changing.begin(windows: [current, minimizedTarget, fourth], current: current)
expectVisibility(changing.snapshot?.windows.contains(fourth) == true, true, "a newly created window enters the next selection session")
changing.cancel()
changing.begin(windows: [fourth], current: current)
expectVisibility(changing.commandReleased() == fourth, true, "one noncurrent candidate is a valid exact destination")
changing.begin(windows: [current, minimizedTarget], current: current)
changing.updateAvailableWindows([current, fourth])
expectVisibility(changing.commandReleased() == current, true, "a replacement window cannot inherit a vanished identity during selection")

print("\(checks) checks, \(failures) failures")
exit(failures == 0 ? 0 : 1)
