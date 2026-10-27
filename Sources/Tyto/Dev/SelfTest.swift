@preconcurrency import AVFAudio
import ImageIO
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
///   Tyto --selftest-settings                                              读出现在的设置（老设置会被换算），只看不写
///   Tyto --selftest-deepgram                                              Deepgram 返回消息的解析
///   以上自测都可以加 --settings-json '{...}'，临时改设置，不写回
///   Tyto --selftest-glass <文件夹>                                         真实玻璃效果：悬浮窗盖在模拟会议画面上，只截这两个窗口
///   Tyto --render-settings <文件夹>                                        把设置窗口每一页画成图片（窗口建在屏幕外，不截屏）
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
        // --settings-json '{...}'：这次自测用的设置盖在现有设置上，不写回
        var current = settings.value
        if let json = value(after: "--settings-json") { current = SettingsStore.overriding(current, with: json) }
        if arguments.contains("--selftest-settings") {
            exit(settingsSummary(current))
        }
        if arguments.contains("--selftest-deepgram") {
            Task { exit(await deepgram()) }
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
        if let path = value(after: "--selftest-glass") {
            Task { exit(await glass(to: path)) }
            return true
        }
        if let path = value(after: "--render-settings") {
            exit(renderSettings(to: path))
        }
        if let path = value(after: "--render-preview") {
            exit(renderPreview(to: path, settings: SettingsStore(persists: false)))
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
        let meetingReply = SampleData.meetingReply()

        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        for theme in ThemeID.allCases {
            settings.value.theme = theme
            settings.value.overlayOpacity = AppSettings().overlayOpacity
            session.showSample(rows: rows, replies: [meetingReply], selection: [rows[3].id])
            guard render(session: session, settings: settings, to: folderURL.appending(path: "overlay-\(theme.rawValue).png"))
            else { return 1 }
        }

        settings.value.theme = .obsidian
        let shot = SampleData.screenshotReply(thumbnail: sampleThumbnail())
        session.showSample(rows: [], replies: [shot], selection: [])
        return render(session: session, settings: settings, to: folderURL.appending(path: "screenshot-reply.png")) ? 0 : 1
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
        let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: SampleBackdrop())
        backdrop.orderFrontRegardless()
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: OverlayState()),
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
        for opacity in [0.0, 0.12, 0.25, 0.5] {
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
                let url = folderURL.appending(path: "glass-\(settings.value.theme.rawValue)-\(Int(opacity * 100)).png")
                try ImageFile.writePNG(image, to: url)
                print(url.path)
            } catch {
                print("截不了：\(error.localizedDescription)")
                return 1
            }
        }
        return 0
    }

    /// 把设置窗口每一页画成图片：窗口建在屏幕外，画它的图层（系统控件也能画出来，不截屏）
    @MainActor
    static func renderSettings(to folder: String) -> Int32 {
        let settings = SettingsStore(persists: false)
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
        return 0
    }

    /// 悬浮窗画在一张模拟的视频会议画面上，玻璃用"模糊后的背景 + 主题底色"近似
    @MainActor
    private static func render(session: SessionModel, settings: SettingsStore, to url: URL) -> Bool {
        let size = CGSize(width: 480, height: 600)
        let backdrop = SampleBackdrop()
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
