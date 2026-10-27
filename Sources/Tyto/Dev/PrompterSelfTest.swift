import AppKit
import ScreenCaptureKit
import SwiftUI

/// --selftest-prompter [截图文件夹]：在真的提词器窗口里载入几份材料，检查
/// 编号和目录、跟读、对方提到时的提示、别人写的 HTML 的字色、文件改了自动刷新；给了文件夹就再截几张图。
/// 材料写在临时文件夹里，测完删掉；设置和会话都不落盘。
extension SelfTest {
    @MainActor
    static func prompter(to folder: String?) async -> Int32 {
        let settings = SettingsStore(persists: false)
        settings.value.prompterPath = ""
        settings.value.prompterRecent = []
        settings.value.prompterFollow = true
        settings.value.prompterHints = true
        let session = SessionModel(settings: settings, skills: SkillStore(), persists: false)
        let model = PrompterModel(settings: settings, session: session)

        let work = FileManager.default.temporaryDirectory.appending(path: "tyto-prompter-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let english = work.appending(path: "acme-sync.md")
        let chinese = work.appending(path: "周会.md")
        let page = work.appending(path: "brief.html")
        try? SampleNotes.english.write(to: english, atomically: true, encoding: .utf8)
        try? SampleNotes.chinese.write(to: chinese, atomically: true, encoding: .utf8)
        try? SampleNotes.html.write(to: page, atomically: true, encoding: .utf8)

        // 真窗口：网页要排版、要能截图
        guard let screen = NSScreen.screens.first else { return 1 }
        let area = screen.visibleFrame
        let stage = NSRect(x: area.midX - 300, y: area.midY - 360, width: 600, height: 720)
        let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: SampleBackdrop(light: false))
        let panel = PrompterPanel(rootView: PrompterView(model: model, settings: settings), remembersFrame: false)
        panel.sharingType = .readOnly
        panel.setFrame(NSRect(x: stage.minX + 70, y: stage.minY + 50, width: 440, height: 620), display: true)
        if folder != nil { backdrop.orderFrontRegardless() }
        panel.orderFrontRegardless()
        defer {
            panel.orderOut(nil)
            backdrop.orderOut(nil)
        }
        // 锁屏或窗口被挡住时 WebKit 不重画；自测（常在锁屏时跑）里关掉这个检查，截图才是真的样子
        let occlusion = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if model.web.view.responds(to: occlusion) { model.web.view.perform(occlusion, with: false) }
        model.start()

        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "✓" : "✗") \(name)\(ok ? "" : "  \(detail())")")
            if !ok { failures += 1 }
        }
        func wait(_ seconds: Double = 8, until condition: () -> Bool) async -> Bool {
            let deadline = Date.now.addingTimeInterval(seconds)
            while Date.now < deadline {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(100))
            }
            return condition()
        }
        func block(containing text: String) -> Int? {
            model.blocks.first { $0.text.contains(text) }?.index
        }
        func section(_ title: String) -> Int? {
            model.sections.firstIndex { $0.title == title }
        }
        let now = Date.now
        func row(_ channel: Channel, _ text: String, translation: String? = nil, ago: Double = 1) -> Utterance {
            var row = Utterance(channel: channel, speaker: channel == .remote ? 1 : nil, language: nil)
            row.text = text
            row.translation = translation
            row.isClosed = channel == .remote
            return Utterance(copying: row, startedAt: now.addingTimeInterval(-ago - 3), updatedAt: now.addingTimeInterval(-ago))
        }
        func say(_ text: String, translation: String? = nil) {
            model.heard([row(.local, text, translation: translation)], me: [], now: now)
        }
        func hear(_ text: String, translation: String? = nil) -> String? {
            model.suggestion = nil
            model.heard([row(.remote, text, translation: translation)], me: [], now: now)
            return model.suggestion?.title
        }

        // 1. Markdown：编号、目录
        model.open(english)
        check("Markdown 载入并编号", await wait { !model.blocks.isEmpty }, model.error ?? "没有收到段落")
        check("目录跳过唯一的一级标题", model.sections.map(\.title) == ["Opening", "Progress since last week", "Enterprise pricing",
                                                         "Launch timeline", "Risks", "Questions to ask"],
              model.sections.map(\.title).joined(separator: " | "))
        check("表格一行算一段", block(containing: "Enterprise 50+") != nil, model.blocks.map(\.text).joined(separator: " | "))
        check("开头的 YAML 属性不显示", block(containing: "title: Acme") == nil)

        // 2. 跟读
        say("so we moved the dedup step before enrichment, and that cut the p95 latency from 820 to 310 milliseconds")
        check("跟读：照着说一段", model.current == block(containing: "ingestion pipeline"), "current=\(model.current.map(String.init) ?? "nil")")
        say("next step is the multi region failover test, which is scheduled for november sixth")
        check("跟读：接着说下一段", model.current == block(containing: "multi-region failover"), "current=\(model.current.map(String.init) ?? "nil")")
        say("and who signs off on the security review on your side")
        check("跟读：短的列表项", model.current == block(containing: "Who signs off"), "current=\(model.current.map(String.init) ?? "nil")")
        let before = model.current
        say("sounds good, let me share my screen")
        check("跟读：闲聊不动", model.current == before)

        // 3. 对方提到
        model.goToSection(0)
        _ = await wait(2) { model.currentSection == 0 }
        check("提示：问定价", hear("What would the enterprise pricing look like for around 200 seats?") == "Enterprise pricing",
              model.suggestion?.title ?? "nil")
        check("提示：问上线时间", hear("When could you launch? Is December still realistic for you?") == "Launch timeline",
              model.suggestion?.title ?? "nil")
        check("提示：寒暄不提示", hear("Sounds good, thanks everyone for joining today.") == nil, model.suggestion?.title ?? "nil")
        if let pricing = section("Enterprise pricing") {
            model.goToSection(pricing)
            _ = await wait(2) { model.currentSection == pricing }
            check("提示：正在讲的那节不提示", hear("And the enterprise pricing, is that per seat?") == nil,
                  "\(model.suggestion?.title ?? "nil") reading=\(model.reading ?? -1) current=\(model.current ?? -1) heading=\(model.sections[pricing].heading) section=\(model.currentSection ?? -1)")
        }

        // 4. 中文材料、英文对话（用译文对）
        model.open(chinese)
        check("中文材料载入", await wait { model.blocks.contains { $0.text.contains("压价") } })
        say("If they push on price, we can offer twelve percent off for a two-year contract",
            translation: "如果他们压价，我们可以为两年合同提供百分之十二的折扣")
        check("跟读：英文说、中文稿", model.current == block(containing: "压价"), "current=\(model.current.map(String.init) ?? "nil")")
        model.goToSection(0)
        _ = await wait(2) { model.currentSection == 0 }
        check("提示：英文问、中文稿", hear("What's the price for the enterprise edition?", translation: "企业版的价格是多少？") == "企业版定价",
              model.suggestion?.title ?? "nil")

        // 5. 别人写的 HTML：白底深色字在深色玻璃上换成正文颜色
        model.open(page)
        check("HTML 载入并编号", await wait { model.blocks.contains { $0.text.contains("Key numbers") } },
              model.blocks.map(\.text).joined(separator: " | "))
        let card = (try? await model.web.view.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.card')).color")) as? String ?? ""
        let red = (try? await model.web.view.evaluateJavaScript(
            "getComputedStyle(document.querySelector('.warn')).color")) as? String ?? ""
        check("HTML 里看不清的字色换掉了", card.contains("255, 255, 255"), card)
        check("HTML 里看得清的颜色保留", red.contains("255, 90, 80"), red)

        // 6. 改了文件自动刷新
        model.open(english)
        _ = await wait { model.sections.count == 6 }
        try? (SampleNotes.english + "\n## Budget\n\nApprovals above $50k need the CFO.\n").write(to: english, atomically: true, encoding: .utf8)
        check("文件改了自动刷新", await wait(6) { model.sections.last?.title == "Budget" }, model.sections.last?.title ?? "nil")

        // 7. 截图：深色会议画面、白底文档
        if let folder {
            let out = URL(filePath: folder)
            try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            if let pricing = section("Enterprise pricing"), let paragraph = block(containing: "12% discount") {
                model.goToSection(pricing)
                try? await Task.sleep(for: .seconds(0.8))
                model.go(to: paragraph)
            }
            model.suggestion = model.sections.firstIndex { $0.title == "Launch timeline" }
                .map { PrompterModel.Suggestion(section: $0, title: "Launch timeline", at: .now) }
            for light in [false, true] {
                backdrop.contentView = NSHostingView(rootView: SampleBackdrop(light: light))
                model.backdropIsLight = light
                try? await Task.sleep(for: .seconds(1.5))
                if let image = await capture([backdrop, panel], stage: stage, screen: screen) {
                    let url = out.appending(path: "prompter-\(light ? "light" : "dark")-\(settings.value.theme.rawValue).png")
                    try? ImageFile.writePNG(image, to: url)
                    print(url.path)
                }
            }
            model.close()
            model.backdropIsLight = false
            backdrop.contentView = NSHostingView(rootView: SampleBackdrop(light: false))
            try? await Task.sleep(for: .seconds(1))
            if let image = await capture([backdrop, panel], stage: stage, screen: screen) {
                let url = out.appending(path: "prompter-empty.png")
                try? ImageFile.writePNG(image, to: url)
                print(url.path)
            }
        }

        print(failures == 0 ? "提词器：全部通过" : "提词器：\(failures) 项没通过")
        return failures == 0 ? 0 : 1
    }

    /// 只截 Tyto 自己的这几个窗口（不截别的 App）
    @MainActor
    private static func capture(_ windows: [NSWindow], stage: NSRect, screen: NSScreen) async -> CGImage? {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value,
              let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        let numbers = Set(windows.map(\.windowNumber))
        let filter = SCContentFilter(display: display, including: content.windows.filter { numbers.contains(Int($0.windowID)) })
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x: stage.minX - screen.frame.minX, y: screen.frame.maxY - stage.maxY,
                                   width: stage.width, height: stage.height)
        config.width = Int(stage.width * 2)
        config.height = Int(stage.height * 2)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}

