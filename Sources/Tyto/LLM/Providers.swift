import Foundation

/// 从服务商那里读模型列表，设置里可以直接选，不用手敲模型名。
enum ModelList {
    static func fetch(_ config: LLMConfig) async throws -> [String] {
        let key = Keychain.get(config.provider.keychainAccount) ?? ProcessInfo.processInfo.environment["TYTO_LLM_API_KEY"]
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = URL(string: base.isEmpty ? config.provider.defaultBaseURL : base) else {
            throw TytoError.server("接口地址不对")
        }
        switch config.provider {
        case .anthropic:
            guard let key else { throw TytoError.missingAPIKey("Anthropic") }
            var request = URLRequest(url: baseURL.appending(path: "v1/models").appending(queryItems: [URLQueryItem(name: "limit", value: "100")]))
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
            return try await ids(request, list: "data", field: "id")
        case .openAICompatible:
            var request = URLRequest(url: baseURL.appending(path: "models"))
            if let key { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
            return try await ids(request, list: "data", field: "id")
        case .ollama:
            return try await Ollama.installed(host: Ollama.host(from: baseURL))
        }
    }

    private static func ids(_ request: URLRequest, list: String, field: String) async throws -> [String] {
        var request = request
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw TytoError.server("读模型列表失败（\(http.statusCode)）")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json[list] as? [[String: Any]] else { return [] }
        return items.compactMap { $0[field] as? String }.sorted()
    }
}

/// 本机的 Ollama：看有没有在跑、装了哪些模型、下载模型。
enum Ollama {
    static let defaultHost = URL(string: "http://127.0.0.1:11434")!

    /// 推荐的本机看图 / OCR 模型（大小来自 Ollama 模型库，2026-10）
    struct Recommended: Identifiable, Sendable {
        let id: String
        let name: String
        let size: String
        let note: String
        let symbol: String
    }

    static let recommended: [Recommended] = [
        Recommended(id: "qwen3-vl:4b-instruct", name: "Qwen3-VL 4B", size: "3.3 GB",
                    note: "推荐：中英文都认得准，看得懂聊天和邮件，M 系列芯片上几秒一张", symbol: "star.fill"),
        Recommended(id: "qwen3-vl:2b-instruct", name: "Qwen3-VL 2B", size: "1.9 GB",
                    note: "最省：占用最小，简单的聊天截图够用", symbol: "leaf.fill"),
        Recommended(id: "qwen3-vl:8b-instruct", name: "Qwen3-VL 8B", size: "6.2 GB",
                    note: "更准：长邮件、复杂版面更稳，内存 16 GB 以上", symbol: "sparkles"),
        Recommended(id: "deepseek-ocr:3b", name: "DeepSeek-OCR 3B", size: "6.7 GB",
                    note: "专门转文字：版面、表格还原得好，但不理解内容（要 Ollama 0.13 以上）", symbol: "doc.text.viewfinder"),
    ]

    static func host(from baseURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = baseURL.scheme ?? "http"
        components.host = baseURL.host() ?? "127.0.0.1"
        components.port = baseURL.port ?? 11434
        return components.url ?? defaultHost
    }

    /// 在跑就返回版本号
    static func version(host: URL = defaultHost) async -> String? {
        var request = URLRequest(url: host.appending(path: "api/version"))
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }

    static func installed(host: URL = defaultHost) async throws -> [String] {
        var request = URLRequest(url: host.appending(path: "api/tags"))
        request.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["name"] as? String }.sorted()
    }

    struct Progress: Sendable {
        let status: String
        let completed: Int64?
        let total: Int64?

        var fraction: Double? {
            guard let completed, let total, total > 0 else { return nil }
            return Double(completed) / Double(total)
        }
    }

    /// 下载模型，边下边报进度
    static func pull(_ model: String, host: URL = defaultHost) -> AsyncThrowingStream<Progress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: host.appending(path: "api/pull"))
                    request.httpMethod = "POST"
                    request.timeoutInterval = 3_600
                    request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])
                    let (bytes, _) = try await URLSession.shared.bytes(for: request)
                    for try await line in bytes.lines {
                        guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                        if let error = json["error"] as? String { throw TytoError.server("下载失败：\(error)") }
                        let progress = Progress(status: json["status"] as? String ?? "",
                                                completed: (json["completed"] as? NSNumber)?.int64Value,
                                                total: (json["total"] as? NSNumber)?.int64Value)
                        continuation.yield(progress)
                        if progress.status == "success" { break }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
