@preconcurrency import AVFAudio
import ImageIO
import Markdown
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
import Foundation

/// 命令行自测，不用开会也能检查识别、翻译、回复：
///   Tyto --selftest-speech <音频文件> [--locale en-US] [--target zh-Hans]   本机识别 + 本机翻译
///   Tyto --selftest-reply                                                  用设置里的大模型生成一条回复
///   Tyto --selftest-echo                                                   去回声的判断（回声要去掉，复述要保留）
///   Tyto --selftest-screenshot <图片> [--instruction 要求]                   截屏回复：本机 OCR + 大模型
///   Tyto --selftest-capture <frontWindow|screen> [--out 文件]                截图并认出是哪个 App
///   Tyto --selftest-providers <地址>                                      读模型列表、Ollama 检测和下载（对着模拟服务）
///   Tyto --set-key <服务商 id> < key 文件                                  把 key 存进钥匙串
///   Tyto --selftest-models <服务商 id>                                     读这个服务商的模型列表
///   Tyto --selftest-settings                                              读出现在的设置（老设置会被换算），只看不写
///   Tyto --selftest-deepgram                                              Deepgram 返回消息的解析
///   Tyto --selftest-streaming                                             AssemblyAI、ElevenLabs 返回消息的解析
///   Tyto --compare-speech <音频> [--reference 参考稿] [--providers soniox,assemblyai,elevenlabs] [--hints en,zh] [--out 文件夹]
///                                                                         几家实时识别同时听同一段音频，比错字、说话人、延迟、价钱
///   以上自测都可以加 --settings-json '{...}'，临时改设置，不写回
///   Tyto --selftest-glass <文件夹> [--light]                               真实玻璃效果：悬浮窗盖在模拟会议画面（或白底页面）上，只截这两个窗口
///   Tyto --render-settings <文件夹>                                        把设置窗口每一页画成图片（窗口建在屏幕外，不截屏）
///   Tyto --render-preview <文件夹>                                         用示例数据把悬浮窗画成图片（不碰屏幕）
///   Tyto --selftest-followup                                              回复建议之后"我实际说的"：找哪几句、判照着说/改了说法/没回
///   Tyto --selftest-backdrop                                              字色自动：在屏幕上放白底页面和会议画面，量亮度，看选白字还是黑字
enum SelfTest {
    /// 自测期间要一直活着的对象
    @MainActor static var keepAlive: AnyObject?

