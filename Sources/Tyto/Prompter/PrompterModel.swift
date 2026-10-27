import AppKit
import Combine
import UniformTypeIdentifiers

/// 提词器：会前准备的材料显示在一个透明窗口里。
/// - 跟读：我照着稿子说的时候，滚到说到的那一段并高亮；
/// - 对方提到：对方的话对上了稿子里的某一节，底下提示一下，⌃⌥J 跳过去；
/// - 文件改了自动重新载入，位置不变。
@MainActor
final class PrompterModel: ObservableObject {
    struct Suggestion: Equatable {
        let section: Int
        let title: String
        let at: Date
    }

    @Published private(set) var document: PrompterDocument?
    @Published private(set) var error: String?
    @Published private(set) var matcher = PrompterMatch.Index([])
    /// 读的位置（窗口里离顶上 30% 那条线上的段）
    @Published private(set) var reading: Int?
    /// 高亮的段（跟读对上的，或者跳过去的）
    @Published private(set) var current: Int?
    @Published var suggestion: Suggestion?
    /// 提词器后面的画面是亮的（字色自动时换黑字）
    @Published var backdropIsLight = false

    let web = PrompterWeb()
    private let settings: SettingsStore
    private let session: SessionModel
    private var subscriptions: Set<AnyCancellable> = []
    private var watchTask: Task<Void, Never>?
    /// 上次跟读比过的话，没变就不再算
    private var lastSaid = ""
    /// 已经看过的对方的话（只对新说完的提示）
    private var seenRemote: Set<UUID> = []

    /// 提示这么久没理就收起来
    static let suggestionLifetime: TimeInterval = 45

    init(settings: SettingsStore, session: SessionModel) {
        self.settings = settings
        self.session = session
        web.onBlocks = { [weak self] blocks in self?.indexed(blocks) }
        web.onReading = { [weak self] index in self?.reading = index }
        web.onDropFile = { [weak self] url in self?.open(url) }
    }

