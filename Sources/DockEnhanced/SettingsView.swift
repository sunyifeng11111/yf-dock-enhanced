import SwiftUI

enum PreviewPreferences {
    static var hoverDelay: Double {
        let value = UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.40
        return min(1.5, max(0.4, value))
    }
}

final class SettingsModel: ObservableObject {
    // Carry the old master switch into each feature until that feature is customized.
    @Published var previewEnabled = UserDefaults.standard.object(forKey: "previewEnabled") as? Bool
        ?? UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(previewEnabled, forKey: "previewEnabled"); onFeaturesChange?() }
    }
    @Published var clickEnabled = UserDefaults.standard.object(forKey: "clickEnabled") as? Bool
        ?? UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(clickEnabled, forKey: "clickEnabled"); onFeaturesChange?() }
    }
    @Published var delay = PreviewPreferences.hoverDelay {
        didSet { UserDefaults.standard.set(delay, forKey: "hoverDelay") }
    }
    @Published var hideMenuBarIcon = UserDefaults.standard.bool(forKey: "hideMenuBarIcon") {
        didSet {
            UserDefaults.standard.set(hideMenuBarIcon, forKey: "hideMenuBarIcon")
            onMenuBarVisibilityChange?(hideMenuBarIcon)
        }
    }
    @Published var accessibilityGranted = false
    @Published var captureGranted = false
    @Published var running = false
    var anyFeatureEnabled: Bool { previewEnabled || clickEnabled }
    var onFeaturesChange: (() -> Void)?
    var onMenuBarVisibilityChange: ((Bool) -> Void)?
}

private enum SettingsPage: String, CaseIterable {
    case dock = "Dock 功能"
    case general = "通用"

    var symbol: String { self == .dock ? "dock.rectangle" : "gearshape" }
    var detail: String { self == .dock ? "让窗口预览与切换符合你的习惯。" : "管理启动、菜单栏显示与系统权限。" }
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

    private var status: String { model.running ? "正在运行" : (model.anyFeatureEnabled ? "等待授权" : "已暂停") }
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
                        if page == .dock { dockSettings } else { generalSettings }
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
                permission("辅助功能", detail: "识别 Dock 图标，操作你选择的窗口。", symbol: "hand.point.up.left", granted: model.accessibilityGranted, action: requestAccessibility)
                Divider().padding(.horizontal, 16)
                permission("屏幕录制", detail: "仅悬停预览需要，用于生成窗口缩略图。", symbol: "rectangle.on.rectangle", granted: model.captureGranted, action: requestCapture)
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
