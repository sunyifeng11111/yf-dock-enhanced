# Native Dock enhancement

Status: ready-for-agent

## Confirmed behavior

- Keep the native macOS Dock.
- Click the foreground application's Dock item to minimize its recent window.
- Click again to restore that same minimized window.
- Click a background application's Dock item to bring that application forward.
- For applications with multiple windows, target only the recent window.
- Hover over a Dock item to show previews of all of that application's windows.
- Click a preview to restore and focus its window.
- Keep the product limited to these two capabilities.

## Confirmed first-version boundaries

- A small menu bar utility with an enable switch and quit action.
- Onboarding for the required Accessibility and Screen Recording permissions.
- Minimized windows use their last cached image. Without a cached image, show their title and application icon.
- Full-screen and non-minimizable windows keep their native Dock click behavior.
- First deliverable is a locally runnable macOS app on this machine.

## Prototype acceptance

Validate native Dock identification, click interception, minimize/restore of the same window, and hover previews in a runnable native macOS experiment. Observe actual UI behavior before claiming that the integration works.

## Technical evidence

See `feasibility.md` for official API sources, read-only host checks, and limitations requiring runtime validation.
