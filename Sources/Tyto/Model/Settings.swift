import Foundation
import Security
import SwiftUI

/// 大模型的连接设置。回复建议用它，选了"大模型翻译"时翻译也用它。
struct LLMConfig: Codable, Equatable, Sendable {
    enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
        case anthropic
        case openAICompatible
        case ollama

        var id: String { rawValue }
        var label: String {
            switch self {
            case .anthropic: "Anthropic"
            case .openAICompatible: "OpenAI 兼容"
            case .ollama: "Ollama 本机"
            }
        }
        var detail: String {
            switch self {
            case .anthropic: "Claude 系列"
            case .openAICompatible: "OpenAI、Gemini、DeepSeek、通义、OpenRouter、LM Studio…"
            case .ollama: "在这台 Mac 上跑开源模型，数据不出本机"
            }
        }
        var symbol: String {
            switch self {
            case .anthropic: "sparkle"
            case .openAICompatible: "network"
            case .ollama: "desktopcomputer"
            }
        }
        var defaultBaseURL: String {
            switch self {
            case .anthropic: "https://api.anthropic.com"
            case .openAICompatible: "https://api.openai.com/v1"
            case .ollama: "http://127.0.0.1:11434/v1"
            }
        }
        var defaultModel: String {
            switch self {
            case .anthropic: "claude-opus-5-5"
            case .openAICompatible: "gpt-5.5"
            case .ollama: "qwen3-vl:4b-instruct"
            }
        }
        var needsKey: Bool { self != .ollama }
        /// 钥匙串里存 API key 用的名字
        var keychainAccount: String {
            switch self {
            case .anthropic: "anthropic"
            case .openAICompatible: "openai-compatible"
            case .ollama: "ollama"
            }
        }
    }

    var provider: Provider = .anthropic
    var baseURL = Provider.anthropic.defaultBaseURL
    var model = "claude-opus-5-5"
    /// 思考深度：low / medium / high；空字符串表示不传（有些模型不支持这个参数）
    var effort = "low"
}

struct AppSettings: Codable, Equatable {
    enum SpeechProvider: String, Codable, CaseIterable, Identifiable {
        case apple
        case soniox

        var id: String { rawValue }
        var label: String {
            switch self {
            case .apple: "Apple 本机识别（免费、不联网，不区分说话人）"
            case .soniox: "Soniox 云端识别（区分说话人，多语言自动识别）"
            }
        }
    }

    enum TranslationProvider: String, Codable, CaseIterable, Identifiable {
        case apple
        case llm

        var id: String { rawValue }
        var label: String {
            switch self {
            case .apple: "Apple 本机翻译（免费、不联网）"
            case .llm: "大模型翻译（用下面的大模型设置）"
            }
        }
    }

    // 语音识别
    var speechProvider: SpeechProvider = .apple
    /// 本机识别时，远端（对方）说的语言
    var remoteLocale = "en-US"
    /// 本机识别时，本地（会议室里）说的语言
    var localLocale = "en-US"
    /// 云端识别时提示可能出现的语言，逗号分隔
    var sonioxLanguageHints = "en,zh"
    var sonioxModel = "stt-rt-v5"

    // 声音来源
    var captureRemote = true
    var captureLocal = true
    /// 外放开会时麦克风也会收到对方的声音：本地出现和远端几乎一样的一句时去掉它
    var echoCancellation = true
    /// 本地用哪个麦克风（设备 UID）；空表示自动：系统默认，但避开 BlackHole 这类虚拟声卡
    var localInputDeviceUID = ""

    // 翻译
    var translationEnabled = true
    var translationProvider: TranslationProvider = .apple
    var targetLanguage = "zh-Hans"

    // 大模型与回复
    var llm = LLMConfig()
    /// 大模型翻译用的模型；空表示跟回复用同一个
    var translationModel = ""
    /// 回复里解释对方意思用的语言
    var explainLanguage = "中文"
    /// 建议回复用的语言；空表示跟对方说话的语言一致
    var replyLanguage = ""
    /// 对方说完一句问话时自动生成回复
    var autoReplyOnQuestion = false

