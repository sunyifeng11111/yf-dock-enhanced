import SwiftUI

enum PreviewPreferences {
    static var hoverDelay: Double {
        let value = UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.40
        return min(1.5, max(0.4, value))
    }
}

final class SettingsModel: ObservableObject {
    private let defaults: UserDefaults
    @Published var previewEnabled: Bool {
        didSet { defaults.set(previewEnabled, forKey: "previewEnabled"); onFeaturesChange?() }
    }
    @Published var clickEnabled: Bool {
        didSet { defaults.set(clickEnabled, forKey: "clickEnabled"); onFeaturesChange?() }
    }
    @Published var switcherEnabled: Bool {
        didSet { defaults.set(switcherEnabled, forKey: "switcherEnabled"); onFeaturesChange?() }
    }
    @Published var switcherAvailable = false
    @Published var switcherUnavailableReason = "快捷键接管尚未就绪"
    @Published var delay: Double {
        didSet { defaults.set(delay, forKey: "hoverDelay") }
    }
    @Published var hideMenuBarIcon: Bool {
        didSet {
            defaults.set(hideMenuBarIcon, forKey: "hideMenuBarIcon")
            onMenuBarVisibilityChange?(hideMenuBarIcon)
        }
    }
    @Published var accessibilityGranted = false
    @Published var captureGranted = false
    @Published var running = false
    var anyFeatureEnabled: Bool { previewEnabled || clickEnabled || switcherEnabled }
    var switcherStatus: String {
        guard switcherEnabled else { return "增强已关闭 · 使用系统 Command+Tab" }
        guard accessibilityGranted else { return "需要辅助功能权限 · 系统 Command+Tab 仍可用" }
        guard switcherAvailable else { return switcherUnavailableReason + " · 系统 Command+Tab 仍可用" }
        return captureGranted ? "增强可用 · 窗口缩略图已启用" : "增强可用 · 图标和标题可用（未授权屏幕录制）"
    }
    var serviceStatus: String {
        guard anyFeatureEnabled else { return "已暂停" }
        guard running else { return accessibilityGranted ? "控制服务未就绪" : "等待辅助功能授权" }
        if switcherEnabled && !switcherAvailable { return "部分功能可用" }
        return "正在运行"
    }
    var onFeaturesChange: (() -> Void)?
    var onMenuBarVisibilityChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Existing Dock choices inherit the former master only until customized.
        // The new feature never inherits that old switch.
        previewEnabled = defaults.object(forKey: "previewEnabled") as? Bool
            ?? defaults.object(forKey: "enabled") as? Bool ?? true
        clickEnabled = defaults.object(forKey: "clickEnabled") as? Bool
            ?? defaults.object(forKey: "enabled") as? Bool ?? true
        switcherEnabled = defaults.object(forKey: "switcherEnabled") as? Bool ?? true
        delay = min(1.5, max(0.4, defaults.object(forKey: "hoverDelay") as? Double ?? 0.40))
        hideMenuBarIcon = defaults.bool(forKey: "hideMenuBarIcon")
    }
}

private enum SettingsPage: String, CaseIterable {
    case dock = "Dock 功能"
    case switcher = "窗口切换"
    case general = "通用"

    var symbol: String {
        switch self {
        case .dock: return "dock.rectangle"
        case .switcher: return "rectangle.3.group"
        case .general: return "gearshape"
        }
    }
    var detail: String {
        switch self {
        case .dock: return "让窗口预览与点击符合你的习惯。"
        case .switcher: return "用 Command+Tab 直接选择具体窗口。"
        case .general: return "管理启动、菜单栏显示与系统权限。"
        }
    }
}