    @MainActor
    static func runIfRequested(settings: SettingsStore) -> Bool {
        let arguments = CommandLine.arguments
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        setvbuf(stdout, nil, _IOLBF, 0)
        // --settings-json '{...}'：这次自测用的设置盖在现有设置上，不写回
        var current = settings.value
        if let json = value(after: "--settings-json") { current = SettingsStore.overriding(current, with: json) }
        L10n.set(current.language)
        // --set-key <服务商 id>：从标准输入读 key 存进钥匙串（由 Tyto 自己写，以后读的时候不弹授权框）
        if let id = value(after: "--set-key") {
            let key = readLine(strippingNewline: true) ?? ""
            Keychain.set(key, for: "provider.\(id)")
            print(key.isEmpty ? "已删除「\(id)」的 key" : "已保存「\(id)」的 key（\(key.count) 个字符）")
            exit(0)
        }
        if let id = value(after: "--selftest-models") {
            Task { exit(await models(id, settings: current)) }
            return true
        }
        // --selftest-tidy <文件>：把 OCR 模型的原始输出整理成"[左]/[右] 文字"（看 Unlimited-OCR 的坐标换算对不对）
        if let file = value(after: "--selftest-tidy") {
            print(VisionPrompt.tidy((try? String(contentsOfFile: file, encoding: .utf8)) ?? ""))
            exit(0)
        }
        if arguments.contains("--selftest-settings") {
            exit(settingsSummary(current))
        }
        if arguments.contains("--selftest-deepgram") {
            Task { exit(await deepgram()) }
            return true
        }
        if arguments.contains("--selftest-streaming") {
            Task { exit(await streamingParsers()) }
            return true
        }
        if let file = value(after: "--compare-speech") {
            let providers = value(after: "--providers") ?? "soniox,assemblyai,elevenlabs"
            let hints = (value(after: "--hints") ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            Task {
                exit(await SpeechCompare.run(file: file, reference: value(after: "--reference"), providers: providers,
                                             hints: hints, out: value(after: "--out"), settings: current))
            }
            return true
        }
        if let target = value(after: "--selftest-capture") {
            Task { exit(await capture(target, to: value(after: "--out"))) }
            return true
        }
        if let host = value(after: "--selftest-providers") {
            Task { exit(await providers(host: host)) }
            return true
        }
        if let file = value(after: "--selftest-speech") {
            let locale = value(after: "--locale") ?? "en-US"
            let target = value(after: "--target") ?? "zh-Hans"
            let translate = !arguments.contains("--no-translate")
            Task { exit(await speech(file: file, locale: locale, target: translate ? target : nil, settings: current)) }
            return true
        }
        if let file = value(after: "--selftest-screenshot") {
            let instruction = value(after: "--instruction")
            let appName = value(after: "--app")
            Task { exit(await screenshot(file: file, instruction: instruction, appName: appName, settings: current)) }
            return true
        }
        // --selftest-update <appcast 地址>：真的走一遍自动更新（scripts/test-update.sh 用，会替换这个 App 自己）
        if let feed = value(after: "--selftest-update") {
            let updater = Updater(feedOverride: feed, forceEnabled: true)
            updater.relaunchesAfterUpdate = false
            updater.automaticallyDownloads = true
            updater.onEvent = { event in
                print("update: \(event)")
                if event.hasPrefix("error") || event == "no update" { exit(1) }
                // 下载好了：像平时一样退出，Sparkle 在退出时装新版
                if event.hasPrefix("ready") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { NSApp.terminate(nil) } }
            }
            updater.updater.checkForUpdatesInBackground()
            SelfTest.keepAlive = updater
            DispatchQueue.main.asyncAfter(deadline: .now() + 90) {
                print("update: timeout")
                exit(1)
            }
            return true
        }
        // --markdown-to-html <文件>：Markdown 转 HTML（发版时写 appcast 里的更新说明）
        if let file = value(after: "--markdown-to-html") {
            print(HTMLFormatter.format((try? String(contentsOfFile: file, encoding: .utf8)) ?? ""))
            exit(0)
        }
        // --selftest-prompter [截图文件夹]：提词器（会在屏幕上开一个窗口几秒）
        if arguments.contains("--selftest-prompter") {
            let folder = value(after: "--selftest-prompter").flatMap { $0.hasPrefix("--") ? nil : $0 }
            Task { exit(await prompter(to: folder)) }
            return true
        }
        if arguments.contains("--selftest-followup") {
            exit(followUp())
        }
        if arguments.contains("--selftest-backdrop") {
            Task { exit(await backdrop()) }
            return true
        }
        if let path = value(after: "--selftest-glass") {
            Task { exit(await glass(to: path)) }
            return true
        }
        if let path = value(after: "--render-settings") {
            exit(renderSettings(to: path, settings: current))
        }
        if let path = value(after: "--render-preview") {
            let store = SettingsStore(persists: false)
            store.value = current
            exit(renderPreview(to: path, settings: store))
        }
        if arguments.contains("--selftest-echo") {
            exit(echo())
        }
        if arguments.contains("--selftest-reply") {
            Task { exit(await reply(current)) }
            return true
        }
        return false
    }