    // 截屏回复
    /// 截屏后怎么读懂截图
    enum ScreenshotMode: String, Codable, CaseIterable, Identifiable {
        /// 图片和本机 OCR 文字一起交给回复模型（要能看图）
        case imageAndText
        /// 先让"看图模型"把截图整理成文字，再交给回复模型（看图模型可以是本机的，图片不出本机）
        case visionModel
        /// 只用本机 OCR 文字
        case textOnly

        var id: String { rawValue }
        var title: String {
            switch self {
            case .imageAndText: "图片直接给回复模型"
            case .visionModel: "先用看图模型读图"
            case .textOnly: "只用本机 OCR"
            }
        }
        var detail: String {
            switch self {
            case .imageAndText: "回复模型自己看截图，再配上本机 OCR 的文字核对人名数字。最准，图片会发给模型服务。"
            case .visionModel: "看图模型先把截图整理成文字，回复模型只看文字。看图模型选本机的，图片就不出这台 Mac。"
            case .textOnly: "系统自带的文字识别，免下载、不联网、0.3 秒。看不到版面，谁发的只能按左右位置猜。"
            }
        }
        var symbol: String {
            switch self {
            case .imageAndText: "photo.on.rectangle.angled"
            case .visionModel: "eye"
            case .textOnly: "text.viewfinder"
            }
        }
    }
    var screenshotMode: ScreenshotMode = .imageAndText

    /// 截屏回复默认截哪里
    enum CaptureTarget: String, Codable, CaseIterable, Identifiable {
        case frontWindow
        case screen
        case region

        var id: String { rawValue }
        var title: String {
            switch self {
            case .frontWindow: "最前面的 App"
            case .screen: "整个屏幕"
            case .region: "框选"
            }
        }
        var symbol: String {
            switch self {
            case .frontWindow: "macwindow"
            case .screen: "display"
            case .region: "rectangle.dashed"
            }
        }
    }
    var captureTarget: CaptureTarget = .frontWindow

    /// 看图用的模型（识别方式选"先用看图模型读图"时用）
    var vision = LLMConfig(provider: .ollama, baseURL: LLMConfig.Provider.ollama.defaultBaseURL,
                           model: LLMConfig.Provider.ollama.defaultModel, effort: "")
    /// 截屏回复生成好后，把第一个回复放进剪贴板
    var copyFirstScreenshotReply = true

    // 悬浮窗
    var theme: ThemeID = .obsidian
    /// 底色浓度：0 是只有玻璃（最透明），越大越深
    var overlayOpacity = 0.45
    var fontSize = 14.0
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "settings.v1"

    @Published var value: AppSettings {
        didSet { if persists { save() } }
    }
    private let persists: Bool

    /// - persists: false 时改了也不写回（预览、自测用，不碰真实设置）
    init(persists: Bool = true) {
        self.persists = persists
        value = UserDefaults.standard.data(forKey: Self.defaultsKey).flatMap(Self.decode) ?? AppSettings()
    }

    /// 存下来的设置盖在默认值上再解析：以后加了新设置项，老设置里没有的字段用默认值，其余照旧。
    static func decode(_ data: Data) -> AppSettings? {
        guard let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any],
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: merge(defaults, stored))
        else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: merged)
    }

    /// 在一份设置上盖一段 JSON（自测用：不写进真实设置）
    static func overriding(_ settings: AppSettings, with json: String) -> AppSettings {
        guard let base = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any],
              let top = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let merged = try? JSONSerialization.data(withJSONObject: merge(base, top)),
              let result = try? JSONDecoder().decode(AppSettings.self, from: merged)
        else { return settings }
        return result
    }

    private static func merge(_ base: [String: Any], _ top: [String: Any]) -> [String: Any] {
        var result = base
        for (key, value) in top {
            if let nested = value as? [String: Any], let baseNested = base[key] as? [String: Any] {
                result[key] = merge(baseNested, nested)
            } else {
                result[key] = value
            }
        }
        return result
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}

/// API key 存在钥匙串里，不写进设置文件。
enum Keychain {
    private static let service = "com.giomni.tyto"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    static func set(_ value: String, for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }
}
