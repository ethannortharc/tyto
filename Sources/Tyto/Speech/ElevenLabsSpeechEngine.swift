import Foundation

/// ElevenLabs 实时识别（Scribe v2 Realtime，WebSocket）。英文准，延迟低；实时版不区分说话人。
/// 协议：参数放在地址里，音频用 JSON 发（input_audio_chunk，base64 的 16-bit PCM）；
/// 返回 partial_transcript（还会变）和 committed_transcript（定稿）。用 VAD 断句：一停顿服务端就定稿一段。
/// 开了 include_timestamps 时同一段还会再来一条 committed_transcript_with_timestamps（带语言），只算一次。
/// 每一秒送进去的音频都计费，安静的时候也算。
final class ElevenLabsSpeechEngine: SpeechEngine, @unchecked Sendable {
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
    private var lastSent = ContinuousClock.now
    /// 刚定稿的一段：另一种定稿消息再来同样的文字就不重复算
    private var unpaired: (withTimestamps: Bool, text: String)?
    private var receiveTask: Task<Void, Never>?
    private var keepAliveTask: Task<Void, Never>?

    private static let chunkSamples = 1_920

    /// - language: 只说一种语言时填它（如 "en"、"zh"）；nil = 自动认
    init(apiKey: String, baseURL: String, model: String, language: String?) {
        self.apiKey = apiKey
        var components = URLComponents(string: baseURL) ?? URLComponents(string: "wss://api.elevenlabs.io/v1/speech-to-text/realtime")!
        var query = [
            URLQueryItem(name: "model_id", value: model),
            URLQueryItem(name: "audio_format", value: "pcm_\(Int(Resampler.outputRate))"),
            URLQueryItem(name: "commit_strategy", value: "vad"),
            // 停顿多久算一句说完（0.192–3 秒）：太长定稿慢，太短会把一句话切开
            URLQueryItem(name: "vad_silence_threshold_secs", value: "0.6"),
            URLQueryItem(name: "include_timestamps", value: "true"),
            URLQueryItem(name: "include_language_detection", value: "true"),
        ]
        if let language { query.append(URLQueryItem(name: "language_code", value: language)) }
        components.queryItems = query
        endpoint = components.url!
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
    }

