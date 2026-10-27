import Foundation
import NaturalLanguage
@preconcurrency import Translation

protocol Translator: Sendable {
    /// - source: 原文语言代码（如 "en"），不知道就传 nil，自动判断
    /// - target: 译文语言代码（如 "zh-Hans"）
    func translate(_ text: String, from source: String?, to target: String) async throws -> String
}

/// Apple 本机翻译。语言包要先下载（模型与服务 → 下载本机翻译语言），之后不联网。
final class AppleTranslator: Translator, @unchecked Sendable {
    private let lock = NSLock()
    private var sessions: [String: TranslationSession] = [:]

    func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        let sourceLanguage = Locale.Language(identifier: source ?? Languages.detect(text) ?? "en")
        let targetLanguage = Locale.Language(identifier: target)
        let key = "\(sourceLanguage.minimalIdentifier)→\(targetLanguage.minimalIdentifier)"
        let session = lock.withLock {
            if let existing = sessions[key] { return existing }
            let created = TranslationSession(installedSource: sourceLanguage, target: targetLanguage)
            sessions[key] = created
            return created
        }
        do {
            return try await session.translate(text).targetText
        } catch {
            lock.withLock { sessions[key] = nil }
            let status = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
            if status != .installed { throw TytoError.translationNotInstalled(key) }
            throw error
        }
    }
}

/// 用大模型翻译：更懂上下文和术语，要联网、要 API key。
struct LLMTranslator: Translator {
    let client: LLMClient

    func translate(_ text: String, from source: String?, to target: String) async throws -> String {
        let system = """
        你是会议同传。把用户发来的一段会议发言翻译成\(Languages.name(target))。
        只输出译文，不加解释、不加引号。人名、产品名、代码、数字保留原样。
        原文来自实时语音识别，可能有错字或断句不准，按上下文理解后再翻。
        """
        return try await client.complete(system: system, user: text, maxTokens: 2_000)
    }
}

enum Languages {
    /// 猜一段文字是什么语言，返回语言代码
    static func detect(_ text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    static func sameLanguage(_ a: String, _ b: String) -> Bool {
        Locale.Language(identifier: a).languageCode == Locale.Language(identifier: b).languageCode
    }

    /// 语言代码在当前界面语言下的名字，如 "en" → "英语" / "English"
    static func name(_ code: String) -> String {
        Locale(identifier: L10n.isEnglish ? "en" : "zh-Hans").localizedString(forIdentifier: code) ?? code
    }
}
