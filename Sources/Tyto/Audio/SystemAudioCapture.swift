import AVFAudio
import CoreAudio
import Foundation

/// 录系统声音（会议软件里对方的声音）。
///
/// 做法：建一个 Core Audio 进程音频捕获（tap），抓除本 app 以外所有进程的声音，
/// 把它挂到一个私有的聚合设备上，再从聚合设备的输入里读数据。
/// 只要"系统录音"权限，不要屏幕录制权限；第一次开始时系统会弹窗询问。
final class SystemAudioCapture: AudioSource, @unchecked Sendable {
    var onSamples: (@Sendable ([Float]) -> Void)?

    private let system = AudioHardwareSystem.shared
    private let queue = DispatchQueue(label: "tyto.system-audio", qos: .userInteractive)
    private var tap: AudioHardwareTap?
    private var aggregate: AudioHardwareAggregateDevice?
    private var procID: AudioDeviceIOProcID?
    private var resampler: Resampler?

    func start() throws {
        var excluded: [AudioObjectID] = []
        if let me = try? system.process(for: getpid()) { excluded.append(me.id) }

        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: excluded)
        description.uuid = UUID()
        description.name = "Tyto 系统声音"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard let tap = try system.makeProcessTap(description: description) else {
            throw TytoError.tapFailed(tr("建不了音频捕获", "Couldn't create the audio capture"))
        }
        self.tap = tap

        guard let output = try system.defaultOutputDevice else { throw TytoError.noOutputDevice }
        let outputUID = try output.uid
        let aggregateDescription: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tyto 系统声音",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: try tap.uid]],
        ]
        guard let aggregate = try system.makeAggregateDevice(description: aggregateDescription) else {
            throw TytoError.tapFailed(tr("建不了聚合设备", "Couldn't create the aggregate device"))
        }
        self.aggregate = aggregate

        let format = try tap.format
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw TytoError.unsupportedAudioFormat
        }
        resampler = Resampler(inputRate: format.mSampleRate)
        let channels = Int(format.mChannelsPerFrame)
        let nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate.id, queue) { [weak self] _, input, _, _, _ in
            guard let self, let resampler = self.resampler else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let mono = Self.mono(list, channels: channels, nonInterleaved: nonInterleaved)
            let samples = resampler.process(mono)
            if !samples.isEmpty { self.onSamples?(samples) }
        }
        guard status == noErr, let procID else { throw TytoError.tapFailed(tr("注册不了音频回调（\(status)）", "Couldn't register the audio callback (\(status))")) }
        self.procID = procID
        try aggregate.start(IOProcID: procID)
    }

    func stop() {
        if let aggregate {
            if let procID {
                try? aggregate.stop(IOProcID: procID)
                AudioDeviceDestroyIOProcID(aggregate.id, procID)
            }
            try? system.destroyAggregateDevice(aggregate)
        }
        if let tap { try? system.destroyProcessTap(tap) }
        procID = nil
        aggregate = nil
        tap = nil
    }

    /// 聚合设备的输入里，系统声音在最后面（输出设备自带麦克风时，它的声道排在前面）。
    private static func mono(_ list: UnsafeMutableAudioBufferListPointer, channels: Int, nonInterleaved: Bool) -> [Float] {
        if nonInterleaved {
            let buffers = Array(list.suffix(max(1, channels)))
            guard let first = buffers.first else { return [] }
            let frames = Int(first.mDataByteSize) / MemoryLayout<Float>.size
            var output = [Float](repeating: 0, count: frames)
            for buffer in buffers {
                guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let count = min(frames, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                for frame in 0..<count { output[frame] += pointer[frame] }
            }
            let scale = 1 / Float(buffers.count)
            for frame in 0..<frames { output[frame] *= scale }
            return output
        }
        guard let buffer = list.last, let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { return [] }
        let step = max(1, Int(buffer.mNumberChannels))
        let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / step
        return (0..<frames).map { frame in
            var sum: Float = 0
            for channel in 0..<step { sum += pointer[frame * step + channel] }
            return sum / Float(step)
        }
    }
}
