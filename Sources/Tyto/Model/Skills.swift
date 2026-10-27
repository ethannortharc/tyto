import AppKit
import Foundation

/// 技能：一份写给大模型的做法说明（Markdown），生成回复时按会话里勾选的技能带上。
/// 存在 ~/Library/Application Support/Tyto/skills/*.md，开头是 name / description。
struct Skill: Identifiable, Equatable {
    /// 文件名（不含 .md）
    let id: String
    var name: String
    var description: String
    var body: String

    var fileText: String {
        "---\nname: \(name)\ndescription: \(description)\n---\n\n\(body.trimmingCharacters(in: .whitespacesAndNewlines))\n"
    }

    static func parse(id: String, text: String) -> Skill {
        var name = id
        var description = ""
        var body = text
        if text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 4)..<text.endIndex) {
            let header = text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound]
            for line in header.split(separator: "\n") {
                let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2 else { continue }
                if parts[0] == "name" { name = parts[1] }
                if parts[0] == "description" { description = parts[1] }
            }
            body = String(text[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return Skill(id: id, name: name, description: description, body: body)
    }
}

@MainActor
final class SkillStore: ObservableObject {
    @Published private(set) var skills: [Skill] = []

    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Tyto/skills") }

    init() {
        seedIfEmpty()
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.folder, includingPropertiesForKeys: nil)) ?? []
        skills = files.filter { $0.pathExtension == "md" }
            .compactMap { url in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                return Skill.parse(id: url.deletingPathExtension().lastPathComponent, text: text)
            }
            .sorted { $0.id < $1.id }
    }

    func save(_ skill: Skill) {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? skill.fileText.write(to: Self.folder.appending(path: "\(skill.id).md"), atomically: true, encoding: .utf8)
        reload()
    }

    func create() -> Skill {
        var number = 1
        while skills.contains(where: { $0.id == "skill-\(number)" }) { number += 1 }
        let skill = Skill(id: "skill-\(number)", name: tr("新技能", "New Skill"), description: tr("什么时候用这个技能", "When to use this skill"),
                          body: tr("写给大模型的做法说明：回复时要注意什么、用什么语气、有哪些固定的说法。", "Instructions for the model: what to watch for in replies, what tone to use, and any set phrases."))
        save(skill)
        return skill
    }

    func delete(_ skill: Skill) {
        try? FileManager.default.removeItem(at: Self.folder.appending(path: "\(skill.id).md"))
        reload()
    }

    func openFolder() {
        NSWorkspace.shared.open(Self.folder)
    }

    private func seedIfEmpty() {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        guard !existing.contains(where: { $0.hasSuffix(".md") }) else { return }
        for skill in Self.seeds { save(skill) }
    }

    /// 第一次打开时放进技能文件夹的几个技能，按当时的界面语言写（之后就是用户自己的文件，不再跟着语言变）
    nonisolated static var seeds: [Skill] {
        [
            Skill(id: "01-general", name: tr("通用会议回复", "General Meeting Reply"),
                  description: tr("默认技能：简短、礼貌、推动会议往前走", "Default: short, polite, moves the meeting forward"),
                  body: tr("""
                  - 先直接回答对方的问题，再补一句理由或下一步。
                  - 口语化，句子短，适合当场说出口；不要书面腔、不要客套堆砌。
                  - 不确定的事不要替我承诺，用"我确认一下，会后回复你"这类说法。
                  - 对方提了要求或期限时，复述一遍关键点（谁、做什么、什么时候），避免误解。
                  """, """
                  - Answer their question first, then add one reason or next step.
                  - Conversational and short, easy to say on the spot; no stiff or padded phrasing.
                  - Don't commit on my behalf when unsure; say something like "Let me check and get back to you after the meeting."
                  - When they set a request or a deadline, restate the key points (who, what, by when) to avoid misunderstandings.
                  """)),
            Skill(id: "02-clarify", name: tr("没听清时追问", "Clarify When Unclear"),
                  description: tr("识别结果不完整或意思含糊时，给出得体的追问", "When the transcript is incomplete or ambiguous, ask a good follow-up"),
                  body: tr("""
                  - 如果对方的话在记录里不完整、有明显识别错误，或者有两种以上的理解，先给一句追问，而不是硬答。
                  - 追问要具体：指出没听清的是哪一部分（数字、名字、日期、范围），让对方只需补那一点。
                  - 常用说法：Sorry, could you repeat the part about …? / Just to make sure I understand, do you mean … or …?
                  """, """
                  - If their words are cut off in the transcript, clearly misrecognized, or could mean two things, ask a follow-up instead of guessing.
                  - Be specific about what was missed (a number, a name, a date, the scope) so they only need to fill in that part.
                  - Useful phrases: "Sorry, could you repeat the part about …?" / "Just to make sure I understand, do you mean … or …?"
                  """)),
            Skill(id: "03-technical", name: tr("技术讨论", "Technical Discussion"),
                  description: tr("讨论架构、接口、故障、排期等技术话题时用", "Architecture, APIs, incidents, schedules"),
                  body: tr("""
                  - 用准确的技术词，不要含糊其辞；提到方案时说清取舍（性能、成本、风险、工期）。
                  - 对方问"能不能做"时，回答可行性 + 前提条件 + 大致工作量。
                  - 对方报故障时，先问影响范围和复现条件，再谈原因和修复。
                  """, """
                  - Use precise technical terms; when proposing an approach, state the trade-offs (performance, cost, risk, timeline).
                  - When asked whether something can be done, answer with feasibility, prerequisites and rough effort.
                  - When they report an incident, ask about impact and how to reproduce it before discussing cause and fix.
                  """)),
            Skill(id: "04-business", name: tr("商务沟通", "Business Talks"),
                  description: tr("谈价格、合同、合作范围、交付时间时用", "Pricing, contracts, scope, delivery dates"),
                  body: tr("""
                  - 语气友好但不让步过快；涉及价格、范围、期限的承诺，一律先说"需要内部确认"。
                  - 对方施压时，先确认对方的核心诉求，再给可选方案，而不是直接答应或拒绝。
                  - 会议结尾主动总结共识和待办，并约定下一次沟通的时间。
                  """, """
                  - Stay friendly but don't concede too fast; for any commitment on price, scope or deadlines, say you need to confirm internally first.
                  - Under pressure, confirm their core need first, then offer options rather than agreeing or refusing outright.
                  - At the end, summarize what was agreed and the action items, and set the next check-in.
                  """)),
        ]
    }
}
