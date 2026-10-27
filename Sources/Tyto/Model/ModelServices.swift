import Foundation
import SwiftUI

/// 服务商的接口类型：决定怎么调用
enum ProviderKind: String, Codable, Sendable {
    /// Claude Messages API
    case anthropic
    /// OpenAI 的 chat/completions、models、audio/transcriptions；绝大多数服务商都兼容
    case openAICompatible
    /// 本机 Ollama：OpenAI 兼容接口 + 自己的模型管理接口
    case ollama
    /// Soniox 实时语音识别（WebSocket）
    case soniox
    /// Deepgram 实时语音识别（WebSocket）
    case deepgram
}

/// 一个配置好的服务商。key 存在钥匙串里（账户名 provider.<id>）。
struct Provider: Codable, Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: ProviderKind
    var baseURL: String
    /// 从哪个模板建的（决定图标和说明）
    var template: String

    var info: ProviderTemplate { ProviderTemplate.find(template) ?? ProviderTemplate.custom }
    var needsKey: Bool { info.needsKey }

    var key: String? {
        Keychain.get("provider.\(id)")
            ?? info.legacyKeyAccount.flatMap(Keychain.get)
            ?? ProcessInfo.processInfo.environment["TYTO_LLM_API_KEY"]
    }

    func setKey(_ value: String) { Keychain.set(value, for: "provider.\(id)") }
}

/// 能做什么
enum Capability: Sendable {
    /// 对话（回复、翻译）
    case chat
    /// 能看图（截屏）
    case vision
    /// 实时语音识别
    case streamingSpeech
    /// 语音转写接口（/audio/transcriptions）
    case transcription
    /// 能"听"音频的对话模型（chat 里带 input_audio）
    case audioChat
}

/// 内置的服务商模板：选一个，填上 key 就能用
struct ProviderTemplate: Identifiable, Sendable {
    let id: String
    let name: String
    let kind: ProviderKind
    let baseURL: String
    let symbol: String
    let colors: [Color]
    let note: String
    let capabilities: Set<Capability>
    var needsKey = true
    /// 在哪里拿 key
    var keyPage: String?
    /// 各用途的推荐模型（列表读不到时也能直接选）
    var suggested: [Capability: [String]] = [:]
    /// 老版本存 key 用的钥匙串账户名（兼容旧设置）
    var legacyKeyAccount: String?

    static func find(_ id: String) -> ProviderTemplate? { all.first { $0.id == id } }

    static let custom = ProviderTemplate(
        id: "custom", name: "自定义接口", kind: .openAICompatible, baseURL: "https://", symbol: "point.3.connected.trianglepath.dotted",
        colors: [Color(red: 0.55, green: 0.58, blue: 0.65), Color(red: 0.35, green: 0.37, blue: 0.45)],
        note: "任何 OpenAI 兼容的接口：公司内部网关、自建的 Whisper 服务……",
        capabilities: [.chat, .vision, .transcription, .audioChat])

