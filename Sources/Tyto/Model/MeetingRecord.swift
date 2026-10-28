import AppKit
import Foundation

/// 存下来的一场会议。current.json（正在开的这场）和会议记录里的每个文件都是这个格式。
struct MeetingRecord: Codable {
    /// 老版本存的文件没有
    var id: UUID?
    var title: String
    var context: String
    var activeSkillIDs: [String]
    var speakerNames: [String: String]
    var rows: [Utterance]
    var replies: [Reply]
    var keywords: String?
    /// 只在 current.json 里有：这场会议存在会议记录的哪个文件里（还没保存过是 nil）
    var recordFile: String?

    /// 按字幕算；只有截屏回复、没有字幕的按回复算
    var startedAt: Date? { rows.first?.startedAt ?? replies.first?.createdAt }
    var endedAt: Date? { rows.last?.updatedAt ?? replies.last?.createdAt }
    var isEmpty: Bool { rows.isEmpty && replies.isEmpty }

    func speakerLabel(_ row: Utterance) -> String {
        if let name = speakerNames[row.speakerKey], !name.isEmpty { return name }
        return Self.defaultSpeakerLabel(row)
    }

    static func defaultSpeakerLabel(_ row: Utterance) -> String {
        row.speaker.map { tr("\(row.channel.label)·说话人\($0)", "\(row.channel.label) · Speaker \($0)") } ?? row.channel.label
    }

    /// 出现过的说话人，按第一次说话的先后
    var speakers: [String] {
        var seen = Set<String>()
        return rows.compactMap { row in seen.insert(row.speakerKey).inserted ? speakerLabel(row) : nil }
    }

    /// 算作"我"的本地说话人：改名成「我」/ Me 的；一个都没有时是整个本地麦克风
    var meSpeakerKeys: Set<String> {
        Set(speakerNames.filter { key, name in
            key.hasPrefix("\(Channel.local.rawValue):")
                && ["我", "me", "myself", "自己"].contains(name.trimmingCharacters(in: .whitespaces).lowercased())
        }.keys)
    }

    /// 这条回复建议之后我实际说了什么
    func followUp(for reply: Reply) -> ReplyFollowUp? {
        FollowUp.find(for: reply, in: rows, me: meSpeakerKeys)
    }

    func markdown() -> String {
        let formatter = Self.fixedFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var text = "# \(title)\n\n"
        if let start = startedAt { text += "\(formatter.string(from: start))\n\n" }
        let background = context.trimmingCharacters(in: .whitespacesAndNewlines)
        if !background.isEmpty { text += tr("## 背景\n\n\(background)\n\n", "## Context\n\n\(background)\n\n") }
        text += tr("## 记录\n\n", "## Transcript\n\n")
        formatter.dateFormat = "HH:mm:ss"
        for row in rows {
            text += "- **\(speakerLabel(row))** \(formatter.string(from: row.startedAt))：\(row.displayText)\n"
            if let translation = row.translation { text += tr("  - 译：\(translation)\n", "  - Translation: \(translation)\n") }
        }
        if !replies.isEmpty {
            text += tr("\n## 回复建议\n", "\n## Suggested Replies\n")
            for reply in replies {
                text += "\n### \(formatter.string(from: reply.createdAt)) · \(reply.target)\n\n"
                if let quote = reply.quote {
                    text += "> \(reply.quoteSpeaker.map { "**\($0)**：" } ?? "")\(quote)\n\n"
                }
                text += "\(reply.text)\n"
                if let followUp = followUp(for: reply), !followUp.rows.isEmpty {
                    text += tr("\n**我实际说的**（\(followUp.verdict.label)）：\(followUp.text)\n",
                               "\n**What I actually said** (\(followUp.verdict.label)): \(followUp.text)\n")
                }
            }
        }
        return text
    }

    /// 导出时建议的文件名：会议名 + 日期
    var suggestedFileName: String {
        let formatter = Self.fixedFormatter()
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return startedAt.map { "\(name) \(formatter.string(from: $0))" } ?? name
    }

    /// 文件名、导出里的日期：固定公历和数字写法，不随系统的日历、地区变
    static func fixedFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter
    }

    /// 会议记录里的文件名：开始时间 + id 前 8 位（改会议名不改文件名）
    static func fileName(id: UUID, startedAt: Date?) -> String {
        let formatter = fixedFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "\(formatter.string(from: startedAt ?? .now))-\(id.uuidString.prefix(8).lowercased()).json"
    }
}

/// 会议记录：sessions 文件夹里除了 current.json，每个文件是一场存下来的会议。
@MainActor
final class MeetingRecords: ObservableObject {
    struct Summary: Identifiable, Equatable, Sendable {
        /// 文件名，也当 id
        let file: String
        var id: String { file }
        let recordID: UUID?
        let title: String
        let startedAt: Date?
        let endedAt: Date?
        let rowCount: Int
        let replyCount: Int
        let speakers: [String]
        /// 搜索用：会议名、背景、每句原文和译文，都转成小写
        let searchText: String
        let modifiedAt: Date
    }

    /// 会议记录有变化（保存、清空、打开、删除）时发
    static let changed = Notification.Name("TytoMeetingRecordsChanged")

