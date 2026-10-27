import Foundation

/// AssemblyAI 实时识别（Streaming v3，WebSocket）。能分出说话人，Universal-3.6 Pro 中英混着说也认得出。
/// 协议：参数都放在地址里，连上就发 16-bit PCM（每帧 50–1000 ms）；返回 Turn：end_of_turn 为 false 的是还会变的，
/// end_of_turn 且 turn_is_formatted 的是这一句的定稿。发 Terminate 结束，服务端回 Termination 后关掉连接。
/// 按连接开着的时长计费，安静时也算。
final class AssemblyAISpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let eventSink: AsyncStream<SpeechEvent>.Continuation
    private let apiKey: String
    private let endpoint: URL

    private let lock = NSLock()
    private var socket: URLSessionWebSocketTask?
    private var outgoing: [Int16] = []
    private var stopping = false
    /// 服务端已经说了出错原因：之后断开就不再报"连接断了"，免得盖掉真正的原因
    private var reportedError = false
    private var receiveTask: Task<Void, Never>?

    private static let chunkSamples = 1_920

    /// - languages: 知道会说哪几种语言时填上（如 ["en", "zh"]），模型会偏向它们；空 = 自动认、自动混说
    init(apiKey: String, baseURL: String, model: String, languages: [String]) {
        self.apiKey = apiKey
        var components = URLComponents(string: baseURL) ?? URLComponents(string: "wss://streaming.assemblyai.com/v3/ws")!
        var query = [
            URLQueryItem(name: "speech_model", value: model),
            URLQueryItem(name: "encoding", value: "pcm_s16le"),
            URLQueryItem(name: "sample_rate", value: String(Int(Resampler.outputRate))),
            URLQueryItem(name: "speaker_labels", value: "true"),
            URLQueryItem(name: "language_detection", value: "true"),
            // 只对 Universal-Streaming 有用：定稿只发一次带标点的（Pro 模型本来就这样，会忽略这个参数）
            URLQueryItem(name: "format_turns", value: "true"),
        ]
        if !languages.isEmpty,
           let list = try? JSONSerialization.data(withJSONObject: languages), let text = String(data: list, encoding: .utf8) {
            query.append(URLQueryItem(name: "language_codes", value: text))
        }
        components.queryItems = query
        endpoint = components.url!
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
    }

    func start() async throws {
        var request = URLRequest(url: endpoint)
        // AssemblyAI 的 key 直接放进 Authorization，不加 Bearer
        request.setValue(apiKey, forHTTPHeaderField: "Authorization")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
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
            // 每帧至少 50 ms，太短的尾巴就不发了
            let rest = outgoing.count < 800 ? nil : outgoing.withUnsafeBufferPointer { Data(buffer: $0) }
            outgoing.removeAll()
            return (self.socket, rest)
        }
        if let socket {
            if let rest { try? await socket.send(.data(rest)) }
            try? await socket.send(.string(#"{"type":"Terminate"}"#))
            // 等服务端把最后一句发完、回 Termination（最多 3 秒）
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
                if handle(Data(text.utf8)) {
                    lock.withLock { self.socket = nil }
                    return
                }
            } catch {
                if !lock.withLock({ stopping || reportedError }) {
                    // 鉴权失败、参数不对时服务端直接关连接，原因在关闭帧里
                    let reason = socket.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? error.localizedDescription
                    eventSink.yield(SpeechEvent(kind: .error, text: tr("AssemblyAI 连接断了（\(socket.closeCode.rawValue)）：\(reason)", "AssemblyAI connection lost (\(socket.closeCode.rawValue)): \(reason)")))
                }
                lock.withLock { self.socket = nil }
                return
            }
        }
    }

    /// 处理一条返回；返回 true 表示会话结束了（自测会直接喂 JSON 进来）
    @discardableResult
    func handle(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        switch json["type"] as? String {
        case "Turn":
            let transcript = json["transcript"] as? String ?? ""
            let words = json["words"] as? [[String: Any]] ?? []
            let turnSpeaker = Self.speaker(json["speaker_label"])
            let language = json["language_code"] as? String
            if json["end_of_turn"] as? Bool == true, json["turn_is_formatted"] as? Bool == true {
                for group in Self.groupBySpeaker(words, fallback: transcript, turnSpeaker: turnSpeaker) where !group.text.isEmpty {
                    eventSink.yield(SpeechEvent(kind: .final, text: group.text, speaker: group.speaker, language: language))
                }
                eventSink.yield(SpeechEvent(kind: .partial))
                eventSink.yield(SpeechEvent(kind: .endOfUtterance))
            } else if json["end_of_turn"] as? Bool != true {
                // 还没说完：transcript 只有已确定的词，后面还会变的词在 words 里
                let text = words.isEmpty ? transcript : words.reduce("") { TextJoin.join($0, $1["text"] as? String ?? "") }
                eventSink.yield(SpeechEvent(kind: .partial, text: text, speaker: turnSpeaker, language: language))
            }
            return false
        case "Termination":
            return true
        case "Error":
            let message = json["error"] as? String ?? json["message"] as? String ?? String(data: data, encoding: .utf8) ?? ""
            lock.withLock { reportedError = true }
            eventSink.yield(SpeechEvent(kind: .error, text: tr("AssemblyAI 出错：\(message)", "AssemblyAI error: \(message)")))
            return false
        default:
            // Begin、SpeechStarted、SpeakerRevision（会后修正说话人，实时显示用不上）
            return false
        }
    }

    /// 说话人是 "A"、"B"……；"UNKNOWN"（不到一秒的短句）和 "PENDING"（还没认出来）当作没给
    private static func speaker(_ value: Any?) -> Int? {
        guard let label = value as? String, label.count == 1, let scalar = label.unicodeScalars.first,
              ("A"..."Z").contains(scalar) else { return nil }
        return Int(scalar.value - ("A" as Unicode.Scalar).value)
    }

    /// 同一句里换了说话人就拆开；没给说话人的词跟着前一个词
    private static func groupBySpeaker(_ words: [[String: Any]], fallback: String, turnSpeaker: Int?) -> [(speaker: Int?, text: String)] {
        let speakers = Set(words.compactMap { speaker($0["speaker"]) })
        guard speakers.count > 1 else { return [(speakers.first ?? turnSpeaker, fallback)] }
        var groups: [(speaker: Int?, text: String)] = []
        for word in words {
            let text = word["text"] as? String ?? ""
            let speaker = speaker(word["speaker"])
            if let last = groups.indices.last, speaker == nil || groups[last].speaker == speaker {
                groups[last].text = TextJoin.join(groups[last].text, text)
            } else if let last = groups.indices.last, groups[last].speaker == nil {
                groups[last].speaker = speaker
                groups[last].text = TextJoin.join(groups[last].text, text)
            } else {
                groups.append((speaker, text))
            }
        }
        return groups
    }
}
