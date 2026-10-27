import Foundation

/// 识别引擎送出来的事件。
struct SpeechEvent: Sendable {
    enum Kind: Sendable {
        /// 还在变的文字：整段替换当前未确定的部分
        case partial
        /// 确定下来的一段文字：接到已确定的部分后面
        case final
        /// 一句话说完了（云端识别的断句信号）
        case endOfUtterance
        case error
    }

    var kind: Kind
    var text = ""
    var speaker: Int?
    var language: String?
}

/// 识别引擎：送进 16kHz 单声道 Float32 音频，送出识别事件。
protocol SpeechEngine: AnyObject, Sendable {
    var events: AsyncStream<SpeechEvent> { get }
    func start() async throws
    func append(_ samples: [Float])
    func stop() async
}
