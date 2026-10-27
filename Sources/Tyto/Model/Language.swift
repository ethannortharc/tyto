import Foundation

/// 界面语言
enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system
    case zh
    case en

    var id: String { rawValue }

    /// 选项本身两种语言都写上，切到哪种都认得出来
    var label: String {
        switch self {
        case .system: "跟随系统 · System"
        case .zh: "中文"
        case .en: "English"
        }
    }

    var isEnglish: Bool {
        switch self {
        case .zh: false
        case .en: true
        case .system: !(Locale.preferredLanguages.first ?? "zh").hasPrefix("zh")
        }
    }
}

/// 当前界面是不是英文。设置一改就更新；后台线程（比如报错信息）也会读，所以加锁。
enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var english = false

    static var isEnglish: Bool { lock.withLock { english } }

    static func set(_ language: AppLanguage) {
        lock.withLock { english = language.isEnglish }
    }
}

/// 界面上的文字：中文和英文写在一起，按当前界面语言取一个。
/// 例：Text(tr("开始听", "Start Listening"))
func tr(_ zh: String, _ en: String) -> String {
    L10n.isEnglish ? en : zh
}
