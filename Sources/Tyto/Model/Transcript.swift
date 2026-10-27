import Foundation

/// 声音从哪来。远端是会议软件里别人的声音（系统音频），本地是麦克风收到的声音（你和会议室里的人）。
enum Channel: String, Codable, CaseIterable, Sendable {
    case remote
    case local

    var label: String {
        switch self {
        case .remote: "远端"
        case .local: "本地"
        }
    }
}

/// 一段话。识别过程中 pending 会不断变化，确定下来的部分进 text。
struct Utterance: Identifiable, Codable, Equatable {
    let id: UUID
    let channel: Channel
    /// 说话人编号（来自云端识别的说话人分离）；本机识别不区分说话人，为 nil
    var speaker: Int?
    var text: String
    var pending: String
    var translation: String?
    /// 识别出的语言代码，如 "en"、"zh"
    var language: String?
    let startedAt: Date
    var updatedAt: Date
    var isClosed: Bool

    init(channel: Channel, speaker: Int?, language: String?) {
        id = UUID()
        self.channel = channel
        self.speaker = speaker
        self.language = language
        text = ""
        pending = ""
        startedAt = .now
        updatedAt = .now
        isClosed = false
    }

    /// 只给自测用：复制一行并改开始、更新时间
    init(copying row: Utterance, startedAt: Date, updatedAt: Date) {
        id = row.id
        channel = row.channel
        speaker = row.speaker
        text = row.text
        pending = row.pending
        translation = row.translation
        language = row.language
        isClosed = row.isClosed
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    var displayText: String { TextJoin.join(text, pending) }

    /// 说话人名字表里用的键，如 "remote:1"、"local:-"
    var speakerKey: String { "\(channel.rawValue):\(speaker.map(String.init) ?? "-")" }
}

/// 一条回复建议
struct Reply: Identifiable, Codable, Equatable {
    let id: UUID
    let createdAt: Date
    /// 针对什么生成的，如"选中的 2 句"
    let target: String
    var text: String
    var isStreaming: Bool
    var error: String?
    /// "screenshot" 表示截屏回复；nil 是会议里的回复
    var source: String?
    /// 截图的小图（界面上显示）
    var thumbnail: Data?
    /// 截屏回复时我补充的要求
    var instruction: String?
    /// 进度提示：识别文字中、生成中……
    var status: String?
    /// 已经放进剪贴板的那一段的标题
    var copiedSection: String?

    var isScreenshot: Bool { source == "screenshot" }

    init(target: String) {
        id = UUID()
        createdAt = .now
        self.target = target
        text = ""
        isStreaming = true
    }
}

enum TextJoin {
    /// 把识别结果一段段接起来：英文之间补空格，中日韩文字之间不加。
    static func join(_ head: String, _ tail: String) -> String {
        if head.isEmpty { return tail.trimmingCharacters(in: .whitespaces) }
        if tail.isEmpty { return head }
        if head.last?.isWhitespace == true || tail.first?.isWhitespace == true { return head + tail }
        if let last = head.unicodeScalars.last, let first = tail.unicodeScalars.first,
           isCJK(last) || isCJK(first) {
            return head + tail
        }
        return head + " " + tail
    }

    static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3000...0x303F, 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xAC00...0xD7AF, 0xF900...0xFAFF, 0xFF00...0xFFEF:
            true
        default:
            false
        }
    }

    static func endsSentence(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return ".?!。？！".contains(last)
    }

    static func isQuestion(_ text: String) -> Bool {
        guard let last = text.trimmingCharacters(in: .whitespaces).last else { return false }
        return last == "?" || last == "？"
    }
}
