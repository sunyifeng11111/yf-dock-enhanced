# Ticket 05 integrated validation

2026-10-16. Integration base: `17c353c`. Host: macOS 27.2 (26B5112a), Apple Silicon, one 2× physical display, Reduce Motion off. Resolution: implementation complete within the explicitly accepted cold-start discovery boundary; the unavailable environment matrix below is not a claim of universal compatibility.

## Changes and evidence boundary

The switcher cancels when Command is continuously absent across at least 100ms without a release callback. A single missing observation gives a queued normal release time to confirm. Explicit session generations reject obsolete preparation/show work. New activity cancels both queued activation and WindowController retries; all three confirmation paths retain their own key/mouse release. Exact restoration failure shows a nonactivating 1.6s notice, with no substitute target. Capability checks revalidate the actual tap keyboard mask, Accessibility, enabled state and secure input. Card metadata refreshes without identity changes; a persistent small application icon and separate minimized label remain visible with thumbnails.

A real regression introduced by the predecessor merge was found before ticket05 changes: minimized restore requested foreground activation synchronously, so immediately following user activity could no longer cancel it. The original native assertion failed. First foreground activation for minimized targets is deferred again; exact-focus completion and bounded retries remain. A failed owner AXWindows query now stops before walking retained elements, avoiding one messaging timeout per known window. Successful full-screen inventories still retain and revalidate known exact AX identities.

Tests use the agreed complete-selection workflow and native adapter seams. Modifier/time and Accessibility observations are injected only at OS boundaries. No real user permission was revoked, no password field or user secret was used, no actual preference domain or login registration was changed. Secure input was actually enabled by a disposable background fixture and disabled by that same fixture. The slow-AX case actually suspended a disposable fixture with SIGSTOP, with unconditional SIGCONT cleanup. No simulated boundary result is called proof of system permission revocation or arbitrary cross-Space support.

## Checks

| Check | Result and practical limit |
| --- | --- |
| DockCoreChecks | 50 checks, 0 failures; frozen order, closing selected/unselected/last window, deferred newcomer, replacement identity, one noncurrent target, MRU, timing and navigation |
| Native recovery | Passed: missing-release observation grace/cancellation, fresh gesture recovery, both tap-disable notifications, injected control-access loss/return, real secure-input cancellation/native Command+Tab/exit, all three minimized confirmations and subsequent new-activity cancellation, real close/new-window updates, exact failed-target notice and dismissal |
| Slow AX | Suspended fixture owner query: 0.061s; no-image panel while its inventory was pending: 0.141s. Cached selection did not await the AX scan. This is two fixture applications, not a benchmark of all third-party applications |
| Native interaction | 40 actual windows; quick MRU round trip, delayed nonactivating panel, geometric arrows, selected-card scrolling, stationary pointer, Enter/mouse/outside cancellation. Actual panel visible at 131ms with 5ms observation resolution; no core timer is used as native performance proof |
| Native reachability | Hidden/minimized exact targets and warm ordinary/full-screen switching rechecked; exact focus and fixture-reported visibility separately checked. Cold child process reproduces the accepted omitted-window boundary |
| Preference/image boundary | 16 checks, 0 failures; separate-process persistence, no-capture title/icon operation, asynchronous image arrival, revocation/regrant generation, minimized cache and cache bound; real TCC permission settings untouched |
| Feature services | 39 checks passed; all eight feature combinations, actual keyboard-hook availability, shared image lifetime and visible image removal using controlled capture boundary |
| Settings UI | Actual sidebar/page navigation and switcher toggle; isolated-domain persistence, icon/title status with capture false, close/reopen. No event tap/image consumer/login mutation. Light/dark screenshots visually inspected |
| Build | Debug and release build pass; source package version 0.6.0/build11, macOS14 minimum, identifier/signing unchanged. Installed app not replaced |

The recovery failure test closes a displayed real target and confirms its exact stale identity before the next inventory. It verifies visible feedback and unchanged exact source focus, rather than accepting an application activation result. All three confirmation-cancellation scenarios observe for 2.4s, beyond the normal bounded restoration retry interval.

## Original Dock regression and baseline comparison

Pre-change baseline is preserved in `/tmp/dock-command-tab-baseline-20261016.md`: original 16 core checks passed; one original runtime run failed native click with click control disabled while the installed app was also running, and the next failed click-only minimization with previews disabled after the installed app quit. These were pre-existing runtime results.

