import SwiftUI

/// 示例数据：外观设置里的实时预览、--render-preview 都用它。
@MainActor
enum SampleData {
    static func rows() -> [Utterance] {
        func row(_ channel: Channel, _ speaker: Int?, _ text: String, _ translation: String?, pending: String = "",
                 at minute: Int, _ second: Int) -> Utterance {
            var row = Utterance(channel: channel, speaker: speaker, language: "en")
            row.text = text
            row.pending = pending
            row.translation = translation
            row.isClosed = pending.isEmpty
            let time = Calendar.current.date(bySettingHour: 10, minute: minute, second: second, of: .now) ?? .now
            return Utterance(copying: row, startedAt: time, updatedAt: time.addingTimeInterval(4))
        }
        return [
            row(.remote, 1, "Thanks for joining, Sarah. We reviewed the Northwind proposal last week.",
                "谢谢参加，Sarah。我们上周看过了 Northwind 的方案。", at: 2, 5),
            row(.remote, 1, "The budget looks fine at $120,000 for Q4.", "第四季度 12 万美元的预算看起来没问题。", at: 2, 12),
            row(.local, 1, "Great, happy to walk through the timeline.", "好的，我很乐意过一遍时间安排。", at: 2, 20),
            row(.remote, 2, "Could we move the launch to the second week of December, or is that too tight for your team?",
                "我们能把上线推到十二月第二周吗？还是对你们团队来说太紧了？", at: 2, 31),
            row(.remote, 2, "Also, what's the status of the", nil, pending: "billing integration", at: 2, 44),
        ]
    }

    static func meetingReply() -> Reply {
        var reply = Reply(target: "选中的 1 句")
        reply.text = """
        【对方的意思】问能不能把上线推到 12 月第二周，以及这个时间对我们是否太紧。
        【建议回复】The second week of December works for us. We'd just need the final specs by November 20th to stay on track.
        【中文对照】12 月第二周可以。我们需要在 11 月 20 日前拿到最终需求，才能按期完成。
        """
        reply.isStreaming = false
        return reply
    }

    static func screenshotReply(thumbnail: Data?) -> Reply {
        var reply = Reply(target: "截图 · Microsoft Teams")
        reply.source = "screenshot"
        reply.thumbnail = thumbnail
        reply.copiedSection = "回复 1 · 推荐"
        reply.isStreaming = false
        reply.text = """
        【场景】Teams 里 David 问你周五前能不能把评审意见发给他，他要在周一的会上用。
        【回复 1 · 推荐】Hi David, yes — I'll send the review notes by Thursday EOD so you have time to go through them before Monday.
        【回复 2 · 追问细节】Sure. Do you need comments on the whole deck, or just the pricing section?
        【回复 3 · 推迟】Friday is tight on my side. Would Monday morning still work for your meeting?
        """
        return reply
    }

    /// 一个填好示例的会话（不读写文件）
    static func session(settings: SettingsStore) -> SessionModel {
        let session = SessionModel(settings: settings, skills: SkillStore(), persists: false)
        let rows = rows()
        session.showSample(rows: rows, replies: [meetingReply()], selection: [rows[3].id])
        session.speakerNames["local:1"] = "我"
        session.keywords = "launch, budget"
        return session
    }
}

/// 模拟会议软件的视频画面，用来看悬浮窗透明的效果
struct SampleBackdrop: View {
    /// 浅色：模拟白底的聊天窗口、文档，用来检查悬浮窗盖在亮画面上的对比度
    var light = false

    var body: some View {
        if light { lightPage } else { meeting }
    }

    private var lightPage: some View {
        let line = Color(white: 0.55)
        return VStack(alignment: .leading, spacing: 14) {
            RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.88)).frame(height: 44)
            ForEach(0..<7, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(Color(white: index.isMultiple(of: 2) ? 0.78 : 0.70)).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(line).frame(width: 120, height: 8)
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.30)).frame(width: index.isMultiple(of: 3) ? 420 : 300, height: 9)
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.30)).frame(width: 220, height: 9)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(white: index.isMultiple(of: 2) ? 0.93 : 0.97)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }

    private var meeting: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.32, green: 0.26, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.95, green: 0.72, blue: 0.55)).frame(width: 220).offset(x: -120, y: -150)
            Circle().fill(Color(red: 0.30, green: 0.55, blue: 0.85)).frame(width: 260).offset(x: 160, y: 120)
            RoundedRectangle(cornerRadius: 30).fill(Color(red: 0.85, green: 0.85, blue: 0.88)).frame(width: 300, height: 140)
                .offset(x: 40, y: -30)
            Circle().fill(Color(red: 0.45, green: 0.75, blue: 0.55)).frame(width: 140).offset(x: -150, y: 220)
        }
        .clipped()
    }
}
