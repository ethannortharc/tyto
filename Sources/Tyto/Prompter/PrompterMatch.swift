import Foundation

/// 提词器的定位，全在本机算：
/// - 跟读：我最近说的话最像稿子里的哪一段，就滚到那一段；
/// - 提示：对方说的话提到了稿子里的哪一节，提示跳过去。
/// 按词重合比较：英文按词（去掉常见虚词、简单去掉词尾），中日韩按相邻两个字（单个字区分不开段落）。
enum PrompterMatch {
    /// 稿子里的一段（网页里的一个段落、列表项、表格行、标题……）
    struct Block: Equatable, Sendable {
        let index: Int
        /// 标题级别 1～6；正文为 0
        let level: Int
        let text: String
    }

    /// 一节：从一个标题到下一个同样参与目录的标题
    struct Section: Equatable, Sendable {
        /// 标题那一段的编号
        let heading: Int
        let title: String
        let level: Int
        /// 这一节包含的段（含标题）
        let blocks: Range<Int>
    }

    // MARK: - 目录

    /// 目录用哪几级标题：文中最高的两级；最高一级只有一个时它是文档标题，往下顺一级
    static func sections(_ blocks: [Block]) -> [Section] {
        let levels = Set(blocks.map(\.level).filter { $0 > 0 }).sorted()
        guard var top = levels.first else { return [] }
        if blocks.filter({ $0.level == top }).count == 1, levels.count > 1 { top = levels[1] }
        let used = Set(levels.filter { $0 >= top }.prefix(2))
        let headings = blocks.filter { used.contains($0.level) }
        return headings.enumerated().map { offset, heading in
            let end = offset + 1 < headings.count ? headings[offset + 1].index : blocks.count
            return Section(heading: heading.index, title: heading.text, level: heading.level, blocks: heading.index..<end)
        }
    }

    /// 某一段属于哪一节（第一个标题之前的段不属于任何一节）
    static func section(containing block: Int, in sections: [Section]) -> Int? {
        sections.lastIndex { $0.heading <= block }
    }

    // MARK: - 索引

    /// 一份材料的索引：每段的词、每个词出现在几段里。载入时算一次，跟读时每次只算我说的那几个词
    struct Index {
        let blocks: [Block]
        let sections: [Section]
        let terms: [Set<String>]
        /// 词 → 出现在几段里
        let frequency: [String: Int]

        init(_ blocks: [Block]) {
            self.blocks = blocks
            sections = PrompterMatch.sections(blocks)
            terms = blocks.map { Set(PrompterMatch.terms($0.text)) }
            var frequency: [String: Int] = [:]
            for set in terms { for term in set { frequency[term, default: 0] += 1 } }
            self.frequency = frequency
        }

        /// 越少段落用到的词越说明问题（"产品""方案"这种到处都有的词分量轻）
        func weight(_ term: String) -> Double {
            log(1 + Double(blocks.count) / Double(frequency[term] ?? 1))
        }

        // MARK: 跟读

        /// 我最近说的话最像哪一段。只看最近说的、稿子里有的 12 个词，越近的分量越重；
        /// 一段的得分 = 这些词有多少落在这一段里（按分量算，0～1）。
        /// current 是现在高亮的那段：照着稿子往下讲是常态，紧跟在后面的几段加分，往回跳要更像才算
        func follow(said: String, current: Int?) -> Int? {
            let window = Array(PrompterMatch.terms(said).filter { frequency[$0] != nil }.suffix(12))
            guard Set(window).count >= 3 else { return nil }
            // 越近越重：最早的 0.5，最近的 1
            var wanted: [String: Double] = [:]
            for (offset, term) in window.enumerated() {
                let recency = 0.5 + 0.5 * Double(offset + 1) / Double(window.count)
                wanted[term] = max(wanted[term] ?? 0, recency * weight(term))
            }
            let total = wanted.values.reduce(0, +)
            var scores: [(index: Int, score: Double)] = []
            for block in blocks where block.level == 0 {
                let own = terms[block.index]
                let shared = own.filter { wanted[$0] != nil }
                // 短的段（列表项）至少对上两个词，长的至少三个
                guard shared.count >= min(3, max(2, own.count - 1)) else { continue }
                var score = shared.reduce(0) { $0 + wanted[$1]! } / total
                if let current {
                    let step = block.index - current
                    if (0...3).contains(step) { score += 0.1 } else if step < 0 { score -= 0.05 }
                }
                scores.append((block.index, score))
            }
            scores.sort { $0.score > $1.score }
            guard let best = scores.first, best.score >= 0.55 else { return nil }
            // 两段差不多像时不动，免得来回跳
            if scores.count > 1, best.score - scores[1].score < 0.12 { return nil }
            return best.index
        }

        // MARK: 对方提到

