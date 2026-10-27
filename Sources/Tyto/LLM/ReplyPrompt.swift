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
        简短，能直接照着说。严格按下面三段输出，每段以【标题】开头，不要别的开场白：
        【对方的意思】用\(explain)一两句话说清对方在问什么、要什么。
        【建议回复】用\(replyLanguage)写可以直接说出口的回复，口语化，2～4 句，不加引号。
        【\(explain)对照】上面这段回复的意思。
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

/// 截屏回复的提示词：看懂截图里的聊天或邮件，给几个能直接粘贴发送的回复。
struct ScreenshotPrompt {
    let system: String
    let user: String

    /// - source: 截图来自哪个 App，如 "Microsoft Teams"
    init(settings: AppSettings, context: String, skills: [Skill], source: String?, ocr: String, imageAttached: Bool,
         instruction: String?) {
        var system = """
        你是我的回复助手，只有我能看到你的输出。我截了一张屏幕，通常是 Teams、Slack、飞书、微信里的聊天，或者一封邮件。
        你要看懂：这是哪里的什么对话、谁在跟我说话、最新一条需要我回应的是什么；然后写好可以直接粘贴发送的回复。
        聊天截图里，通常右边的（或者标着"我"、我的名字的）是我发的，左边的是别人发的。
        """
        let background = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !background.isEmpty {
            system += "\n\n## 我这边的背景（相关时参考，不相关就忽略）\n\(background)"
        }
        if !skills.isEmpty {
            system += "\n\n## 回复时要遵循的技能\n"
            for skill in skills { system += "\n### \(skill.name)\n\(skill.body)\n" }
        }
        let explain = settings.explainLanguage
        let language = settings.replyLanguage.trimmingCharacters(in: .whitespaces).isEmpty
            ? "对方使用的语言" : settings.replyLanguage
        system += """


        ## 输出格式
        严格按下面的格式，每段以【标题】开头，不要别的开场白：
        【场景】用\(explain)一句话：这是哪里的什么对话，对方是谁，要我做什么。
        【回复 1 · 推荐】最合适的回复，可以直接粘贴发送。
        【回复 2 · 取向】换一种取向，标题里写明取向（比如：更简短、追问细节）。
        【回复 3 · 取向】再换一种（比如：婉拒、推迟、需要先确认）。
        回复用\(language)。聊天回复口语、简短；邮件回复要有称呼和落款，落款写"[我的名字]"。回复正文不加引号、不加解释。
        """
        self.system = system

        var user = imageAttached ? "截图在上面。" : "（没有发图片，只有识别出的文字。）"
        if let source { user += "\n截图来自：\(source)。" }
        if !ocr.isEmpty {
            user += "\n\n截图里识别出的文字（[左]/[右] 表示在截图的左半边还是右半边，用来核对人名、数字）：\n\(ocr)"
        }
        if let instruction, !instruction.trimmingCharacters(in: .whitespaces).isEmpty {
            user += "\n\n我的要求：\(instruction)"
        }
        user += "\n\n请按格式给出回复。"
        self.user = user
    }
}

/// "先用看图模型读图"时，让看图模型把截图整理成文字（不写回复）。
struct VisionPrompt {
    let system: String
    let user: String

    init(model: String, source: String?) {
        // 专门转文字的 OCR 模型对提示很敏感，用它们自己的固定说法
        let lowered = model.lowercased()
        if lowered.contains("ocr") {
            system = ""
            user = lowered.contains("deepseek") ? "Free OCR." : "Text Recognition:"
            return
        }
        system = "你把屏幕截图整理成文字，交给另一个助手去写回复。只整理看到的内容，不要回复，不要编造，看不清的写「?」。"
        user = """
        \(source.map { "截图来自 \($0)。\n" } ?? "")按下面的格式整理：
        应用和页面：哪个 App、什么页面（聊天、群聊、邮件……）
        内容：按时间顺序，每条一行「发送人（时间）：内容」。我发的（通常在右边）发送人写「我」。邮件写出发件人、收件人、主题和正文。
        其他：附件、引用的消息、表情回应等要点。
        """
    }
}
