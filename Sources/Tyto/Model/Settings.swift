import Foundation
import Security
import SwiftUI

struct AppSettings: Codable, Equatable {
    enum TranslationProvider: String, Codable, CaseIterable, Identifiable {
        case apple
        case llm

        var id: String { rawValue }
        var label: String {
            switch self {
            case .apple: tr("Apple 本机翻译（免费、不联网）", "Apple on-device (free, offline)")
            case .llm: tr("大模型翻译（用下面的大模型设置）", "LLM (uses the model set below)")
            }
        }
    }

    // 服务商和各个用途的模型（字段名都是新的，和老版本的 llm / vision / translationModel 不冲突）
    var providers: [Provider] = AppSettings.defaultProviders
    var replySlot = ModelSlot(providerID: "anthropic", model: "claude-opus-5-5", effort: "low")
    var visionSlot = ModelSlot(providerID: "ollama", model: Ollama.recommended[0].id)
    /// 大模型翻译用的；providerID 为空表示跟回复用同一个
    var translationSlot = ModelSlot(providerID: "", model: "")

    // 语音识别
    var speechMethod: SpeechMethod = .apple
    /// 云端识别用的服务商和模型（实时识别、转写接口、听写模型）
    var speechSlot = ModelSlot(providerID: "", model: "")
    /// 本机识别时，远端（对方）说的语言
    var remoteLocale = "en-US"
    /// 本机识别时，本地（会议室里）说的语言
    var localLocale = "en-US"
    /// 云端识别时可能出现的语言，逗号分隔
    var speechLanguageHints = "en,zh"

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

    // 回复
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
            case .imageAndText: tr("图片直接给回复模型", "Image to Reply Model")
            case .visionModel: tr("先用看图模型读图", "Vision Model First")
            case .textOnly: tr("只用本机 OCR", "On-Device OCR Only")
            }
        }
        var detail: String {
            switch self {
            case .imageAndText: tr("回复模型自己看截图，再配上本机 OCR 的文字核对人名数字。最准，图片会发给模型服务。", "The reply model reads the screenshot itself, and on-device OCR text is used to check names and numbers. Most accurate; the image is sent to the model service.")
            case .visionModel: tr("看图模型先把截图整理成文字，回复模型只看文字。看图模型选本机的，图片就不出这台 Mac。", "A vision model turns the screenshot into text, and the reply model only sees the text. Pick an on-device vision model and the image never leaves this Mac.")
            case .textOnly: tr("系统自带的文字识别，免下载、不联网、0.3 秒。看不到版面，谁发的只能按左右位置猜。", "Built-in text recognition: no download, offline, about 0.3 s. It can't see the layout, so who said what is guessed from left/right position.")
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
            case .frontWindow: tr("最前面的 App", "Frontmost App")
            case .screen: tr("整个屏幕", "Entire Screen")
            case .region: tr("框选", "Select Area")
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

    /// 截屏回复生成好后，把第一个回复放进剪贴板
    var copyFirstScreenshotReply = true

    // 界面语言
    var language: AppLanguage = .system

    // 悬浮窗
    var theme: ThemeID = .obsidian
    /// 底色浓度：0 是完全透明（连玻璃都没有），往右先出现玻璃，再加深底色
    var overlayOpacity = 0.45
    var fontSize = 14.0
}

@MainActor
final class SettingsStore: ObservableObject {
    private static let defaultsKey = "settings.v1"

    @Published var value: AppSettings {
        didSet {
            if value.language != oldValue.language { L10n.set(value.language) }
            if persists { save() }
        }
    }
    private let persists: Bool

    /// - persists: false 时改了也不写回（预览、自测用，不碰真实设置）
    init(persists: Bool = true) {
        self.persists = persists
        value = UserDefaults.standard.data(forKey: Self.defaultsKey).flatMap(Self.decode) ?? AppSettings()
        L10n.set(value.language)
    }

    /// 存下来的设置盖在默认值上再解析：以后加了新设置项，老设置里没有的字段用默认值，其余照旧。
    static func decode(_ data: Data) -> AppSettings? {
        guard let defaults = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any],
              var stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        if stored["providers"] == nil { stored = migrate(stored) }
        guard let merged = try? JSONSerialization.data(withJSONObject: merge(defaults, stored)) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: merged)
    }

    /// 老版本（每个用途各填一套地址）换成"服务商 + 用途"
    private static func migrate(_ old: [String: Any]) -> [String: Any] {
        var result = old
        let templateFor = ["anthropic": "anthropic", "openAICompatible": "openai", "ollama": "ollama"]
        var providers: [[String: Any]] = []
        func slot(from config: [String: Any]?) -> [String: Any]? {
            guard let config, let kind = config["provider"] as? String, let template = templateFor[kind],
                  let info = ProviderTemplate.find(template) else { return nil }
            if !providers.contains(where: { $0["id"] as? String == template }) {
                providers.append(["id": template, "name": info.name, "kind": info.kind.rawValue,
                                  "baseURL": config["baseURL"] as? String ?? info.baseURL, "template": template])
            }
            return ["providerID": template, "model": config["model"] as? String ?? "", "effort": config["effort"] as? String ?? ""]
        }
        if let reply = slot(from: old["llm"] as? [String: Any]) { result["replySlot"] = reply }
        if let vision = slot(from: old["vision"] as? [String: Any]) { result["visionSlot"] = vision }
        if let model = old["translationModel"] as? String, !model.isEmpty, var reply = result["replySlot"] as? [String: Any] {
            reply["model"] = model
            result["translationSlot"] = reply
        }
        if old["speechProvider"] as? String == "soniox", let soniox = ProviderTemplate.find("soniox") {
            providers.append(["id": "soniox", "name": soniox.name, "kind": soniox.kind.rawValue, "baseURL": soniox.baseURL,
                              "template": "soniox"])
            result["speechMethod"] = SpeechMethod.streaming.rawValue
            result["speechSlot"] = ["providerID": "soniox", "model": old["sonioxModel"] as? String ?? "stt-rt-v5", "effort": ""]
        }
        if let hints = old["sonioxLanguageHints"] as? String { result["speechLanguageHints"] = hints }
        for id in ["anthropic", "ollama"] where !providers.contains(where: { $0["id"] as? String == id }) {
            if let info = ProviderTemplate.find(id) {
                providers.append(["id": id, "name": info.name, "kind": info.kind.rawValue, "baseURL": info.baseURL, "template": id])
            }
        }
        result["providers"] = providers
        return result
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
