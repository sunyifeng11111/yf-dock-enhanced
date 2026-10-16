import AppKit
import ApplicationServices

#if DEBUG
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}
let application = NSApplication.shared
let delegate: NSApplicationDelegate
if let index = CommandLine.arguments.firstIndex(of: "--check-command-tab"), CommandLine.arguments.count > index + 2 {
    delegate = WindowSwitcherCheck(urls: CommandLine.arguments[(index + 1)...(index + 2)].map { URL(fileURLWithPath: $0) })
}
else if CommandLine.arguments.contains("--check-chrome-preview") { delegate = ChromePreviewCheck() }
else if CommandLine.arguments.contains("--check-window-count") { delegate = WindowInventoryCheck() }
else if CommandLine.arguments.contains("--fixture") { delegate = FixtureDelegate() }
else { delegate = AppDelegate() }
#else
let application = NSApplication.shared
let delegate = AppDelegate()
#endif
application.delegate = delegate
application.run()
