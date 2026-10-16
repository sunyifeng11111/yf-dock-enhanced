# Optional menu bar icon

Status: ready-for-agent

Add a persistent “隐藏菜单栏图标” setting, default off. Hide/restore the status item immediately without changing preview, click, or login preferences. Keep an explicit recovery instruction beside the switch: open Dock Enhanced from Applications or Spotlight to open settings. Reopening a running application also opens settings. Provide a quit button in settings so hiding the icon does not remove the exit control.

Manual launches always show settings; background login/service launches remain quiet when permissions are available. Read the launch reason from the open-application Apple event as documented by [Apple](https://developer.apple.com/documentation/coreservices/apple_events/1556410-launch_apple_event_constants).

Validate hiding/restoring, saved state after relaunch, reopening settings while hidden, and the exit control in the installed app. Existing feature settings and 0.40-second delay must remain unchanged.

## Validation

Release 0.4.1 builds and passes bundle signature verification. In the installed app, toggling the hide switch on persists across quitting through the new settings button and manually launching the application again. The settings window opens with the hidden preference still on; opening the already-running app also returns to settings. Switching off restores the visible preference immediately. The final preference is off, preserving the prior visible-icon choice.

The actual settings screenshot confirms the recovery explanation and the bottom quit button are readable. Preview and click control remain on, login launch remains on, and hover delay remains 0.40 seconds. No reboot was performed; quiet login launch follows Apple's documented launch-event classification.
