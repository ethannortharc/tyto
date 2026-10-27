@preconcurrency import AVFAudio
import Foundation

/// 采集到的声音统一交给识别引擎的格式：16kHz、单声道、Float32。
protocol AudioSource: AnyObject, Sendable {
    var onSamples: (@Sendable ([Float]) -> Void)? { get set }
    func start() throws
    func stop()
}

enum TytoError: LocalizedError {
    case noMicrophone
    case noOutputDevice
    case tapFailed(String)
    case unsupportedLocale(String)
    case unsupportedAudioFormat
    case missingAPIKey(String)
    case translationNotInstalled(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "找不到麦克风"
        case .noOutputDevice: "找不到声音输出设备"
        case .tapFailed(let detail): "录不了系统声音：\(detail)"
        case .unsupportedLocale(let locale): "本机识别不支持这个语言：\(locale)"
        case .unsupportedAudioFormat: "不支持的音频格式"
        case .missingAPIKey(let what): "还没填 \(what) 的 API key（模型与服务 里填）"
        case .translationNotInstalled(let pair): "本机翻译语言没下载：\(pair)（模型与服务 → 下载本机翻译语言）"
        case .server(let message): message
        }
    }
}

/// 把任意采样率的单声道 Float32 连续地转成 16kHz。
final class Resampler: @unchecked Sendable {
    static let outputRate = 16_000.0

    private let inputFormat: AVAudioFormat
    private let outputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init?(inputRate: Double) {
        guard inputRate > 0,
              let input = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputRate, channels: 1, interleaved: false),
              let output = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Self.outputRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: output)
        else { return nil }
        inputFormat = input
        outputFormat = output
        self.converter = converter
    }

    func process(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        if inputFormat.sampleRate == Self.outputRate { return samples }
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return [] }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            input.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        let capacity = AVAudioFrameCount(Double(samples.count) * Self.outputRate / inputFormat.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        let feed = FeedOnce(input)
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in feed.next(status) }
        guard error == nil, let data = output.floatChannelData else { return [] }
        return Array(UnsafeBufferPointer(start: data[0], count: Int(output.frameLength)))
    }
}

/// 每次转换只喂一块数据；用 .noDataNow 而不是 .endOfStream，转换器才会保留状态、接着处理下一块。
final class FeedOnce: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

enum Downmix {
    /// 多声道混成单声道。回声消除打开时第 0 声道是处理过的人声，只取它。
    static func mono(_ buffer: AVAudioPCMBuffer, firstChannelOnly: Bool = false) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return [] }

        if buffer.format.isInterleaved {
            let pointer = data[0]
            if firstChannelOnly || channels == 1 {
                return (0..<frames).map { pointer[$0 * channels] }
            }
            return (0..<frames).map { frame in
                var sum: Float = 0
                for channel in 0..<channels { sum += pointer[frame * channels + channel] }
                return sum / Float(channels)
            }
        }

        let used = firstChannelOnly ? 1 : channels
        var output = [Float](repeating: 0, count: frames)
        for channel in 0..<used {
            let pointer = data[channel]
            for frame in 0..<frames { output[frame] += pointer[frame] }
        }
        if used > 1 {
            let scale = 1 / Float(used)
            for frame in 0..<frames { output[frame] *= scale }
        }
        return output
    }

    /// 音量（0～1），给界面上的电平显示用
    static func level(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        return min(1, (sum / Float(samples.count)).squareRoot() * 4)
    }
}
