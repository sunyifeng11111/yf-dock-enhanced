# Symmetric preview spacing and centered portrait thumbnails

Status: ready-for-agent

Baseline: 6e05818

## Request

Fix unequal left/right spacing between the outer glass surface and inner hover card, and center small/portrait application thumbnails within their cards.

## Acceptance

- The first and last cards have equal outer margins, with gaps only between cards.
- Captured wide and portrait windows retain their source aspect ratio without padded capture canvases that shift the visible window off center.
- Native image views explicitly center thumbnails. Native glass and neutral hover feedback remain.
- Verify with real wide and portrait test windows, a rendered screenshot, and existing exact-window selection and Dock interaction checks.

## Diagnosis and results

The previous list width included a trailing 10-point gap after the last card. It now includes gaps only between cards, leaving 12 points on each side for both single- and two-window panels.

The portrait fixture reproduced `FAIL: wide and portrait thumbnails preserve their window aspect ratios`. The old capture configuration fixed width at 500 pixels while capping height at 400, leaving an off-center padded canvas. Capture now fits both dimensions together using the capture filter's actual content size. The regression passes.

Native checks pass for wide/portrait capture aspect ratios, equal margins with one and two cards, exact-window selection, context-menu suppression, cached minimized previews, and minimize/restore. Native screenshots were visually inspected: `docs/images/preview.png` and `docs/images/portrait-preview.png`. The latter shows a centered portrait thumbnail inside a single highlighted card with symmetric side margins.

Standards and Spec follow-up reviews reported no actionable findings. Packaged as 0.2.2.
