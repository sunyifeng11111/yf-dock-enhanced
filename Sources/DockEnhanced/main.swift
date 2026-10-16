import AppKit
import ApplicationServices

#if DEBUG
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}
let application = NSApplication.shared
if let index = CommandLine.arguments.firstIndex(of: "--probe-fixture-inventory") {
    NSApp.setActivationPolicy(.accessory)
    guard CommandLine.arguments.count > index + 1, let pid = Int32(CommandLine.arguments[index + 1]),
          let app = NSRunningApplication(processIdentifier: pid),
          app.bundleIdentifier?.hasPrefix("dev.yifeng.DockEnhancedSwitcherFixture") == true, AXIsProcessTrusted() else { exit(2) }
    let windows = WindowController().windows(of: app)
    print("COLD-PROBE: count=\(windows.count), fixtureIdentifiers=\(windows.map { (AX.value($0.element, kAXIdentifierAttribute) as String?) ?? "none" })")
    exit(windows.count == 2 ? 0 : 3)
}
let delegate: NSApplicationDelegate
if let index = CommandLine.arguments.firstIndex(of: "--check-switcher-interaction"), CommandLine.arguments.count > index + 2 {
    delegate = WindowSwitcherInteractionCheck(urls: CommandLine.arguments[(index + 1)...(index + 2)].map { URL(fileURLWithPath: $0) })
}
else if CommandLine.arguments.contains("--interaction-fixture") { delegate = SwitcherInteractionFixture() }
else if let index = CommandLine.arguments.firstIndex(of: "--check-command-tab"), CommandLine.arguments.count > index + 2 {
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
