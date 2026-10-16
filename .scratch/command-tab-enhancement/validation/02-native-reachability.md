# Ticket 02 native reachability evidence

2026-10-16; macOS 27.2 (26B5112a), Apple Silicon, one physical display. Existing Accessibility/event-posting authorization was used. No installed app, system setting, permission, or user window was modified. Two independent temporary fixture apps provided two ordinary windows each; the fixture's own Hide menu handled real Command+H.

## Implementation and test boundary

`WindowController.reveal` accepts an exact live AX identity, explicitly unhides its owner and independently restores minimization. It refreshes the target and retries requests for at most 21 checks at 100 ms intervals. Completion reports observed foreground PID + unhidden owner + nonminimized target + CFEqual AXFocusedWindow. A new request/user activity invalidates pending work. A missing exact target fails before activating its application. Initial validation reads only the selected element’s actual PID, live role and frame; it does not scan every window inside the original Dock mouse callback. The closed-target native scenario was rerun successfully with this bounded guard after integrating tickets 03 and 04.

AXWindows can omit a valid ordinary window while the same application is full screen. Inventory now also rechecks exact AX elements observed earlier in this utility run; live role, frame, minimization and full-screen state are read again. Entries are never recovered by title or geometry. The existing Dock full-screen native fallback remains unchanged.

The native test independently records actual target visibility using fixture-owned public NSWindow.isOnActiveSpace, NSWindow.isVisible and NSWindow.windowNumber, corroborated by the onscreen CG window list. These fixture identifiers and numbers are not used to identify production windows. No screenshots or user window content were captured. Metadata lives in a temporary directory removed during cleanup.

## Red → green

- Adding the exact-focus completion scenario first failed compilation because `reveal` did not accept completion; implementation then built successfully.
- Before retained inventory, real full-screen entry passed but fresh raw AXWindows exposed only the full-screen fixture. The same-app ordinary/full-screen inventory assertion failed.
- After retaining and revalidating known exact AX elements, `scripts/check-switcher-native.sh --reachability` completed all runnable scenarios successfully on the integration containing ticket 03. DockCoreChecks: **46 checks, 0 failures**. Build and whitespace checks passed.

## Observed outcomes

| Case | Inventory / selection | Actual result |
| --- | --- | --- |
| Command+H ordinary target, browse then Escape | Hidden target remains a separate card; exact card selected | Owner remains hidden; original exact source retains focus |
| Hidden ordinary target, confirm | Exact target card selected with real Command+Tab | Owner unhidden; exact AX focus and target visibility on active Space verified |
| Hidden + minimized target, browse then confirm | Both independent states preserved while browsing | Confirm unhides owner, restores only the target, and verifies exact focus plus actual target visibility |
| Same app, full-screen → ordinary | Both known exact AX windows included; target selected through actual panel | `exactFocus=true`, `visibleOnActiveSpace=true` |
| Same app, ordinary → full-screen | Exact full-screen card selected through actual panel | `exactFocus=true`, `visibleOnActiveSpace=true` |
| Closed target retained in a previous inventory | Close real fixture window, request its old exact identity | Rejected with false completion; other app window is not activated |
| Original Dock full-screen click policy | Full-screen state read from real fixture | Native fallback retained |

The fixture full-screen window retained key 5, the ordinary window key 4. In full screen, raw app AXWindows contained only identifier `switcher-fixture-0`; app AXChildren contained roles `[AXWindow, AXMenuBar]`. The previously seen ordinary element remained a valid AXWindow with a live frame; retained inventory contained both identifiers and correct full-screen states. No identity substitution was required.

## Demonstrated limitation and remaining validation

A **fresh child utility process**, launched while the fixture app was full screen, used a new WindowController and empty in-memory identity registry. It reported `COLD-PROBE: count=1, fixtureIdentifiers=["switcher-fixture-0"]`. It could not discover the omitted ordinary window. Warm discovery and switching do not fulfill cold-start discovery of all existing windows. No reviewed public AX/AppKit API supplies an exact missing AX target from the CG window list; private AX/CGS/SkyLight APIs and title/geometry matching are not used.

Two ordinary desktop Spaces have **not been validated**; the successful two-Space scenario consists of an ordinary desktop and a full-screen Space. Physical multi-display selection is **unavailable on this one-display host**. These are not passes. The implementation is complete within the explicitly accepted discovery boundary; the remaining compatibility matrix is recorded for integrated validation. Broader third-party application coverage is not implied by the AppKit fixture results.

Production exact-focus completion cannot independently query another application's NSWindow.isOnActiveSpace or supported public AX-to-CG window number. The real fixture proves visibility for the cases above; no universal cross-Space visibility guarantee is claimed.

The user explicitly accepted this demonstrated cold-start discovery boundary on 2026-10-16 after seeing the successful warm switching behavior and the missing ordinary-window reproduction. The parent spec records that decision. README now explains: leave full screen once so the tool can identify ordinary windows, then enter full screen again; those known exact targets remain available. No acceptance of untested ordinary-desktop or multi-display behavior is inferred from that decision.

A bounded ordinary-desktop fixture exploration used only public Mission Control accessibility. On this host the surface is WindowManager (`mc.display`, `mc.spaces`, `mc.spaces.list`, `mc.spaces.add`). The sole existing desktop control exposed only AXPress, no child controls and no AXCloseButton; creation was visible but exact safe removal was not discoverable. No Space was created, no window moved, and no desktop arrangement changed. Mission Control was dismissed, the fixture terminated and original foreground restored. This establishes why the optional two-ordinary-desktop automated fixture was not completed; it does not establish that ordinary desktop switching fails. No screenshots or user window titles were captured.

All fixture windows left full screen and both temporary app processes terminated on completion/failure; prior exact foreground window was restored and pointer position was untouched. The installed /Applications/Dock Enhanced.app bundle remained untouched and off for root-agent final restoration.

Development-run logs: `/tmp/dock-02-completion-red.log`, `/tmp/dock-02-fullscreen-green.log` (pre-retention failure), `/tmp/dock-02-hidden-green.log`, `/tmp/dock-02-retained-native.log` (successful runnable cases plus explicit limitations), `/tmp/dock-02-cheap-guard-native.log` (integrated closed-target validation), `/tmp/dock-02-mission-control-probe-final.log` (safe ordinary-desktop fixture unavailable). This document preserves the material observations without depending on temporary logs.
