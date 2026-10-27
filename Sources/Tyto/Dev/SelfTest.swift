@preconcurrency import AVFAudio
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// 命令行自测，不用开会也能检查识别、翻译、回复：
///   Tyto --selftest-speech <音频文件> [--locale en-US] [--target zh-Hans]   本机识别 + 本机翻译
///   Tyto --selftest-reply                                                  用设置里的大模型生成一条回复
///   Tyto --selftest-echo                                                   去回声的判断（回声要去掉，复述要保留）
///   Tyto --selftest-screenshot <图片> [--instruction 要求]                   截屏回复：本机 OCR + 大模型
///   Tyto --render-preview <文件夹>                                         用示例数据把悬浮窗画成图片（不碰屏幕）
enum SelfTest {
    @MainActor
    static func runIfRequested(settings: SettingsStore) -> Bool {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        if let file = value(after: "--selftest-speech") {
            let locale = value(after: "--locale") ?? "en-US"
            let target = value(after: "--target") ?? "zh-Hans"
            Task { exit(await speech(file: file, locale: locale, target: target)) }
            return true
        }
        if let file = value(after: "--selftest-screenshot") {
            let instruction = value(after: "--instruction")
            let current = settings.value
            Task { exit(await screenshot(file: file, instruction: instruction, settings: current)) }
            return true
        }
        if let path = value(after: "--render-preview") {
            exit(renderPreview(to: path, settings: SettingsStore(persists: false)))
        }
        if arguments.contains("--selftest-echo") {
            exit(echo())
        }
        if arguments.contains("--selftest-reply") {
            let current = settings.value
            Task { exit(await reply(current)) }
            return true
        }
        return false
    }

    static func speech(file: String, locale: String, target: String) async -> Int32 {
        print("本机识别：\(file)（\(locale)）")
        let engine = AppleSpeechEngine(locale: locale)
        do {
            try await engine.start()
        } catch {
            print("识别没启动：\(error.localizedDescription)")
            return 1
        }
        let collector = Task { () -> [String] in
            var finals: [String] = []
            for await event in engine.events {
                switch event.kind {
                case .final:
                    print("  确定：\(event.text)")
                    finals.append(event.text)
                case .error:
                    print("  出错：\(event.text)")
                default:
                    break
                }
            }
            return finals
        }

        do {
            let audio = try AVAudioFile(forReading: URL(filePath: file))
            let format = audio.processingFormat
            guard let resampler = Resampler(inputRate: format.sampleRate),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else { return 1 }
            while audio.framePosition < audio.length {
                try audio.read(into: buffer, frameCount: 4_096)
                engine.append(resampler.process(Downmix.mono(buffer)))
            }
        } catch {
            print("读不了音频：\(error.localizedDescription)")
            return 1
        }
        await engine.stop()

        let text = await collector.value.reduce("") { TextJoin.join($0, $1) }
        print("识别结果：\(text)")
        guard !text.isEmpty else { return 1 }

        let source = Locale(identifier: locale).language.languageCode?.identifier
        do {
            let translation = try await AppleTranslator().translate(text, from: source, to: target)
            print("本机翻译（\(target)）：\(translation)")
        } catch {
            print("翻译失败：\(error.localizedDescription)")
            return 2
        }
        return 0
    }

    static func echo() -> Int32 {
        let base = Date.now
        func row(_ channel: Channel, _ text: String, start: Double, end: Double) -> Utterance {
            var row = Utterance(channel: channel, speaker: nil, language: "en")
            row.text = text
            row = Utterance(copying: row, startedAt: base.addingTimeInterval(start), updatedAt: base.addingTimeInterval(end))
            return row
        }
        let question = row(.remote, "Could we move the launch to the second week of December?", start: 0, end: 4)
        let cases: [(String, Utterance, Bool)] = [
            ("外放回声（同时发生、内容相同）",
             row(.local, "Could we move the launch to the second week of December", start: 0.4, end: 4.2), true),
            ("回声识别得不完整", row(.local, "move the launch to the second week of", start: 1.0, end: 3.8), true),
            ("说完之后复述着回话", row(.local, "Yes, the second week of December works.", start: 5.5, end: 7.5), false),
            ("对方说话时插话，内容不同", row(.local, "Sorry, which launch do you mean?", start: 2.0, end: 3.5), false),
            ("太短的应答", row(.local, "December?", start: 1.0, end: 1.5), false),
            ("中文回声", row(.local, "我们能把发布推迟到十二月第二周吗", start: 0.3, end: 3.0), false),
        ]
        var failed = 0
        for (name, local, expected) in cases {
            let remote = name == "中文回声"
                ? [row(.remote, "我们能把发布推迟到十二月第二周吗？", start: 0, end: 3)]
                : [question]
            let expectedHere = name == "中文回声" ? true : expected
            let actual = SessionModel.isEcho(local, remote: remote)
            let ok = actual == expectedHere
            if !ok { failed += 1 }
            print("\(ok ? "✓" : "✗") \(name)：\(actual ? "当成回声去掉" : "保留")")
        }
        print(failed == 0 ? "全部通过" : "\(failed) 个不对")
        return failed == 0 ? 0 : 1
    }

