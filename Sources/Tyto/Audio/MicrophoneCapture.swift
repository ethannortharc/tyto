@preconcurrency import AVFAudio
import Foundation

/// 录麦克风（会议室里本地的声音，包括你自己）。
///
/// 用外放开会时，麦克风也会收到会议软件放出来的对方声音，字幕里会重复一遍。
/// 打开回声消除（系统的语音处理）可以把这部分去掉；戴耳机时用不着。
final class MicrophoneCapture: AudioSource, @unchecked Sendable {
    var onSamples: (@Sendable ([Float]) -> Void)?

    private var engine = AVAudioEngine()
    private let echoCancellation: Bool
    private var resampler: Resampler?

    init(echoCancellation: Bool) {
        self.echoCancellation = echoCancellation
    }

    func start() throws {
        do {
            try start(voiceProcessing: echoCancellation)
        } catch where echoCancellation {
            // 有些设备开不了语音处理，退回普通录音
            engine.stop()
            engine = AVAudioEngine()
            try start(voiceProcessing: false)
        }
    }

    private func start(voiceProcessing: Bool) throws {
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            // 语音处理默认会把别的声音压低，会议软件的声音也会变小；关掉这个效果
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw TytoError.noMicrophone }
        let resampler = Resampler(inputRate: format.sampleRate)
        self.resampler = resampler
        let firstChannelOnly = voiceProcessing
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let resampler else { return }
            let samples = resampler.process(Downmix.mono(buffer, firstChannelOnly: firstChannelOnly))
            if !samples.isEmpty { self.onSamples?(samples) }
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}
