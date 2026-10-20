import SwiftUI

enum PreviewPreferences {
    static var hoverDelay: Double {
        let value = UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.40
        return min(1.5, max(0.4, value))
    }
}

final class SettingsModel: ObservableObject {
    private let defaults: UserDefaults
    let localization: Localization
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
        guard switcherEnabled else { return localization.text("增强已关闭 · 使用系统 Command+Tab") }
        guard accessibilityGranted else { return localization.text("需要辅助功能权限 · 系统 Command+Tab 仍可用") }
        guard switcherAvailable else { return localization.text(switcherUnavailableReason) + localization.text(" · 系统 Command+Tab 仍可用") }
        return captureGranted ? localization.text("增强可用 · 窗口缩略图已启用") : localization.text("增强可用 · 图标和标题可用（未授权屏幕录制）")
    }
    var serviceStatus: String {
        guard anyFeatureEnabled else { return localization.text("已暂停") }
        guard running else { return accessibilityGranted ? localization.text("控制服务未就绪") : localization.text("等待辅助功能授权") }
        if switcherEnabled && !switcherAvailable { return previewEnabled || clickEnabled ? localization.text("部分功能可用") : localization.text("窗口切换不可用") }
        return localization.text("正在运行")
    }
    var onFeaturesChange: (() -> Void)?
    var onMenuBarVisibilityChange: ((Bool) -> Void)?

    init(defaults: UserDefaults = .standard, localization: Localization = .shared) {
        self.localization = localization
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

// Shared settings tokens keep the native controls and custom surfaces in step.
private enum SettingsDesign {
    static let small: CGFloat = 8
    static let inset: CGFloat = 16
    static let section: CGFloat = 24
    static let radius: CGFloat = 12
    static let title = Font.system(size: 26, weight: .semibold)
    static let label = Font.system(size: 13, weight: .medium)
    static let body = Font.system(size: 12)
    static let caption = Font.system(size: 11)
}

private struct SettingsPalette {
    let scheme: ColorScheme
    private func color(_ light: UInt32, _ dark: UInt32) -> Color {
        let value = scheme == .dark ? dark : light
        return Color(.sRGB, red: Double((value >> 16) & 255) / 255,
                     green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
    var accent: Color { color(0x1B65A6, 0x82B9F4) }
    var background: Color { color(0xF3F6F8, 0x1F242A) }
    var sidebar: Color { color(0xEAF0F4, 0x252C33) }
    var surface: Color { color(0xFFFFFF, 0x2B323A) }
    var primary: Color { color(0x24323D, 0xEEF3F8) }
    var secondary: Color { color(0x5E6D7A, 0xB0BEC9) }
    var line: Color { color(0xDBE3E9, 0x414D58) }
    var selection: Color { color(0xDFEBF5, 0x2D4357) }
    var success: Color { color(0x35714D, 0x92C9A6) }
}

struct SettingsView: View {
    @ObservedObject private var localization: Localization
    @ObservedObject var model: SettingsModel
    @ObservedObject var loginItem: LoginItem
    @ObservedObject var updates: ApplicationUpdates
    let requestAccessibility: () -> Void
    let requestCapture: () -> Void
    @ViewState private var page = SettingsPage.dock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    private var palette: SettingsPalette { SettingsPalette(scheme: colorScheme) }

    init(model: SettingsModel, loginItem: LoginItem, updates: ApplicationUpdates = ApplicationUpdates(), requestAccessibility: @escaping () -> Void, requestCapture: @escaping () -> Void) {
        self.model = model
        self.loginItem = loginItem
        self.updates = updates
        self.localization = model.localization
        self.requestAccessibility = requestAccessibility
        self.requestCapture = requestCapture
    }

    private func L(_ key: String) -> String { localization.text(key) }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("开发版") }
    private var statusColor: Color {
        guard model.anyFeatureEnabled else { return palette.secondary }
        return model.running && (!model.switcherEnabled || model.switcherAvailable) ? palette.success : palette.accent
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 200)
            Rectangle().fill(palette.line).frame(width: 1)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: SettingsDesign.small) {
                    Text(L(page.rawValue)).font(SettingsDesign.title).accessibilityAddTraits(.isHeader)
                    Text(L(page.detail)).font(SettingsDesign.body).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SettingsDesign.section)
                .background(SettingsWindowDragArea())
                ScrollView {
                    VStack(alignment: .leading, spacing: SettingsDesign.section) {
                        switch page {
                        case .dock: dockSettings
                        case .switcher: switcherSettings
                        case .general: generalSettings
                        }
                    }
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, SettingsDesign.section)
                    .padding(.bottom, SettingsDesign.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(page)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(palette.background)
        }
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .frame(minWidth: 760, minHeight: 500)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: SettingsDesign.small) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 32, height: 32)
                    .accessibilityHidden(true)
                Text("Dock Enhanced").font(SettingsDesign.label)
            }
            .padding(.horizontal, SettingsDesign.inset)
            .padding(.top, 56).padding(.bottom, SettingsDesign.section)
            .background(SettingsWindowDragArea())
            VStack(spacing: 4) {
                ForEach(SettingsPage.allCases, id: \.self) { item in
                    Button { page = item } label: {
                        HStack(spacing: SettingsDesign.small) {
                            Image(systemName: item.symbol).font(.system(size: 16, weight: .medium)).frame(width: 24)
                            Text(L(item.rawValue)).font(SettingsDesign.label).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(page == item ? palette.accent : palette.secondary)
                        .padding(.horizontal, SettingsDesign.small)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .background(page == item ? palette.selection : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(page == item ? .isSelected : [])
                    .accessibilityIdentifier("settings.page.\(item)")
                }
            }.padding(.horizontal, SettingsDesign.small)
            Spacer(minLength: SettingsDesign.section)
            HStack(spacing: SettingsDesign.small) {
                Circle().fill(statusColor).frame(width: 6, height: 6).accessibilityHidden(true)
                Text(model.serviceStatus).font(SettingsDesign.caption)
                    .foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, SettingsDesign.inset).padding(.bottom, SettingsDesign.inset)
            Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, SettingsDesign.inset)
            HStack {
                Text(L("版本 ") + version).font(SettingsDesign.caption).foregroundStyle(palette.secondary)
                Spacer(minLength: 0)
                Button(L("退出")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain).font(SettingsDesign.caption).foregroundStyle(palette.secondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel(L("退出 Dock Enhanced"))
            }.padding(.horizontal, SettingsDesign.inset).padding(.vertical, 4)
        }
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
    }

    @ViewBuilder private var dockSettings: some View {
        VStack(spacing: 0) {
            settingToggle(L("悬停预览"), detail: L("停留在 Dock 图标上，预览并选择窗口。"), symbol: "rectangle.on.rectangle", isOn: $model.previewEnabled,
                          needsPermission: model.previewEnabled && (!model.accessibilityGranted || !model.captureGranted), identifier: "settings.preview")
            if model.previewEnabled {
                groupDivider
                VStack(alignment: .leading, spacing: SettingsDesign.small) {
                    HStack {
                        Text(L("预览停留时间")).font(SettingsDesign.body)
                        Spacer()
                        Text(String(format: L("%.2f 秒"), model.delay))
                            .font(SettingsDesign.body.monospacedDigit()).foregroundStyle(palette.accent)
                            .padding(.horizontal, SettingsDesign.small).padding(.vertical, 4)
                            .background(palette.selection, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Slider(value: $model.delay, in: 0.4...1.5, step: 0.05)
                        .controlSize(.regular).accessibilityLabel(L("预览停留时间"))
                        .accessibilityValue(String(format: L("%.2f 秒"), model.delay))
                    HStack {
                        Text(String(format: L("%.2f 秒"), 0.4))
                        Spacer()
                        Text(String(format: L("%.2f 秒"), 1.5))
                    }.font(SettingsDesign.caption).foregroundStyle(palette.secondary)
                }.padding(SettingsDesign.inset)
            }
        }
        .settingsGroup()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.previewEnabled)

        settingToggle(L("点击收起 / 恢复"), detail: L("点击前台应用的 Dock 图标收起，再点击恢复。"), symbol: "cursorarrow.click", isOn: $model.clickEnabled,
                      needsPermission: model.clickEnabled && !model.accessibilityGranted, identifier: "settings.click")
            .settingsGroup()
    }

    @ViewBuilder private var switcherSettings: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            settingToggle(L("Command+Tab 增强"), detail: L("跨应用逐个选择窗口，包含已最小化和隐藏应用的窗口。"), symbol: "rectangle.3.group", isOn: $model.switcherEnabled,
                          needsPermission: model.switcherEnabled && !model.accessibilityGranted, identifier: "settings.switcher")
                .settingsGroup()
            Label(model.switcherStatus, systemImage: model.switcherEnabled && model.accessibilityGranted && model.switcherAvailable ? "checkmark.circle" : "info.circle")
                .font(SettingsDesign.body).foregroundStyle(palette.secondary)
                .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
        }
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("快捷键"))
            VStack(spacing: 0) {
                shortcutRow(["⌘", "Tab"], title: L("选择下一个窗口"))
                groupDivider
                shortcutRow(["⌘", "⇧", "Tab"], title: L("反向选择窗口"))
                groupDivider
                shortcutRow(["Esc"], title: L("取消切换"))
            }.settingsGroup()
            Text(L("按住 Command 浏览，松开即可切换。也可使用方向键、鼠标和 Enter。"))
                .settingsFootnote()
        }
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("缩略图与隐私"))
            Text(L("屏幕录制仅用于缩略图；未授权时仍可使用图标和标题切换窗口。最小化窗口使用最近缓存，并标注“已最小化”。"))
                .font(SettingsDesign.body).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var generalSettings: some View {
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("语言"))
            HStack(spacing: SettingsDesign.inset) {
                settingIcon("globe")
                Text(L("界面语言")).font(SettingsDesign.label)
                Spacer(minLength: SettingsDesign.small)
                Picker(L("界面语言"), selection: $localization.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
                .frame(minHeight: 44)
            }.padding(.horizontal, SettingsDesign.inset).padding(.vertical, SettingsDesign.small).settingsGroup()
        }
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("系统权限"))
            VStack(spacing: 0) {
                permission(L("辅助功能"), detail: L("识别 Dock 图标与切换快捷键，操作你选择的窗口。"), symbol: "hand.point.up.left", granted: model.accessibilityGranted, action: requestAccessibility)
                groupDivider
                permission(L("屏幕录制"), detail: L("用于悬停预览与窗口切换的缩略图；不影响图标和标题切换。"), symbol: "rectangle.on.rectangle", granted: model.captureGranted, action: requestCapture)
            }.settingsGroup()
            Text(L("若授权后仍未生效，请退出并重新打开应用。"))
                .settingsFootnote()
        }
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("启动与显示"))
            VStack(spacing: 0) {
                settingToggle(L("登录时启动"), detail: L("开机登录后自动在后台运行。"), symbol: "sunrise", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.needsApproval {
                    Button(L("前往系统设置允许启动")) { loginItem.openSystemSettings() }
                        .buttonStyle(.link).font(SettingsDesign.body).frame(minHeight: 44)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, SettingsDesign.inset)
                }
                if let error = loginItem.error {
                    Text(error).font(SettingsDesign.body).foregroundStyle(.red).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, SettingsDesign.inset).padding(.bottom, SettingsDesign.inset)
                }
                groupDivider
                settingToggle(L("隐藏菜单栏图标"), detail: L("隐藏后仍可从“应用程序”或 Spotlight 打开设置。"), symbol: "menubar.rectangle", isOn: $model.hideMenuBarIcon)
                if model.hideMenuBarIcon {
                    Text(L("按 ⌘ 空格，搜索 Dock Enhanced 并打开，即可重新进入设置。"))
                        .font(SettingsDesign.body).foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, SettingsDesign.inset).padding(.bottom, SettingsDesign.inset)
                }
            }.settingsGroup()
        }
        VStack(alignment: .leading, spacing: SettingsDesign.small) {
            sectionTitle(L("软件更新"))
            VStack(alignment: .leading, spacing: 0) {
                settingToggle(L("自动检查更新"), detail: "", symbol: "arrow.triangle.2.circlepath", isOn: $updates.automaticChecks)
                groupDivider
                HStack(spacing: SettingsDesign.inset) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(updates.statusKey)).font(SettingsDesign.body).foregroundStyle(palette.secondary)
                        if let lastCheck = updates.lastCheck {
                            Text(L("上次检查：") + lastCheck.formatted(date: .abbreviated, time: .shortened))
                                .font(SettingsDesign.caption).foregroundStyle(palette.secondary)
                        }
                    }.fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Button(L("检查更新…")) { updates.checkNow() }
                        .disabled(!updates.canCheck).controlSize(.regular).frame(minHeight: 44)
                }.padding(.horizontal, SettingsDesign.inset).padding(.vertical, SettingsDesign.small)
            }.settingsGroup()
        }
    }

    private var groupDivider: some View {
        Rectangle().fill(palette.line).frame(height: 1).padding(.horizontal, SettingsDesign.inset)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(SettingsDesign.label).foregroundStyle(palette.secondary)
            .padding(.leading, 4).accessibilityAddTraits(.isHeader)
    }

    private func settingToggle(_ title: String, detail: String, symbol: String, isOn: Binding<Bool>, needsPermission: Bool = false, identifier: String = "") -> some View {
        HStack(alignment: .center, spacing: SettingsDesign.inset) {
            settingIcon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsDesign.label)
                if !detail.isEmpty {
                    Text(detail).font(SettingsDesign.body).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if needsPermission {
                    Button { page = .general } label: {
                        HStack(spacing: 4) {
                            Text(L("需要授权 · 前往通用设置"))
                            Image(systemName: "arrow.up.right").font(SettingsDesign.caption)
                        }.font(SettingsDesign.body).foregroundStyle(palette.accent).frame(minHeight: 44)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier(identifier + ".permission")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier(identifier)
        }.padding(SettingsDesign.inset)
    }

    private func settingIcon(_ symbol: String) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(palette.accent)
            .frame(width: 32, height: 32).background(palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private func shortcutRow(_ keys: [String], title: String) -> some View {
        HStack(spacing: SettingsDesign.inset) {
            Text(title).font(SettingsDesign.body)
            Spacer(minLength: SettingsDesign.small)
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    Text(key).font(SettingsDesign.body.monospaced())
                        .frame(minWidth: 28, minHeight: 28)
                        .padding(.horizontal, 4)
                        .background(palette.background, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(palette.line, lineWidth: 1))
                }
            }.accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, SettingsDesign.inset).padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined(separator: " + ") + ", " + title)
    }

    private func permission(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: SettingsDesign.inset) {
            settingIcon(symbol)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(SettingsDesign.label)
                if !granted {
                    Text(detail).font(SettingsDesign.body).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: SettingsDesign.small)
            if granted {
                Label(L("已授权"), systemImage: "checkmark.circle.fill").font(SettingsDesign.body).foregroundStyle(palette.success)
                    .fixedSize()
            } else {
                Button(L("前往授权"), action: action).buttonStyle(.bordered).controlSize(.regular)
                    .frame(minHeight: 44).fixedSize().accessibilityLabel(L("授权") + title)
            }
        }.frame(minHeight: 44).padding(SettingsDesign.inset)
    }
}

private struct SettingsGroup: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let palette = SettingsPalette(scheme: scheme)
        content.frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: SettingsDesign.radius))
            .overlay(RoundedRectangle(cornerRadius: SettingsDesign.radius).strokeBorder(palette.line.opacity(0.7), lineWidth: 1))
    }
}

private struct SettingsFootnote: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content.font(SettingsDesign.caption).foregroundStyle(SettingsPalette(scheme: scheme).secondary)
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 4)
    }
}

private extension View {
    func settingsGroup() -> some View { modifier(SettingsGroup()) }
    func settingsFootnote() -> some View { modifier(SettingsFootnote()) }
}
