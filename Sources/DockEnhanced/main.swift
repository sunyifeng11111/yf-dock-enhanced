import AppKit
import ApplicationServices

#if DEBUG
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}
let application = NSApplication.shared
let delegate: NSApplicationDelegate = CommandLine.arguments.contains("--fixture") ? FixtureDelegate() : AppDelegate()
#else
let application = NSApplication.shared
let delegate = AppDelegate()
#endif
application.delegate = delegate
application.run()
