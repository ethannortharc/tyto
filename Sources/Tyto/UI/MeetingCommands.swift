import AppKit
import UniformTypeIdentifiers

/// 保存、清空、打开、导出、删除会议记录。悬浮窗菜单、设置窗口、菜单栏都走这里；要问一句的在这里问
@MainActor
enum MeetingCommands {
    /// 清空，开始新会议。有内容还没存进会议记录的，先问存不存
    static func clear(_ session: SessionModel) {
        guard !session.isEmpty else { return }
        guard let saved = confirmLeaving(session, opening: nil) else { return }
        Task {
            await session.clear()
            session.show(saved ? tr("已存进会议记录，开始新会议", "Saved to Meeting Records; new meeting started")
                               : tr("已清空，开始新会议", "Cleared; new meeting started"))
        }
    }

    /// 打开会议记录里的一场接着记
    static func open(_ file: String, in records: MeetingRecords, session: SessionModel) {
        guard file != session.recordFile, let record = records.record(file) else { return }
        guard confirmLeaving(session, opening: record.title) != nil else { return }
        Task { await session.open(record, file: file) }
    }

    /// 现在这场有没存的内容时问：保存 / 不保存 / 取消。
    /// 返回 nil 是取消；true 是存了；false 是没内容要存或选了不保存
    private static func confirmLeaving(_ session: SessionModel, opening next: String?) -> Bool? {
        guard session.hasUnsavedContent else { return false }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = tr("这场会议还没存进会议记录", "This meeting isn't in Meeting Records yet")
        alert.informativeText = next.map {
            tr("打开「\($0)」之前，要先保存现在这场吗？不保存的话，现在的记录就清掉了。",
               "Save the current meeting before opening “\($0)”? If you don't, the current transcript is cleared.")
        } ?? tr("清空之前要先保存吗？不保存的话，现在的记录就找不回来了。",
                "Save it before clearing? If you don't, the current transcript can't be recovered.")
        alert.addButton(withTitle: next == nil ? tr("保存并清空", "Save and Clear") : tr("保存后打开", "Save and Open"))
        alert.addButton(withTitle: tr("不保存", "Don't Save"))
        alert.addButton(withTitle: tr("取消", "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            session.saveToRecords()
            return true
        case .alertSecondButtonReturn:
            return false
        default:
            return nil
        }
    }

    /// 导出成 Markdown
    static func export(_ record: MeetingRecord) {
        guard !record.isEmpty else { return }
        NSApp.activate()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(record.suggestedFileName).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try record.markdown().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    /// 删除会议记录里的一场（移到废纸篓），先确认
    @discardableResult
    static func delete(_ file: String, title: String, in records: MeetingRecords, session: SessionModel) -> Bool {
        let alert = NSAlert()
        alert.messageText = tr("删除「\(title)」？", "Delete “\(title)”?")
        alert.informativeText = tr("会移到废纸篓。", "It will be moved to the Trash.")
        alert.addButton(withTitle: tr("删除", "Delete")).hasDestructiveAction = true
        alert.addButton(withTitle: tr("取消", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn, records.delete(file) else { return false }
        session.recordDeleted(file)
        return true
    }
}
