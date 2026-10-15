# Dock interaction and UI refinements

Status: ready-for-agent

Baseline: a2bf855

## Requested changes

- Redesign the settings/permissions window with a deliberate native visual hierarchy.
- Highlight a window preview card on pointer hover.
- Animate preview appearance and dismissal; respect Reduce Motion.
- Fix visible Chrome windows showing only the application icon instead of a captured thumbnail.
- Prevent preview from interfering with minimize/restore clicks and native Dock context menus.

## Acceptance

- Settings includes clear status, the existing enable control, permission rows, and an adjustable hover delay.
- Pointer hover gives a visible card highlight and focus treatment.
- Preview transitions are short and interruptible; delayed hide must not close a newly shown preview.
- A native Chrome check asserts actual cached images for non-minimized Chrome windows without logging browser titles or URLs.
- Mouse down hides an existing preview immediately. Button holds, context menus, and the remainder of the same icon hover do not reopen it. Leaving and reentering the icon starts a fresh hover.
- Existing exact-window minimize/restore and preview selection behavior remains intact.
