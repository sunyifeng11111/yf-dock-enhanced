# Minimal glass window previews

Status: ready-for-agent

Baseline: 17e780a

## Request

Use the supplied competitor screenshot as a visual reference: a single translucent glass surface, centered application name, window thumbnails with centered titles, and subtle neutral hover feedback without a purple border.

## Implementation

- Use native `NSGlassEffectView` on macOS 26 and later, with a 32-point corner radius and regular untinted glass. Older systems keep a native popover blur fallback.
- Remove individual card backgrounds and the repeated click/status text; preserve the information in accessibility help.
- Center the application name and each window title. Keep existing preview transitions, cached thumbnails, and exact-window selection.
- Hover uses a short neutral translucent fill, with no colored outline or focus ring.

## Validation

Build and run the existing native two-window integration check, inspect the rendered preview screenshot, and package the updated application.

Results: native two-window integration passed, including menu suppression, exact-window selection, minimize/restore, and cached previews. The composited preview screenshot was visually inspected: native glass edge and backdrop, centered title, captions below thumbnails, and neutral hover fill without a colored border. Saved to `docs/images/preview.png`.

API: [Apple NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview), verified against the installed AppKit SDK headers.
