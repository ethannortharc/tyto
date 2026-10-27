import Foundation

/// 回复建议之后，我实际说了什么：从字幕里找出来，和建议比一比
struct ReplyFollowUp: Equatable {
    enum Verdict: Equatable {
        /// 基本照着建议说的
        case followed
        /// 回了，但换了说法
        case rephrased
        /// 对方已经接着说别的了，我没回
        case skipped
        /// 还在等我开口
        case waiting

        var label: String {
            switch self {
            case .followed: tr("基本照着说", "Followed")
            case .rephrased: tr("改了说法", "Rephrased")
            case .skipped: tr("没回", "No reply")
            case .waiting: tr("等你开口", "Waiting")
            }
        }
    }

    var rows: [Utterance]
    var verdict: Verdict
    /// 和建议的重合度，0～1（只在回了的时候有意义）
    var overlap: Double

    var text: String { rows.map(\.displayText).reduce("") { TextJoin.join($0, $1) } }
}

enum FollowUp {
    /// 对方说完以后多久还没开口，就算没回
    static let patience: TimeInterval = 120
    /// 对方同一个人接着补充（间隔这么久以内）不算"对方已经说别的了"
    static let sameTurnGap: TimeInterval = 8
    /// 我说完一段停了这么久，后面的话就不算这次回复了（比如接着讲别的事）
    static let pauseEnds: TimeInterval = 15
    static let maxRows = 6

    /// 找"我实际说的"：建议针对的那几句之后，到对方再说别的之前，本地「我」说的话。
    /// - me: 算作"我"的本地说话人；空表示整个本地麦克风
    /// - now: 判断"还在等"还是"没回"用的当前时间
    static func find(for reply: Reply, in rows: [Utterance], me: Set<String>, now: Date = .now) -> ReplyFollowUp? {
        guard !reply.isScreenshot, let ids = reply.targetIDs, !ids.isEmpty else { return nil }
        let wanted = Set(ids)
        let targetIndices = rows.indices.filter { wanted.contains(rows[$0].id) }
        // 只回自己说的话（比如选了自己的几句）时没有"对方"，不比
        guard let lastTarget = targetIndices.last,
              targetIndices.contains(where: { rows[$0].channel == .remote }) else { return nil }
        let anchor = targetIndices.map { rows[$0].updatedAt }.max() ?? rows[lastTarget].updatedAt

        var said: [Utterance] = []
        var lastRemote = rows[lastTarget]
        var movedOn = false
        for row in rows[(lastTarget + 1)...] {
            if row.channel == .local {
                guard me.isEmpty || me.contains(row.speakerKey) else { continue }
                if said.isEmpty, row.startedAt.timeIntervalSince(anchor) > patience { break }
                if let last = said.last, row.startedAt.timeIntervalSince(last.updatedAt) > pauseEnds { break }
                said.append(row)
                if said.count == maxRows { break }
                continue
            }
            if isBackchannel(row) { continue }
            // 对方同一个人紧接着补充，还算同一轮
            if said.isEmpty, row.speakerKey == lastRemote.speakerKey,
               row.startedAt.timeIntervalSince(lastRemote.updatedAt) <= sameTurnGap {
                lastRemote = row
                continue
            }
            movedOn = true
            break
        }

        guard !said.isEmpty else {
            let waiting = !movedOn && now.timeIntervalSince(anchor) <= patience
            return ReplyFollowUp(rows: [], verdict: waiting ? .waiting : .skipped, overlap: 0)
        }
        let suggestion = ReplyFormat.sections(reply.text).first(where: \.isCopyable)?.body ?? reply.text
        let actual = said.map(\.displayText).joined(separator: " ")
        let (overlap, shared) = similarity(suggestion, actual)
        return ReplyFollowUp(rows: said, verdict: overlap >= 0.6 && shared >= 3 ? .followed : .rephrased, overlap: overlap)
    }

    /// "OK""Right""嗯嗯"这类附和，不算对方接着说别的
    static func isBackchannel(_ row: Utterance) -> Bool {
        let text = row.displayText.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return text.count <= 12 && text.split(separator: " ").count <= 3
    }

    /// 重合度：两边共有的词占较短那一边的多少（英文按词，中日韩按字，去掉常见虚词）。
    /// 按较短的一边算，只说了建议的前半句、或者照着说完又补了几句，都算照着说
    static func similarity(_ suggestion: String, _ actual: String) -> (overlap: Double, shared: Int) {
        let wanted = tokens(suggestion)
        let said = tokens(actual)
        guard !wanted.isEmpty, !said.isEmpty else { return (0, 0) }
        let shared = wanted.intersection(said).count
        return (Double(shared) / Double(min(wanted.count, said.count)), shared)
    }

    static func tokens(_ text: String) -> Set<String> {
        var result: Set<String> = []
        var word = ""
        func flush() {
            if !word.isEmpty, !stopWords.contains(word) { result.insert(word) }
            word = ""
        }
        for scalar in text.lowercased().unicodeScalars {
            if (0x4E00...0x9FFF).contains(scalar.value) || (0x3040...0x30FF).contains(scalar.value)
                || (0xAC00...0xD7AF).contains(scalar.value) {
                flush()
                let character = String(scalar)
                if !stopWords.contains(character) { result.insert(character) }
            } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                word.unicodeScalars.append(scalar)
            } else {
                flush()
            }
        }
        flush()
        return result
    }

    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "in", "on", "for", "at", "by", "with", "is", "are", "was", "be",
        "it", "its", "it's", "that", "this", "i", "we", "you", "i'm", "we're", "i'll", "we'll", "so", "just", "but",
        "do", "does", "can", "will", "would", "could", "our", "your", "my", "me", "us", "them", "they", "yes", "ok",
        "的", "了", "是", "我", "你", "们", "在", "就", "也", "都", "和", "吧", "啊", "呢", "吗", "这", "那", "个", "一", "有", "不",
    ]
}