    func start() async throws {
        var request = URLRequest(url: endpoint)
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        let socket = URLSession.shared.webSocketTask(with: request)
        socket.resume()
        lock.withLock {
            self.socket = socket
            lastSent = .now
        }
        receiveTask = Task { [weak self] in await self?.receiveLoop(socket) }
        // 系统声音只在有声音时才送数据；没有保持连接的消息，安静久了就补一小段静音（静音也计费，所以只补 0.1 秒）
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                if lock.withLock({ ContinuousClock.now - lastSent > .seconds(5) }) {
                    send([Int16](repeating: 0, count: 1_600), commit: false)
                }
            }
        }
    }

    func append(_ samples: [Float]) {
        let chunk: [Int16]? = lock.withLock {
            guard socket != nil, !stopping else { return nil }
            outgoing.append(contentsOf: samples.map { Int16(max(-1, min(1, $0)) * Float(Int16.max)) })
            guard outgoing.count >= Self.chunkSamples else { return nil }
            defer { outgoing.removeAll(keepingCapacity: true) }
            return outgoing
        }
        if let chunk { send(chunk, commit: false) }
    }

    private func send(_ samples: [Int16], commit: Bool) {
        guard let socket = lock.withLock({ () -> URLSessionWebSocketTask? in
            lastSent = .now
            return self.socket
        }) else { return }
        socket.send(.string(Self.chunkMessage(samples, commit: commit))) { _ in }
    }

    private static func chunkMessage(_ samples: [Int16], commit: Bool) -> String {
        let audio = samples.withUnsafeBufferPointer { Data(buffer: $0) }.base64EncodedString()
        return #"{"message_type":"input_audio_chunk","audio_base_64":"\#(audio)","commit":\#(commit),"sample_rate":\#(Int(Resampler.outputRate))}"#
    }

    func stop() async {
        keepAliveTask?.cancel()
        let (socket, rest): (URLSessionWebSocketTask?, [Int16]) = lock.withLock {
            stopping = true
            defer { outgoing.removeAll() }
            return (self.socket, outgoing)
        }
        if let socket {
            // 最后一段手动定稿，等它回来（最多 3 秒）；不发空音频，没剩下的就带 0.1 秒静音
            try? await socket.send(.string(Self.chunkMessage(rest.isEmpty ? [Int16](repeating: 0, count: 1_600) : rest, commit: true)))
            let committed = lock.withLock { unpaired?.text }
            for _ in 0..<30 where lock.withLock({ self.socket != nil && unpaired?.text == committed }) {
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
                if !lock.withLock({ stopping || reportedError }) {
                    let reason = socket.closeReason.flatMap { String(data: $0, encoding: .utf8) } ?? error.localizedDescription
                    eventSink.yield(SpeechEvent(kind: .error, text: tr("ElevenLabs 连接断了（\(socket.closeCode.rawValue)）：\(reason)", "ElevenLabs connection lost (\(socket.closeCode.rawValue)): \(reason)")))
                }
                lock.withLock { self.socket = nil }
                return
            }
        }
    }

    /// 处理一条返回（自测会直接喂 JSON 进来）
    func handle(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["message_type"] as? String else { return }
        let text = json["text"] as? String ?? ""
        switch type {
        case "partial_transcript":
            eventSink.yield(SpeechEvent(kind: .partial, text: text))
        case "committed_transcript", "committed_transcript_with_timestamps":
            let withTimestamps = type == "committed_transcript_with_timestamps"
            let isDuplicate = lock.withLock { () -> Bool in
                if let last = unpaired, last.withTimestamps != withTimestamps, last.text == text {
                    unpaired = nil
                    return true
                }
                unpaired = (withTimestamps, text)
                return false
            }
            guard !isDuplicate, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let words = json["words"] as? [[String: Any]] ?? []
            let language = json["language_code"] as? String
            for group in Self.groupBySpeaker(words, fallback: text) where !group.text.isEmpty {
                eventSink.yield(SpeechEvent(kind: .final, text: group.text, speaker: group.speaker, language: language))
            }
            eventSink.yield(SpeechEvent(kind: .partial))
            eventSink.yield(SpeechEvent(kind: .endOfUtterance))
        default:
            // 出错的消息（auth_error、quota_exceeded、input_error……）都带 error；warning 等其余的不用管
            guard let message = json["error"] as? String else { return }
            lock.withLock { reportedError = true }
            eventSink.yield(SpeechEvent(kind: .error, text: tr("ElevenLabs 出错（\(type)）：\(message)", "ElevenLabs error (\(type)): \(message)")))
        }
    }

    /// 词上带了 speaker_id（"speaker_0"……）就按人拆开；实时版目前不给，整段算一个人
    private static func groupBySpeaker(_ words: [[String: Any]], fallback: String) -> [(speaker: Int?, text: String)] {
        func speaker(_ word: [String: Any]) -> Int? {
            (word["speaker_id"] as? String).flatMap { Int($0.split(separator: "_").last ?? "") }
        }
        let speakers = Set(words.compactMap(speaker))
        guard speakers.count > 1 else { return [(speakers.first, fallback)] }
        var groups: [(speaker: Int?, text: String)] = []
        for word in words {
            // spacing 是词之间的空格；按人拆开时各段自己补空格
            guard word["type"] as? String != "spacing", let text = word["text"] as? String else { continue }
            let speaker = speaker(word)
            if let last = groups.indices.last, speaker == nil || groups[last].speaker == speaker {
                groups[last].text = TextJoin.join(groups[last].text, text)
            } else {
                groups.append((speaker, text))
            }
        }
        return groups
    }
}
