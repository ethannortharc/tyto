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
    /// 回复里解释对方意思用的语言；空表示跟界面语言一致
    var explainLanguage = ""
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

    // 通用
    /// 在程序坞显示图标（关掉后只在菜单栏有图标）
    var showInDock = true
    /// 开始听时把程序坞和菜单栏里的 Tyto 图标藏起来（整屏共享时对方看得到程序坞和菜单栏）
    var hideIconsWhileListening = false

    // 设置窗口
    var iconStyle: IconStyle = .graphite

    // 悬浮窗
    var theme: ThemeID = .graphite
    /// 字色：自动按悬浮窗后面画面的明暗选白字或黑字，也可以固定
    var overlayTextColor: OverlayTextColor = .auto
    var transcriptStyle: TranscriptStyle = .avatar
    /// 回复面板（悬浮窗旁边一列）开着没有；生成新回复时自动打开
    var showReplyPanel = false
    /// 底色浓度：0 是完全透明（连玻璃都没有），往右先出现玻璃，再加深底色
    var overlayOpacity = 0.45
    var fontSize = 14.0
    /// 悬浮窗的大小：完整、字幕条、按钮条
    var overlayLayout: OverlayLayout = .full
    /// 字幕条显示几行（拖字幕条的下边改）
    var captionLines = 2

    // 提词器
    var showPrompter = false
    /// 正在看的材料（文件路径）；空表示没有
    var prompterPath = ""
    /// 最近用过的材料，最新的在前
    var prompterRecent: [String] = []
    var prompterFontSize = 17.0
    /// 跟读：我照着稿子说时，滚到说到的那一段
    var prompterFollow = true
    /// 对方提到稿子里的某一节时提示跳过去
    var prompterHints = true
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
        // 加界面语言之前就在用的人，界面一直是中文：保持中文，不因为系统是英文就突然换掉（新用户才跟随系统）
        if stored["language"] == nil { stored["language"] = AppLanguage.zh.rawValue }
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
/// 钥匙串条目只信任创建它的那份 App 的签名：0.4 以前用开发版签名存的 key，正式版去读时系统会弹框问，
/// 正式版也改不了、删不掉那条旧的（以前改 key 会悄悄存不进去）。所以现在存在新的一条（service 末尾带 .keys），
/// 旧条目第一次读到就搬过来；在设置里改过或清空过的账户，不再去读旧条目。
enum Keychain {
    private static let service = "com.giomni.tyto.keys"
    private static let legacyService = "com.giomni.tyto"
    /// 已经搬过或改过的账户（存在 defaults 里）：不再读旧条目
    private static let settledDefaultsKey = "keychainSettledAccounts"
    /// 这次运行里已经去读过旧条目的账户：没读到（你点了拒绝）也不再问，免得一直弹框
    nonisolated(unsafe) private static var askedLegacy: Set<String> = []
    private static let lock = NSLock()

    static func get(_ account: String) -> String? {
        if let value = read(service, account) { return value }
        guard shouldAskLegacy(account), let value = read(legacyService, account) else { return nil }
        if write(value, service, account) == errSecSuccess { settle(account) }
        return value
    }

    /// 存 key（空的就删掉）。返回出错信息，nil 表示存好了
    @discardableResult
    static func set(_ value: String, for account: String) -> String? {
        settle(account)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let status = trimmed.isEmpty ? delete(service, account) : write(trimmed, service, account)
        guard status != errSecSuccess, status != errSecItemNotFound else { return nil }
        let reason = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        RunLog.write("钥匙串存不进 \(account)：\(reason)")
        return reason
    }

    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static func read(_ service: String, _ account: String) -> String? {
        var request = query(service, account)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return nil }
        return text
    }

    /// 有就改、没有就建（不先删：删别的签名建的条目会失败）
    private static func write(_ value: String, _ service: String, _ account: String) -> OSStatus {
        let data = Data(value.utf8)
        let status = SecItemUpdate(query(service, account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        guard status == errSecItemNotFound else { return status }
        var item = query(service, account)
        item[kSecValueData as String] = data
        return SecItemAdd(item as CFDictionary, nil)
    }

    private static func delete(_ service: String, _ account: String) -> OSStatus {
        SecItemDelete(query(service, account) as CFDictionary)
    }

    private static func shouldAskLegacy(_ account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let settled = UserDefaults.standard.stringArray(forKey: settledDefaultsKey) ?? []
        guard !settled.contains(account), !askedLegacy.contains(account) else { return false }
        askedLegacy.insert(account)
        return true
    }

    private static func settle(_ account: String) {
        lock.lock()
        defer { lock.unlock() }
        var settled = UserDefaults.standard.stringArray(forKey: settledDefaultsKey) ?? []
        guard !settled.contains(account) else { return }
        settled.append(account)
        UserDefaults.standard.set(settled, forKey: settledDefaultsKey)
    }
}

/// 设置窗口侧栏的图标块：统一石墨色，或每页一个低饱和的颜色
enum IconStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case graphite
    case muted

    var id: String { rawValue }
    var label: String {
        switch self {
        case .graphite: tr("石墨", "Graphite")
        case .muted: tr("彩色", "Color")
        }
    }
}

/// 悬浮窗的字色。黑字时玻璃和底色也换成浅色
enum OverlayTextColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto
    case white
    case black

    var id: String { rawValue }
    var label: String {
        switch self {
        case .auto: tr("自动", "Auto")
        case .white: tr("白字", "White")
        case .black: tr("黑字", "Black")
        }
    }
}

/// 悬浮窗的三种大小
enum OverlayLayout: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 顶部按钮、字幕列表、底部回复按钮
    case full
    /// 只有最近一两行字幕（打开译文时下面一行是译文）
    case captions
    /// 只有一行按钮（截屏回复、回复、面板开关）
    case buttons

    var id: String { rawValue }
    var label: String {
        switch self {
        case .full: tr("完整", "Full")
        case .captions: tr("字幕条", "Caption Bar")
        case .buttons: tr("按钮条", "Button Bar")
        }
    }
    var symbol: String {
        switch self {
        case .full: "rectangle.portrait"
        case .captions: "captions.bubble"
        case .buttons: "ellipsis.rectangle"
        }
    }
    var detail: String {
        switch self {
        case .full: tr("字幕列表、选句回复、全部按钮", "Transcript list, reply to selected lines, all buttons")
        case .captions: tr("只显示最近的一两行字幕，拖下边改行数", "Only the latest line or two; drag the bottom edge to change")
        case .buttons: tr("只留一行按钮，截屏回复用", "Just a row of buttons, for screenshot replies")
        }
    }
    /// ⌃⌥M 按这个顺序换
    var next: OverlayLayout {
        let all = Self.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// 字幕每一行的样式
enum TranscriptStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    /// 说话人头像 + 名字，正文和名字对齐
    case avatar
    /// 左边一条说话人颜色的细线
    case bar

    var id: String { rawValue }
    var label: String {
        switch self {
        case .avatar: tr("头像", "Avatar")
        case .bar: tr("细线", "Line")
        }
    }
}
