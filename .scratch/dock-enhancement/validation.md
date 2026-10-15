# Validation

Date: 2026-10-15 (Asia/Shanghai)

## Agreed test boundaries

The user approved automatic checks at the public Dock click behavior interface. Real Dock integration, permissions, and previews are verified through a local two-window fixture. Review compares implementation commits against baseline `155dca5`.

## Results

- Eight public behavior checks pass using `DockCoreChecks`.
- The foreground-window, consecutive restore, unsupported-window, and previously minimized-window slices were observed failing before their implementations were added.
- The local Command Line Tools installation lacks XCTest. The behavior checks therefore use a dependency-free Swift executable with a failing exit status instead of XCTest.
- Native integration passes: active event tap; authorized capture; two Accessibility windows; foreground fixture; correct Dock identity; both previews; both actual window images; no focus theft on hover; exact preview selection; only the recent window minimized; cached minimized preview remains selectable; same window restored; intervening keyboard activity makes the next click target the current window.
- The dedicated fixture windows are closed after the integration check. The original pointer position is restored. The test restores the previous foreground application through Accessibility, with AppKit activation as a fallback.
- The preview screenshot at `docs/images/preview.png` was inspected: both thumbnails, titles, selection hints, and layout are visible without clipping.
- Release build passes, produces an arm64 Mach-O executable, and passes strict local code-signature verification.

## Commands

```sh
swift run --build-system native DockCoreChecks
scripts/check-native.sh
scripts/build-app.sh
codesign --verify --deep --strict 'dist/Dock Enhanced.app'
```

## Remaining compatibility coverage

Full-screen and unsupported windows are covered by the behavior policy. Real application compatibility, additional displays, Dock magnification, auto-hide, left/right Dock placement, and Spaces switching have not all been exercised in this run.

A separately launched app still requires its own Accessibility and Screen Recording authorization. The command-line integration process's authorization is not evidence that the newly packaged app is already authorized.

## Review follow-up

Standards review found two integration reliability issues; Spec review found one related keyboard-focus issue. They were fixed by reading live focus at click time, ending consecutive restore on keyboard activity, and refreshing preview metadata and selection snapshots. Follow-up reviews found no unresolved issues.

Final native integration passed with the keyboard-activity regression check. A separate experimental metadata assertion was removed after proving unstable during desktop UI runs; metadata updates were inspected in code review. The suite locates the application icon again after Dock reflow and runs best while the desktop is idle.
