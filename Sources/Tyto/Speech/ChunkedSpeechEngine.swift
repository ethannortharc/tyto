import Foundation

/// "说完一句传一句"的识别：按停顿把声音切成一句一句，交给不能实时识别的接口。
/// 两种接口：
/// - 语音转写接口（OpenAI 兼容的 /audio/transcriptions）：OpenAI、Groq、硅基流动、自建 Whisper……
/// - 能听音频的对话模型（chat 里带 input_audio）：OpenRouter、Gemini……
/// 比实时识别慢一两秒（要等一句说完），说话中显示"…"。
final class ChunkedSpeechEngine: SpeechEngine, @unchecked Sendable {
    enum Backend: Sendable {
        case transcription(baseURL: URL, apiKey: String?, model: String, language: String?)
        case audioChat(baseURL: URL, apiKey: String?, model: String, languages: String)
    }

    let events: AsyncStream<SpeechEvent>
    private let eventSink: AsyncStream<SpeechEvent>.Continuation
    private let backend: Backend
    private let segmenter = Segmenter()
    private let chunks: AsyncStream<[Float]>
    private let chunkSink: AsyncStream<[Float]>.Continuation
    private var worker: Task<Void, Never>?

    init(backend: Backend) {
        self.backend = backend
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
        (chunks, chunkSink) = AsyncStream.makeStream(of: [Float].self)
    }

    func start() async throws {
        let backend = backend
        let sink = eventSink
        let chunks = chunks
        // 一句一句按顺序转写，保证字幕顺序和说话顺序一致
        worker = Task {
            for await chunk in chunks {
                do {
                    let text = try await Self.transcribe(chunk, with: backend)
                    if !text.isEmpty { sink.yield(SpeechEvent(kind: .final, text: text)) }
                    sink.yield(SpeechEvent(kind: .endOfUtterance))
                } catch {
                    sink.yield(SpeechEvent(kind: .error, text: tr("转写失败：\(error.localizedDescription)", "Transcription failed: \(error.localizedDescription)")))
                    sink.yield(SpeechEvent(kind: .partial))
                }
            }
        }
    }

    func append(_ samples: [Float]) {
        for event in segmenter.feed(samples) {
            switch event {
            case .started: eventSink.yield(SpeechEvent(kind: .partial, text: "…"))
            case .chunk(let chunk): chunkSink.yield(chunk)
            }
        }
    }

    func stop() async {
        if let rest = segmenter.flush() { chunkSink.yield(rest) }
        chunkSink.finish()
        await worker?.value
        eventSink.finish()
    }

