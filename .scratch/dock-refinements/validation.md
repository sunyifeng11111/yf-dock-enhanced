# UI and preview refinements — validation

Date: 2026-10-15 (Asia/Shanghai)

## Reproduction and diagnosis

`swift run --build-system native DockEnhanced --check-chrome-preview` reproduced the actual image-cache failure: `Chrome thumbnail check: 0/1 actual images`.

The minimal case was one non-minimized Chrome window. Read-only instrumentation found two capture windows with identical geometry, zero exact title matches, and one match after removing application-added title suffixes. The old strict matching rule rejected both candidates. Normalizing the suffix while requiring a unique match fixed the original loop: `Chrome thumbnail check: 1/1 actual images`. Browser titles and URLs were neither logged nor saved.

`scripts/check-native.sh` reproduced the right-click failure: `FAIL: right click hides a visible preview immediately`. The old right-click branch never dismissed the panel or blocked the ongoing hover. The new policy dismisses on mouse down, blocks held buttons and menus, and re-arms only after leaving/reentering an icon.

## Verification

- 16 public behavior checks pass, covering click selection plus hover dwell, held buttons, post-click suppression, context-menu blocking, fast clicks before the first hover tick, and moving between icons.
- Native two-window integration passes, including immediate right-click dismissal, held-right-button suppression, suppression after release, suppression after minimize, exact preview selection, cached minimized preview, restoration, and keyboard activity.
- The real native Dock context menu was detected, navigated with an arrow key after leaving/reentering the icon, and dismissed with Escape. Previews remained suppressed during navigation and resumed after menu closure.
- A missed-release regression failed before the recovery fix (`FAIL: event-tap recovery restores hover after a missed button release`) and passed afterward. Recovery reconciles physical button state while retaining suppression for the clicked icon.
- Native screenshot `docs/images/preview.png` was visually inspected: the hovered second card has a tinted background and indigo outline.
- The actual packaged settings window was inspected through native Accessibility and a screenshot. Hero, running status, enable switch, hover-delay slider, permission rows, and footer fit without clipping.
- Appearance/dismissal transitions use native AppKit animations with cancellation generations; Reduce Motion reduces duration and removes the entry offset.
- Temporary Chrome instrumentation was removed. The Chrome check remains as a debug-only regression tool.

## Final review

Standards: two reliability findings were fixed (keyboard navigation releasing menu suppression; stale held-button state after event-tap interruption). Follow-up review found no remaining actionable issues.

Spec: the menu-navigation finding was fixed. Follow-up review found no remaining requirement gaps or scope creep. The added real-menu integration check subsequently passed.

## Limits and setup

The Chrome regression passed with one eligible visible window. A later run after desktop integration reported no eligible visible Chrome windows; this is an unavailable test scenario, not a capture failure.

Minimized windows continue to use their last cached frame; windows minimized before the first capture retain the icon/title fallback. The newly packaged app showed its own permissions as ungranted, so the user needs to grant Accessibility and Screen Recording to this updated local build.
