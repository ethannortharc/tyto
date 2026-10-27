import Foundation

/// 运行日志：~/Library/Logs/Tyto.log。记启动、权限、有没有收到声音、出错，方便排查"为什么没字幕"。
enum RunLog {
    private static let lock = NSLock()
    private static let url = URL.libraryDirectory.appending(path: "Logs/Tyto.log")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func write(_ message: String) {
        lock.withLock {
            let line = "\(formatter.string(from: .now)) \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: url)
            }
        }
    }
}

/// 每一路声音只在开头和每隔一段时间记一次音量，确认真的收到了声音
final class AudioProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let name: String
    private var samples = 0
    private var peak: Float = 0
    private var nextReport = 0

    init(_ name: String) { self.name = name }

    func observe(_ chunk: [Float]) {
        let report: String? = lock.withLock {
            samples += chunk.count
            peak = max(peak, chunk.map(abs).max() ?? 0)
            guard samples >= nextReport else { return nil }
            defer {
                nextReport = samples + Int(Resampler.outputRate) * 30
                peak = 0
            }
            return "\(name)：已收到 \(samples / Int(Resampler.outputRate)) 秒声音，最大音量 \(String(format: "%.3f", peak))"
        }
        if let report { RunLog.write(report) }
    }
}