    static func reply(_ settings: AppSettings) async -> Int32 {
        print("大模型：\(settings.llm.provider.rawValue) \(settings.llm.model)")
        let client: LLMClient
        do {
            client = try LLMFactory.make(settings.llm)
        } catch {
            print(error.localizedDescription)
            return 1
        }
        var rows: [Utterance] = []
        for (channel, speaker, text) in [
            (Channel.remote, 1, "Thanks for joining. We reviewed the proposal last week."),
            (Channel.local, nil, "Sure, happy to walk through it."),
            (Channel.remote, 1, "Could we move the launch to the second week of December, or is that too tight for your team?"),
        ] as [(Channel, Int?, String)] {
            var row = Utterance(channel: channel, speaker: speaker, language: "en")
            row.text = text
            row.isClosed = true
            rows.append(row)
        }
        let prompt = ReplyPrompt(settings: settings, title: "自测", context: "和供应商讨论新版本的上线时间，我是项目负责人。",
                                 skills: SkillStore.seeds.prefix(1).map { $0 }, rows: rows,
                                 targets: [rows[2].id], label: { $0.channel.label })
        do {
            for try await chunk in client.stream(system: prompt.system, user: prompt.user, maxTokens: 16_000) {
                print(chunk, terminator: "")
            }
            print()
            return 0
        } catch {
            print("\n出错：\(error.localizedDescription)")
            return 1
        }
    }

    /// 用示例数据把悬浮窗画成 PNG，检查排版（不截屏）。每个主题一张会议字幕，再加一张截屏回复。
    @MainActor
    static func renderPreview(to folder: String, settings: SettingsStore) -> Int32 {
        let session = SessionModel(settings: settings, skills: SkillStore(), persists: false)
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
        let rows = [
            row(.remote, 1, "Thanks for joining, Sarah. We reviewed the Northwind proposal last week.",
                "谢谢参加，Sarah。我们上周看过了 Northwind 的方案。", at: 2, 5),
            row(.remote, 1, "The budget looks fine at $120,000 for Q4.", "第四季度 12 万美元的预算看起来没问题。", at: 2, 12),
            row(.local, 1, "Great, happy to walk through the timeline.", "好的，我很乐意过一遍时间安排。", at: 2, 20),
            row(.remote, 2, "Could we move the launch to the second week of December, or is that too tight for your team?",
                "我们能把上线推到十二月第二周吗？还是对你们团队来说太紧了？", at: 2, 31),
            row(.remote, 2, "Also, what's the status of the", nil, pending: "billing integration", at: 2, 44),
        ]
        var meetingReply = Reply(target: "选中的 1 句")
        meetingReply.text = """
        【对方的意思】问能不能把上线推到 12 月第二周，以及这个时间对我们是否太紧。
        【建议回复】The second week of December works for us. We'd just need the final specs by November 20th to stay on track.
        【中文对照】12 月第二周可以。我们需要在 11 月 20 日前拿到最终需求，才能按期完成。
        """
        meetingReply.isStreaming = false

        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        session.speakerNames["local:1"] = "我"
        session.keywords = "launch, budget"

        for theme in ThemeID.allCases {
            settings.value.theme = theme
            settings.value.overlayOpacity = AppSettings().overlayOpacity
            session.showSample(rows: rows, replies: [meetingReply], selection: [rows[3].id])
            guard render(session: session, settings: settings, to: folderURL.appending(path: "overlay-\(theme.rawValue).png"))
            else { return 1 }
        }

        settings.value.theme = .obsidian
        var shot = Reply(target: "截图")
        shot.source = "screenshot"
        shot.thumbnail = sampleThumbnail()
        shot.copiedSection = "回复 1 · 推荐"
        shot.isStreaming = false
        shot.text = """
        【场景】Teams 里 David 问你周五前能不能把评审意见发给他，他要在周一的会上用。
        【回复 1 · 推荐】Hi David, yes — I'll send the review notes by Thursday EOD so you have time to go through them before Monday.
        【回复 2 · 追问细节】Sure. Do you need comments on the whole deck, or just the pricing section?
        【回复 3 · 推迟】Friday is tight on my side. Would Monday morning still work for your meeting?
        """
        session.showSample(rows: [], replies: [shot], selection: [])
        return render(session: session, settings: settings, to: folderURL.appending(path: "screenshot-reply.png")) ? 0 : 1
    }