    static func speech(file: String, locale: String, target: String?, settings: AppSettings) async -> Int32 {
        var settings = settings
        settings.remoteLocale = locale
        print("识别：\(file)（\(settings.speechMethod.title)"
              + (settings.speechMethod == .apple ? "，\(locale)）" : "，\(settings.speechSlot.providerID) / \(settings.speechSlot.model)）"))
        let engine: SpeechEngine
        do {
            engine = try SpeechEngines.make(for: .remote, settings: settings)
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

        guard let target else { return 0 }
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
        print("回复模型：\(settings.replySlot.providerID) / \(settings.replySlot.model)")
        let client: LLMClient
        do {
            client = try LLMFactory.make(settings.replySlot, for: "回复", in: settings)
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
        let session = SampleData.session(settings: settings)
        let rows = SampleData.rows()
        let meetingReply = SampleData.meetingReply(answering: rows)
        let sideReplies = [SampleData.screenshotReply(thumbnail: sampleThumbnail()), meetingReply]

        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for theme in ThemeID.allCases {
            settings.value.theme = theme
            settings.value.overlayOpacity = AppSettings().overlayOpacity
            session.showSample(rows: rows, replies: sideReplies, selection: [rows[3].id])
            guard render(session: session, settings: settings, sidecar: true,
                         to: folderURL.appending(path: "overlay-\(theme.rawValue).png"))
            else { return 1 }
        }

        let shot = SampleData.screenshotReply(thumbnail: sampleThumbnail())
        for theme in ThemeID.allCases {
            settings.value.theme = theme
            session.showSample(rows: [], replies: [shot], selection: [])
            guard render(session: session, settings: settings, sidecar: true,
                         to: folderURL.appending(path: "screenshot-reply-\(theme.rawValue).png"))
            else { return 1 }
        }
        // 两种字幕样式，盖在会议画面（白字）和白底页面（黑字）上
        settings.value.theme = AppSettings().theme
        let style = settings.value.transcriptStyle
        for transcriptStyle in TranscriptStyle.allCases {
            settings.value.transcriptStyle = transcriptStyle
            for light in [false, true] {
                session.showSample(rows: rows, replies: sideReplies, selection: [rows[3].id])
                guard render(session: session, settings: settings, light: light, sidecar: true,
                             to: folderURL.appending(path: "style-\(transcriptStyle.rawValue)-\(light ? "light" : "dark").png"))
                else { return 1 }
            }
        }
        settings.value.transcriptStyle = style
        // 翻译语言包没下载时的提示条
        session.showSample(rows: rows, replies: [], selection: [])
        session.notice = TytoError.translationNotInstalled(tr("英语 → 简体中文", "English → Simplified Chinese")).localizedDescription
        session.noticeOpensTranslation = true
        defer { session.notice = nil }
        return render(session: session, settings: settings, to: folderURL.appending(path: "notice-translation.png")) ? 0 : 1
    }

    static func models(_ id: String, settings: AppSettings) async -> Int32 {
        guard let provider = settings.provider(id) else {
            print("设置里没有服务商「\(id)」")
            return 1
        }
        do {
            let started = Date.now
            let models = try await ModelList.fetch(provider)
            print("\(provider.name)：\(models.count) 个模型，\(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
            for prefix in ["anthropic/claude", "google/gemini", "openai/gpt", "qwen/qwen", "deepseek/"] {
                let matched = models.filter { $0.hasPrefix(prefix) }
                if !matched.isEmpty { print("  \(prefix)…：\(matched.suffix(6).joined(separator: "、"))") }
            }
            return 0
        } catch {
            print("出错：\(error.localizedDescription)")
            return 1
        }
    }

    static func settingsSummary(_ settings: AppSettings) -> Int32 {
        print("服务商：" + settings.providers.map { "\($0.name)（\($0.kind.rawValue)，\($0.needsKey ? ($0.key == nil ? "缺 key" : "有 key") : "本机")）" }
            .joined(separator: "、"))
        func slot(_ slot: ModelSlot) -> String {
            slot.providerID.isEmpty ? "跟回复一样" : "\(settings.provider(slot.providerID)?.name ?? "（找不到 \(slot.providerID)）") / \(slot.model)"
                + (slot.effort.isEmpty ? "" : "，思考 \(slot.effort)")
        }
        print("回复：\(slot(settings.replySlot))")
        print("看图：\(slot(settings.visionSlot))")
        print("翻译：\(settings.translationProvider == .apple ? "Apple 本机" : slot(settings.translationSlot))")
        print("语音识别：\(settings.speechMethod.title)" + (settings.speechMethod == .apple ? "（远端 \(settings.remoteLocale)，本地 \(settings.localLocale)）" : "，\(slot(settings.speechSlot))"))
        print("外观：\(settings.theme.rawValue)，底色 \(Int(settings.overlayOpacity * 100))%，字号 \(Int(settings.fontSize))")
        return 0
    }

    /// 把 Deepgram 的几种典型返回喂进去，看解析出的事件
    static func deepgram() async -> Int32 {
        let engine = DeepgramSpeechEngine(apiKey: "test", baseURL: "wss://api.deepgram.com/v1/listen", model: "nova-3", language: "multi")
        let messages = [
            #"{"type":"Results","is_final":false,"speech_final":false,"channel":{"alternatives":[{"transcript":"could we move","words":[{"word":"could","speaker":0},{"word":"we","speaker":0},{"word":"move","speaker":0}]}]}}"#,
            #"{"type":"Results","is_final":true,"speech_final":false,"channel":{"alternatives":[{"transcript":"Could we move the launch? Sure, let me check.","words":[{"word":"could","punctuated_word":"Could","speaker":0},{"word":"we","punctuated_word":"we","speaker":0},{"word":"move","punctuated_word":"move","speaker":0},{"word":"the","punctuated_word":"the","speaker":0},{"word":"launch","punctuated_word":"launch?","speaker":0},{"word":"sure","punctuated_word":"Sure,","speaker":1},{"word":"let","punctuated_word":"let","speaker":1},{"word":"me","punctuated_word":"me","speaker":1},{"word":"check","punctuated_word":"check.","speaker":1}]}]}}"#,
            #"{"type":"Results","is_final":true,"speech_final":true,"channel":{"alternatives":[{"transcript":"Thanks.","words":[{"word":"thanks","punctuated_word":"Thanks.","speaker":1}]}]}}"#,
            #"{"type":"UtteranceEnd","last_word_end":3.1}"#,
        ]
        let collector = Task { () -> [String] in
            var lines: [String] = []
            for await event in engine.events {
                let speaker = event.speaker.map { "说话人\($0)" } ?? "-"
                lines.append("\(event.kind)｜\(speaker)｜\(event.text)")
            }
            return lines
        }
        for message in messages { engine.handle(Data(message.utf8)) }
        await engine.stop()
        let lines = await collector.value
        lines.forEach { print($0) }
        let finals = lines.filter { $0.hasPrefix("final") }
        let ok = finals.count == 3 && finals[0].contains("说话人0｜Could we move the launch?")
            && finals[1].contains("说话人1｜Sure, let me check.") && lines.filter { $0.hasPrefix("endOfUtterance") }.count == 2
        print(ok ? "解析正确" : "解析不对")
        return ok ? 0 : 1
    }

    /// AssemblyAI、ElevenLabs 的典型返回喂进去看解析出的事件；再检查对比识别的算分
    static func streamingParsers() async -> Int32 {
        func run(_ handle: (Data) -> Void, _ engine: SpeechEngine, _ messages: [String]) async -> [SpeechEvent] {
            let collector = Task { () -> [SpeechEvent] in
                var events: [SpeechEvent] = []
                for await event in engine.events { events.append(event) }
                return events
            }
            for message in messages { handle(Data(message.utf8)) }
            await engine.stop()
            return await collector.value
        }
        func show(_ name: String, _ events: [SpeechEvent]) {
            print("\(name)：")
            for event in events where event.kind != .partial || !event.text.isEmpty {
                print("  \(event.kind)｜\(event.speaker.map { "说话人\($0)" } ?? "-")｜\(event.language ?? "-")｜\(event.text)")
            }
        }
        var failed: [String] = []

        let assembly = AssemblyAISpeechEngine(apiKey: "test", baseURL: "wss://streaming.assemblyai.com/v3/ws", model: "universal-3-6-pro", languages: [])
        let assemblyEvents = await run({ assembly.handle($0) }, assembly, [
            #"{"type":"Begin","id":"x","expires_at":1772570132,"configuration":{"model":"universal-3-6-pro"}}"#,
            #"{"type":"SpeechStarted","timestamp":120,"confidence":0.9}"#,
            #"{"type":"Turn","turn_order":0,"end_of_turn":false,"turn_is_formatted":false,"transcript":"Could we","words":[{"text":"Could","word_is_final":true},{"text":"we","word_is_final":true},{"text":"move","word_is_final":false}]}"#,
            #"{"type":"Turn","turn_order":0,"end_of_turn":true,"turn_is_formatted":true,"speaker_label":"A","language_code":"en","transcript":"Could we move the launch? Sure, let me check.","words":[{"text":"Could","speaker":"A"},{"text":"we","speaker":"A"},{"text":"move","speaker":"PENDING"},{"text":"the","speaker":"A"},{"text":"launch?","speaker":"A"},{"text":"Sure,","speaker":"B"},{"text":"let","speaker":"B"},{"text":"me","speaker":"UNKNOWN"},{"text":"check.","speaker":"B"}]}"#,
            #"{"type":"Turn","turn_order":1,"end_of_turn":true,"turn_is_formatted":false,"transcript":"wo men xia zhou","words":[]}"#,
            #"{"type":"Turn","turn_order":1,"end_of_turn":true,"turn_is_formatted":true,"speaker_label":"B","language_code":"zh","transcript":"我们下周再说吧。","words":[{"text":"我们","speaker":"B"},{"text":"下周","speaker":"B"},{"text":"再说吧。","speaker":"B"}]}"#,
            #"{"type":"Error","error":"Invalid audio chunk"}"#,
            #"{"type":"Termination","audio_duration_seconds":6,"session_duration_seconds":7}"#,
        ])
        show("AssemblyAI", assemblyEvents)
        let assemblyFinals = assemblyEvents.filter { $0.kind == .final }.map { "\($0.speaker.map(String.init) ?? "-")|\($0.text)" }
        if assemblyFinals != ["0|Could we move the launch?", "1|Sure, let me check.", "1|我们下周再说吧。"] { failed.append("AssemblyAI 定稿：\(assemblyFinals)") }
        if assemblyEvents.first(where: { $0.kind == .partial && !$0.text.isEmpty })?.text != "Could we move" { failed.append("AssemblyAI 未定的字") }
        if assemblyEvents.filter({ $0.kind == .endOfUtterance }).count != 2 { failed.append("AssemblyAI 一句说完的次数") }
        if assemblyEvents.filter({ $0.kind == .error }).count != 1 { failed.append("AssemblyAI 出错消息") }

        let eleven = ElevenLabsSpeechEngine(apiKey: "test", baseURL: "wss://api.elevenlabs.io/v1/speech-to-text/realtime", model: "scribe_v2_realtime", language: nil)
        let elevenEvents = await run({ eleven.handle($0) }, eleven, [
            #"{"message_type":"session_started","session_id":"x","config":{}}"#,
            #"{"message_type":"partial_transcript","text":"could we"}"#,
            #"{"message_type":"committed_transcript","text":"Could we move the launch?"}"#,
            #"{"message_type":"committed_transcript_with_timestamps","text":"Could we move the launch?","language_code":"en","words":[]}"#,
            #"{"message_type":"committed_transcript_with_timestamps","text":"我们下周再说吧。","language_code":"zh","words":[]}"#,
            #"{"message_type":"committed_transcript","text":"我们下周再说吧。"}"#,
            #"{"message_type":"committed_transcript","text":"Yes."}"#,
            #"{"message_type":"committed_transcript","text":"Yes."}"#,
            #"{"message_type":"committed_transcript","text":""}"#,
            #"{"message_type":"warning","warning":"Audio is quiet"}"#,
            #"{"message_type":"auth_error","error":"Invalid API key"}"#,
        ])
        show("ElevenLabs", elevenEvents)
        let elevenFinals = elevenEvents.filter { $0.kind == .final }.map { "\($0.language ?? "-")|\($0.text)" }
        if elevenFinals != ["-|Could we move the launch?", "zh|我们下周再说吧。", "-|Yes.", "-|Yes."] { failed.append("ElevenLabs 定稿：\(elevenFinals)") }
        if elevenEvents.filter({ $0.kind == .endOfUtterance }).count != 4 { failed.append("ElevenLabs 一句说完的次数") }
        if elevenEvents.filter({ $0.kind == .error }).count != 1 { failed.append("ElevenLabs 出错消息") }

        // 对比识别的算分
        let tokens = ScoreToken.tokens("Hello, World! 我們的 API’s").map(\.text)
        if tokens != ["hello", "world", "我", "们", "的", "api's"] { failed.append("分词：\(tokens)") }
        let aligned = Alignment.align(["a", "b", "c"], ["x", "a", "y", "c", "d"], steps: true)
        if aligned.distance != 3 { failed.append("编辑距离：\(aligned.distance)") }
        let steps = (aligned.steps ?? []).map { step -> String in
            switch step {
            case .same(let i, let j): "=\(i)\(j)"
            case .substitute(let i, let j): "~\(i)\(j)"
            case .insert(let j): "+\(j)"
            case .delete(let i): "-\(i)"
            }
        }
        if steps != ["+0", "=01", "~12", "=23", "+4"] { failed.append("对齐：\(steps)") }
        // 开头多出来的算到第一个字，后面多出来的算到前一个字
        if Alignment.errorPositions(aligned.steps ?? []) != [1, 2, 0] { failed.append("错误位置：\(Alignment.errorPositions(aligned.steps ?? []))") }
        let accuracy = Report.speakerAccuracy([("A", 0), ("A", 0), ("B", 1), ("B", 0)])
        if abs(accuracy - 0.75) > 0.001 { failed.append("说话人分对：\(accuracy)") }
        let reference = ReferenceText("Sarah: Hi there\n婷婷：你好")
        if !reference.hasSpeakers || reference.lines.map({ $0.speaker ?? "" }) != ["Sarah", "婷婷"] { failed.append("参考稿说话人") }
        if ReferenceText("Agenda: budget\nThen we talk").hasSpeakers { failed.append("参考稿不是每行都有说话人") }
        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.2)) * 0.1 }
        let segments = SpeechActivity.segments([Float](repeating: 0, count: 16_000) + tone + [Float](repeating: 0, count: 16_000))
        if segments.count != 1 || abs(segments[0].start - 1) > 0.05 || abs(segments[0].end - 2) > 0.05 { failed.append("说话段落：\(segments)") }

        if failed.isEmpty { print("解析和算分都正确") } else { failed.forEach { print("不对：\($0)") } }
        return failed.isEmpty ? 0 : 1
    }

