import Foundation

/// 回复按【标题】分段，界面按段画：说明性的段落普通显示，"回复"段落可以一键复制。
struct ReplySection: Identifiable, Equatable {
    let id: Int
    let title: String
    let body: String

    /// 可以直接说出口 / 粘贴发送的那几段
    var isCopyable: Bool {
        let lowered = title.lowercased()
        return title.hasPrefix("建议回复") || title.hasPrefix("回复")
            || lowered.hasPrefix("suggested reply") || lowered.hasPrefix("reply")
    }
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
        // 模型有时不省略，而是写一句"（此段省略）""(omitted)"占位，这种段落不显示
        return sections.filter { !isPlaceholder($0.body) }
    }

    private static func isPlaceholder(_ body: String) -> Bool {
        guard body.count < 60 else { return false }
        let lowered = body.lowercased()
        return body.contains("省略") || lowered.contains("omitted") || lowered.contains("not applicable")
            || body == "—" || body == "-" || lowered == "n/a"
    }

    /// 第一段可以复制的回复
    static func firstReply(_ text: String) -> ReplySection? {
        sections(text).first { $0.isCopyable && !$0.body.isEmpty }
    }
}