    static let all: [ProviderTemplate] = [
        ProviderTemplate(
            id: "anthropic", name: "Anthropic", kind: .anthropic, baseURL: "https://api.anthropic.com", symbol: "sparkle",
            colors: [Color(red: 0.86, green: 0.52, blue: 0.36), Color(red: 0.72, green: 0.38, blue: 0.24)],
            note: "Claude 系列，回复和看图都强", capabilities: [.chat, .vision],
            keyPage: "https://console.anthropic.com/settings/keys",
            suggested: [.chat: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
                        .vision: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"]],
            legacyKeyAccount: "anthropic"),
        ProviderTemplate(
            id: "openai", name: "OpenAI", kind: .openAICompatible, baseURL: "https://api.openai.com/v1", symbol: "circle.hexagongrid.fill",
            colors: [Color(red: 0.25, green: 0.70, blue: 0.58), Color(red: 0.10, green: 0.50, blue: 0.42)],
            note: "GPT 系列；语音转写 gpt-4o-transcribe、whisper-1", capabilities: [.chat, .vision, .transcription, .audioChat],
            keyPage: "https://platform.openai.com/api-keys",
            suggested: [.transcription: ["gpt-4o-transcribe", "gpt-4o-mini-transcribe", "whisper-1"]],
            legacyKeyAccount: "openai-compatible"),
        ProviderTemplate(
            id: "openrouter", name: "OpenRouter", kind: .openAICompatible, baseURL: "https://openrouter.ai/api/v1", symbol: "arrow.triangle.branch",
            colors: [Color(red: 0.42, green: 0.45, blue: 0.95), Color(red: 0.28, green: 0.25, blue: 0.80)],
            note: "一个 key 用几百个模型；能听音频的模型（如 Gemini）也可以拿来做语音识别",
            capabilities: [.chat, .vision, .audioChat], keyPage: "https://openrouter.ai/keys",
            suggested: [.audioChat: ["google/gemini-2.5-flash"]]),
        ProviderTemplate(
            id: "gemini", name: "Google Gemini", kind: .openAICompatible,
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", symbol: "diamond.fill",
            colors: [Color(red: 0.36, green: 0.58, blue: 1.0), Color(red: 0.55, green: 0.40, blue: 0.95)],
            note: "看图、听音频都强，Flash 很便宜", capabilities: [.chat, .vision, .audioChat],
            keyPage: "https://aistudio.google.com/apikey",
            suggested: [.audioChat: ["gemini-2.5-flash"], .vision: ["gemini-2.5-flash"]]),
        ProviderTemplate(
            id: "deepseek", name: "DeepSeek", kind: .openAICompatible, baseURL: "https://api.deepseek.com/v1", symbol: "fish.fill",
            colors: [Color(red: 0.30, green: 0.50, blue: 0.98), Color(red: 0.18, green: 0.32, blue: 0.85)],
            note: "便宜，中文好；不能看图", capabilities: [.chat], keyPage: "https://platform.deepseek.com/api_keys",
            suggested: [.chat: ["deepseek-chat"]]),
        ProviderTemplate(
            id: "dashscope", name: "通义千问", kind: .openAICompatible,
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1", symbol: "cloud.fill",
            colors: [Color(red: 0.45, green: 0.38, blue: 0.95), Color(red: 0.30, green: 0.22, blue: 0.80)],
            note: "阿里云百炼；Qwen-VL 看图、中文识字强", capabilities: [.chat, .vision],
            keyPage: "https://bailian.console.aliyun.com/", suggested: [.vision: ["qwen-vl-max", "qwen-vl-plus"]]),
        ProviderTemplate(
            id: "siliconflow", name: "硅基流动", kind: .openAICompatible, baseURL: "https://api.siliconflow.cn/v1",
            symbol: "bolt.horizontal.fill",
            colors: [Color(red: 0.55, green: 0.35, blue: 0.95), Color(red: 0.38, green: 0.20, blue: 0.80)],
            note: "国内访问快，很多开源模型；语音转写 SenseVoice", capabilities: [.chat, .vision, .transcription],
            keyPage: "https://cloud.siliconflow.cn/account/ak",
            suggested: [.transcription: ["FunAudioLLM/SenseVoiceSmall"]]),
        ProviderTemplate(
            id: "groq", name: "Groq", kind: .openAICompatible, baseURL: "https://api.groq.com/openai/v1", symbol: "hare.fill",
            colors: [Color(red: 0.95, green: 0.42, blue: 0.30), Color(red: 0.80, green: 0.25, blue: 0.20)],
            note: "极快；Whisper 语音转写便宜", capabilities: [.chat, .transcription], keyPage: "https://console.groq.com/keys",
            suggested: [.transcription: ["whisper-large-v3-turbo", "whisper-large-v3"]]),
        ProviderTemplate(
            id: "ollama", name: "Ollama 本机", kind: .ollama, baseURL: "http://127.0.0.1:11434/v1", symbol: "desktopcomputer",
            colors: [Color(red: 0.30, green: 0.30, blue: 0.34), Color(red: 0.10, green: 0.10, blue: 0.12)],
            note: "在这台 Mac 上跑开源模型，数据不出本机", capabilities: [.chat, .vision], needsKey: false,
            suggested: [.vision: Ollama.recommended.map(\.id)]),
        ProviderTemplate(
            id: "lmstudio", name: "LM Studio 本机", kind: .openAICompatible, baseURL: "http://127.0.0.1:1234/v1", symbol: "laptopcomputer",
            colors: [Color(red: 0.40, green: 0.42, blue: 0.95), Color(red: 0.20, green: 0.22, blue: 0.70)],
            note: "本机跑 MLX 模型（Apple 芯片上快）", capabilities: [.chat, .vision], needsKey: false),
        ProviderTemplate(
            id: "soniox", name: "Soniox", kind: .soniox, baseURL: "wss://stt-rt.soniox.com/transcribe-websocket", symbol: "waveform.badge.mic",
            colors: [Color(red: 1.0, green: 0.62, blue: 0.30), Color(red: 0.92, green: 0.40, blue: 0.18)],
            note: "实时语音识别，分得出说话人，60 多种语言，约 $0.12/小时", capabilities: [.streamingSpeech],
            keyPage: "https://console.soniox.com/", suggested: [.streamingSpeech: ["stt-rt-v5"]], legacyKeyAccount: "soniox"),
        ProviderTemplate(
            id: "deepgram", name: "Deepgram", kind: .deepgram, baseURL: "wss://api.deepgram.com/v1/listen", symbol: "waveform.path",
            colors: [Color(red: 0.20, green: 0.85, blue: 0.70), Color(red: 0.08, green: 0.60, blue: 0.55)],
            note: "实时语音识别，延迟低，分得出说话人；中文用 nova-2", capabilities: [.streamingSpeech],
            keyPage: "https://console.deepgram.com/", suggested: [.streamingSpeech: ["nova-3", "nova-2"]]),
        custom,
    ]
}

/// 某个用途用哪个服务商的哪个模型
struct ModelSlot: Codable, Equatable, Sendable {
    var providerID: String
    var model: String
    /// 思考深度（只有回复用）：low / medium / high；空表示不传
    var effort = ""
}

/// 语音识别的方式
enum SpeechMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case apple
    /// Soniox / Deepgram 这类实时识别
    case streaming
    /// OpenAI 兼容的转写接口：按停顿切成一句一句上传（OpenAI、Groq、硅基流动、自建 Whisper……）
    case transcription
    /// 让能听音频的模型转写（OpenRouter、Gemini……）
    case audioModel

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apple: "Apple 本机"
        case .streaming: "实时识别服务"
        case .transcription: "语音转写接口"
        case .audioModel: "让模型听写"
        }
    }
    var detail: String {
        switch self {
        case .apple: "免费、不联网。一路只认一种语言，不区分说话人。"
        case .streaming: "Soniox、Deepgram：边说边出字，分得出说话人，最适合开会。"
        case .transcription: "OpenAI、Groq、硅基流动或自建 Whisper：说完一句传一句，比实时慢一两秒。"
        case .audioModel: "OpenRouter、Gemini 等能听音频的模型：说完一句传一句，多语言混说也行。"
        }
    }
    var symbol: String {
        switch self {
        case .apple: "apple.logo"
        case .streaming: "dot.radiowaves.left.and.right"
        case .transcription: "text.bubble"
        case .audioModel: "ear"
        }
    }
    /// 这种方式要服务商有什么能力
    var capability: Capability? {
        switch self {
        case .apple: nil
        case .streaming: .streamingSpeech
        case .transcription: .transcription
        case .audioModel: .audioChat
        }
    }
}