// Disambiguate the property wrapper from the newer SDK's same-named macro.
private typealias ViewState<Value> = SwiftUI.State<Value>

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var loginItem: LoginItem
    let requestAccessibility: () -> Void
    let requestCapture: () -> Void
    @ViewState private var page = SettingsPage.dock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var status: String { model.serviceStatus }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版" }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 178)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(page.rawValue).font(.system(size: 23, weight: .semibold))
                    Text(page.detail).font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28).padding(.top, 24).padding(.bottom, 22)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch page {
                        case .dock: dockSettings
                        case .switcher: switcherSettings
                        case .general: generalSettings
                        }
                    }
                    .padding(.horizontal, 28).padding(.bottom, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 30, height: 30)
                    .accessibilityHidden(true)
                Text("Dock Enhanced").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 14).padding(.top, 20).padding(.bottom, 24)
            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 15)).frame(width: 20)
                            Text(item.rawValue).font(.system(size: 13, weight: page == item ? .medium : .regular))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(page == item ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 10).padding(.vertical, 10)
                        .background(page == item ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                }
            }.padding(.horizontal, 10)
            Spacer()
            HStack(spacing: 6) {
                Circle().fill(model.running ? Color.green : (model.anyFeatureEnabled ? .orange : .secondary)).frame(width: 6, height: 6)
                Text(status).font(.system(size: 11)).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.bottom, 14)
            Divider().padding(.horizontal, 14)
            HStack {
                Text("版本 " + version).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityLabel("退出 Dock Enhanced")
            }.padding(.horizontal, 16).padding(.vertical, 14)
        }
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
    }

    @ViewBuilder private var dockSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                settingToggle("悬停预览", detail: "停留在 Dock 图标上，预览并选择窗口。", symbol: "rectangle.on.rectangle", isOn: $model.previewEnabled,
                              needsPermission: model.previewEnabled && (!model.accessibilityGranted || !model.captureGranted))
                if model.previewEnabled {
                    Divider().padding(.horizontal, 16)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("预览停留时间").font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f 秒", model.delay)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        Slider(value: $model.delay, in: 0.4...1.5, step: 0.05)
                            .controlSize(.small).accessibilityLabel("预览停留时间")
                    }.padding(16)
                }
            }.settingsGroup()
            Text("点击或右键时暂时关闭预览，移开后再悬停显示。最小化窗口使用最近一次的缓存画面。")
                .settingsFootnote()
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.previewEnabled)

        VStack(alignment: .leading, spacing: 8) {
            settingToggle("点击收起 / 恢复", detail: "点击前台应用的 Dock 图标收起，再点击恢复。", symbol: "cursorarrow.click", isOn: $model.clickEnabled,
                          needsPermission: model.clickEnabled && !model.accessibilityGranted)
                .settingsGroup()
            Text("关闭后，Dock 点击沿用系统行为，仍可通过预览选择窗口。")
                .settingsFootnote()
        }
    }

    @ViewBuilder private var switcherSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            settingToggle("Command+Tab 增强", detail: "跨应用逐个选择窗口，包含已最小化和隐藏应用的窗口。", symbol: "rectangle.3.group", isOn: $model.switcherEnabled,
                          needsPermission: model.switcherEnabled && !model.accessibilityGranted)
                .settingsGroup()
            Label(model.switcherStatus, systemImage: model.switcherAvailable ? "checkmark.circle" : "info.circle")
                .font(.system(size: 12)).foregroundStyle(model.switcherAvailable ? Color.secondary : Color.orange)
                .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            Text("按住 Command 并按 Tab 浏览，松开确认；Shift+Tab 反向选择。方向键和鼠标也可选中，Enter 确认，Esc 取消。关闭后立即恢复系统 Command+Tab。")
                .settingsFootnote()
        }
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("缩略图与隐私")
            VStack(alignment: .leading, spacing: 10) {
                Text("屏幕录制仅用于缩略图；未授权时仍可使用图标和标题切换窗口。最小化窗口使用最近缓存，并标注“已最小化”。")
                Text("图片只在内存中保留，最多 64 张；关闭两种预览、撤销录屏权限或退出会清除。窗口标题、使用历史与图片不会写入磁盘。")
                Text("仅识别切换和导航需要的物理按键与修饰键，不读取或记录输入文字。")
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(16).settingsGroup()
        }
    }

    @ViewBuilder private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("启动与显示")
            VStack(spacing: 0) {
                settingToggle("登录时启动", detail: "开机登录后自动在后台运行。", symbol: "sunrise", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    Button("前往系统设置允许启动") { loginItem.openSystemSettings() }
                        .buttonStyle(.link).font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
                }
                if let error = loginItem.error {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
                }
                Divider().padding(.horizontal, 16)
                settingToggle("隐藏菜单栏图标", detail: "隐藏后仍可从“应用程序”或 Spotlight 打开设置。", symbol: "menubar.rectangle", isOn: $model.hideMenuBarIcon)
                if model.hideMenuBarIcon {
                    Text("按 ⌘ 空格，搜索 Dock Enhanced 并打开，即可重新进入设置。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.bottom, 14)
                }
            }.settingsGroup()
        }
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("系统权限")
            VStack(spacing: 0) {
                permission("辅助功能", detail: "识别 Dock 图标与切换快捷键，操作你选择的窗口。", symbol: "hand.point.up.left", granted: model.accessibilityGranted, action: requestAccessibility)
                Divider().padding(.horizontal, 16)
                permission("屏幕录制", detail: "用于悬停预览与窗口切换的缩略图；不影响图标和标题切换。", symbol: "rectangle.on.rectangle", granted: model.captureGranted, action: requestCapture)
            }.settingsGroup()
            Text("若授权后仍未生效，请退出并重新打开应用。")
                .settingsFootnote()
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 2)
    }

    private func settingToggle(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>, needsPermission: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 12) {
            settingIcon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if needsPermission {
                    Button("需要授权 · 前往通用设置") { page = .general }
                        .buttonStyle(.link).font(.system(size: 11)).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }.padding(16)
    }

    private func settingIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(Color.accentColor)
            .frame(width: 28, height: 28).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
            .accessibilityHidden(true)
    }

    private func permission(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            settingIcon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                if !granted { Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 12)
            if granted {
                Label("已授权", systemImage: "checkmark.circle.fill").font(.system(size: 11)).foregroundStyle(.green)
            } else {
                Button("前往授权", action: action).buttonStyle(.bordered).controlSize(.small)
                    .accessibilityLabel("授权" + title)
            }
        }.padding(16)
    }
}

private extension View {
    func settingsGroup() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }

    func settingsFootnote() -> some View {
        self.font(.system(size: 11)).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }
}
