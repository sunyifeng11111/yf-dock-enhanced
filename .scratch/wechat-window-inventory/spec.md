# Invisible helper in WeChat window inventory

Status: ready-for-agent

## Report and scope

The user reports one extra WeChat entry in the Dock preview/window switcher. Do not control WeChat: no activation, clicks, minimize/restore, closing, posted input, or integration scripts that restore focus to it. Read-only window metadata and independent owned fixtures are allowed within the diagnosis scope.

## Reproduction

` .build/debug/DockEnhanced --check-window-count com.tencent.xinWeChat 1 ` returned exit 1: `Window inventory check: expected 1, found 2`.

A single read-only AX/WindowServer snapshot found an untitled 187×51 AXDialog, AXMain=false, AXMinimized=false, reported as focused, without close/minimize/zoom buttons. Its matching WindowServer record has alpha=0 and layer=8. The genuine main window is a titled, minimized AXDialog with controls, alpha=1, layer=0. No chat text or screenshot was captured.

## Ranked hypotheses

1. Fully transparent helper is admitted because inventory does not consult compositor transparency. Excluding a positively matched transparent floating helper should leave one real window.
2. Dialog/focused exemption in the existing untitled-window rule admits the helper. Reproducing an untitled transparent AXDialog should fail the same inventory path even in a fresh process.
3. Registry retains a closed or duplicate window. A fresh process should eliminate the extra entry if this is the sole cause; the cold count above already weighs against it.

## Acceptance

- Positively identified untitled transparent floating dialogs do not appear in previews or switcher inventory, including when cached or reported focused.
- Preserve minimized windows, normal untitled windows, opaque small dialogs, and ambiguous/missing compositor matches.
- No app-specific name/size blacklist, no WeChat control, no screen contents captured.
- Exercise the real inventory in a disposable fixture and repeat the read-only live count.

## Diagnosis and validation

Confirmed: the existing dialog exemption admitted an invisible elevated dialog. Thumbnail capture already rejected fully transparent records, but the shared AX inventory still created an entry. This was reproduced in a fresh process, so stale cache was not required.

The shared inventory now excludes an untitled, non-main, non-minimized, non-full-screen AXDialog only when matching same-process, exact-frame compositor records all positively report alpha=0 and layer>0. It does not depend on application name, window size, or focused state. Missing records and conflicting visible/normal-level records preserve eligibility.

` .build/debug/DockEnhanced --check-transparent-window-inventory ` first failed the transparent-dialog assertion, then passed all 5 checks after the fix: untitled standard/visible small dialogs, cached transparent helper removal, ambiguous geometry preservation, normal-level dialog preservation, and visibility recovery. The fixture only operates its own windows and never activates or restores another application.

` .build/debug/DockEnhanced --check-window-count com.tencent.xinWeChat 1 ` changed from exit 1 (`expected 1, found 2`) to exit 0 (`expected 1, found 1`) using read-only enumeration; the legitimate minimized main window remained present.

`swift run --build-system native DockCoreChecks`: 50 checks, 0 failures. `git diff --check`: clean. The temporary metadata inspection script was removed; no production debug logging was added.

## Local delivery

Release build and strict signature verification passed. Installed to `/Applications/Dock Enhanced.app` with the same designated signing requirement, then restarted only Dock Enhanced. Previous application backed up at `/var/folders/fs/my09tpqs11xfqf8p22vlylfh0000gn/T/dock-enhanced-before-window-fix-p4t4pntb/Dock Enhanced.app`. WeChat was neither activated nor restarted nor sent window/input commands. This was a local installation; no release publication or commit was made.
