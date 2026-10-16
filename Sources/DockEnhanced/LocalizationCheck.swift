#if DEBUG
import Foundation

func checkLocalization() -> Int32 {
    let suite = "dev.yifeng.DockEnhanced.localization-check." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var failures = 0
    var count = 0
    func require(_ value: Bool, _ name: String) {
        count += 1
        if !value { failures += 1 }
        print("\(value ? "PASS" : "FAIL"): \(name)")
    }
    let language = Localization(defaults: defaults, preferredLanguages: ["en-US"])
    require(language.language == .english, "English system defaults to English")
    let chinese = Localization(defaults: defaults, preferredLanguages: ["zh-TW"])
    require(chinese.language == .simplifiedChinese, "Chinese system defaults to Chinese")
    let unsupported = Localization(defaults: defaults, preferredLanguages: ["fr-FR"])
    require(unsupported.language == .english, "unsupported system languages fall back to English")
    let model = SettingsModel(defaults: defaults, localization: language)
    model.accessibilityGranted = true
    model.switcherAvailable = true
    require(model.switcherStatus == "Ready · Icons and titles available (no Screen Recording access)", "English settings status is translated")
    var updates = 0
    let observer = NotificationCenter.default.addObserver(forName: Localization.didChange, object: language, queue: nil) { notification in
        if notification.object as? Localization === language { updates += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    language.language = .simplifiedChinese
    require(updates == 1 && language.text("通用") == "通用", "switching language notifies native UI immediately")
    require(model.switcherStatus == "增强可用 · 图标和标题可用（未授权屏幕录制）", "existing settings model updates without recreation")
    require(Localization(defaults: defaults, preferredLanguages: ["en-US"]).language == .simplifiedChinese, "explicit choice survives reopening on a different system language")
    language.language = .english
    let reopened = Localization(defaults: defaults, preferredLanguages: ["zh-Hans"])
    require(reopened.language == .english && reopened.text("通用") == "General", "English selection is persisted")
    defaults.set("unsupported", forKey: "appLanguage")
    require(Localization(defaults: defaults, preferredLanguages: ["en"]).language == .english, "invalid stored preference safely falls back")
    require(language.text("External window title") == "External window title", "external names and window titles remain unchanged")
    require(Localization.english.values.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy { !(0x3400...0x9FFF).contains($0.value) } }, "all English translations are populated and contain no Chinese text")
    require(String(format: language.text("%.2f 秒"), 0.4) == "0.40 s", "formatted delay uses the selected language")
    require(language.text("无法切换到此窗口，请重试") == "Could not switch to this window. Try again.", "failure notice is translated")
    require(language.text("已最小化") == "Minimized", "window switcher badge is translated")
    print("\(count) localization checks, \(failures) failures")
    return failures == 0 ? 0 : 1
}
#endif
