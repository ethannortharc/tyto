import AppKit
import Foundation

/// 一场会议：两路声音（远端、本地）各自识别，结果按"一句一行"排在 rows 里；
/// 每行确定后翻译；点某几行或"最近的话"生成回复建议。
@MainActor
final class SessionModel: ObservableObject {
    @Published var title = "新会议" { didSet { scheduleSave() } }
    @Published var context = "" { didSet { scheduleSave() } }
    @Published var activeSkillIDs: Set<String> = ["01-general"] { didSet { scheduleSave() } }
    @Published var speakerNames: [String: String] = [:] { didSet { scheduleSave() } }
    /// 字幕里要高亮的词，逗号分隔
    @Published var keywords = "" { didSet { scheduleSave() } }
    /// 这次开始听的时间（界面上显示时长）
    @Published private(set) var listeningSince: Date?
    @Published private(set) var rows: [Utterance] = []
    @Published private(set) var replies: [Reply] = []
    @Published var selection: Set<UUID> = []
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    /// 最近一条提示（多半是出错信息）
    @Published var notice: String?
    @Published private(set) var levels: [Channel: Float] = [:]

    let settings: SettingsStore
    let skills: SkillStore

    private struct Pipeline {
        let source: AudioSource
        let engine: SpeechEngine
        let consumer: Task<Void, Never>
    }

    private var pipelines: [Channel: Pipeline] = [:]
    private var openRow: [Channel: UUID] = [:]
    private var translationTasks: [UUID: Task<Void, Never>] = [:]
    private var replyTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private let appleTranslator = AppleTranslator()
    private let meter = LevelMeter()
    /// 每一路开始录音的时间，和是否已经听到过声音（用来提示权限问题）
    private var startedAt: [Channel: Date] = [:]
    private var heard: Set<Channel> = []
    private var lastTranslationError: String?

    /// 一段话停顿这么久就算说完（云端识别有自己的断句信号，本机识别靠这个）
    private static let silenceGap: TimeInterval = 1.5
    /// 识别中的文字这么久没变化，也当说完处理
    private static let staleGap: TimeInterval = 4

    /// false 时不读写会话文件（预览、自测用，不碰真实记录）
    private let persists: Bool

    init(settings: SettingsStore, skills: SkillStore, persists: Bool = true) {
        self.settings = settings
        self.skills = skills
        self.persists = persists
    }

    // MARK: - 开始、停止

    func toggle() {
        Task { isRunning ? await stop() : await start() }
    }

    func start() async {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        notice = nil
        let current = settings.value

        var channels: [Channel] = []
        if current.captureRemote { channels.append(.remote) }
        if current.captureLocal { channels.append(.local) }
        guard !channels.isEmpty else {
            notice = "远端和本地都关着，没有声音可听（模型与服务 → 声音来源）"
            return
        }

        RunLog.write("开始听：\(channels.map(\.label).joined(separator: "、"))，识别 \(current.speechProvider.rawValue)")
        // 两路各开各的：一路在等权限框时，另一路照样能先开起来
        await withTaskGroup(of: Void.self) { group in
            for channel in channels {
                group.addTask { await self.startChannel(channel, settings: current) }
            }
        }
        isRunning = !pipelines.isEmpty
    }