    /// 截图并认出来源 App（只打印大小和 App 名字）
    static func capture(_ target: String, to out: String?) async -> Int32 {
        guard let target = AppSettings.CaptureTarget(rawValue: target) else {
            print("截图方式：frontWindow / screen / region")
            return 1
        }
        do {
            guard let image = try await Capture.capture(target) else {
                print("取消了")
                return 1
            }
            let size = Screenshot.cgImage(image.png).map { "\($0.width)x\($0.height)" } ?? "?"
            print("截了：\(target.title)，\(size)，来自 \(image.appName ?? "?")（\(image.bundleID ?? "?")）")
            if let out { try image.png.write(to: URL(filePath: out)) }
            return 0
        } catch {
            print("出错：\(error.localizedDescription)")
            return 1
        }
    }

    /// 对着一个地址（模拟服务）测：三家服务商读模型列表、Ollama 检测、下载进度
    static func providers(host: String) async -> Int32 {
        guard let url = URL(string: host) else { return 1 }
        var failed = 0
        for (template, base) in [("anthropic", host), ("openrouter", "\(host)/v1"), ("ollama", "\(host)/v1"), ("deepgram", host)] {
            guard let info = ProviderTemplate.find(template) else { continue }
            let provider = Provider(id: "test-\(template)", name: info.name, kind: info.kind, baseURL: base, template: template)
            do {
                let models = try await ModelList.fetch(provider)
                print("\(info.name) 模型列表：\(models)")
            } catch {
                failed += 1
                print("\(info.name) 模型列表出错：\(error.localizedDescription)")
            }
        }
        print("Ollama 版本：\(await Ollama.version(host: url) ?? "没检测到")")
        do {
            var last = ""
            for try await progress in Ollama.pull("qwen3-vl:4b-instruct", host: url) {
                let percent = progress.fraction.map { " \(Int($0 * 100))%" } ?? ""
                let line = "\(progress.status)\(percent)"
                if line != last { print("下载：\(line)") }
                last = line
            }
        } catch {
            failed += 1
            print("下载出错：\(error.localizedDescription)")
        }
        return failed == 0 ? 0 : 1
    }

