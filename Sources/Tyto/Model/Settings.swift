import Foundation
import Security
import SwiftUI

/// 大模型的连接设置。回复建议用它，选了"大模型翻译"时翻译也用它。
struct LLMConfig: Codable, Equatable, Sendable {
    enum Provider: String, Codable, CaseIterable, Identifiable, Sendable {
        case anthropic
        case openAICompatible

        var id: String { rawValue }
        var label: String {
            switch self {
            case .anthropic: "Anthropic（Claude）"
            case .openAICompatible: "OpenAI 兼容接口（OpenAI、DeepSeek、通义、Gemini、Ollama…）"
            }
        }
        var defaultBaseURL: String {
            switch self {
            case .anthropic: "https://api.anthropic.com"
            case .openAICompatible: "https://api.openai.com/v1"
            }
        }
        /// 钥匙串里存 API key 用的名字
        var keychainAccount: String {
            switch self {
            case .anthropic: "anthropic"
            case .openAICompatible: "openai-compatible"
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

    // 悬浮窗
    var overlayOpacity = 0.82
    var fontSize = 14.0
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "settings.v1"

    @Published var value: AppSettings {
        didSet { save() }
    }

    init() {
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