        /// 对方这句话提到了哪一节（返回节的序号）。标题里的词对上分量加倍；
        /// 没对上标题时正文至少要对上 3 个词；最像的一节要明显比第二像的高，才提示
        func suggest(heard: String, excluding current: Int?) -> Int? {
            let asked = Set(PrompterMatch.terms(heard)).filter { frequency[$0] != nil }
            guard !asked.isEmpty, sections.count >= 2 else { return nil }
            var scores: [(section: Int, score: Double)] = []
            for (index, section) in sections.enumerated() {
                let title = terms[section.heading]
                let body = section.blocks.dropFirst().reduce(into: Set<String>()) { $0.formUnion(terms[$1]) }
                let titleHits = asked.intersection(title)
                let bodyHits = asked.intersection(body).subtracting(titleHits)
                guard !titleHits.isEmpty || bodyHits.count >= 3 else { continue }
                let score = titleHits.reduce(0) { $0 + 2 * weight($1) } + bodyHits.reduce(0) { $0 + weight($1) }
                scores.append((index, score))
            }
            scores.sort { $0.score > $1.score }
            guard let best = scores.first, best.score >= 2.5 else { return nil }
            if scores.count > 1, best.score < scores[1].score * 1.3 { return nil }
            return best.section == current ? nil : best.section
        }
    }

    // MARK: - 分词

    /// 比较用的词：英文小写、去虚词、去词尾；中日韩相邻两个字一组（含虚词的组不要），孤零零一个字就用这个字
    static func terms(_ text: String) -> [String] {
        var result: [String] = []
        var word = ""
        var run: [Character] = []
        func flushWord() {
            defer { word = "" }
            guard !word.isEmpty, !stopWords.contains(word) else { return }
            let stemmed = stem(word)
            let numeric = stemmed.allSatisfy(\.isNumber)
            guard stemmed.count >= 2 || (numeric && !stemmed.isEmpty), !stopWords.contains(stemmed) else { return }
            result.append(stemmed)
        }
        func flushRun() {
            defer { run = [] }
            if run.count == 1 {
                if !stopCharacters.contains(run[0]) { result.append(String(run[0])) }
                return
            }
            for index in run.indices.dropLast() {
                let pair = (run[index], run[index + 1])
                if stopCharacters.contains(pair.0) || stopCharacters.contains(pair.1) { continue }
                result.append(String([pair.0, pair.1]))
            }
        }
        for scalar in text.lowercased().unicodeScalars {
            if isCJK(scalar) {
                flushWord()
                run.append(Character(scalar))
            } else if CharacterSet.alphanumerics.contains(scalar) || scalar == "'" {
                flushRun()
                word.unicodeScalars.append(scalar)
            } else {
                flushWord()
                flushRun()
            }
        }
        flushWord()
        flushRun()
        return result
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
            || (0x3040...0x30FF).contains(scalar.value) || (0xAC00...0xD7AF).contains(scalar.value)
    }

    /// 很粗的英文去词尾：pricing / prices / priced → pric，plans → plan
    static func stem(_ word: String) -> String {
        var stem = word
        if stem.hasSuffix("'s") { stem.removeLast(2) }
        if stem.count > 4, stem.hasSuffix("ies") { return String(stem.dropLast(3)) + "y" }
        for suffix in ["ing", "ed", "es", "s"] where stem.count > suffix.count + 2 && stem.hasSuffix(suffix) {
            if suffix == "s", stem.hasSuffix("ss") { break }
            stem.removeLast(suffix.count)
            break
        }
        if stem.count > 3, stem.hasSuffix("e") { stem.removeLast() }
        return stem
    }

    private static let stopWords: Set<String> = [
        "the", "a", "an", "to", "of", "and", "or", "in", "on", "for", "at", "by", "with", "from", "as", "into", "about",
        "is", "are", "was", "were", "be", "been", "being", "am", "has", "have", "had", "having",
        "it", "its", "it's", "that", "this", "these", "those", "there", "here", "then", "than",
        "i", "we", "you", "he", "she", "they", "me", "us", "him", "her", "them", "my", "our", "your", "their",
        "i'm", "we're", "you're", "they're", "i'll", "we'll", "you'll", "i've", "we've", "don't", "doesn't", "didn't",
        "so", "just", "but", "do", "does", "did", "can", "will", "would", "could", "should", "may", "might", "must",
        "what", "what's", "how", "why", "when", "where", "which", "who", "whom",
        "yes", "no", "not", "ok", "okay", "yeah", "right", "well", "also", "very", "really", "more", "some", "any",
        "all", "if", "like", "get", "got", "go", "going", "know", "think", "tell", "please", "thank", "thanks",
        "one", "out", "up", "now", "let", "let's", "say", "said", "see", "want", "need", "make",
    ]

    /// 只放纯虚字：含"上""会""对"的词（上线、会议、对比）都有意思，不能丢
    private static let stopCharacters: Set<Character> = [
        "的", "了", "是", "我", "你", "他", "她", "们", "在", "就", "也", "都", "和", "吧", "啊", "呢", "吗",
        "嗯", "哦", "这", "那", "个", "很", "把", "被", "着", "过", "还",
    ]
}