    /// 悬浮窗画在一张模拟的视频会议画面上，玻璃用"模糊后的背景 + 主题底色"近似
    @MainActor
    private static func render(session: SessionModel, settings: SettingsStore, to url: URL) -> Bool {
        let size = CGSize(width: 480, height: 600)
        let backdrop = PreviewBackdrop()
        let view = ZStack {
            backdrop
            backdrop.blur(radius: 26)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            OverlayView(session: session, settings: settings, ui: OverlayState(), flatForPreview: true)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width + 80, height: size.height + 80)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("画不出来")
            return false
        }
        do {
            try ImageFile.writePNG(image, to: url)
            print(url.path)
            return true
        } catch {
            print("存不了：\(error.localizedDescription)")
            return false
        }
    }

    @MainActor
    private static func sampleThumbnail() -> Data? {
        let view = VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.36, green: 0.36, blue: 0.78)).frame(width: 90, height: 14)
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.85)).frame(width: 120, height: 14)
            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.85)).frame(width: 70, height: 14)
        }
        .padding(12)
        .frame(width: 160, height: 160)
        .background(Color(red: 0.94, green: 0.94, blue: 0.97))
        guard let image = ImageRenderer(content: view).cgImage else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// 截屏回复自测：本机 OCR，再用设置里的大模型生成回复
    ///   Tyto --selftest-screenshot <图片> [--instruction "婉拒"]
    @MainActor
    static func screenshot(file: String, instruction: String?, settings: AppSettings) async -> Int32 {
        guard let png = try? Data(contentsOf: URL(filePath: file)) else {
            print("读不了图片")
            return 1
        }
        let started = Date.now
        let lines = await Screenshot.recognizeText(png)
        print("本机 OCR：\(lines.count) 行，\(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
        let layout = Screenshot.layoutText(lines)
        print(layout)
        let client: LLMClient
        do {
            client = try LLMFactory.make(settings.llm)
        } catch {
            print(error.localizedDescription)
            return 2
        }
        let withImage = settings.screenshotMode == .imageAndText
        let prompt = ScreenshotPrompt(settings: settings, context: "", skills: [], ocr: layout,
                                      imageAttached: withImage, instruction: instruction)
        print("\n大模型：\(settings.llm.model)，\(withImage ? "图片 + OCR 文字" : "只有 OCR 文字")")
        var text = ""
        do {
            for try await chunk in client.stream(system: prompt.system, user: prompt.user,
                                                 images: withImage ? [Screenshot.forModel(png)] : [], maxTokens: 16_000) {
                text += chunk
            }
        } catch {
            print("出错：\(error.localizedDescription)")
            return 1
        }
        for section in ReplyFormat.sections(text) {
            print("[\(section.title)\(section.isCopyable ? "，可复制" : "")] \(section.body)")
        }
        print("会放进剪贴板的：\(ReplyFormat.firstReply(text)?.title ?? "（没有）")")
        return 0
    }
}

/// 预览用的背景：模拟会议软件的视频画面
private struct PreviewBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.30), Color(red: 0.32, green: 0.26, blue: 0.24)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Color(red: 0.95, green: 0.72, blue: 0.55)).frame(width: 220).offset(x: -120, y: -150)
            Circle().fill(Color(red: 0.30, green: 0.55, blue: 0.85)).frame(width: 260).offset(x: 160, y: 120)
            RoundedRectangle(cornerRadius: 30).fill(Color(red: 0.85, green: 0.85, blue: 0.88)).frame(width: 300, height: 140)
                .offset(x: 40, y: -30)
            Circle().fill(Color(red: 0.45, green: 0.75, blue: 0.55)).frame(width: 140).offset(x: -150, y: 220)
        }
    }
}

enum ImageFile {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw TytoError.server("存不了图片") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TytoError.server("存不了图片") }
    }
}