    /// 看真实的玻璃效果（ImageRenderer 和图层渲染都画不出系统玻璃）：
    /// 屏幕上放一个模拟会议画面的窗口，悬浮窗盖在上面，只截这两个窗口（屏幕上别的东西不会进图）。
    /// 要屏幕录制权限：从有权限的终端里运行。
    @MainActor
    static func glass(to folder: String) async -> Int32 {
        let settings = SettingsStore(persists: false)
        let session = SampleData.session(settings: settings)
        guard let screen = NSScreen.screens.first else { return 1 }
        let area = screen.visibleFrame
        let stage = NSRect(x: area.midX - 320, y: area.midY - 380, width: 640, height: 760)
        let light = CommandLine.arguments.contains("--light")
        let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: SampleBackdrop(light: light))
        backdrop.orderFrontRegardless()
        let state = OverlayState()
        state.backdropIsLight = light && CommandLine.arguments.contains("--auto")
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state),
                                 remembersFrame: false)
        panel.sharingType = .readOnly
        panel.setFrame(NSRect(x: stage.minX + 80, y: stage.minY + 80, width: 480, height: 600), display: true)
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
            backdrop.orderOut(nil)
        }
        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let opacities = light ? [0.0, 0.25, 0.45, 0.62, 0.9] : [0.0, 0.12, 0.25, 0.5]
        for opacity in opacities {
            settings.value.overlayOpacity = opacity
            try? await Task.sleep(for: .seconds(1.2))
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ours = content.windows.filter {
                    [backdrop.windowNumber, panel.windowNumber].contains(Int($0.windowID))
                }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return 1 }
                let filter = SCContentFilter(display: display, including: ours)
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: stage.minX - screen.frame.minX, y: screen.frame.maxY - stage.maxY,
                                           width: stage.width, height: stage.height)
                config.width = Int(stage.width * 2)
                config.height = Int(stage.height * 2)
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let url = folderURL.appending(path: "glass-\(light ? "light-" : "")\(state.backdropIsLight ? "auto-" : "")\(settings.value.theme.rawValue)-\(Int(opacity * 100)).png")
                try ImageFile.writePNG(image, to: url)
                print(url.path)
            } catch {
                print("截不了：\(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }

    /// "我实际说的"：几种典型的对话，看找得对不对、判得对不对
    @MainActor
    static func followUp() -> Int32 {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func row(_ channel: Channel, _ speaker: Int, _ text: String, at second: Double, length: Double = 4) -> Utterance {
            var row = Utterance(channel: channel, speaker: speaker, language: "en")
            row.text = text
            row.isClosed = true
            return Utterance(copying: row, startedAt: start.addingTimeInterval(second),
                             updatedAt: start.addingTimeInterval(second + length))
        }
        let question = row(.remote, 2, "Could we move the launch to the second week of December?", at: 0)
        var reply = Reply(target: "1")
        reply.text = "【对方的意思】问能不能推到十二月第二周。\n【建议回复】The second week of December works for us, we just need the final specs by November 20th.\n【中文对照】可以。"
        reply.isStreaming = false
        reply.targetIDs = [question.id]
        let me: Set<String> = ["local:1"]

        struct Case { let name: String; let rows: [Utterance]; let now: Double; let verdict: ReplyFollowUp.Verdict; let said: Int }
        let cases: [Case] = [
            Case(name: "照着说", rows: [question, row(.local, 1, "The second week of December works for us. We just need the final specs by November 20th.", at: 6)],
                 now: 30, verdict: .followed, said: 1),
            Case(name: "改了说法", rows: [question, row(.local, 1, "Let me check with the team about testing and get back to you after the meeting.", at: 6)],
                 now: 30, verdict: .rephrased, said: 1),
            Case(name: "对方换了个人说别的", rows: [question, row(.remote, 1, "Let's move on to the pricing section of the deck.", at: 8)],
                 now: 30, verdict: .skipped, said: 0),
            Case(name: "还在等我开口", rows: [question], now: 30, verdict: .waiting, said: 0),
            Case(name: "等太久算没回", rows: [question], now: 200, verdict: .skipped, said: 0),
            Case(name: "会议室里别人说的不算", rows: [question, row(.local, 2, "I think December is fine for the backend.", at: 6)],
                 now: 30, verdict: .waiting, said: 0),
            Case(name: "对方附和一声不打断", rows: [question, row(.remote, 2, "Right?", at: 5, length: 1),
                                              row(.local, 1, "Yes, the second week of December works, with final specs by November 20th.", at: 7)],
                 now: 30, verdict: .followed, said: 1),
            Case(name: "对方同一个人接着补充", rows: [question, row(.remote, 2, "We have a marketing event that week, so it would help a lot.", at: 6),
                                                row(.local, 1, "Understood, let me confirm with engineering first.", at: 13)],
                 now: 30, verdict: .rephrased, said: 1),
            Case(name: "说完停很久再说的不算", rows: [question, row(.local, 1, "Second week of December works for us.", at: 6),
                                                row(.local, 1, "Okay, next topic: the hiring plan for next quarter.", at: 40)],
                 now: 60, verdict: .followed, said: 1),
        ]
        var failed = 0
        for item in cases {
            let result = FollowUp.find(for: reply, in: item.rows, me: me, now: start.addingTimeInterval(item.now))
            let ok = result?.verdict == item.verdict && result?.rows.count == item.said
            if !ok { failed += 1 }
            print("\(ok ? "✓" : "✗") \(item.name)：\(result.map { "\($0.verdict.label)，\($0.rows.count) 句，重合 \(Int($0.overlap * 100))%" } ?? "无")")
        }
        // 中文：按字比
        var chinese = reply
        chinese.text = "【建议回复】十二月第二周可以，我们需要在十一月二十号之前拿到最终需求。"
        let zhRows = [question, row(.local, 1, "十二月第二周没问题，不过最终需求要十一月二十号前给我们", at: 6)]
        let zh = FollowUp.find(for: chinese, in: zhRows, me: me, now: start.addingTimeInterval(30))
        let zhOK = zh?.verdict == .followed
        if !zhOK { failed += 1 }
        print("\(zhOK ? "✓" : "✗") 中文照着说：\(zh.map { "\($0.verdict.label)，重合 \(Int($0.overlap * 100))%" } ?? "无")")
        // 回复面板的位置：悬浮窗靠右时贴左边，靠左时贴右边，高度一样
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            let overlay = NSWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
            let sidecar = SidecarPanel(rootView: EmptyView())
            overlay.setFrame(NSRect(x: area.maxX - 500, y: area.minY + 100, width: 480, height: 520), display: false)
            sidecar.place(beside: overlay)
            let leftOK = sidecar.frame.maxX <= overlay.frame.minX && sidecar.frame.height == overlay.frame.height
            overlay.setFrame(NSRect(x: area.minX + 10, y: area.minY + 100, width: 480, height: 520), display: false)
            sidecar.place(beside: overlay)
            let rightOK = sidecar.frame.minX >= overlay.frame.maxX
            if !(leftOK && rightOK) { failed += 1 }
            print("\(leftOK && rightOK ? "✓" : "✗") 回复面板：悬浮窗靠右时在左边，靠左时在右边")
        }
        // 截屏回复、只回自己的话：不比
        var shot = reply
        shot.source = "screenshot"
        let mine = row(.local, 1, "I'll send it tonight.", at: 0)
        var own = reply
        own.targetIDs = [mine.id]
        let skippedKinds = FollowUp.find(for: shot, in: [question], me: me) == nil
            && FollowUp.find(for: own, in: [mine], me: me) == nil
        if !skippedKinds { failed += 1 }
        print("\(skippedKinds ? "✓" : "✗") 截屏回复、只回自己的话不比")
        print(failed == 0 ? "全部通过" : "\(failed) 项不对")
        return failed == 0 ? 0 : 1
    }

    /// 字色自动的判断：在屏幕上依次放白底页面、会议画面，量那块区域的亮度，看会不会选对
    @MainActor
    static func backdrop() async -> Int32 {
        guard CGPreflightScreenCaptureAccess() else {
            print("没有录屏权限，量不了")
            return 1
        }
        guard let screen = NSScreen.screens.first,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return 1 }
        let area = screen.visibleFrame
        let stage = NSRect(x: area.midX - 240, y: area.midY - 300, width: 480, height: 600)
        var wrong = 0
        for light in [true, false] {
            let window = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.contentView = NSHostingView(rootView: SampleBackdrop(light: light))
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(0.8))
            let rect = CGRect(x: stage.minX - screen.frame.minX + 40, y: screen.frame.maxY - stage.maxY + 40,
                              width: stage.width - 80, height: stage.height - 80)
            do {
                let started = Date.now
                let value = try await BackdropProbe.luminance(of: rect, display: displayID)
                let ms = Int(Date.now.timeIntervalSince(started) * 1000)
                let black = BackdropProbe.isLight(value, current: false)
                print("\(light ? "白底页面" : "会议画面")：亮度 \(String(format: "%.2f", value))（\(ms) ms）→ \(black ? "黑字" : "白字")")
                if black != light { wrong += 1 }
            } catch {
                print("量不了：\(error.localizedDescription)")
                wrong += 1
            }
            window.orderOut(nil)
        }
        print(wrong == 0 ? "判断正确" : "判断不对")
        return wrong == 0 ? 0 : 1
    }

    /// 把设置窗口每一页画成图片：窗口建在屏幕外，画它的图层（系统控件也能画出来，不截屏）
    @MainActor
    static func renderSettings(to folder: String, settings current: AppSettings) -> Int32 {
        let settings = SettingsStore(persists: false)
        settings.value = current
        let session = SampleData.session(settings: settings)
        let skills = SkillStore()
        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        NSApp.setActivationPolicy(.accessory)
        for page in SettingsPage.allCases {
            let window = OffscreenWindow(contentRect: NSRect(x: -6000, y: -6000, width: 900, height: 680),
                                         styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                         backing: .buffered, defer: false)
            window.sharingType = .none
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: .darkAqua)
            let host = NSHostingView(rootView: MainView(session: session, settings: settings, skills: skills, initialPage: page))
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))
            host.layoutSubtreeIfNeeded()
            guard let layer = host.layer else { continue }
            let scale: CGFloat = 2
            let size = host.bounds.size
            guard let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            context.setFillColor(NSColor(white: 0.12, alpha: 1).cgColor)
            context.fill(CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale))
            context.scaleBy(x: scale, y: scale)
            if host.isFlipped {
                context.translateBy(x: 0, y: size.height)
                context.scaleBy(x: 1, y: -1)
            }
            layer.render(in: context)
            window.orderOut(nil)
            if let image = context.makeImage() {
                let url = folderURL.appending(path: "settings-\(page.rawValue).png")
                try? ImageFile.writePNG(image, to: url)
                print(url.path)
            }
        }
        // 侧栏是系统材质，上面那种画法画不出来，单独按侧栏的样子画一张图标列表
        let sidebar = VStack(alignment: .leading, spacing: 6) {
            ForEach(SettingsPage.groups, id: \.title) { group in
                Text(group.title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 8)
                ForEach(group.pages) { page in
                    HStack(spacing: 8) {
                        IconTile(symbol: page.symbol, colors: page.colors(settings.value.iconStyle), size: 22)
                        Text(page.title).font(.system(size: 13))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6).fill(page == .session ? Brand.accent.opacity(0.35) : .clear))
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .background(Color(white: 0.17))
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: sidebar)
        renderer.scale = 2
        if let image = renderer.cgImage {
            let url = folderURL.appending(path: "settings-sidebar.png")
            try? ImageFile.writePNG(image, to: url)
            print(url.path)
        }
        return 0
    }

    /// 悬浮窗画在一张模拟的视频会议画面上，玻璃用"模糊后的背景 + 主题底色"近似
    @MainActor
    /// - sidecar: 左边带上回复面板（和真实的一样贴在悬浮窗旁边）
    private static func render(session: SessionModel, settings: SettingsStore, light: Bool = false, sidecar: Bool = false,
                               to url: URL) -> Bool {
        let size = CGSize(width: 480, height: 600)
        let side = sidecar ? SidecarPanel.width + SidecarPanel.gap : 0
        let backdrop = SampleBackdrop(light: light)
        let state = OverlayState()
        state.backdropIsLight = light
        settings.value.showReplyPanel = sidecar
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let view = ZStack {
            backdrop
            // 玻璃的近似：模糊的背景只露在两个面板的形状里
            backdrop.blur(radius: 26)
                .mask {
                    HStack(spacing: SidecarPanel.gap) {
                        if sidecar { shape.frame(width: SidecarPanel.width) }
                        shape.frame(width: size.width)
                    }
                    .frame(height: size.height)
                }
            HStack(spacing: SidecarPanel.gap) {
                if sidecar {
                    SidecarView(session: session, settings: settings, ui: state, flatForPreview: true)
                        .frame(width: SidecarPanel.width)
                }
                OverlayView(session: session, settings: settings, ui: state, flatForPreview: true)
                    .frame(width: size.width)
            }
            .frame(height: size.height)
        }
        .frame(width: size.width + side + 80, height: size.height + 80)
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
    static func screenshot(file: String, instruction: String?, appName: String?, settings: AppSettings) async -> Int32 {
        guard let png = try? Data(contentsOf: URL(filePath: file)) else {
            print("读不了图片")
            return 1
        }
        let client: LLMClient
        let visionClient: LLMClient?
        do {
            client = try LLMFactory.make(settings.replySlot, for: "回复", in: settings)
            visionClient = settings.screenshotMode == .visionModel
                ? try LLMFactory.make(settings.visionSlot, for: "看图", in: settings) : nil
        } catch {
            print(error.localizedDescription)
            return 2
        }
        print("识别方式：\(settings.screenshotMode.title)；回复模型：\(settings.replySlot.model)"
              + (visionClient != nil ? "；看图模型：\(settings.visionSlot.model)" : ""))
        let image = CapturedImage(png: png, appName: appName, bundleID: nil, windowTitle: nil)
        var text = ""
        do {
            try await ScreenshotReplier.run(image, settings: settings, context: "", skills: [], instruction: instruction,
                                            reply: client, vision: visionClient,
                                            status: { print("· \($0)") }, text: { text += $0 })
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

/// 画图用的窗口：系统会把带标题栏的窗口挪回屏幕内，这里不让它挪，免得在屏幕上闪一下
private final class OffscreenWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

enum ImageFile {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw TytoError.server("存不了图片") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw TytoError.server("存不了图片") }
    }
}
