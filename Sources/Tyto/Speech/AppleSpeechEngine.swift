@preconcurrency import AVFAudio
import Foundation
import Speech

/// Apple 本机识别（macOS 26 的 SpeechAnalyzer）。免费、不联网；一次只认一种语言，不区分说话人。
/// 第一次用某个语言时会自动下载识别模型。
final class AppleSpeechEngine: SpeechEngine, @unchecked Sendable {
    let events: AsyncStream<SpeechEvent>
    private let eventSink: AsyncStream<SpeechEvent>.Continuation
    private let localeIdentifier: String
    private let sourceFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Resampler.outputRate,
                                             channels: 1, interleaved: false)!

    private let lock = NSLock()
    private var analyzer: SpeechAnalyzer?
    private var inputSink: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    init(locale: String) {
        localeIdentifier = locale
        (events, eventSink) = AsyncStream.makeStream(of: SpeechEvent.self)
    }

    func start() async throws {
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: localeIdentifier)) else {
            throw TytoError.unsupportedLocale(localeIdentifier)
        }
        let transcriber = SpeechTranscriber(locale: locale, transcriptionOptions: [],
                                            reportingOptions: [.volatileResults, .fastResults],
                                            attributeOptions: [])
        _ = try? await AssetInventory.reserve(locale: locale)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw TytoError.unsupportedAudioFormat
        }

        let (inputs, inputSink) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        lock.withLock {
            self.analyzer = analyzer
            self.inputSink = inputSink
            analyzerFormat = format
            converter = format == sourceFormat ? nil : AVAudioConverter(from: sourceFormat, to: format)
        }
        try await analyzer.start(inputSequence: inputs)

        let sink = eventSink
        let language = locale.language.languageCode?.identifier
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    sink.yield(SpeechEvent(kind: result.isFinal ? .final : .partial, text: text, language: language))
                }
            } catch {
                sink.yield(SpeechEvent(kind: .error, text: tr("本机识别出错：\(error.localizedDescription)", "On-device recognition error: \(error.localizedDescription)")))
            }
        }
    }

    func append(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        guard let inputSink, let analyzerFormat, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        guard let converter else {
            inputSink.yield(AnalyzerInput(buffer: buffer))
            return
        }
        let capacity = AVAudioFrameCount(Double(samples.count) * analyzerFormat.sampleRate / sourceFormat.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        let feed = FeedOnce(buffer)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in feed.next(status) }
        if error == nil, output.frameLength > 0 {
            inputSink.yield(AnalyzerInput(buffer: output))
        }
    }

    func stop() async {
        let (analyzer, inputSink) = lock.withLock { () -> (SpeechAnalyzer?, AsyncStream<AnalyzerInput>.Continuation?) in
            defer {
                self.inputSink = nil
                self.analyzer = nil
            }
            return (self.analyzer, self.inputSink)
        }
        inputSink?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        eventSink.finish()
    }

    /// 本机识别支持的语言（给设置界面用）
    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { $0.identifier < $1.identifier }
    }
}
