# Compact settings navigation

Status: ready-for-agent

Replace the growing single-page settings stack with a compact native-style sidebar and two pages, as agreed with the user:

- Dock 功能 (default): independent preview/click switches. Show the delay control only under enabled previews; preserve saved values. Missing permissions link to 通用.
- 通用: a 启动与显示 group (login launch, hidden menu icon), and a 系统权限 group (Accessibility, Screen Recording). Granted permissions use concise status; missing permissions show purpose and an authorization action.
- Small app identity in the sidebar; remove the large promotional header. Keep running status, version, and exit visible in the footer.
- Show recovery guidance when menu icon hiding is enabled. Keep manual reopen behavior.
- Use compact grouped rows, scrolling for constrained windows, and a resizable settings window. Preserve all feature behavior and preference keys.

Validate both pages in the installed release, conditional controls and permission links, saved switch values, and hidden-icon recovery. This is a presentation change; do not alter Dock window handling.

## Validation

Release 0.5.0 builds and passes installed bundle signature verification. Actual screenshots show both pages fitting the default 780×560 content area, with fixed sidebar footer and no clipped settings. The window supports resizing with a 760×500 minimum, and detail content scrolls.

In the installed app, turning preview off removes its delay control and permission link; turning it back on restores the saved 0.40-second value. The permission link selects 通用. Enabling icon hiding reveals the recovery instructions; the settings remains accessible while hidden, and icon visibility was restored to the original off value afterward. Both feature switches and login launch remain on. Missing-permission actions are visible under 通用; granting OS permissions was not part of this check.

This host's newer SwiftUI SDK exposes both a State macro and property wrapper with the same name. A type alias selects the existing property wrapper, avoiding a dependency on an unavailable macro plugin in the Command Line Tools environment.