    static func transcribe(_ samples: [Float], with backend: Backend) async throws -> String {
        let wav = WAV.encode(samples)
        switch backend {
        case let .transcription(baseURL, apiKey, model, language):
            var form = MultipartForm()
            form.add("model", model)
            form.add("response_format", "json")
            if let language { form.add("language", language) }
            form.addFile("file", filename: "speech.wav", type: "audio/wav", data: wav)
            var request = URLRequest(url: baseURL.appending(path: "audio/transcriptions"))
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue(form.contentType, forHTTPHeaderField: "Content-Type")
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = form.body
            let json = try await send(request)
            return (json["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        case let .audioChat(baseURL, apiKey, model, languages):
            let prompt = "把这段会议录音逐字转写成文字。只输出转写的原文，不翻译、不解释、不加引号；没有人说话就什么都不输出。可能出现的语言：\(languages)。"
            let body: [String: Any] = [
                "model": model,
                "stream": false,
                "messages": [[
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "input_audio", "input_audio": ["data": wav.base64EncodedString(), "format": "wav"]],
                    ],
                ]],
            ]
            var request = URLRequest(url: baseURL.appending(path: "chat/completions"))
            request.httpMethod = "POST"
            request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let json = try await send(request)
            let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
            return (message?["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? String(decoding: data.prefix(200), as: UTF8.self)
            throw TytoError.server(tr("接口返回 \(http.statusCode)：\(message)", "API returned \(http.statusCode): \(message)"))
        }
        return json
    }
}

/// 按音量切句：声音持续超过阈值算开始说话，停顿 0.7 秒算说完，一句最长 15 秒。
/// 阈值跟着环境底噪自动调整。
final class Segmenter: @unchecked Sendable {
    enum Event {
        case started
        case chunk([Float])
    }

    private let lock = NSLock()
    private static let frame = 480                 // 30ms
    private static let startFrames = 3             // 连续 90ms 有声音才算开始
    private static let endFrames = 24              // 停顿 0.72 秒算说完
    private static let preRollFrames = 10          // 开始前多留 0.3 秒，免得吞掉第一个字
    private static let maxSamples = Int(Resampler.outputRate) * 15
    private static let minSamples = Int(Resampler.outputRate * 0.4)

    private var pending: [Float] = []
    private var preRoll: [[Float]] = []
    private var current: [Float] = []
    private var speaking = false
    private var loudFrames = 0
    private var quietFrames = 0
    private var noise: Float = 0.005

    func feed(_ samples: [Float]) -> [Event] {
        lock.withLock {
            pending.append(contentsOf: samples)
            var events: [Event] = []
            while pending.count >= Self.frame {
                let frame = Array(pending.prefix(Self.frame))
                pending.removeFirst(Self.frame)
                events.append(contentsOf: process(frame))
            }
            return events
        }
    }

    /// 停止时把正在说的那句交出去
    func flush() -> [Float]? {
        lock.withLock {
            defer {
                current = []
                speaking = false
            }
            return speaking && current.count >= Self.minSamples ? current : nil
        }
    }

    private func process(_ frame: [Float]) -> [Event] {
        var sum: Float = 0
        for sample in frame { sum += sample * sample }
        let rms = (sum / Float(frame.count)).squareRoot()
        let threshold = max(0.012, noise * 3.5)
        let loud = rms > threshold

        guard speaking else {
            if !loud { noise = noise * 0.98 + rms * 0.02 }
            preRoll.append(frame)
            if preRoll.count > Self.preRollFrames { preRoll.removeFirst() }
            loudFrames = loud ? loudFrames + 1 : 0
            guard loudFrames >= Self.startFrames else { return [] }
            speaking = true
            quietFrames = 0
            current = preRoll.flatMap { $0 }
            preRoll = []
            return [.started]
        }

        current.append(contentsOf: frame)
        quietFrames = loud ? 0 : quietFrames + 1
        if quietFrames >= Self.endFrames || current.count >= Self.maxSamples {
            let chunk = current
            current = []
            // 停顿够了就算说完；只是太长被切开的话，接着收下一段
            speaking = quietFrames < Self.endFrames
            loudFrames = 0
            return chunk.count >= Self.minSamples ? [.chunk(chunk)] : []
        }
        return []
    }
}

/// 16kHz 单声道 16-bit 的 WAV 文件
enum WAV {
    static func encode(_ samples: [Float], rate: Int = Int(Resampler.outputRate)) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let bytes = samples.count * 2
        data.append(contentsOf: Array("RIFF".utf8)); append(UInt32(36 + bytes))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); append(UInt32(bytes))
        for sample in samples { append(Int16(max(-1, min(1, sample)) * Float(Int16.max))) }
        return data
    }
}

/// multipart/form-data 请求体
struct MultipartForm {
    private let boundary = "tyto-\(UUID().uuidString)"
    private var parts = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }
    /// 取的时候才补上结尾标记，所以字段和文件按什么顺序加都行
    var body: Data { parts + Data("--\(boundary)--\r\n".utf8) }

    mutating func add(_ name: String, _ value: String) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
    }

    mutating func addFile(_ name: String, filename: String, type: String, data: Data) {
        parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\nContent-Type: \(type)\r\n\r\n".utf8))
        parts.append(data)
        parts.append(Data("\r\n".utf8))
    }
}
