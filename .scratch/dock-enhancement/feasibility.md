# Native Dock feasibility

## Read-only host findings

Verified on 2026-10-14: macOS 27.2 (26B5112a), Apple Silicon, Swift 6.4, and Command Line Tools are available. The current execution process passed Accessibility, Screen Capture, Listen Event, and Post Event permission preflights. A separately packaged app must check its own authorization.

The Dock exposes an Accessibility tree containing `AXDockItem` nodes, with application URLs and geometry available on this host. No application names or URLs were logged, no permission prompt was opened, and no window was changed during these checks.

## Official API support

- [AX hit-testing](https://developer.apple.com/documentation/applicationservices/1462077-axuielementcopyelementatposition) can identify an accessible element at a screen coordinate.
- [Window minimized attribute](https://developer.apple.com/documentation/applicationservices/kaxminimizedattribute) supports observing window state. Check whether the attribute is settable before [writing it](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue).
- An active [CGEventTap callback](https://developer.apple.com/documentation/coregraphics/cgeventtapcallback) can suppress an original click. A passive listener cannot. Failure to install or process the tap must preserve native behavior.
- [WWDC22 ScreenCaptureKit](https://developer.apple.com/videos/play/wwdc2022/10155/) describes single-window capture across displays and Spaces, including occluded and offscreen windows. Capture pauses while a window is minimized and resumes after restoration. Use the last frame, or a title/icon fallback when no frame exists.
- [NSScreen.screens](https://developer.apple.com/documentation/AppKit/NSScreen/screens) must be refreshed when the display configuration changes.

## Remaining runtime questions

Validate Dock auto-hide, magnification, bottom/left/right placement, multiple displays, Spaces, unsupported application Accessibility implementations, Dock restarts, and event tap timeout recovery. Full-screen and non-minimizable windows should retain native behavior in the first version.

## Prior implementation evidence

[DockDoor's original repository](https://github.com/ejbills/DockDoor) demonstrates native Dock window previews and window operations. Its GPLv3 implementation is a feasibility reference; this project will implement independently.