/// 自测和截图用的材料
enum SampleNotes {
    static let english = """
    ---
    title: Acme weekly sync
    ---
    # Acme weekly sync — Oct 28

    ## Opening

    - Thank them for the quick turnaround on the API keys.
    - Today: progress, pricing for the enterprise tier, and the December launch date.

    ## Progress since last week

    The ingestion pipeline now handles **2.4 million events per hour** on a single node, up from 900k. We moved the dedup step before enrichment, which cut the p95 latency from 820 ms to 310 ms.

    Next step is the multi-region failover test, scheduled for **November 6**.

    ## Enterprise pricing

    | Plan | Seats | Price |
    |---|---|---|
    | Team | up to 50 | $18 / seat |
    | Enterprise | 50+ | $14 / seat, annual |

    If they push on price, offer a **12% discount** for a two-year commitment, but keep SSO and audit logs in the enterprise tier only.

    ## Launch timeline

    We can launch in the second week of December if final specs arrive by November 20. Marketing needs two weeks for the landing page.

    ## Risks

    1. Their security review usually takes three weeks.
    2. Data residency in Frankfurt is not ready until January.

    ## Questions to ask

    - [ ] Who signs off on the security review?
    - [ ] Do they need the Frankfurt region at launch?
    """

    static let chinese = """
    # 和 Acme 的周会

    ## 项目进展

    数据接入现在单节点每小时能处理 240 万条事件。去重放到补全前面以后，延迟从 820 毫秒降到 310 毫秒。

    ## 企业版定价

    企业版 50 个席位以上，每个席位 14 美元，按年付。如果对方压价，可以给两年合同 12% 的折扣，但单点登录和审计日志只放在企业版。

    ## 上线时间

    如果 11 月 20 日前拿到最终需求，可以在 12 月第二周上线。市场部做落地页要两周。
    """

    static let html = """
    <!doctype html>
    <html><head><meta charset="utf-8"><style>
    body { background: #ffffff; color: #222; font-family: Georgia, serif; }
    .card { padding: 8px 0; color: #333; }
    .warn { color: rgb(255, 90, 80); font-weight: bold; }
    </style></head><body>
    <div class="card">Key numbers for the call</div>
    <div class="card">Churn is down to 2.1% this quarter.</div>
    <div class="card"><span class="warn">Do not</span> promise the Frankfurt region before January.</div>
    </body></html>
    """
}
