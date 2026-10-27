import Foundation

/// 识别引擎送出来的事件。
struct SpeechEvent: Sendable {
    enum Kind: Sendable {
        /// 还在变的文字：整段替换当前未确定的部分
        case partial
        /// 确定下来的一段文字：接到已确定的部分后面
        case final
        /// 一句话说完了（云端识别的断句信号）
        case endOfUtterance
        case error
    }

    var kind: Kind
    var text = ""
    var speaker: Int?
    var language: String?
}

/// 识别引擎：送进 16kHz 单声道 Float32 音频，送出识别事件。
protocol SpeechEngine: AnyObject, Sendable {
    var events: AsyncStream<SpeechEvent> { get }
    func start() async throws
    func append(_ samples: [Float])
    func stop() async
}

/// 按设置建识别引擎（app 和自测共用）
enum SpeechEngines {
    static func make(for channel: Channel, settings: AppSettings) throws -> SpeechEngine {
        let hints = settings.speechLanguageHints.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        switch settings.speechMethod {
        case .apple:
            return AppleSpeechEngine(locale: channel == .remote ? settings.remoteLocale : settings.localLocale)
        case .streaming:
            let resolved = try settings.resolve(settings.speechSlot, for: tr("语音识别", "speech recognition"))
            return try streaming(resolved.provider, model: resolved.model, languageHints: hints)
        case .transcription, .audioModel:
            let resolved = try settings.resolve(settings.speechSlot, for: tr("语音识别", "speech recognition"))
            let provider = resolved.provider
            guard provider.kind == .openAICompatible || provider.kind == .ollama,
                  let url = URL(string: provider.baseURL.trimmingCharacters(in: .whitespaces)) else {
                throw TytoError.server(tr("「\(provider.name)」不能用来转写，请选 OpenAI 兼容的服务商", "“\(provider.name)” can't be used for transcription; pick an OpenAI-compatible provider"))
            }
            let backend: ChunkedSpeechEngine.Backend = settings.speechMethod == .transcription
                ? .transcription(baseURL: url, apiKey: provider.key, model: resolved.model,
                                 language: hints.count == 1 ? hints[0] : nil)
                : .audioChat(baseURL: url, apiKey: provider.key, model: resolved.model,
                             languages: hints.isEmpty ? "自动判断" : hints.joined(separator: "、"))
            return ChunkedSpeechEngine(backend: backend)
        }
    }

    /// 实时识别服务的引擎（对比识别的自测也用它）
    static func streaming(_ provider: Provider, model: String, languageHints hints: [String]) throws -> SpeechEngine {
        let key = provider.key ?? ""
        switch provider.kind {
        case .soniox:
            return SonioxSpeechEngine(apiKey: key, baseURL: provider.baseURL, model: model, languageHints: hints)
        case .deepgram:
            return DeepgramSpeechEngine(apiKey: key, baseURL: provider.baseURL, model: model,
                                        language: hints.count == 1 ? hints[0] : "multi")
        case .assemblyai:
            return AssemblyAISpeechEngine(apiKey: key, baseURL: provider.baseURL, model: model, languages: hints)
        case .elevenlabs:
            return ElevenLabsSpeechEngine(apiKey: key, baseURL: provider.baseURL, model: model,
                                          language: hints.count == 1 ? hints[0] : nil)
        default:
            throw TytoError.server(tr("「\(provider.name)」不是实时识别服务，请选 Soniox、AssemblyAI、ElevenLabs 或 Deepgram", "“\(provider.name)” isn't a real-time recognition service; pick Soniox, AssemblyAI, ElevenLabs or Deepgram"))
        }
    }
}
