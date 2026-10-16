import AppKit
import SwiftUI
import Sparkle

/// Sparkle owns scheduling, signatures, replacement, recovery and relaunch.
/// This adapter owns app-language UI and never opts into automatic downloads.
final class ApplicationUpdates: NSObject, ObservableObject, SPUUpdaterDelegate, SPUUserDriver, NSWindowDelegate {
    static let releasePage = URL(string: "https://github.com/sunyifeng11111/yf-dock-enhanced/releases/latest")!
    @Published var automaticChecks: Bool {
        didSet {
            defaults.set(automaticChecks, forKey: "SUEnableAutomaticChecks")
            updater?.automaticallyChecksForUpdates = automaticChecks
        }
    }
    @Published private(set) var canCheck = false
    @Published private(set) var statusKey = "尚未检查更新"
    @Published private(set) var lastCheck: Date?
    @Published private(set) var titleKey = "软件更新"
    @Published private(set) var messageKey = ""
    @Published private(set) var offeredVersion = ""
    @Published private(set) var errorDetail = ""
    @Published private(set) var progress: Double?
    @Published private(set) var actions: [UpdateAction] = []
    private let defaults: UserDefaults
    private let bundle: Bundle
    private var updater: SPUUpdater?
    private var subscriptions: [NSKeyValueObservation] = []
    private var window: NSWindow?
    private var closeAction: (() -> Void)?
    private var received: UInt64 = 0
    private var expected: UInt64 = 0
    private var locationAvailable = false

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        self.bundle = bundle
        self.defaults = defaults
        automaticChecks = defaults.object(forKey: "SUEnableAutomaticChecks") as? Bool ?? true
        super.init()
    }

    func start() {
        guard updater == nil else { return }
        let url = bundle.bundleURL
        let readOnly = (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true
        let path = url.standardizedFileURL.path
        let applications = ["/Applications/", FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path + "/"]
        guard url.pathExtension == "app", applications.contains(where: { path.hasPrefix($0) }),
              !readOnly, !path.contains("/AppTranslocation/") else {
            statusKey = "请先将应用移入应用程序文件夹"
            return
        }
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              URL(string: feed)?.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            statusKey = "此构建未配置更新"
            return
        }
        locationAvailable = true
        let engine = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: self, delegate: self)
        updater = engine
        engine.sendsSystemProfile = false
        engine.automaticallyDownloadsUpdates = false
        engine.automaticallyChecksForUpdates = automaticChecks
        engine.updateCheckInterval = 24 * 60 * 60
        engine.userAgentString = "DockEnhanced-Updater"
        subscriptions = [
            engine.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] engine, _ in
                self?.canCheck = engine.canCheckForUpdates
            },
            engine.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] engine, _ in
                self?.lastCheck = engine.lastUpdateCheckDate
            }
        ]
        do { try engine.start(); statusKey = "尚未检查更新" }
        catch { updater = nil; canCheck = false; statusKey = "更新检查失败"; errorDetail = error.localizedDescription }
    }

    func checkNow() {
        guard locationAvailable else {
            present(title: "软件更新", message: statusKey, actions: [UpdateAction("好") {}])
            return
        }
        guard let updater else {
            present(title: "更新检查失败", message: statusKey, actions: [UpdateAction("好") {}], detail: errorDetail)
            return
        }
        guard updater.canCheckForUpdates else { showUpdateInFocus(); return }
        updater.checkForUpdates()
    }

    // Only the default (stable) channel is allowed. Sparkle also filters OS/arch
    // incompatibility and uses CFBundleVersion to prevent ordinary downgrades.
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { [] }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) { statusKey = "发现新版本" }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { statusKey = "已是最新版本" }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { statusKey = "更新检查失败" }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        canCheck = updater.canCheckForUpdates
        lastCheck = updater.lastUpdateCheckDate
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticChecks, automaticUpdateDownloading: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        statusKey = "正在检查更新…"
        present(title: "软件更新", message: statusKey, actions: [UpdateAction("取消", action: cancellation)])
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        offeredVersion = appcastItem.displayVersionString
        statusKey = "发现新版本"
        if appcastItem.isInformationOnlyUpdate {
            present(title: statusKey, message: "请从发布页面下载此版本", actions: [
                UpdateAction("前往下载") { NSWorkspace.shared.open(Self.releasePage); reply(.dismiss) },
                UpdateAction("稍后") { reply(.dismiss) }
            ])
            return
        }
        present(title: statusKey, message: "下载完成后将安装并重新启动，保留现有设置。", actions: [
            UpdateAction("下载并更新") { reply(.install) },
            UpdateAction("稍后") { reply(.dismiss) },
            UpdateAction("跳过此版本") { reply(.skip) }
        ], activate: state.userInitiated)
        closeAction = { reply(.dismiss) }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        statusKey = "已是最新版本"
        present(title: statusKey, message: "没有适用于当前系统的新版本。", actions: [UpdateAction("好", action: acknowledgement)])
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        statusKey = "更新失败，仍可使用当前版本"
        errorDetail = error.localizedDescription
        present(title: "更新失败", message: statusKey, actions: [
            UpdateAction("重试") { [weak self] in
                acknowledgement()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkNow() }
            },
            UpdateAction("前往下载") { NSWorkspace.shared.open(Self.releasePage); acknowledgement() },
            UpdateAction("关闭", action: acknowledgement)
        ], detail: error.localizedDescription)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        received = 0; expected = 0
        present(title: "正在下载更新…", message: "下载完成后将安装并重新启动，保留现有设置。", actions: [UpdateAction("取消", action: cancellation)])
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        if expected > 0 { progress = min(1, Double(received) / Double(expected)) }
    }
    func showDownloadDidStartExtractingUpdate() {
        present(title: "正在验证并准备更新…", message: "请稍候…", actions: [])
    }
    func showExtractionReceivedProgress(_ progress: Double) { self.progress = min(1, max(0, progress)) }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        present(title: "正在安装更新…", message: "安装完成后将重新启动。", actions: applicationTerminated ? [] : [UpdateAction("重新尝试退出", action: retryTerminatingApplication)])
        closeAction = nil
        window?.styleMask.remove(.closable)
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { dismissUpdateInstallation(); acknowledgement() }
    func dismissUpdateInstallation() { window?.orderOut(nil); closeAction = nil; actions = []; offeredVersion = "" }
    func showUpdateInFocus() { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }

    private func present(title: String, message: String, actions: [UpdateAction], detail: String = "", activate: Bool = true) {
        titleKey = title; messageKey = message; self.actions = actions; errorDetail = detail; progress = nil
        closeAction = actions.last?.action
        if window == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 480, height: 300), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentView = NSHostingView(rootView: UpdateProgressView(updates: self))
            panel.center()
            window = panel
        }
        window?.title = "Dock Enhanced"
        if actions.isEmpty { window?.styleMask.remove(.closable) } else { window?.styleMask.insert(.closable) }
        if activate { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { window?.orderFront(nil) }
    }
    func choose(_ action: UpdateAction) {
        window?.orderOut(nil)
        closeAction = nil
        action.action()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let closeAction else { return false }
        self.closeAction = nil
        closeAction()
        return true
    }
}

struct UpdateAction: Identifiable {
    let id = UUID()
    let key: String
    let action: () -> Void
    init(_ key: String, action: @escaping () -> Void) { self.key = key; self.action = action }
}

private struct UpdateProgressView: View {
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject private var localization = Localization.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.text(updates.titleKey)).font(.title2).bold()
            if !updates.offeredVersion.isEmpty { Text("Dock Enhanced " + updates.offeredVersion).font(.headline) }
            Text(localization.text(updates.messageKey)).fixedSize(horizontal: false, vertical: true)
            if let progress = updates.progress { ProgressView(value: progress) }
            if !updates.errorDetail.isEmpty {
                ScrollView { Text(updates.errorDetail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }.frame(maxHeight: 70)
            }
            Spacer(minLength: 0)
            HStack {
                ForEach(updates.actions) { action in
                    Button(localization.text(action.key)) { updates.choose(action) }
                }
            }
        }.padding(24).frame(width: 480, height: 300)
    }
}
