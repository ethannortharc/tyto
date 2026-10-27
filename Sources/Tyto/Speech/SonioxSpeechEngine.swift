import Foundation

/// Soniox 云端实时识别（WebSocket）。能区分说话人，多种语言混着说也能自动认出来。
/// 协议：连上后先发一条 JSON 配置，再连续发 16-bit PCM 音频，发一个空文本帧表示结束。
/// 每条响应里的 tokens：is_final 的是确定的文字，其余是还会变的尾巴；"<end>" 表示一句话说完。
final class SonioxSpeechEngine: SpeechEngine, @unchecked Sendable {
    static let endpoint = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!

    let events: AsyncStream<SpeechEvent>
    private let eventSink: AsyncStream<SpeechEvent>.Continuation
    private let apiKey: String
    private let model: String
    private let languageHints: [String]

    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var outgoing: [Int16] = []
    private var stopping = false
    private var finished: CheckedContinuation<Void, Never>?
    private var receiveTask: Task<Void, Never>?

    /// 大约 120ms 发一次音频
    private static let chunkSamples = 1_920

    init(apiKey: String, model: String, languageHints: [String]) {
        self.apiKey = apiKey
        self.model = model
        self.languageHints = languageHints
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
    }

    func start() async throws {
        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()

        var config: [String: Any] = [
            // 配置里的 api_key 2027-01-15 起停用，现在和请求头一起发，两边都认
            "api_key": apiKey,
            "model": model,
            "audio_format": "pcm_s16le",
            "sample_rate": Int(Resampler.outputRate),
            "num_channels": 1,
            "enable_speaker_diarization": true,
            "enable_language_identification": true,
            "enable_endpoint_detection": true,
            "client_reference_id": "tyto",
        ]
        if !languageHints.isEmpty { config["language_hints"] = languageHints }
        let configText = String(data: try JSONSerialization.data(withJSONObject: config), encoding: .utf8)!
        try await socket.send(.string(configText))

        lock.withLock { self.socket = socket }
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
    }

    func append(_ samples: [Float]) {
        let chunk: Data? = lock.withLock {
            guard socket != nil, !stopping else { return nil }
            outgoing.append(contentsOf: samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) })
            guard outgoing.count >= Self.chunkSamples else { return nil }
            defer { outgoing.removeAll(keepingCapacity: true) }
            return outgoing.withUnsafeBufferPointer { Data(buffer: $0) }
        }
        guard let chunk, let socket = lock.withLock({ self.socket }) else { return }
        socket.send(.data(chunk)) { _ in }
    }

    func stop() async {
        let (socket, rest): (URLSessionWebSocketTask?, Data?) = lock.withLock {
            stopping = true
            let rest = outgoing.isEmpty ? nil : outgoing.withUnsafeBufferPointer { Data(buffer: $0) }
            outgoing.removeAll()
            return (self.socket, rest)
        }
        guard let socket else {
            eventSink.finish()
            return
        }
        if let rest { try? await socket.send(.data(rest)) }
        try? await socket.send(.string(""))
        // 等服务端把剩下的结果发完（最多 3 秒）
        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await withCheckedContinuation { continuation in
                    guard let self else { return continuation.resume() }
                    let alreadyDone = self.lock.withLock { () -> Bool in
                        if self.socket == nil { return true }
                        self.finished = continuation
                        return false
                    }
                    if alreadyDone { continuation.resume() }
                }
            }
            group.addTask { try? await Task.sleep(for: .seconds(3)) }
            await group.next()
            group.cancelAll()
        }
        socket.cancel(with: .normalClosure, reason: nil)
        receiveTask?.cancel()
        finish()
    }

    private func finish() {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            socket = nil
            defer { finished = nil }
            return finished
        }
        continuation?.resume()
        eventSink.finish()
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                if handle(data) {
                    finish()
                    return
                }
            } catch {
                if !lock.withLock({ stopping }) {
                    eventSink.yield(SpeechEvent(kind: .error, text: "Soniox 连接断了：\(error.localizedDescription)"))
                }
                finish()
                return
            }
        }
    }

    /// 处理一条响应；返回 true 表示服务端说结束了。
    private func handle(_ data: Data) -> Bool {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else { return false }
        if let code = response.error_code {
            eventSink.yield(SpeechEvent(kind: .error, text: "Soniox 出错（\(code)）：\(response.error_message ?? "")"))
            return true
        }

        var final: SpeechEvent?
        var partial = SpeechEvent(kind: .partial)
        for token in response.tokens ?? [] where token.translation_status != "translation" {
            if token.text == "<end>" {
                if let event = final { eventSink.yield(event) }
                final = nil
                eventSink.yield(SpeechEvent(kind: .endOfUtterance))
                continue
            }
            let speaker = token.speaker?.value
            if token.is_final == true {
                if let current = final, current.speaker != speaker {
                    eventSink.yield(current)
                    final = nil
                }
                if final == nil { final = SpeechEvent(kind: .final, speaker: speaker, language: token.language) }
                final?.text += token.text
            } else {
                if partial.text.isEmpty {
                    partial.speaker = speaker
                    partial.language = token.language
                }
                partial.text += token.text
            }
        }
        if let event = final { eventSink.yield(event) }
        eventSink.yield(partial)
        return response.finished == true
    }

    private struct Response: Decodable {
        let tokens: [Token]?
        let finished: Bool?
        let error_code: Int?
        let error_message: String?
    }

    private struct Token: Decodable {
        let text: String
        let is_final: Bool?
        let speaker: FlexibleInt?
        let language: String?
        let translation_status: String?
    }

    /// 说话人编号有时是数字，有时是字符串
    private struct FlexibleInt: Decodable {
        let value: Int?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = number
            } else if let text = try? container.decode(String.self) {
                value = Int(text)
            } else {
                value = nil
            }
        }
    }
}
