import Foundation

/// 生成回复建议的提示词：会议背景 + 勾选的技能 + 会议记录（标出要回复的话）。
struct ReplyPrompt {
    let system: String
    let user: String

    init(settings: AppSettings, title: String, context: String, skills: [Skill],
         rows: [Utterance], targets: Set<UUID>, label: (Utterance) -> String) {
        let replyLanguage: String
        if settings.replyLanguage.trimmingCharacters(in: .whitespaces).isEmpty {
            let spoken = rows.filter { targets.contains($0.id) }
                .compactMap { $0.language ?? Languages.detect($0.text) }
                .first
            replyLanguage = spoken.map { "对方说话的语言（\(Languages.name($0))）" } ?? "对方说话的语言"
        } else {
            replyLanguage = settings.replyLanguage
        }
        let explain = settings.explainLanguage

        let background = context.trimmingCharacters(in: .whitespacesAndNewlines)
        var system = """
        你是我开会时的私人助手，只有我能看到你的输出。会议记录来自实时语音识别，可能有错字、漏词、断句不准，要结合上下文理解。
        "远端"是会议软件里传来的声音，"本地"是我这边麦克风收到的声音（我和会议室里的人）。

        ## 这场会议
        名称：\(title.isEmpty ? "（未命名）" : title)
        背景：
        \(background.isEmpty ? "（没有填写）" : background)
        """
        if !skills.isEmpty {
            system += "\n\n## 回复时要遵循的技能\n"
            for skill in skills {
                system += "\n### \(skill.name)\n\(skill.body)\n"
            }
        }
        system += """


        ## 输出格式
        简短，能直接照着说。严格按下面三段输出，不要别的开场白：
        **对方的意思**：用\(explain)一两句话说清对方在问什么、要什么。
        **建议回复**：用\(replyLanguage)写可以直接说出口的回复，口语化，2～4 句。
        **\(explain)对照**：上面这段回复的意思。
        如果信息不够、或者对方的话识别得不完整，"建议回复"就写一个得体的追问。
        """
        self.system = system

        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        for row in rows {
            let text = row.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let mark = targets.contains(row.id) ? "▶ " : ""
            lines.append("\(mark)[\(formatter.string(from: row.startedAt))] \(label(row))：\(text)")
        }
        user = """
        会议记录（按时间顺序，最新的在最后；▶ 标出的是要回复的话）：

        \(lines.joined(separator: "\n"))

        请针对 ▶ 标出的话给出建议回复。
        """
    }
}
