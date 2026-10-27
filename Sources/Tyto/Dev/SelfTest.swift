@preconcurrency import AVFAudio
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// 命令行自测，不用开会也能检查识别、翻译、回复：
///   Tyto --selftest-speech <音频文件> [--locale en-US] [--target zh-Hans]   本机识别 + 本机翻译
///   Tyto --selftest-reply                                                  用设置里的大模型生成一条回复
///   Tyto --selftest-echo                                                   去回声的判断（回声要去掉，复述要保留）
///   Tyto --render-preview <png>                                            用示例数据把悬浮窗画成图片（不碰屏幕）
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
        if let path = value(after: "--render-preview") {
            exit(renderPreview(to: path, settings: settings))
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

    /// 用示例数据把悬浮窗画成 PNG，检查排版（不截屏）
    @MainActor
    static func renderPreview(to path: String, settings: SettingsStore) -> Int32 {
        let session = SessionModel(settings: settings, skills: SkillStore())
        func row(_ channel: Channel, _ speaker: Int?, _ text: String, _ translation: String?, pending: String = "") -> Utterance {
            var row = Utterance(channel: channel, speaker: speaker, language: "en")
            row.text = text
            row.pending = pending
            row.translation = translation
            row.isClosed = pending.isEmpty
            return row
        }
        let rows = [
            row(.remote, 1, "Thanks for joining. We reviewed your proposal last week.", "感谢参加。我们上周看过了你们的方案。"),
            row(.local, 1, "Sure, happy to walk through the timeline.", "好的，我很乐意过一遍时间安排。"),
            row(.remote, 2, "Could we move the launch to the second week of December, or is that too tight for your team?",
                "我们能把发布推迟到十二月第二周吗？还是说这对你们团队来说太紧了？"),
            row(.remote, 1, "Also, what's the status of the", nil, pending: "billing integration"),
        ]
        var reply = Reply(target: "选中的 1 句")
        reply.text = "**对方的意思**：问能不能把发布推到 12 月第二周，以及这个时间对我们是否太紧。\n**建议回复**：December second week works for us. We'd need the final specs by November 20th to stay on track.\n**中文对照**：12 月第二周可以。我们需要在 11 月 20 日前拿到最终需求，才能按期完成。"
        reply.isStreaming = false
        session.showSample(rows: rows, replies: [reply], selection: [rows[2].id])
        session.speakerNames["local:1"] = "我"

        let view = OverlayView(session: session, settings: settings, ui: OverlayState(), openMain: {}, hide: {},
                               flatForPreview: true)
            .frame(width: 520, height: 640)
            .background(Color(white: 0.85))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            print("画不出来")
            return 1
        }
        do {
            try ImageFile.writePNG(image, to: URL(filePath: path))
        } catch {
            print("存不了：\(error.localizedDescription)")
            return 1
        }
        print(path)
        return 0
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
