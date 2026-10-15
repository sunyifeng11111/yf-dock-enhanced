# Window inventory and foreground restoration

Status: ready-for-agent

Baseline: e78f97d

## User reports

- ChatGPT has one user window, but the preview sometimes contains an extra untitled entry with the same content.
- After minimizing an application and using another application, selecting its preview sometimes unfolds the window without keeping it foreground. Mail was one observed source application, not a special case.

## Acceptance

- Skip duplicate AX elements and untitled, nonstandard background helper windows. Keep normal untitled windows and main/focused custom windows or dialogs.
- Do not use fully transparent capture windows as thumbnail candidates.
- Finish a minimized-window restore after the window is available again, with bounded retries and foreground verification outside the event-tap callback.
- New user interaction, another window command, or stopping the utility cancels deferred focus work.
- Preserve exact-window selection, cached minimized previews, and existing Dock interactions.

## Diagnosis and validation

The exact ChatGPT duplicate snapshot did not recur during live inventory/hover checks or a 90-second read-only observation. Its internal AX roles were therefore not captured. A real AppKit fixture reproduced the underlying overinclusive inventory behavior: two standard windows (one untitled), plus a transparent nonactivating internal panel exposed as `AXSystemDialog`; the old inventory returned all three. The filter returns the two real windows and preserves the untitled standard window. Transparent capture candidates are excluded so the panel cannot obstruct matching the real untitled window.

The actual minimized ChatGPT → Mail → preview-select path reproduced the foreground failure. Unminimize succeeded, but immediate AXRaise returned `-25204` (cannot complete); AXWindows briefly became empty, then the restored window reappeared while Mail remained foreground. The asynchronous readiness/retry fix brought ChatGPT foreground and kept it there. The regression checks that the preview action really ran, the selected window was restored, and foreground ownership does not revert after activation. It follows the current Dock position after minimize rather than using stale coordinates.

The final native two-window check passes inventory filtering, untitled-window preservation, real images, aspect ratios, margins, cross-application selection of the exact window, minimize/restore, menu suppression, and cancellation of deferred activation on new user activity. A held intercepted Dock press verifies cancellation happens on mouse-down, before mouse-up executes the next command.

Four sequential actual ChatGPT checks passed during development: two minimized-window restores with Mail foreground, and two with Finder foreground. The final implementation was checked again with Mail and Finder, both passing. Each reported inventory/preview count 1, actual selection invoked, restored window, and stable foreground ownership. Temporary instrumentation was removed.

The 16 core checks pass. Final Standards and Spec reviews have no remaining actionable findings. The original duplicate ChatGPT snapshot remains unverified; the helper-window fixture proves the filtering behavior, not the exact source of that screenshot.

API reference: [NSRunningApplication activation](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(options:)), supplemented by installed AppKit and Accessibility SDK headers. A successful activation request is not itself proof of foreground ownership.
