import SwiftUI

enum PreviewPreferences {
    static var hoverDelay: Double {
        let value = UserDefaults.standard.object(forKey: "hoverDelay") as? Double ?? 0.85
        return min(1.5, max(0.4, value))
    }
}

final class SettingsModel: ObservableObject {
    @Published var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: "enabled"); onEnabledChange?(enabled) }
    }
    @Published var delay = PreviewPreferences.hoverDelay {
        didSet { UserDefaults.standard.set(delay, forKey: "hoverDelay") }
    }
    @Published var accessibilityGranted = false
    @Published var captureGranted = false
    @Published var running = false
    var onEnabledChange: ((Bool) -> Void)?
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @ObservedObject var loginItem: LoginItem
    let requestAccessibility: () -> Void
    let requestCapture: () -> Void

    private var status: String { model.running ? "正在运行" : (model.enabled ? "等待授权" : "已暂停") }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable().interpolation(.high).frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        Text("Dock Enhanced").font(.system(size: 18, weight: .semibold))
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(model.running ? Color.green : Color.orange).frame(width: 6, height: 6)
                            Text(status).font(.system(size: 11, weight: .medium))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.background.opacity(0.7), in: Capsule())
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("窗口切换，轻一点。").font(.system(size: 29, weight: .bold, design: .rounded))
                        Text("保留熟悉的 Dock，让收起、恢复和预览自然衔接。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                }
                .padding(22).frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [.indigo.opacity(0.13), .cyan.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))

                HStack(spacing: 14) {
                    tile("power", color: .indigo)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("启用 Dock 增强").font(.system(size: 14, weight: .semibold))
                        Text("点击收起 / 恢复，悬停选择窗口。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("启用 Dock 增强", isOn: $model.enabled).labelsHidden().toggleStyle(.switch).tint(.indigo)
                }.padding(16).card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 14) {
                        tile("sunrise", color: .teal)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("登录时启动").font(.system(size: 14, weight: .semibold))
                            Text(loginItem.needsApproval ? "等待在系统设置中允许。" : "开机登录后，自动在菜单栏运行。")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("登录时启动", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                            .labelsHidden().toggleStyle(.switch).tint(.indigo)
                    }
                    if loginItem.needsApproval {
                        Button("打开系统登录项设置") { loginItem.openSystemSettings() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                    if let error = loginItem.error {
                        Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
                    }
                }.padding(16).card()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("预览停留时间", systemImage: "cursorarrow.rays").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text(String(format: "%.2f 秒", model.delay)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.indigo)
                    }
                    Slider(value: $model.delay, in: 0.4...1.5, step: 0.05).tint(.indigo)
                    Text("点击或右键后，移开鼠标再悬停，预览才会重新出现。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(16).card()

                VStack(alignment: .leading, spacing: 12) {
                    Text("必要权限").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                    permission("辅助功能", detail: "用于准确操作你选择的窗口", symbol: "hand.point.up.left", granted: model.accessibilityGranted, action: requestAccessibility)
                    Divider()
                    permission("屏幕录制", detail: "用于显示真实的窗口缩略图", symbol: "rectangle.on.rectangle", granted: model.captureGranted, action: requestCapture)
                }.padding(16).card()

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.indigo)
                    Text("最小化窗口使用缓存画面。授权后若缩略图未更新，退出并重新打开应用即可。")
                        .foregroundStyle(.secondary)
                }.font(.system(size: 11)).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
            }
            .padding(24)
        }
        .frame(width: 624)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func tile(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 17, weight: .medium)).foregroundStyle(color)
            .frame(width: 36, height: 36).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
    }

    private func permission(_ title: String, detail: String, symbol: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            tile(granted ? "checkmark.shield" : symbol, color: granted ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if granted { Text("已授权").font(.system(size: 10)).foregroundStyle(.green) }
                }
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(granted ? "查看" : "前往授权", action: action).buttonStyle(.bordered).tint(.indigo).controlSize(.regular)
        }
    }
}

private extension View {
    func card() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.045), lineWidth: 1))
    }
}
