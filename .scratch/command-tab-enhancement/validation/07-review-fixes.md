# Final review fixes

2026-10-16. Based on integration `5bac844`, with the independent findings recorded in [review 06](06-code-review.md). The same single implementer handled every actionable finding. Host remains macOS 27.2 / Apple Silicon / one 2× physical display. Existing agreed test seams are the complete selection workflow and native event/window adapters; the reviewer additionally requested a small registry lifecycle boundary check.

## Changes

- Healthy empty inventories consume Command+Tab and its Tab release, end any obsolete selection/restoration, leave the source focused and never show an empty panel. Unavailable enhancement still passes Command+Tab through the native event adapter.
- Screen configuration notifications resolve the original host by display identity, refresh its usable geometry and reflow/recenter the panel. The panel rebuilds on geometry changes even when candidate identities are unchanged. The frozen order and selected identity survive; the selected card is scrolled into view. Display removal retains cancellation.
- Window identities are pruned only after an actual AX role query returns `invalidUIElement`. Successful AXWindows omission and transient failure do not retire identities; monotonically allocated IDs are never recycled. This removes closed handles from later inventory scans without breaking accepted warm full-screen retention.
- The two native check scripts share their fixture packaging/signing helper. The switcher and failure notice share one small nonactivating panel factory, retaining their individual titles and mouse handling.

## Red → green evidence

All three regressions were observed before their corresponding behavior fix. Logs contain only controlled fixture state.

| Regression | Before | After |
| --- | --- | --- |
| Empty native adapter | `/tmp/dock-review-empty-red.log`: fails `empty healthy enhancement consumes Tab press` | `/tmp/dock-review-empty-green.log`: consumes press/release, no empty UI or focus change, native fallback preserved |
| Same connected display | `/tmp/dock-review-geometry-red.log`: initial usable geometry succeeds, configuration notification fails to relayout | `/tmp/dock-review-geometry-green.log`: 3→2 columns, new bounds/center, same host/order/selection/focus, selected card visible after scrolling |
| Closed AX handles | `/tmp/dock-review-registry-red.log`: first create/close cycle fails to restore retained count | `/tmp/dock-review-registry-green.log`: 8 cycles, baseline 2 handles and final 2, 8 distinct retired identities; real owner timeout preserves handles and successful full-screen omission preserves both live exact identities |

The added `scripts/check-switcher-native.sh --review` entry runs all these checks through the production native adapter and real AppKit/AX fixtures. Display usable-frame values alone are injected at the OS query boundary; the actual display configuration is unchanged. Registry counts use its existing `knownElements` boundary to verify that future enumeration no longer walks retired handles. A disposable fixture is briefly stopped and unconditionally resumed for the timeout check. No test was added just to mirror the two mechanical extractions.

## Final checks

All final commands exited 0 after the production changes and extractions:

| Check | Result / evidence |
| --- | --- |
| Focused review regressions | 33 pass lines, no failures: `/tmp/dock-review-final.log` |
| Core behavior | 50 checks / 0 failures: `/tmp/dock-review-core.log` |
| Preferences / image lifecycle | 16 checks / 0 failures: `/tmp/dock-review-preferences.log` |
| Native shared services | 39 checks passed: `/tmp/dock-review-services.log` |
| Actual 40-window interaction | Quick MRU round trip, nonactivating delayed panel, geometry/scrolling, stationary pointer, Enter, pointer and outside cancellation passed: `/tmp/dock-review-interaction.log`; panel observed at 127ms with 5ms sampling |
| Native exact reachability | Existing same-app/cross-app, hidden/minimized, exact completion, warm ordinary/full-screen switching and disabled native fallback passed: `/tmp/dock-review-reachability.log`; accepted cold-start omission and unavailable environments remain explicit |
| Debug / release builds | Pass; native script builds and `/tmp/dock-review-release.log` |
| Source application package | `scripts/build-app.sh release` and strict deep signature verification passed: `/tmp/dock-review-package.log`. `dist/Dock Enhanced.app` is 0.6.0 / build 11, macOS 14 minimum, identifier `dev.yifeng.DockEnhanced`. Installed application was not replaced |
| Source / scripts | `git diff --check` and zsh syntax checks for both wrappers/shared helper passed |

The integration coordinator must rebuild or copy the updated source package after merging; a package from before these fixes contains the prior executable.

## Limits and cleanup

The geometry check proves actual AppKit relayout under a changed usable-frame observation; it does not establish real physical display removal or scale changes. No second display, second ordinary desktop, other macOS version, actual permission revocation, third-party shortcut conflict or Reduce Motion enabled matrix was added. The accepted cold-start full-screen discovery limit remains. The previously recorded original Dock runtime intermittent/baseline failures remain disclosed in validation 05; the full original Dock suite was not repeated for these review fixes.

All native fixtures are terminated, isolated control files removed, stopped fixtures resumed, and original exact foreground/pointer restored. No installed app, real preference domain, login registration or system permission was changed. The installed app remains off for the root coordinator to restore after integration.
