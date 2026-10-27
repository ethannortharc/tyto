import Foundation

/// Deepgram 实时识别（WebSocket）。边说边出字，能分出说话人。
/// 协议：连上就直接发 16-bit PCM；返回 Results（is_final 的是确定的文字，否则是还会变的），
/// speech_final 或 UtteranceEnd 表示一句话说完。没声音时要定时发 KeepAlive，否则 10 秒后断开。
final class DeepgramSpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let eventSink: AsyncStream<SpeechEvent>.Continuation
    private let apiKey: String
    private let endpoint: URL

    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var outgoing: [Int16] = []
    private var stopping = false
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    private static let chunkSamples = 1_920

    /// - language: 只说一种语言时填它（如 "en"、"zh"）；混着说填 "multi"（nova-3 支持）
    init(apiKey: String, baseURL: String, model: String, language: String) {
        self.apiKey = apiKey
        var components = URLComponents(string: baseURL) ?? URLComponents(string: "wss://api.deepgram.com/v1/listen")!
        components.queryItems = [
            URLQueryItem(name: "model", value: model),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "encoding", value: "linear16"),
            URLQueryItem(name: "sample_rate", value: String(Int(Resampler.outputRate))),
            URLQueryItem(name: "channels", value: "1"),
            URLQueryItem(name: "interim_results", value: "true"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "punctuate", value: "true"),
            URLQueryItem(name: "diarize", value: "true"),
            URLQueryItem(name: "endpointing", value: "300"),
            URLQueryItem(name: "utterance_end_ms", value: "1000"),
        ]
        endpoint = components.url!
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
    }

    func start() async throws {
        var request = URLRequest(url: endpoint)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        lock.withLock { self.socket = socket }
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
        // 系统声音只在有声音时才送数据，安静时也要定时告诉服务端连接还在用
        keepAliveTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                socket.send(.string(#"{"type":"KeepAlive"}"#)) { _ in }
            }
        }
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
        keepAliveTask?.cancel()
        let (socket, rest): (URLSessionWebSocketTask?, Data?) = lock.withLock {
            stopping = true
            let rest = outgoing.isEmpty ? nil : outgoing.withUnsafeBufferPointer { Data(buffer: $0) }
            outgoing.removeAll()
            return (self.socket, rest)
        }
        if let socket {
            if let rest { try? await socket.send(.data(rest)) }
            try? await socket.send(.string(#"{"type":"CloseStream"}"#))
            // 等服务端把最后的结果发完、自己关掉连接（最多 3 秒）
            for _ in 0..<30 where lock.withLock({ self.socket != nil }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            socket.cancel(with: .normalClosure, reason: nil)
        }
        receiveTask?.cancel()
        lock.withLock { self.socket = nil }
        eventSink.finish()
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await socket.receive()
                guard case .string(let text) = message else { continue }
                handle(Data(text.utf8))
            } catch {
                if !lock.withLock({ stopping }) {
                    eventSink.yield(SpeechEvent(kind: .error, text: tr("Deepgram 连接断了：\(error.localizedDescription)", "Deepgram connection lost: \(error.localizedDescription)")))
                }
                lock.withLock { self.socket = nil }
                return
            }
        }
    }

    /// 处理一条返回（自测会直接喂 JSON 进来）
    func handle(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        switch json["type"] as? String {
        case "UtteranceEnd":
            eventSink.yield(SpeechEvent(kind: .endOfUtterance))
        case "Results":
            let channel = json["channel"] as? [String: Any]
            let alternative = (channel?["alternatives"] as? [[String: Any]])?.first
            let transcript = alternative?["transcript"] as? String ?? ""
            let words = alternative?["words"] as? [[String: Any]] ?? []
            let firstSpeaker = words.first?["speaker"] as? Int
            if json["is_final"] as? Bool == true {
                for group in Self.groupBySpeaker(words, fallback: transcript) where !group.text.isEmpty {
                    eventSink.yield(SpeechEvent(kind: .final, text: group.text, speaker: group.speaker))
                }
                eventSink.yield(SpeechEvent(kind: .partial))
                if json["speech_final"] as? Bool == true { eventSink.yield(SpeechEvent(kind: .endOfUtterance)) }
            } else {
                eventSink.yield(SpeechEvent(kind: .partial, text: transcript, speaker: firstSpeaker))
            }
        default:
            if let message = json["err_msg"] as? String ?? json["description"] as? String {
                eventSink.yield(SpeechEvent(kind: .error, text: tr("Deepgram 出错：\(message)", "Deepgram error: \(message)")))
            }
        }
    }

    /// 同一段里换了说话人就拆开
    private static func groupBySpeaker(_ words: [[String: Any]], fallback: String) -> [(speaker: Int?, text: String)] {
        let speakers = Set(words.compactMap { $0["speaker"] as? Int })
        guard speakers.count > 1 else { return [(words.first?["speaker"] as? Int, fallback)] }
        var groups: [(speaker: Int?, text: String)] = []
        for word in words {
            let speaker = word["speaker"] as? Int
            let text = word["punctuated_word"] as? String ?? word["word"] as? String ?? ""
            if let last = groups.indices.last, groups[last].speaker == speaker {
                groups[last].text = TextJoin.join(groups[last].text, text)
            } else {
                groups.append((speaker, text))
            }
        }
        return groups
    }
}
