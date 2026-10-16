# Dock Enhancement

A small utility that adds window controls and previews to the native macOS Dock.

## Language

**Dock item**:
The native Dock icon representing an application.

**Recent window**:
The window of an application that the user most recently worked with. This is the window targeted by a Dock click when that application has several windows.

**Minimized window**:
A window that has been put away individually and can be restored later.
_Avoid_: Hidden application, closed window

**Window preview**:
A thumbnail representing one application window, selectable to bring that window forward. For a minimized window, the thumbnail may show its last available image.

**Window switcher**:
A cross-application chooser whose entries each represent an individual window, including minimized windows. Multiple windows belonging to the same application are separate entries; browser tabs are not separate entries.
_Avoid_: Application switcher

**Selected window**:
The window currently highlighted in the window switcher as the candidate for a confirmed switch. It is not necessarily the foreground window.

**Hidden application**:
A running application whose windows have been hidden together, such as through Command+H. Hiding an application is distinct from minimizing an individual window.
_Avoid_: Minimized window

**Foreground application**:
The application currently receiving the user's input.

**Background application**:
A running application that is not currently receiving the user's input.

**Update check**:
A lookup for a newer application release; it does not itself replace or restart the installed application.
_Avoid_: Update installation

**In-app update**:
An application upgrade that downloads a new release, replaces the installed application, and restarts it through the application's update flow.
_Avoid_: Download-page redirect

**Stable release**:
A published application release intended for normal use, distinct from a draft or prerelease.
