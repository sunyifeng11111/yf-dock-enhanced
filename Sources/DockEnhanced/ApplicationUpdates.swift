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
    @Published var showErrorDetails = false {
        didSet { resizeWindow() }
    }
    var applicationIcon: NSImage {
        if let url = bundle.url(forResource: "AppIcon", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSApplication.shared.applicationIconImage
    }
    var currentVersion: String { bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版") }
    var isBusy: Bool { ["正在检查更新…", "正在下载更新…", "正在验证并准备更新…", "正在安装更新…"].contains(titleKey) }
    var panelHeight: CGFloat {
        if !errorDetail.isEmpty { return showErrorDetails ? 310 : 222 }
        if isBusy { return 224 }
        return titleKey == "已是最新版本" ? 176 : 210
    }
    #if DEBUG
    var previewWindow: NSWindow? { window }
    #endif
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
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        // Sparkle also ends a successful no-update cycle through this callback,
        // after the user acknowledges the up-to-date dialog.
        if error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue) {
            statusKey = "已是最新版本"
        } else {
            statusKey = "更新检查失败"
        }
    }
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
        present(title: statusKey, message: "完成后将重新启动。", actions: [
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
        present(title: statusKey, message: "", actions: [UpdateAction("完成", action: acknowledgement)])
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
        present(title: "正在下载更新…", message: "完成后将重新启动。", actions: [UpdateAction("取消", action: cancellation)])
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) { expected = expectedContentLength }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += length
        if expected > 0 { progress = min(1, Double(received) / Double(expected)) }
    }
    func showDownloadDidStartExtractingUpdate() {
        present(title: "正在验证并准备更新…", message: "", actions: [])
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
        titleKey = title; messageKey = message; self.actions = actions; errorDetail = detail; progress = nil; showErrorDetails = false
        closeAction = actions.last?.action
        if window == nil {
            let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: panelHeight), styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.contentView = NSHostingView(rootView: UpdateProgressView(updates: self))
            panel.center()
            window = panel
        }
        resizeWindow()
        window?.title = "Dock Enhanced"
        if actions.isEmpty { window?.styleMask.remove(.closable) } else { window?.styleMask.insert(.closable) }
        if activate { window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        else { window?.orderFront(nil) }
    }
    private func resizeWindow() {
        guard let window else { return }
        var frame = window.frame
        let height = window.frameRect(forContentRect: CGRect(x: 0, y: 0, width: 440, height: panelHeight)).height
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true)
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
    private var upToDate: Bool { updates.titleKey == "已是最新版本" }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                Image(nsImage: updates.applicationIcon)
                    .resizable().interpolation(.high).frame(width: 56, height: 56)
                    .overlay(alignment: .bottomTrailing) {
                        if upToDate {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette).foregroundStyle(.white, .green)
                                .font(.system(size: 18)).background(.background, in: Circle())
                                .offset(x: 3, y: 3)
                        }
                    }
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 6) {
                    Text(localization.text(updates.titleKey)).font(.system(size: 17, weight: .semibold))
                    Text("Dock Enhanced " + (updates.offeredVersion.isEmpty ? updates.currentVersion : updates.offeredVersion))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if !updates.messageKey.isEmpty {
                        Text(localization.text(updates.messageKey))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if updates.isBusy {
                if let progress = updates.progress { ProgressView(value: progress) }
                else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, alignment: .leading) }
            }
            if !updates.errorDetail.isEmpty {
                DisclosureGroup(localization.text("详细信息"), isExpanded: $updates.showErrorDetails) {
                    ScrollView {
                        Text(updates.errorDetail).font(.system(size: 11)).foregroundStyle(.secondary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(height: 76)
                }.font(.system(size: 11))
            }
            Spacer(minLength: 0)
            Divider()
            HStack(spacing: 8) {
                if updates.actions.count > 2, let last = updates.actions.last {
                    Button(localization.text(last.key)) { updates.choose(last) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if updates.actions.count > 1 {
                    let secondary = updates.actions[1]
                    Button(localization.text(secondary.key)) { updates.choose(secondary) }
                        .buttonStyle(.bordered)
                }
                if let primary = updates.actions.first {
                    Button(localization.text(primary.key)) { updates.choose(primary) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }.controlSize(.regular)
        }
        .padding(.horizontal, 24).padding(.vertical, 20)
        .frame(width: 440, height: updates.panelHeight, alignment: .topLeading)
    }
}
