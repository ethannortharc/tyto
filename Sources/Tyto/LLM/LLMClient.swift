import Foundation

/// 大模型：给系统提示和用户消息（可以带图片），流式返回文字。
protocol LLMClient: Sendable {
    /// - images: PNG 图片，放在文字前面
    func stream(system: String, user: String, images: [Data], maxTokens: Int) -> AsyncThrowingStream<String, Error>
}

extension LLMClient {
    func stream(system: String, user: String, maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        stream(system: system, user: user, images: [], maxTokens: maxTokens)
    }
}

enum LLMFactory {
    static func make(_ resolved: ResolvedModel) throws -> LLMClient {
        let provider = resolved.provider
        let base = provider.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base.isEmpty ? provider.info.baseURL : base) else {
            throw TytoError.server(tr("「\(provider.name)」的接口地址不对：\(provider.baseURL)", "Invalid endpoint address for “\(provider.name)”: \(provider.baseURL)"))
        }
        switch provider.kind {
        case .anthropic:
            guard let key = provider.key else { throw TytoError.missingAPIKey(provider.name) }
            return AnthropicClient(baseURL: baseURL, apiKey: key, model: resolved.model, effort: resolved.effort)
        case .openAICompatible:
            // 本机的 LM Studio、自建服务可以不用 key
            return OpenAICompatibleClient(baseURL: baseURL, apiKey: provider.key, model: resolved.model, effort: resolved.effort)
        case .ollama:
            // Ollama 也提供 OpenAI 兼容接口（/v1/chat/completions），本机不用 key
            return OpenAICompatibleClient(baseURL: baseURL, apiKey: nil, model: resolved.model, effort: "")
        case .soniox, .deepgram:
            throw TytoError.server(tr("「\(provider.name)」是语音识别服务，不能用来回复", "“\(provider.name)” is a speech recognition service and can't be used for replies"))
        }
    }

    /// 某个用途的模型
    static func make(_ slot: ModelSlot, for use: String, in settings: AppSettings) throws -> LLMClient {
        try make(settings.resolve(slot, for: use))
    }
}

/// Claude Messages API（直接用 HTTP，Swift 没有官方 SDK）。
struct AnthropicClient: LLMClient {
    let baseURL: URL
    let apiKey: String
    let model: String
    let effort: String

    /// 这些模型在 Anthropic 自己的接口上支持服务端兜底：模型拒答时自动换一个模型重答
    private static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-fable-5-1", "claude-sonnet-5-5"]

    func stream(system: String, user: String, images: [Data], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        var request = URLRequest(url: baseURL.appending(path: "v1/messages"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": [["role": "user", "content": Self.content(user, images: images)]],
        ]
        if !system.isEmpty { body["system"] = system }
        if !effort.isEmpty { body["output_config"] = ["effort": effort] }
        if Self.fallbackModels.contains(model), baseURL.host() == "api.anthropic.com" {
            body["fallbacks"] = "default"
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return SSE.stream(request, service: "Claude") { event in
            switch event["type"] as? String {
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any]
                return delta?["type"] as? String == "text_delta" ? .text(delta?["text"] as? String ?? "") : .skip
            case "message_delta":
                let delta = event["delta"] as? [String: Any]
                return delta?["stop_reason"] as? String == "refusal" ? .fail(tr("模型拒绝回答这一条", "The model declined to answer this one")) : .skip
            case "error":
                let error = event["error"] as? [String: Any]
                return .fail(tr("Claude 出错：\(error?["message"] as? String ?? "未知错误")", "Claude error: \(error?["message"] as? String ?? "unknown error")"))
            case "message_stop":
                return .done
            default:
                return .skip
            }
        }
    }
}

extension AnthropicClient {
    /// 图片在前、文字在后
    static func content(_ text: String, images: [Data]) -> Any {
        guard !images.isEmpty else { return text }
        var blocks: [[String: Any]] = images.map { image in
            ["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": image.base64EncodedString()]]
        }
        blocks.append(["type": "text", "text": text])
        return blocks
    }
}

/// OpenAI 的 Chat Completions 接口；DeepSeek、通义、Gemini、OpenRouter、Ollama 等都兼容这个格式。
struct OpenAICompatibleClient: LLMClient {
    let baseURL: URL
    let apiKey: String?
    let model: String
    let effort: String

    func stream(system: String, user: String, images: [Data], maxTokens: Int) -> AsyncThrowingStream<String, Error> {
        var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        var messages: [[String: Any]] = []
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        messages.append(["role": "user", "content": Self.content(user, images: images)])
        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages,
        ]
        // 只有 OpenAI 自己认 reasoning_effort，别家可能报错
        if !effort.isEmpty, baseURL.host()?.hasSuffix("openai.com") == true { body["reasoning_effort"] = effort }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        return SSE.stream(request, service: tr("大模型", "LLM"), done: "[DONE]") { event in
            let choices = event["choices"] as? [[String: Any]]
            let delta = choices?.first?["delta"] as? [String: Any]
            if let text = delta?["content"] as? String { return .text(text) }
            if let error = event["error"] as? [String: Any] { return .fail(tr("大模型出错：\(error["message"] as? String ?? "")", "LLM error: \(error["message"] as? String ?? "")")) }
            return .skip
        }
    }
}

extension OpenAICompatibleClient {
    static func content(_ text: String, images: [Data]) -> Any {
        guard !images.isEmpty else { return text }
        var parts: [[String: Any]] = [["type": "text", "text": text]]
        for image in images {
            parts.append(["type": "image_url", "image_url": ["url": "data:image/png;base64,\(image.base64EncodedString())"]])
        }
        return parts
    }
}

/// 读 Server-Sent Events：一行一个 "data: {json}"。
enum SSE {
    enum Step {
        case text(String)
        case skip
        case done
        case fail(String)
    }

    static func stream(_ request: URLRequest, service: String, done: String? = nil,
                       parse: @escaping @Sendable ([String: Any]) -> Step) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var text = ""
                        for try await line in bytes.lines { text += line }
                        throw TytoError.server(tr("\(service)接口返回 \(http.statusCode)：\(errorMessage(text))", "\(service) API returned \(http.statusCode): \(errorMessage(text))"))
                    }
                    lines: for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if let done, payload == done { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        switch parse(event) {
                        case .text(let text): continuation.yield(text)
                        case .skip: continue
                        case .done: break lines
                        case .fail(let message): throw TytoError.server(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func errorMessage(_ body: String) -> String {
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return String(body.prefix(300))
    }
}

extension LLMClient {
    /// 不需要流式时，把结果拼成一段
    func complete(system: String, user: String, images: [Data] = [], maxTokens: Int) async throws -> String {
        var output = ""
        for try await chunk in stream(system: system, user: user, images: images, maxTokens: maxTokens) { output += chunk }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