The merged predecessor baseline in `/tmp/dock-05-native-baseline.log` newly failed `new user activity cancels deferred foreground activation`; ticket05 fixed that production regression without weakening its assertion. The native harness now uses a separate disposable source fixture instead of minimizing or restoring real user source windows. It awaits actual asynchronous thumbnail readiness. `/tmp/dock-05-dock-final.log` passed the complete original native suite, including the held intercepted Dock press, click-only minimization/restoration, preview-only selection, native right-click menu/navigation, hover suppression, exact preview selection and feature restart. A subsequent controlled-backdrop run encountered an intermittent preview-click delivery failure; this is recorded rather than hidden. The final bounded rerun (`/tmp/dock-05-dock-last.log`) passed exact preview selection and both deferred-cancellation assertions, then failed `click control minimizes a window with previews disabled`, the same failure point as the pre-change second baseline. No further repeated runs were used to hide that result. The final status is therefore: one complete pass, a documented intermittent preview-click failure, and the reproduced pre-existing click-only failure; original Dock runtime stability remains a limitation.

Actual Dock icon dragging, modifier-click OS behavior, menu-bar-hide/reopen flow and login registration were not changed or exercised destructively; routing/bindings remain reviewed, and login registration was deliberately not mutated. Those scenarios are not additional runtime passes.

## User-story coverage (all 62)

“Pass” is bounded by the fixtures/system boundary stated above; “partial” identifies the actual unverified part.

| Stories | Evidence / status |
| --- | --- |
| 1–2 | Pass: independent default-on preference and upgrade/persistence boundary checks |
| 3–4 | Pass: actual two-app/multiple-window native inventory and exact selection |
| 5 | Implemented: only AX windows are candidates; browser-tab-specific third-party runtime coverage unverified |
| 6–7 | Pass: real minimized target preserved during browsing, restored to exact focus after confirmation |
| 8–9 | Pass: actual Command+H, cancel without unhide, confirm with exact visible target; hidden+minimized separately checked |
| 10 | Partial: ordinary/full-screen Spaces pass; two ordinary desktops unverified |
| 11 | Unavailable: second physical display absent |
| 12 | Pass for known exact full-screen windows, with explicitly accepted cold-start omission boundary |
| 13 | Partial: real untitled standard window passes; independent dialog matrix not separately exercised |
| 14–15 | Pass for duplicate/internal fixture filtering and actual Dock menu exclusion; broader application helper/dialog matrix unverified |
| 16 | Implemented: no application placeholder, empty inventory yields no card; windowless third-party application not separately exercised |
| 17–18 | Pass: real quick return/no flash, actual delayed native panel, slow-AX/no-image response |
| 19–21 | Pass: native Tab exact selection and deterministic reverse/wrap behavior |
| 22 | Implemented: native repeated key-down delivery advances; actual system key-repeat cadence not separately benchmarked |
| 23–24 | Pass: real release confirms once; browsing preserves exact source/minimized state |
| 25–29 | Pass: native arrows, Enter, pointer move/click, stationary pointer, Escape/outside cancellation |
| 30–32 | Pass: observed-focus MRU, real two-window round trip and separate same-app identities; deterministic per-window history |
| 33–36 | Pass: frozen session, minimized ordering, stable startup order and in-memory-only history; live rename identity core checks |
| 37 | Pass on the single display; multi-display placement unavailable |
| 38–39 | Implemented; no-foreground pointer fallback and cross-display pointer movement/display removal not physically exercised |
| 40–42 | Pass: inspected actual light/dark glass composition, centered titles, persistent app icons, neutral selection |
| 43–44 | Pass: actual 40-window grid, vertical scrolling and selected-card visibility |
| 45 | Pass: actual wide/portrait captures centered without distortion in preserved screenshots |
| 46–47 | Pass: controlled async title/icon-first path plus actual cached thumbnail/minimized label |
| 48 | Pass by implementation/boundary checks: memory-only bounded image cache; only dedicated test screenshots saved |
| 49–50 | Pass at capture-access boundary, including visible clearing/in-flight rejection; actual TCC revocation/regrant not performed |
| 51 | Pass for real working tap, actual secure-input fallback and injected AX loss; actual TCC revocation and OS-denied tap creation not forced |
| 52 | Pass: native session/deferred work canceled after capability faults; fresh gesture works after recovery |
| 53–54 | Pass: actual close removes/advances in frozen order, actual newcomer waits until next session |
| 55 | Pass through complete core workflow: empty/current-only/noncurrent-only/replacement identity |
| 56 | Pass: exact real closed-target feedback, unchanged source focus, auto-dismiss; retries remain bounded |
| 57 | Pass: all three native confirmation paths plus subsequent new activity; stale work cannot steal focus/show feedback |
| 58 | Pass: real dedicated settings toggle/persistence; menu-bar state/actions reviewed, not separately UI-driven |
| 59 | Pass: eight feature combinations and no-capture/hover-off switching |
| 60 | Complete original native suite passed once after regression fix; intermittent later preview-click failure documented, final bounded rerun reproduced the pre-existing click-only minimization failure. Drag/modifier OS matrix unverified |
| 61 | Pass: actual settings screenshot and status checks distinguish control from imagery |
| 62 | Implemented with existing system reduced-motion guards; actual host has Reduce Motion off, enabled-system visual matrix unverified |

