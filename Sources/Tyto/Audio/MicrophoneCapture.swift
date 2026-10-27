@preconcurrency import AVFAudio
import CoreAudio
import Foundation

/// 录麦克风（会议室里本地的声音，包括你自己）。
///
/// 直接用 Core Audio 从选定的麦克风读数据。没用 AVAudioEngine：它在 macOS 上输入、输出共用一个音频单元，
/// 换不了单独的输入设备（实测换到别的麦克风后一块数据都收不到）。
/// 外放开会时麦克风也会收到对方的声音，这部分在会话里按文字去重（见 SessionModel.isEcho）。
final class MicrophoneCapture: AudioSource, @unchecked Sendable {
    var onSamples: (@Sendable ([Float]) -> Void)?

    private let deviceUID: String
    private let queue = DispatchQueue(label: "tyto.microphone", qos: .userInteractive)
    private var device: AudioHardwareDevice?
    private var procID: AudioDeviceIOProcID?
    private var resampler: Resampler?
    /// 实际用的麦克风（写日志用）
    private(set) var deviceName = "系统默认"

    /// - deviceUID: 用哪个麦克风；空字符串表示自动（见 InputDevices.resolve）
    init(deviceUID: String) {
        self.deviceUID = deviceUID
    }

    func start() throws {
        guard let chosen = InputDevices.resolve(uid: deviceUID),
              let device = try AudioHardwareSystem.shared.device(forUID: chosen.uid)
        else { throw TytoError.noMicrophone }
        deviceName = chosen.name
        guard let stream = try device.streams.first(where: { (try? $0.direction) == .input }) else {
            throw TytoError.noMicrophone
        }
        let format = try stream.virtualFormat
        guard format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            throw TytoError.unsupportedAudioFormat
        }
        RunLog.write("本地：麦克风「\(chosen.name)」\(Int(format.mSampleRate))Hz \(format.mChannelsPerFrame) 声道")
        let resampler = Resampler(inputRate: format.mSampleRate)
        self.resampler = resampler

        var procID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, device.id, queue) { [weak self] _, input, _, _, _ in
            guard let self, let resampler else { return }
            let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            let samples = resampler.process(Self.mono(list))
            if !samples.isEmpty { self.onSamples?(samples) }
        }
        guard status == noErr, let procID else { throw TytoError.microphoneDevice(chosen.name, status) }
        self.device = device
        self.procID = procID
        try device.start(IOProcID: procID)
    }

    func stop() {
        if let device, let procID {
            try? device.stop(IOProcID: procID)
            AudioDeviceDestroyIOProcID(device.id, procID)
        }
        device = nil
        procID = nil
    }

    /// 所有输入声道混成单声道（每个缓冲区里是交错排列的 Float32）
    private static func mono(_ list: UnsafeMutableAudioBufferListPointer) -> [Float] {
        var output: [Float] = []
        var channelsMixed = 0
        for buffer in list {
            guard let pointer = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let step = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / step
            if output.isEmpty { output = [Float](repeating: 0, count: frames) }
            for frame in 0..<min(frames, output.count) {
                for channel in 0..<step { output[frame] += pointer[frame * step + channel] }
            }
            channelsMixed += step
        }
        if channelsMixed > 1 {
            let scale = 1 / Float(channelsMixed)
            for frame in output.indices { output[frame] *= scale }
        }
        return output
    }

    static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }
}

struct InputDevice: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    /// BlackHole、Loopback 这类虚拟声卡，以及聚合设备
    let isVirtual: Bool
}

enum InputDevices {
    /// 所有能录音的设备（不含 Tyto 自己建的系统声音设备）
    static func all() -> [InputDevice] {
        ((try? AudioHardwareSystem.shared.devices) ?? []).compactMap { device in
            let channels = ((try? device.inputStreamConfiguration) ?? []).reduce(0) { $0 + Int($1.mNumberChannels) }
            guard channels > 0, let uid = try? device.uid else { return nil }
            let name = (try? device.name) ?? uid
            guard !name.hasPrefix("Tyto") else { return nil }
            let transport = (try? device.transportType) ?? 0
            return InputDevice(id: device.id, uid: uid, name: name,
                               isVirtual: transport == kAudioDeviceTransportTypeVirtual
                                   || transport == kAudioDeviceTransportTypeAggregate)
        }
    }

    /// 选了就用选的（拔掉了就退回自动）。自动 = 系统默认输入；
    /// 但默认输入是虚拟声卡时（装了 BlackHole 的机器常这样），改用第一个真实的麦克风。
    static func resolve(uid: String) -> InputDevice? {
        let devices = all()
        if !uid.isEmpty, let chosen = devices.first(where: { $0.uid == uid }) { return chosen }
        let defaultID = (try? AudioHardwareSystem.shared.defaultInputDevice)?.id
        let systemDefault = devices.first { $0.id == defaultID }
        if let systemDefault, !systemDefault.isVirtual { return systemDefault }
        return devices.first { !$0.isVirtual } ?? systemDefault
    }
}