    private func startChannel(_ channel: Channel, settings current: AppSettings) async {
        if channel == .local {
            RunLog.write("本地：请求麦克风权限")
            guard await MicrophoneCapture.requestPermission() else {
                notice = "没有麦克风权限：系统设置 → 隐私与安全性 → 麦克风 → 打开 Tyto"
                RunLog.write(notice ?? "")
                return
            }
        }
        do {
            let engine = try makeEngine(for: channel, settings: current)
            try await engine.start()
            RunLog.write("\(channel.label)：识别引擎已启动")
            let source: AudioSource = channel == .remote
                ? SystemAudioCapture()
                : MicrophoneCapture(deviceUID: current.localInputDeviceUID)
            let meter = meter
            let probe = AudioProbe(channel.label)
            source.onSamples = { samples in
                probe.observe(samples)
                meter.update(channel, Downmix.level(samples))
                engine.append(samples)
            }
            do {
                // 第一次录系统声音时，系统弹权限框，这一步会一直等到你点"允许"；放到后台，悬浮窗不会卡住
                try await Task.detached(priority: .userInitiated) { try source.start() }.value
            } catch {
                await engine.stop()
                throw error
            }
            let consumer = Task { [weak self] in
                for await event in engine.events { self?.handle(event, from: channel) }
            }
            pipelines[channel] = Pipeline(source: source, engine: engine, consumer: consumer)
            startedAt[channel] = .now
            heard.remove(channel)
            if let microphone = source as? MicrophoneCapture {
                RunLog.write("本地：开始录音，麦克风是「\(microphone.deviceName)」")
            } else {
                RunLog.write("\(channel.label)：开始录音")
            }
            // 有一路开起来就算在听了
            if !isRunning {
                isRunning = true
                listeningSince = .now
                startTicking()
            }
        } catch {
            notice = "\(channel.label)没启动：\(error.localizedDescription)"
            RunLog.write(notice ?? "")
        }
    }

    func stop() async {
        tickTask?.cancel()
        let current = pipelines
        pipelines = [:]
        for pipeline in current.values { pipeline.source.stop() }
        for pipeline in current.values {
            await pipeline.engine.stop()
            await pipeline.consumer.value
        }
        for channel in Channel.allCases { closeOpenRow(channel) }
        isRunning = false
        listeningSince = nil
        levels = [:]
        startedAt = [:]
        scheduleSave()
    }

    private func makeEngine(for channel: Channel, settings: AppSettings) throws -> SpeechEngine {
        switch settings.speechProvider {
        case .apple:
            return AppleSpeechEngine(locale: channel == .remote ? settings.remoteLocale : settings.localLocale)
        case .soniox:
            guard let key = Keychain.get("soniox") else { throw TytoError.missingAPIKey("Soniox") }
            let hints = settings.sonioxLanguageHints.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            return SonioxSpeechEngine(apiKey: key, model: settings.sonioxModel, languageHints: hints)
        }
    }