/// 一个用途解析出来的：服务商 + 模型
struct ResolvedModel: Sendable {
    let provider: Provider
    let model: String
    let effort: String
}

extension AppSettings {
    static let defaultProviders: [Provider] = ["anthropic", "ollama"].compactMap { id in
        ProviderTemplate.find(id).map { Provider(id: $0.id, name: $0.name, kind: $0.kind, baseURL: $0.baseURL, template: $0.id) }
    }

    func provider(_ id: String) -> Provider? { providers.first { $0.id == id } }

    /// 找出某个用途的服务商和模型；没选或服务商被删了就报一句看得懂的错
    func resolve(_ slot: ModelSlot, for use: String) throws -> ResolvedModel {
        guard let provider = provider(slot.providerID) else {
            throw TytoError.server("\(use)还没选服务商（会话与设置 → 模型与服务）")
        }
        guard !slot.model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw TytoError.server("\(use)还没选模型（会话与设置 → 模型与服务）")
        }
        if provider.needsKey, provider.key == nil { throw TytoError.missingAPIKey(provider.name) }
        return ResolvedModel(provider: provider, model: slot.model.trimmingCharacters(in: .whitespaces), effort: slot.effort)
    }

    /// 翻译用的模型：没单独选就跟回复一样
    var effectiveTranslationSlot: ModelSlot {
        translationSlot.providerID.isEmpty ? replySlot : translationSlot
    }

    /// 能做某件事的服务商
    func providers(for capability: Capability) -> [Provider] {
        providers.filter { $0.info.capabilities.contains(capability) }
    }
}