## Preserved visual evidence

All `docs/images/command-tab-05-*.png` are dedicated controlled fixture/settings captures. An opaque controlled backdrop covers the crop background. The final grid contains 12 actual captured fixture-window thumbnails and icon fallbacks, including portrait/wide/long-title and cached minimized targets. It does not fabricate thumbnails. Settings use the production SettingsView with isolated preferences and capture false.

- `command-tab-05-dock-preview.png` (original Dock preview against the same controlled background)
- `command-tab-05-grid-light.png`, `command-tab-05-grid-dark.png`, `command-tab-05-grid-scrolled.png`
- `command-tab-05-row.png`, `command-tab-05-single.png`
- `command-tab-05-settings-dock-light.png`, `command-tab-05-settings-switcher-light.png`, `command-tab-05-settings-switcher-dark.png`, `command-tab-05-settings-general-dark.png`

Reviewed: geometry, glass edges, neutral selection, corner radii, symmetric margins, readable titles, long-title truncation, persistent app icon, separate minimized status, actual thumbnail aspect ratios and icon fallback. Root also visually inspected the final shapes. This is actual compositor output, not isolated view rendering.

## Unavailable / deliberately unmodified matrix

- A second physical display and alternate scaling ratios; cross-display placement/removal.
- Two ordinary desktops: prior public Mission Control fixture exploration could not guarantee safely removing a newly created Space, so desktop arrangement was left unchanged. This does not demonstrate a switching failure.
- Other macOS versions (including macOS14 material fallback), third-party application dialog/browser matrices and simultaneous third-party shortcut tools.
- Actual TCC permission revoke/regrant and an OS-denied tap creation; access-query and capture boundaries were injected instead.
- System Reduce Motion enabled; current system setting was read, not changed.
- Login-item registration/unregistration and real menu-bar-hidden relaunch; user settings and installed app remained unchanged.
- Broad cold/hot startup and many-application benchmarking; measured paths are two controlled applications, 4/40 native windows, actual 0.12s-target panel and a real unresponsive fixture.

All native harnesses terminate their temporary apps, remove isolated preference/control files, resume any suspended fixture, and restore prior exact foreground/pointer where they change them. Root retains responsibility for relaunching the original installed app after final review; its bundle stayed untouched throughout.

## Final artifact and run references

- Production/native-check commit: `7f7bfd2` (ticket05). Debug and release builds passed. Source package `dist/Dock Enhanced.app`: version0.6.0/build11; the installed `/Applications/Dock Enhanced.app` is unchanged.
- `/tmp/dock-05-core-final.log`:50/0. `/tmp/dock-05-recovery-all-native.log`:all recovery cases pass. `/tmp/dock-05-interaction-final.log`:40-window interaction pass,131ms display observation. `/tmp/dock-05-reachability-final.log`:runnable exact-focus/visibility/full-screen cases pass plus explicit unavailable matrix.
- `/tmp/dock-05-preferences-final.log`:16/0. `/tmp/dock-05-services-final.log`:39 passed. `/tmp/dock-05-settings-final.log`:actual UI toggle/persistence/reopen pass. `/tmp/dock-05-visual-shapes-final.log`:12 real fixture images and composed shape/appearance evidence.
- Red evidence: `/tmp/dock-05-watchdog-red.log` (missing native watchdog API); `/tmp/dock-05-native-baseline.log` (new synchronous minimized-restoration regression). Real green evidence is the recovery and original Dock run noted above. Existing core cases were extended and passed; no false failing result is claimed for rules already implemented by predecessors.