    private func startTicking() {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                self?.tick()
            }
        }
    }

    private func tick() {
        levels = meter.snapshot()
        let now = Date.now
        for (channel, level) in levels where level > 0.002 { heard.insert(channel) }
        for (channel, started) in startedAt where !heard.contains(channel) && now.timeIntervalSince(started) > 20 {
            startedAt[channel] = nil
            notice = channel == .remote
                ? "远端 20 秒都没收到声音。如果会议里有人在说话，检查：系统设置 → 隐私与安全性 → 录屏与系统录音 → 「仅系统录音」里打开 Tyto"
                : "本地 20 秒都没收到声音，检查：系统设置 → 隐私与安全性 → 麦克风 → 打开 Tyto"
            RunLog.write(notice ?? "")
        }
        for (channel, id) in openRow {
            guard let row = rows.first(where: { $0.id == id }) else { continue }
            let quiet = now.timeIntervalSince(row.updatedAt)
            if (row.pending.isEmpty && quiet > Self.silenceGap) || quiet > Self.staleGap {
                closeOpenRow(channel)
            }
        }
    }

    // MARK: - 识别结果分段

    private func handle(_ event: SpeechEvent, from channel: Channel) {
        switch event.kind {
        case .error:
            notice = event.text
            RunLog.write("\(channel.label)：\(event.text)")
        case .endOfUtterance:
            closeOpenRow(channel)
        case .partial:
            guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                if let id = openRow[channel], let index = rows.firstIndex(where: { $0.id == id }) {
                    rows[index].pending = ""
                }
                return
            }
            let index = rowIndex(for: channel, speaker: event.speaker, language: event.language)
            rows[index].pending = event.text
            rows[index].updatedAt = .now
        case .final:
            guard !event.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let index = rowIndex(for: channel, speaker: event.speaker, language: event.language)
            rows[index].text = TextJoin.join(rows[index].text, event.text)
            rows[index].pending = ""
            rows[index].updatedAt = .now
            if let language = event.language { rows[index].language = language }
            // 一个人说很长一段时，在句末断开，免得整段挤在一行
            if rows[index].text.count > 320, TextJoin.endsSentence(rows[index].text) {
                closeOpenRow(channel)
            } else {
                scheduleTranslation(rows[index].id, after: .milliseconds(900))
            }
        }
    }

    /// 这一路当前正在说的那一行；换了说话人就另起一行。
    private func rowIndex(for channel: Channel, speaker: Int?, language: String?) -> Int {
        if let id = openRow[channel], let index = rows.firstIndex(where: { $0.id == id }) {
            let current = rows[index].speaker
            if speaker == nil || current == nil || speaker == current {
                if current == nil, speaker != nil { rows[index].speaker = speaker }
                return index
            }
            closeOpenRow(channel)
        }
        let row = Utterance(channel: channel, speaker: speaker, language: language)
        rows.append(row)
        openRow[channel] = row.id
        return rows.count - 1
    }

    private func closeOpenRow(_ channel: Channel) {
        guard let id = openRow.removeValue(forKey: channel),
              let index = rows.firstIndex(where: { $0.id == id }) else { return }
        if !rows[index].pending.isEmpty {
            rows[index].text = TextJoin.join(rows[index].text, rows[index].pending)
            rows[index].pending = ""
        }
        guard !rows[index].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            rows.remove(at: index)
            return
        }
        if channel == .local, settings.value.echoCancellation, isEcho(rows[index]) {
            RunLog.write("本地：去掉回声「\(rows[index].text)」")
            rows.remove(at: index)
            return
        }
        rows[index].isClosed = true
        RunLog.write("\(channel.label)：\(rows[index].text)")
        scheduleTranslation(id, after: .zero)
        if settings.value.autoReplyOnQuestion, channel == .remote, TextJoin.isQuestion(rows[index].text) {
            reply(to: [id])
        }
        scheduleSave()
    }

    private func isEcho(_ row: Utterance) -> Bool {
        Self.isEcho(row, remote: rows.filter { $0.channel == .remote })
    }

    /// 本地这一句是不是麦克风收到的远端声音（外放开会时）。两个条件都满足才算：
    /// - 时间：本地这句是在远端某句说的过程中开始的（回声和原声同时发生；回话总在对方说完之后）；
    /// - 内容：本地这句七成以上的词都出现在那几句远端的话里。
    /// 只看内容会误删复述对方的回话，比如 "Yes, the second week of December works."
    nonisolated static func isEcho(_ row: Utterance, remote: [Utterance]) -> Bool {
        let words = words(row.text)
        guard words.count >= 3 else { return false }
        let overlapping = remote.filter {
            row.startedAt >= $0.startedAt.addingTimeInterval(-2) && row.startedAt <= $0.updatedAt.addingTimeInterval(1)
        }
        guard !overlapping.isEmpty else { return false }
        let remoteWords = Set(overlapping.flatMap { Self.words($0.displayText) })
        let shared = words.filter(remoteWords.contains).count
        return Double(shared) / Double(words.count) >= 0.7
    }

    /// 拆成词：英文按单词，中日韩按单字，忽略大小写和标点
    nonisolated static func words(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for scalar in text.lowercased().unicodeScalars {
            if TextJoin.isCJK(scalar), CharacterSet.letters.contains(scalar) {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(scalar))
            } else if CharacterSet.alphanumerics.contains(scalar) {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    // MARK: - 翻译

    /// 翻译打开时，把最近还没译的句子补上
    func translationToggled() {
        guard settings.value.translationEnabled else { return }
        for row in rows.suffix(30) where row.isClosed && row.translation == nil {
            scheduleTranslation(row.id, after: .zero)
        }
    }

    private func scheduleTranslation(_ id: UUID, after delay: Duration) {
        guard settings.value.translationEnabled else { return }
        translationTasks[id]?.cancel()
        translationTasks[id] = Task { [weak self] in
            if delay > .zero { try? await Task.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self?.translate(id)
        }
    }

    private func translate(_ id: UUID) async {
        guard let row = rows.first(where: { $0.id == id }) else { return }
        let text = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let target = settings.value.targetLanguage
        let source = row.language ?? Languages.detect(text)
        if let source, Languages.sameLanguage(source, target) { return }
        do {
            let translation = try await makeTranslator().translate(text, from: source, to: target)
            guard !Task.isCancelled, let index = rows.firstIndex(where: { $0.id == id }) else { return }
            rows[index].translation = translation
            lastTranslationError = nil
            if rows[index].isClosed { scheduleSave() }
        } catch {
            // 同样的错误（比如语言包没下载）每句都会碰到，只提示、只记一次
            if !Task.isCancelled, !(error is CancellationError), error.localizedDescription != lastTranslationError {
                lastTranslationError = error.localizedDescription
                notice = error.localizedDescription
                RunLog.write("翻译：\(error.localizedDescription)")
            }
        }
    }

    private func makeTranslator() throws -> Translator {
        let current = settings.value
        switch current.translationProvider {
        case .apple:
            return appleTranslator
        case .llm:
            let model = current.translationModel.trimmingCharacters(in: .whitespaces)
            return LLMTranslator(client: try LLMFactory.make(current.llm, model: model.isEmpty ? nil : model))
        }
    }

    // MARK: - 回复建议

    /// - ids: 要回复的那几行；nil 表示"最近的话"
    func reply(to ids: [UUID]?) {
        let current = settings.value
        let client: LLMClient
        do {
            client = try LLMFactory.make(current.llm)
        } catch {
            notice = error.localizedDescription
            return
        }

        let targets = ids.map { wanted in rows.filter { wanted.contains($0.id) } } ?? recentRowsToAnswer()
        guard let last = targets.last, let lastIndex = rows.firstIndex(where: { $0.id == last.id }) else {
            notice = "还没有可以回复的话"
            return
        }
        let context = Array(rows[max(0, lastIndex - 59)...lastIndex])
        let prompt = ReplyPrompt(settings: current, title: title, context: self.context,
                                 skills: skills.skills.filter { activeSkillIDs.contains($0.id) },
                                 rows: context, targets: Set(targets.map(\.id)), label: speakerLabel)

        if let previous = replies.indices.last, replies[previous].isStreaming {
            replyTask?.cancel()
            replies[previous].isStreaming = false
            replies[previous].error = "被新的回复打断"
        }
        let reply = Reply(target: ids == nil ? "最近的话" : "选中的 \(targets.count) 句")
        replies.append(reply)
        let replyID = reply.id
        replyTask = Task { [weak self] in
            do {
                for try await chunk in client.stream(system: prompt.system, user: prompt.user, maxTokens: 16_000) {
                    self?.updateReply(replyID) { $0.text += chunk }
                }
                self?.updateReply(replyID) { $0.isStreaming = false }
            } catch {
                let message = error is CancellationError ? "已停止" : error.localizedDescription
                self?.updateReply(replyID) {
                    if $0.isStreaming { $0.error = message }
                    $0.isStreaming = false
                }
            }
            self?.scheduleSave()
        }
    }

    func stopReply() {
        replyTask?.cancel()
    }

    /// "最近的话"：最后一次本地发言之后远端说的话（最多 3 句）；没有就取最后 2 句
    private func recentRowsToAnswer() -> [Utterance] {
        let spoken = rows.filter { !$0.displayText.trimmingCharacters(in: .whitespaces).isEmpty }
        var remote: [Utterance] = []
        for row in spoken.reversed() {
            if row.channel == .local { break }
            remote.insert(row, at: 0)
            if remote.count == 3 { break }
        }
        return remote.isEmpty ? Array(spoken.suffix(2)) : remote
    }

    private func updateReply(_ id: UUID, _ change: (inout Reply) -> Void) {
        guard let index = replies.firstIndex(where: { $0.id == id }) else { return }
        change(&replies[index])
    }

    var keywordList: [String] {
        keywords.split(whereSeparator: { ",，、;；\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - 截屏回复

    /// 截图原图（重新生成时用），只放在内存里
    private var screenshotImages: [UUID: Data] = [:]

    /// 框选一块屏幕，生成回复
    func captureAndReply() {
        Task {
            guard let png = await Screenshot.captureInteractive() else { return }
            replyToScreenshot(png)
        }
    }

    /// 用剪贴板里的图片生成回复
    func replyToClipboardImage() {
        guard let png = Screenshot.clipboardImage() else {
            notice = "剪贴板里没有图片。可以用 ⌘⌃⇧4 截一块屏幕到剪贴板，或者直接按 ⌃⌥S 框选。"
            return
        }
        replyToScreenshot(png)
    }

    /// 看懂截图里的聊天或邮件，生成几个能直接粘贴的回复；第一个自动放进剪贴板
    func replyToScreenshot(_ png: Data, instruction: String? = nil) {
        let current = settings.value
        let client: LLMClient
        do {
            client = try LLMFactory.make(current.llm)
        } catch {
            notice = error.localizedDescription
            return
        }
        if let previous = replies.indices.last, replies[previous].isStreaming {
            replyTask?.cancel()
            replies[previous].isStreaming = false
            replies[previous].error = "被新的回复打断"
        }
        var reply = Reply(target: "截图")
        reply.source = "screenshot"
        reply.thumbnail = Screenshot.thumbnail(png)
        reply.instruction = instruction
        reply.status = "识别截图里的文字…"
        replies.append(reply)
        let replyID = reply.id
        screenshotImages[replyID] = png
        let skills = skills.skills.filter { activeSkillIDs.contains($0.id) }
        let context = context

        replyTask = Task { [weak self] in
            let started = Date.now
            let lines = await Screenshot.recognizeText(png)
            RunLog.write("截屏回复：OCR \(lines.count) 行，\(Int(Date.now.timeIntervalSince(started) * 1000)) ms")
            let withImage = current.screenshotMode == .imageAndText
            let prompt = ScreenshotPrompt(settings: current, context: context, skills: skills,
                                          ocr: Screenshot.layoutText(lines), imageAttached: withImage,
                                          instruction: instruction)
            self?.updateReply(replyID) { $0.status = "生成回复…" }
            do {
                let images = withImage ? [Screenshot.forModel(png)] : []
                for try await chunk in client.stream(system: prompt.system, user: prompt.user, images: images,
                                                     maxTokens: 16_000) {
                    self?.updateReply(replyID) {
                        $0.text += chunk
                        $0.status = nil
                    }
                }
                self?.finishScreenshotReply(replyID, copyFirst: current.copyFirstScreenshotReply)
            } catch {
                let message = error is CancellationError ? "已停止" : error.localizedDescription
                self?.updateReply(replyID) {
                    if $0.isStreaming { $0.error = message }
                    $0.isStreaming = false
                    $0.status = nil
                }
            }
            self?.scheduleSave()
        }
    }

    /// 带着新的要求（比如"婉拒""用中文"）对同一张截图重新生成
    func regenerateScreenshotReply(_ id: UUID, instruction: String) {
        guard let png = screenshotImages[id] else {
            notice = "原图已经不在了（重启过 Tyto），请重新截一次"
            return
        }
        replyToScreenshot(png, instruction: instruction)
    }

    func canRegenerate(_ id: UUID) -> Bool { screenshotImages[id] != nil }

    private func finishScreenshotReply(_ id: UUID, copyFirst: Bool) {
        updateReply(id) { reply in
            reply.isStreaming = false
            reply.status = nil
            if copyFirst, let first = ReplyFormat.firstReply(reply.text) {
                Clipboard.copy(first.body)
                reply.copiedSection = first.title
            }
        }
    }

    func copy(_ section: ReplySection, of id: UUID) {
        Clipboard.copy(section.body)
        updateReply(id) { $0.copiedSection = section.title }
    }

    // MARK: - 说话人、选择

    func speakerLabel(_ row: Utterance) -> String {
        if let name = speakerNames[row.speakerKey], !name.isEmpty { return name }
        return defaultSpeakerLabel(row)
    }

    func defaultSpeakerLabel(_ row: Utterance) -> String {
        row.speaker.map { "\(row.channel.label)·说话人\($0)" } ?? row.channel.label
    }

    func rename(_ key: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        speakerNames[key] = trimmed.isEmpty ? nil : trimmed
    }

    /// 会话里出现过的说话人（键 → 默认名字），给"说话人"设置用
    var knownSpeakers: [(key: String, label: String)] {
        var seen = Set<String>()
        return rows.compactMap { row in
            guard seen.insert(row.speakerKey).inserted else { return nil }
            return (row.speakerKey, defaultSpeakerLabel(row))
        }
    }

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    /// 只给自测的预览图用：直接放进示例记录
    func showSample(rows: [Utterance], replies: [Reply], selection: Set<UUID>) {
        self.rows = rows
        self.replies = replies
        self.selection = selection
    }

    // MARK: - 保存、新会议、导出

    private struct SessionFile: Codable {
        var title: String
        var context: String
        var activeSkillIDs: [String]
        var speakerNames: [String: String]
        var rows: [Utterance]
        var replies: [Reply]
        var keywords: String?
    }

    static var folder: URL { URL.applicationSupportDirectory.appending(path: "Tyto/sessions") }
    private static var currentFile: URL { folder.appending(path: "current.json") }

    func load() {
        guard let data = try? Data(contentsOf: Self.currentFile),
              let file = try? JSONDecoder().decode(SessionFile.self, from: data) else { return }
        title = file.title
        context = file.context
        activeSkillIDs = Set(file.activeSkillIDs)
        speakerNames = file.speakerNames
        keywords = file.keywords ?? ""
        rows = file.rows.map { row in
            var row = row
            row.isClosed = true
            return row
        }
        replies = file.replies.map { reply in
            var reply = reply
            reply.isStreaming = false
            reply.status = nil
            return reply
        }
    }

    private func scheduleSave() {
        guard persists else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        guard persists else { return }
        let file = SessionFile(title: title, context: context, activeSkillIDs: activeSkillIDs.sorted(),
                               speakerNames: speakerNames, rows: rows.filter(\.isClosed), replies: replies,
                               keywords: keywords)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(file) {
            try? data.write(to: Self.currentFile, options: .atomic)
        }
    }

    /// 把当前会议存档（sessions/日期-名称.json），清空记录；背景和技能留着，下一场常常用得上
    func newSession() async {
        if isRunning { await stop() }
        save()
        if !rows.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let name = title.replacingOccurrences(of: "/", with: "-")
            try? FileManager.default.copyItem(
                at: Self.currentFile,
                to: Self.folder.appending(path: "\(formatter.string(from: .now))-\(name).json"))
        }
        rows = []
        replies = []
        selection = []
        speakerNames = [:]
        title = "新会议"
        save()
    }

    func markdown() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = "# \(title)\n\n"
        if let first = rows.first { text += "\(formatter.string(from: first.startedAt))\n\n" }
        let background = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !background.isEmpty { text += "## 背景\n\n\(background)\n\n" }
        text += "## 记录\n\n"
        formatter.dateFormat = "HH:mm:ss"
        for row in rows {
            text += "- **\(speakerLabel(row))** \(formatter.string(from: row.startedAt))：\(row.displayText)\n"
            if let translation = row.translation { text += "  - 译：\(translation)\n" }
        }
        if !replies.isEmpty {
            text += "\n## 回复建议\n"
            for reply in replies {
                text += "\n### \(formatter.string(from: reply.createdAt)) · \(reply.target)\n\n\(reply.text)\n"
            }
        }
        return text
    }
}

/// 音频线程写、界面线程读的音量表
final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Channel: Float] = [:]

    func update(_ channel: Channel, _ level: Float) {
        lock.withLock { values[channel] = max(level, (values[channel] ?? 0) * 0.8) }
    }

    func snapshot() -> [Channel: Float] {
        lock.withLock {
            let current = values
            for key in values.keys { values[key] = (values[key] ?? 0) * 0.6 }
            return current
        }
    }
}

enum Clipboard {
    @MainActor
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