    /// 开始工作：载入上次的材料、跟着会议记录走、盯着文件有没有改
    func start() {
        let path = settings.value.prompterPath
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) { open(URL(filePath: path), remember: false) }
        session.$rows
            .throttle(for: .milliseconds(350), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] rows in
                guard let self else { return }
                heard(rows, me: session.meSpeakerKeys, now: .now)
            }
            .store(in: &subscriptions)
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.reloadIfChanged()
                self?.expireSuggestion()
            }
        }
    }

    var blocks: [PrompterMatch.Block] { matcher.blocks }
    var sections: [PrompterMatch.Section] { matcher.sections }

    var currentSection: Int? {
        guard let block = reading ?? current else { return nil }
        return PrompterMatch.section(containing: block, in: sections)
    }

    // MARK: - 材料

    func open(_ url: URL, remember: Bool = true) {
        do {
            let document = try PrompterDocument.load(url)
            let reopening = self.document?.url == document.url
            self.document = document
            error = nil
            if !reopening {
                current = nil
                reading = nil
                suggestion = nil
            }
            web.load(document, keeping: reopening ? reading : nil)
            if remember { addToRecent(url) }
        } catch {
            self.error = tr("打不开「\(url.lastPathComponent)」：\(error.localizedDescription)",
                            "Can't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = PrompterDocument.kinds.keys.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.message = tr("选一份讲稿或材料：Markdown、HTML 或纯文本", "Choose your notes: Markdown, HTML, or plain text")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func close() {
        document = nil
        matcher = PrompterMatch.Index([])
        current = nil
        reading = nil
        suggestion = nil
        web.clear()
        settings.value.prompterPath = ""
    }

    func revealInFinder() {
        guard let url = document?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 最近用过的材料（还在的）
    var recent: [URL] {
        settings.value.prompterRecent.map { URL(filePath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func addToRecent(_ url: URL) {
        var value = settings.value
        value.prompterPath = url.path
        value.prompterRecent = Array(([url.path] + value.prompterRecent.filter { $0 != url.path }).prefix(8))
        settings.value = value
    }

    private func reloadIfChanged() {
        guard let document, let modified = PrompterDocument.modificationDate(of: document.url),
              modified != document.modified else { return }
        open(document.url, remember: false)
    }

    private func indexed(_ blocks: [PrompterMatch.Block]) {
        matcher = PrompterMatch.Index(blocks)
        if let current, current >= blocks.count { self.current = nil }
        web.mark(current)
    }

    // MARK: - 跳转

    func go(to block: Int) {
        current = block
        // 滚到那儿以后读的位置就是这一段；网页的滚动消息晚一点到，先记上
        reading = block
        web.go(to: block, mark: true)
    }

    func goToSection(_ index: Int) {
        guard sections.indices.contains(index) else { return }
        go(to: sections[index].heading)
        if suggestion?.section == index { suggestion = nil }
    }

    /// 上一节 / 下一节（从读的位置算）
    func step(_ direction: Int) {
        guard !sections.isEmpty else { return }
        let here = currentSection
        let target: Int
        if let here {
            // 往上：读的位置已经在这一节中间时，先回到这一节的标题
            if direction < 0, let reading, reading > sections[here].heading {
                target = here
            } else {
                target = here + direction
            }
        } else {
            target = direction > 0 ? 0 : -1
        }
        goToSection(min(max(target, 0), sections.count - 1))
    }

    func jumpToSuggestion() {
        guard let suggestion else { return }
        goToSection(suggestion.section)
        self.suggestion = nil
    }

    private func expireSuggestion() {
        if let suggestion, Date.now.timeIntervalSince(suggestion.at) > Self.suggestionLifetime { self.suggestion = nil }
    }

    // MARK: - 跟读、对方提到

    /// 会议记录变了：我在说 → 跟读；对方刚说完一句 → 看是不是提到了哪一节
    func heard(_ rows: [Utterance], me: Set<String>, now: Date) {
        guard document != nil, !blocks.isEmpty else { return }
        if settings.value.prompterFollow { follow(rows, me: me, now: now) }
        if settings.value.prompterHints { hint(rows, now: now) }
    }

    private func isMe(_ row: Utterance, _ me: Set<String>) -> Bool {
        row.channel == .local && (me.isEmpty || me.contains(row.speakerKey))
    }

    private func follow(_ rows: [Utterance], me: Set<String>, now: Date) {
        guard let index = rows.lastIndex(where: { isMe($0, me) }) else { return }
        let row = rows[index]
        // 只跟正在说的（几秒内还在变的）
        guard now.timeIntervalSince(row.updatedAt) < 6 else { return }
        var said = [row.displayText, row.translation ?? ""]
        // 这一句刚开头时，带上紧挨着的上一句
        if let previous = rows[..<index].last(where: { isMe($0, me) }),
           row.startedAt.timeIntervalSince(previous.updatedAt) < 4 {
            said.insert(contentsOf: [previous.displayText, previous.translation ?? ""], at: 0)
        }
        let text = said.joined(separator: " ")
        guard text != lastSaid else { return }
        lastSaid = text
        guard let block = matcher.follow(said: text, current: current), block != current else { return }
        go(to: block)
    }

    private func hint(_ rows: [Utterance], now: Date) {
        let fresh = rows.filter { $0.channel == .remote && $0.isClosed && !seenRemote.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seenRemote.formUnion(fresh.map(\.id))
        guard let last = fresh.last, now.timeIntervalSince(last.updatedAt) < 30 else { return }
        // 同一个人连着说的几句一起看（问题常常被断成两句）
        var heard = [last.displayText, last.translation ?? ""]
        if let index = rows.firstIndex(where: { $0.id == last.id }), index > 0 {
            let previous = rows[index - 1]
            if previous.speakerKey == last.speakerKey, last.startedAt.timeIntervalSince(previous.updatedAt) < 8 {
                heard.insert(contentsOf: [previous.displayText, previous.translation ?? ""], at: 0)
            }
        }
        guard let section = matcher.suggest(heard: heard.joined(separator: " "), excluding: currentSection) else { return }
        suggestion = Suggestion(section: section, title: sections[section].title, at: now)
    }

    // MARK: - 外观

    func applyStyle(theme: OverlayTheme) {
        web.apply(theme: theme, opacity: settings.value.overlayOpacity, fontSize: settings.value.prompterFontSize)
    }
}
