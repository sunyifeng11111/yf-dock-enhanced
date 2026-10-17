#if DEBUG
import AppKit
import Sparkle

@MainActor
func checkApplicationUpdates() async -> Int32 {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let suite = "dev.yifeng.DockEnhanced.update-check." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var count = 0, failures = 0
    func require(_ condition: Bool, _ message: String) {
        count += 1
        if !condition { failures += 1 }
        print("\(condition ? "PASS" : "FAIL"): \(message)")
    }
    let visual = CommandLine.arguments.contains("--visual")
    let fixture = FileManager.default.temporaryDirectory.appendingPathComponent(suite + ".app")
    defer { try? FileManager.default.removeItem(at: fixture) }
    var host = Bundle.main
    if visual {
        let resources = fixture.appendingPathComponent("Contents/Resources")
        try? FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": suite, "CFBundleShortVersionString": "0.6.8", "CFBundlePackageType": "APPL"]
        let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try? data?.write(to: fixture.appendingPathComponent("Contents/Info.plist"))
        try? FileManager.default.copyItem(atPath: FileManager.default.currentDirectoryPath + "/assets/AppIcon.icns", toPath: resources.appendingPathComponent("AppIcon.icns").path)
        host = Bundle(url: fixture) ?? .main
    }
    let updates = ApplicationUpdates(bundle: host, defaults: defaults)
    defer { updates.dismissUpdateInstallation() }
    require(updates.automaticChecks, "automatic checking defaults on")
    updates.automaticChecks = false
    require(!ApplicationUpdates(defaults: defaults).automaticChecks, "disabled automatic checks persist without disabling the manual control")
    updates.automaticChecks = true
    require(ApplicationUpdates(defaults: defaults).automaticChecks, "automatic checking can be re-enabled")
    var cancelled = 0
    updates.showUserInitiatedUpdateCheck { cancelled += 1 }
    require(updates.statusKey == "正在检查更新…" && updates.actions.count == 1, "manual check presents cancellable progress")
    updates.choose(updates.actions[0])
    require(cancelled == 1, "cancel invokes Sparkle cancellation exactly once")
    updates.showDownloadInitiated { cancelled += 1 }
    updates.showDownloadDidReceiveExpectedContentLength(100)
    updates.showDownloadDidReceiveData(ofLength: 25)
    require(updates.progress == 0.25, "download progress reflects received bytes")
    updates.showDownloadDidReceiveData(ofLength: 200)
    require(updates.progress == 1, "unexpected content lengths do not overflow progress")
    updates.choose(updates.actions[0])
    require(cancelled == 2, "download cancellation is forwarded")
    updates.showDownloadDidStartExtractingUpdate()
    require(updates.actions.isEmpty, "extraction does not expose unsafe cancellation")
    var installChoice: SPUUserUpdateChoice?
    updates.showReady(toInstallAndRelaunch: { installChoice = $0 })
    require(installChoice == .install, "explicitly approved download proceeds to installation and relaunch")
    var acknowledgements = 0
    updates.showUpdaterError(NSError(domain: "ControlledUpdateFailure", code: 1)) { acknowledgements += 1 }
    require(updates.actions.map(\.key) == ["重试", "前往下载", "关闭"], "failure offers retry and manual fallback")
    updates.choose(updates.actions.last!)
    require(acknowledgements == 1, "closing an error finishes the failed Sparkle session")
    let channelEngine = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: updates, delegate: nil)
    defer { withExtendedLifetime(channelEngine) {} }
    require(updates.allowedChannels(for: channelEngine).isEmpty, "only the stable default channel is selected")
    let noUpdate = NSError(domain: SUSparkleErrorDomain, code: Int(SUError.noUpdateError.rawValue))
    updates.showUserInitiatedUpdateCheck {}
    updates.updaterDidNotFindUpdate(channelEngine, error: noUpdate)
    updates.showUpdateNotFoundWithError(noUpdate) {
        // Sparkle finishes this path by reporting SUNoUpdateError to the
        // updater delegate after the user acknowledges the latest-version UI.
        updates.updater(channelEngine, didAbortWithError: noUpdate)
        updates.updater(channelEngine, didFinishUpdateCycleFor: .updates, error: noUpdate)
    }
    require(updates.statusKey == "已是最新版本", "a successful check with no release shows up-to-date")
    updates.choose(updates.actions[0])
    require(updates.statusKey == "已是最新版本", "acknowledging no update cannot overwrite success with a failure")
    updates.updaterDidNotFindUpdate(channelEngine, error: noUpdate)
    updates.updater(channelEngine, didAbortWithError: noUpdate)
    updates.updater(channelEngine, didFinishUpdateCycleFor: .updatesInBackground, error: noUpdate)
    require(updates.statusKey == "已是最新版本", "background no-update completion also preserves success")
    for error in [NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet),
                  NSError(domain: SUSparkleErrorDomain, code: Int(SUError.signatureError.rawValue)),
                  NSError(domain: "UnrelatedErrorDomain", code: Int(SUError.noUpdateError.rawValue))] {
        updates.updater(channelEngine, didAbortWithError: error)
        require(updates.statusKey == "更新检查失败", "actual errors remain failures: \(error.domain)/\(error.code)")
    }
    if CommandLine.arguments.contains("--visual") {
        let preview = ApplicationUpdates(bundle: host, defaults: defaults)
        defer { preview.dismissUpdateInstallation() }
        NSApp.applicationIconImage = NSImage(contentsOfFile: FileManager.default.currentDirectoryPath + "/assets/AppIcon.icns")
        let backdrop = controlledBackdrop()
        defer { backdrop.orderOut(nil) }
        preview.showUpdateNotFoundWithError(NSError(domain: "Controlled", code: 0)) {}
        if let window = preview.previewWindow {
            window.level = .floating
            window.orderFrontRegardless()
            window.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? saveControlledCompositor(window, name: "current-dark", prefix: "update-compact-")
            window.appearance = NSAppearance(named: .aqua)
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? saveControlledCompositor(window, name: "current-light", prefix: "update-compact-")
        }
        preview.showUpdaterError(NSError(domain: "ControlledUpdateFailure", code: 1, userInfo: [NSLocalizedDescriptionKey: "The download could not be verified."])) {}
        if let window = preview.previewWindow {
            window.level = .floating
            window.orderFrontRegardless()
            window.appearance = NSAppearance(named: .darkAqua)
            try? await Task.sleep(nanoseconds: 250_000_000)
            try? saveControlledCompositor(window, name: "error-dark", prefix: "update-compact-")
        }
    }
    let keys = ["软件更新", "自动检查更新", "检查更新…", "下载并更新", "稍后", "跳过此版本", "更新失败，仍可使用当前版本"]
    require(keys.allSatisfy { Localization.text($0, language: .english) != $0 }, "update controls have English translations")
    if let index = CommandLine.arguments.firstIndex(of: "--engine-app"), CommandLine.arguments.count > index + 1,
       let bundle = Bundle(path: CommandLine.arguments[index + 1]) {
        let engineDefaults = UserDefaults(suiteName: bundle.bundleIdentifier!)!
        engineDefaults.set(false, forKey: "SUEnableAutomaticChecks")
        defer { engineDefaults.removePersistentDomain(forName: bundle.bundleIdentifier!) }
        let live = ApplicationUpdates(bundle: bundle, defaults: engineDefaults)
        live.start()
        require(live.canCheck && live.statusKey != "更新检查失败", "packaged Sparkle engine starts with signed-feed verification and manual checking available")
        require(!live.automaticChecks && live.lastCheck == nil, "disabled scheduling does not trigger a startup network check")
        if !live.canCheck { print("ENGINE ERROR: \(live.errorDetail)") }
    }
    if let index = CommandLine.arguments.firstIndex(of: "--read-only-app"), CommandLine.arguments.count > index + 1,
       let bundle = Bundle(path: CommandLine.arguments[index + 1]) {
        let readOnly = ApplicationUpdates(bundle: bundle, defaults: defaults)
        readOnly.start()
        require(!readOnly.canCheck && readOnly.statusKey == "请先将应用移入应用程序文件夹", "disk-image app cannot initiate an in-place update")
    }
    if let index = CommandLine.arguments.firstIndex(of: "--engine-no-update-app"), CommandLine.arguments.count > index + 1,
       let bundle = Bundle(path: CommandLine.arguments[index + 1]) {
        let engineDefaults = UserDefaults(suiteName: bundle.bundleIdentifier!)!
        engineDefaults.set(false, forKey: "SUEnableAutomaticChecks")
        defer { engineDefaults.removePersistentDomain(forName: bundle.bundleIdentifier!) }
        let live = ApplicationUpdates(bundle: bundle, defaults: engineDefaults)
        live.start()
        live.checkNow()
        var acknowledged = false
        for _ in 0..<500 {
            if !acknowledged, live.titleKey == "已是最新版本", let done = live.actions.first {
                acknowledged = true
                live.choose(done)
            }
            if acknowledged && live.canCheck { break }
            if !live.errorDetail.isEmpty { break }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        require(acknowledged && live.canCheck && live.statusKey == "已是最新版本", "real signed-feed check stays up-to-date after acknowledgement and engine completion")
        require(live.lastCheck != nil, "real no-update cycle records its check date")
        if !acknowledged { print("ENGINE ERROR: \(live.statusKey) \(live.errorDetail)") }
        live.dismissUpdateInstallation()
    }
    print("\(count) update UI checks, \(failures) failures")
    return failures == 0 ? 0 : 1
}
#endif
