import Foundation

/// 回复按【标题】分段，界面按段画：说明性的段落普通显示，"回复"段落可以一键复制。
struct ReplySection: Identifiable, Equatable {
    let id: Int
    let title: String
    let body: String

    /// 可以直接说出口 / 粘贴发送的那几段
    var isCopyable: Bool { title.hasPrefix("建议回复") || title.hasPrefix("回复") }
}

enum ReplyFormat {
    private static let marker = try! NSRegularExpression(pattern: "【([^】\\n]{1,40})】")

    static func sections(_ text: String) -> [ReplySection] {
        let nsText = text as NSString
        let matches = marker.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return body.isEmpty ? [] : [ReplySection(id: 0, title: "", body: body)]
        }
        var sections: [ReplySection] = []
        let lead = nsText.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty { sections.append(ReplySection(id: 0, title: "", body: lead)) }
        for (index, match) in matches.enumerated() {
            let title = nsText.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            let body = nsText.substring(with: NSRange(location: start, length: end - start))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(ReplySection(id: index + 1, title: title, body: body))
        }
        return sections
    }

    /// 第一段可以复制的回复
    static func firstReply(_ text: String) -> ReplySection? {
        sections(text).first { $0.isCopyable && !$0.body.isEmpty }
    }
}
