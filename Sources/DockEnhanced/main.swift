import AppKit
import ApplicationServices

#if DEBUG
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}
let application = NSApplication.shared
let delegate: NSApplicationDelegate
if CommandLine.arguments.contains("--check-chrome-preview") { delegate = ChromePreviewCheck() }
else if CommandLine.arguments.contains("--check-window-count") { delegate = WindowInventoryCheck() }
else if CommandLine.arguments.contains("--fixture") { delegate = FixtureDelegate() }
else { delegate = AppDelegate() }
#else
let application = NSApplication.shared
let delegate = AppDelegate()
#endif
application.delegate = delegate
application.run()
