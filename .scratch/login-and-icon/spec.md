# Login launch and application identity

Status: ready-for-agent

## Request

Add launch at login and a logo to Dock Enhanced.

## Acceptance

- A settings switch registers/unregisters the installed main app using macOS ServiceManagement. Display actual system status, errors, and an approval link when needed; do not keep a separate preference that can drift from the OS.
- Enable login launch on this computer from the installed `/Applications/Dock Enhanced.app`, as requested. Login launches quietly in the menu bar when permissions are available.
- Ship a distinctive window/Dock-themed application icon, with all standard icon sizes, and use it in the settings header.
- Reopening the running utility from Applications or Spotlight opens its settings, so the login switch remains accessible.
- Keep the settings usable on smaller screens and preserve existing window behavior.

## Reference

[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [main-app registration behavior](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29).

## Validation

- Release build and 16 core checks passed.
- Actual installed app: login switch off → on → off → on, with each state refreshed from SMAppService and no error. The system login database reports `enabled, allowed, notified` and `/Applications/Dock Enhanced.app`.
- After installing the final build and restarting the application, the switch remains on. Version 0.3.0 is installed and running; its settings currently requires renewed Accessibility and Screen Recording permission for the window-control features.
- The settings screenshot shows the custom app icon, readable login row, permissions, and footer without clipping. The settings uses a scroll container and caps initial window height to the current display.
- ICNS decodes as 1024×1024 and the app's displayed icon confirms macOS loaded it from the bundle. Generator includes standard and Retina sizes.
- No reboot was performed; registration was verified without interrupting the user's session.
