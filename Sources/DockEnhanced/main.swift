import AppKit
import ApplicationServices

#if DEBUG
if CommandLine.arguments.contains("--diagnose") {
    print("Accessibility=\(AXIsProcessTrusted()) ScreenCapture=\(CGPreflightScreenCaptureAccess())")
    exit(0)
}
if let index = CommandLine.arguments.firstIndex(of: "--check-preference-restart"), CommandLine.arguments.count > index + 4,
   let defaults = UserDefaults(suiteName: CommandLine.arguments[index + 1]) {
    let settings = SettingsModel(defaults: defaults)
    let actual = [settings.previewEnabled, settings.clickEnabled, settings.switcherEnabled]
    let expected = CommandLine.arguments[(index + 2)...(index + 4)].map { $0 == "true" }
    exit(actual == expected ? 0 : 1)
}
if CommandLine.arguments.contains("--check-preview-settings") {
    Task { @MainActor in exit(await checkPreviewSettings()) }
    RunLoop.main.run()
}
if CommandLine.arguments.contains("--check-feature-services") {
    let checkApplication = NSApplication.shared
    checkApplication.setActivationPolicy(.accessory)
    Task { @MainActor in exit(await checkFeatureServices()) }
    checkApplication.run()
}
let application = NSApplication.shared
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