    @Published private(set) var items: [Summary] = []
    @Published private(set) var isLoading = false
    let folder: URL
    /// 文件改动时间没变就不再解析
    private var cache: [String: Summary] = [:]
    private var watchers = 0
    private var stale = true
    private var loadTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?

    init(folder: URL = SessionModel.defaultFolder) {
        self.folder = folder
        observer = NotificationCenter.default.addObserver(forName: Self.changed, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
    }

    /// 会议记录页打开时才跟着文件变化刷新（开会时当前这场每隔几秒存一次，没人看就不重读）
    func startWatching() {
        watchers += 1
        if stale { reload() }
    }

    func stopWatching() { watchers = max(0, watchers - 1) }

    private func changed() {
        stale = true
        if watchers > 0 { reload() }
    }

    func reload() {
        stale = false
        if items.isEmpty { isLoading = true }
        let folder = folder
        let cache = cache
        loadTask?.cancel()
        loadTask = Task {
            let found = await Task.detached(priority: .userInitiated) { Self.scan(folder, cache: cache) }.value
            guard !Task.isCancelled else { return }
            self.cache = Dictionary(uniqueKeysWithValues: found.map { ($0.file, $0) })
            items = found
            isLoading = false
        }
    }

    func url(_ file: String) -> URL { folder.appending(path: file) }

    func record(_ file: String) -> MeetingRecord? {
        guard let data = try? Data(contentsOf: url(file)) else { return nil }
        return try? JSONDecoder().decode(MeetingRecord.self, from: data)
    }

    /// 改会议名（不是正在开的这场；那场改 SessionModel.title）
    func rename(_ file: String, to title: String) {
        guard var record = record(file) else { return }
        record.title = title
        if let data = try? JSONEncoder().encode(record) { try? data.write(to: url(file), options: .atomic) }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }

    /// 删掉一场：移到废纸篓（toTrash 为 false 时直接删，自测用）
    @discardableResult
    func delete(_ file: String, toTrash: Bool = true) -> Bool {
        do {
            if toTrash {
                try FileManager.default.trashItem(at: url(file), resultingItemURL: nil)
            } else {
                try FileManager.default.removeItem(at: url(file))
            }
        } catch {
            RunLog.write("删不了会议记录 \(file)：\(error.localizedDescription)")
            return false
        }
        NotificationCenter.default.post(name: Self.changed, object: nil)
        return true
    }

    /// 读一遍文件夹：新的、改过的文件重新解析，其余用上次的结果。最近的会议在前
    nonisolated static func scan(_ folder: URL, cache: [String: Summary]) -> [Summary] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        var result: [Summary] = []
        for url in files where url.pathExtension == "json" && url.lastPathComponent != SessionModel.currentFileName {
            let modified = (try? url.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            let file = url.lastPathComponent
            if let cached = cache[file], cached.modifiedAt == modified {
                result.append(cached)
                continue
            }
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(MeetingRecord.self, from: data) else { continue }
            let text = ([record.title, record.context] + record.rows.flatMap { [$0.text, $0.translation ?? ""] })
                .joined(separator: "\n").lowercased()
            result.append(Summary(file: file, recordID: record.id, title: record.title, startedAt: record.startedAt,
                                  endedAt: record.endedAt, rowCount: record.rows.count, replyCount: record.replies.count,
                                  speakers: record.speakers, searchText: text, modifiedAt: modified))
        }
        return result.sorted { ($0.startedAt ?? $0.modifiedAt) > ($1.startedAt ?? $1.modifiedAt) }
    }
}

/// 会议时长、日期、句数的显示，跟着界面语言走（不跟系统）
enum MeetingTime {
    static func lines(_ count: Int) -> String { tr("\(count) 句", count == 1 ? "1 line" : "\(count) lines") }
    static func replies(_ count: Int) -> String { tr("\(count) 条回复建议", count == 1 ? "1 reply" : "\(count) replies") }
    static func names(_ names: [String]) -> String { names.joined(separator: tr("、", ", ")) }

    static func duration(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let minutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded()))
        if minutes < 60 { return tr("\(minutes) 分钟", "\(minutes) min") }
        return minutes % 60 == 0
            ? tr("\(minutes / 60) 小时", "\(minutes / 60) h")
            : tr("\(minutes / 60) 小时 \(minutes % 60) 分", "\(minutes / 60) h \(minutes % 60) min")
    }

    /// 今天的只写时间；今年的写月日；更早的带年份
    static func day(_ date: Date?) -> String {
        guard let date else { return "" }
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: L10n.isEnglish ? "en_US" : "zh_CN")
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
            return tr("今天 \(formatter.string(from: date))", "Today \(formatter.string(from: date))")
        }
        if calendar.isDateInYesterday(date) {
            formatter.dateFormat = "HH:mm"
            return tr("昨天 \(formatter.string(from: date))", "Yesterday \(formatter.string(from: date))")
        }
        let thisYear = calendar.component(.year, from: date) == calendar.component(.year, from: .now)
        formatter.dateFormat = L10n.isEnglish ? (thisYear ? "MMM d, HH:mm" : "MMM d, yyyy HH:mm")
                                              : (thisYear ? "M月d日 HH:mm" : "yyyy年M月d日 HH:mm")
        return formatter.string(from: date)
    }
}
