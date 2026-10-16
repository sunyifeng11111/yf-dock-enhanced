import Foundation
import Combine

enum AppLanguage: String, CaseIterable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    var displayName: String { self == .english ? "English" : "简体中文" }
}

/// App-owned text only: window titles and application names remain untouched.
final class Localization: ObservableObject {
    static let shared = Localization()
    static let didChange = Notification.Name("DockEnhancedLanguageDidChange")
    private let defaults: UserDefaults
    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            defaults.set(language.rawValue, forKey: "appLanguage")
            NotificationCenter.default.post(name: Self.didChange, object: self)
        }
    }
    init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        language = defaults.string(forKey: "appLanguage").flatMap(AppLanguage.init(rawValue:))
            ?? (preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english)
    }
    func text(_ key: String) -> String { Self.text(key, language: language) }
    static func text(_ key: String, language: AppLanguage) -> String {
        language == .english ? english[key] ?? key : key
    }
    static let english: [String: String] = [
        "Dock 功能": "Dock Features",
        "窗口切换": "Window Switching",
        "通用": "General",
        "让窗口预览与点击符合你的习惯。": "Customize window previews and Dock clicks.",
        "用 Command+Tab 直接选择具体窗口。": "Use Command+Tab to select individual windows.",
        "管理启动、菜单栏显示与系统权限。": "Manage startup, language, menu bar visibility, and permissions.",
        "开发版": "Development",
        "版本 ": "Version ",
        "退出": "Quit",
        "退出 Dock Enhanced": "Quit Dock Enhanced",
        "悬停预览": "Hover Previews",
        "停留在 Dock 图标上，预览并选择窗口。": "Hover over a Dock icon to preview and select windows.",
        "预览停留时间": "Preview Delay",
        "%.2f 秒": "%.2f s",
        "点击或右键时暂时关闭预览，移开后再悬停显示。最小化窗口使用最近一次的缓存画面。": "Clicking or right-clicking dismisses the preview until you move away and hover again. Minimized windows use their last cached image.",
        "点击收起 / 恢复": "Click to Minimize / Restore",
        "点击前台应用的 Dock 图标收起，再点击恢复。": "Click the foreground app’s Dock icon to minimize its recent window. Click again to restore it.",
        "关闭后，Dock 点击沿用系统行为，仍可通过预览选择窗口。": "When off, Dock clicks use system behavior. You can still select windows through previews.",
        "Command+Tab 增强": "Enhanced Command+Tab",
        "跨应用逐个选择窗口，包含已最小化和隐藏应用的窗口。": "Choose individual windows across apps, including minimized windows and windows in hidden apps.",
        "按住 Command 并按 Tab 浏览，松开确认；Shift+Tab 反向选择。方向键和鼠标也可选中，Enter 确认，Esc 取消。关闭后立即恢复系统 Command+Tab。": "Hold Command and press Tab to browse; release Command to switch. Shift+Tab goes backward. Use arrow keys or the mouse to select, Enter to confirm, and Esc to cancel. Turning this off restores system Command+Tab.",
        "缩略图与隐私": "Thumbnails and Privacy",
        "屏幕录制仅用于缩略图；未授权时仍可使用图标和标题切换窗口。最小化窗口使用最近缓存，并标注“已最小化”。": "Screen Recording is used only for thumbnails. Without it, you can still switch using icons and titles. Minimized windows show cached images and a “Minimized” label.",
        "图片只在内存中保留，最多 64 张；关闭两种预览、撤销录屏权限或退出会清除。窗口标题、使用历史与图片不会写入磁盘。": "Up to 64 images are kept in memory. Turning off both preview features, revoking Screen Recording, or quitting clears them. Window titles, usage history, and images are never written to disk.",
        "仅识别切换和导航需要的物理按键与修饰键，不读取或记录输入文字。": "Only keys and modifiers needed for switching and navigation are recognized. Typed text is never read or recorded.",
        "启动与显示": "Startup and Appearance",
        "登录时启动": "Launch at Login",
        "开机登录后自动在后台运行。": "Run in the background when you log in.",
        "前往系统设置允许启动": "Allow in System Settings",
        "隐藏菜单栏图标": "Hide Menu Bar Icon",
        "隐藏后仍可从“应用程序”或 Spotlight 打开设置。": "You can still open settings from Applications or Spotlight.",
        "按 ⌘ 空格，搜索 Dock Enhanced 并打开，即可重新进入设置。": "Press ⌘ Space, search for Dock Enhanced, and open it to return to settings.",
        "系统权限": "System Permissions",
        "辅助功能": "Accessibility",
        "识别 Dock 图标与切换快捷键，操作你选择的窗口。": "Identify Dock icons and switching shortcuts, and control the windows you select.",
        "屏幕录制": "Screen Recording",
        "用于悬停预览与窗口切换的缩略图；不影响图标和标题切换。": "Enable thumbnails for hover previews and window switching. Icons and titles work without this permission.",
        "若授权后仍未生效，请退出并重新打开应用。": "If access is not recognized after granting permission, quit and reopen the app.",
        "需要授权 · 前往通用设置": "Permission needed · Open General",
        "已授权": "Granted",
        "前往授权": "Grant Access",
        "授权": "Grant access to ",
        "增强已关闭 · 使用系统 Command+Tab": "Enhancement off · Using system Command+Tab",
        "需要辅助功能权限 · 系统 Command+Tab 仍可用": "Accessibility required · System Command+Tab is still available",
        " · 系统 Command+Tab 仍可用": " · System Command+Tab is still available",
        "增强可用 · 窗口缩略图已启用": "Ready · Window thumbnails enabled",
        "增强可用 · 图标和标题可用（未授权屏幕录制）": "Ready · Icons and titles available (no Screen Recording access)",
        "已暂停": "Paused",
        "控制服务未就绪": "Window control is not ready",
        "等待辅助功能授权": "Waiting for Accessibility access",
        "部分功能可用": "Some features available",
        "窗口切换不可用": "Window switching unavailable",
        "正在运行": "Running",
        "快捷键接管尚未就绪": "Shortcut handling is not ready",
        "系统暂停了快捷键监听": "The system paused shortcut monitoring",
        "需要辅助功能权限": "Accessibility access required",
        "增强已关闭": "Enhancement is off",
        "无法创建快捷键监听": "Could not start shortcut monitoring",
        "系统未开放完整的键盘事件": "Full keyboard event access is unavailable",
        "安全输入期间暂不可用": "Unavailable while Secure Input is active",
        "设置…": "Settings…",
        "Dock Enhanced · 设置": "Dock Enhanced · Settings",
        "已最小化": "Minimized",
        "无标题窗口": "Untitled Window",
        "应用": "App",
        " · 已最小化": " · Minimized",
        "已最小化 · 缓存画面": "Minimized · Cached image",
        "选择并切换此窗口": "Select and switch to this window",
        "已选中": "Selected",
        "无法切换到此窗口，请重试": "Could not switch to this window. Try again.",
        "已最小化 · 点击恢复": "Minimized · Click to restore",
        "点击切换窗口": "Click to switch windows",
        "Dock 窗口预览": "Dock Window Preview",
        "无法更新登录项：": "Could not update login item: ",
        "语言": "Language",
        "界面语言": "App Language",
        "切换后立即生效，无需重新启动。": "Changes apply immediately. No restart needed.",
    ]
}

func L(_ key: String) -> String { Localization.shared.text(key) }
