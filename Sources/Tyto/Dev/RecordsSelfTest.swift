import Foundation

extension SelfTest {
    /// 会议记录：保存、自动更新、清空、打开接着记、重开 Tyto、老文件、删除、导出。
    /// 全在临时文件夹里做，不碰真实的会话和会议记录
    @MainActor
    static func records() async -> Int32 {
        let folder = FileManager.default.temporaryDirectory.appending(path: "tyto-records-test-\(UUID().uuidString.prefix(8))")
        defer { try? FileManager.default.removeItem(at: folder) }
        let settings = SettingsStore(persists: false)
        let session = SessionModel(settings: settings, skills: SkillStore(), persists: true, folder: folder)
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "✓ " : "✗ ") + what)
            if !ok { failures += 1 }
        }
        func files() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasSuffix(".json") && $0 != SessionModel.currentFileName }.sorted()
        }
        func read(_ file: String) -> MeetingRecord? {
            (try? Data(contentsOf: folder.appending(path: file))).flatMap { try? JSONDecoder().decode(MeetingRecord.self, from: $0) }
        }
        let store = MeetingRecords(folder: folder)
        store.startWatching()
        func waitForList(_ count: Int) async {
            for _ in 0..<60 where store.items.count != count { try? await Task.sleep(for: .milliseconds(50)) }
        }

        session.saveToRecords()
        check(files().isEmpty && session.recordFile == nil && session.toast?.ok == false, "没内容时不保存，提示还没有内容")

        let rows = SampleData.rows()
        let closed = rows.filter(\.isClosed).count
        session.showSample(rows: rows, replies: [SampleData.meetingReply(answering: rows)], selection: [])
        session.title = "Northwind 评审"
        session.speakerNames["local:1"] = "我"
        check(session.hasUnsavedContent, "有内容、还没保存：清空前要问")
        session.saveToRecords()
        let first = session.recordFile ?? ""
        check(files() == [first] && !first.isEmpty, "保存后会议记录里多了一个文件（\(first)）")
        check(!session.hasUnsavedContent && session.toast?.ok == true, "保存后不再算没保存，有确认提示")
        check(read(first)?.rows.count == closed && read(first)?.replies.count == 1, "存了说完的 \(closed) 句和 1 条回复（没说完的那句不存）")
        check(read(first)?.id == session.sessionID && read(first)?.recordFile == nil, "文件里记着这场的编号")

        session.title = "Northwind 方案评审"
        session.save()
        check(files() == [first] && read(first)?.title == "Northwind 方案评审", "保存过的会议有改动时自动更新那个文件，不多出文件")
        session.saveToRecords()
        check(files() == [first], "再点保存也还是那一个文件")

        await waitForList(1)
        check(store.items.count == 1 && store.items.first?.rowCount == closed && store.items.first?.title == "Northwind 方案评审",
              "会议记录列表读到这场")
        check(store.items.first?.searchText.contains("december") == true && store.items.first?.searchText.contains("十二月") == true,
              "原文和译文都能搜到")
        check(store.items.first?.speakers.first == tr("远端·说话人1", "Remote · Speaker 1") && store.items.first?.speakers.contains("我") == true,
              "说话人：改过名的用名字，没改的用默认名字")

        let firstID = session.sessionID
        await session.clear()
        check(session.isEmpty && session.recordFile == nil && session.sessionID != firstID && session.title == tr("新会议", "New Meeting"),
              "清空后是新的一场")
        check(files() == [first], "清空不动会议记录")
        let current = (try? Data(contentsOf: folder.appending(path: SessionModel.currentFileName)))
            .flatMap { try? JSONDecoder().decode(MeetingRecord.self, from: $0) }
        check(current?.rows.isEmpty == true && current?.recordFile == nil, "current.json 也清空了")

        session.showSample(rows: Array(rows.prefix(2)), replies: [], selection: [])
        session.title = "周会"
        check(session.hasUnsavedContent, "新的一场有内容、没保存")
        session.saveToRecords()
        let second = session.recordFile ?? ""
        check(files().count == 2 && second != first, "第二场存成另一个文件")

        guard let firstRecord = read(first) else {
            print("✗ 读不了第一场")
            return 1
        }
        await session.open(firstRecord, file: first)
        check(session.sessionID == firstID && session.rows.count == closed && session.title == "Northwind 方案评审" && session.recordFile == first,
              "打开第一场接着记")
        session.title = "Northwind 方案评审（续）"
        session.save()
        check(read(first)?.title == "Northwind 方案评审（续）" && files().count == 2, "接着记的改动写回原来的文件")

        let relaunched = SessionModel(settings: settings, skills: SkillStore(), persists: false, folder: folder)
        relaunched.load()
        check(relaunched.recordFile == first && relaunched.sessionID == firstID && relaunched.rows.count == closed,
              "重开 Tyto：还认得这场在会议记录里")

        // 老版本「开始新会议」存的文件：没有编号，文件名带会议名
        var legacy = firstRecord
        legacy.id = nil
        legacy.title = "老格式的会"
        let legacyFile = "20261001-100000-老格式的会.json"
        try? JSONEncoder().encode(legacy).write(to: folder.appending(path: legacyFile))
        await waitForList(3)
        check(store.items.contains { $0.file == legacyFile && $0.recordID == nil }, "老格式的文件也列得出来")
        await session.open(legacy, file: legacyFile)
        check(read(legacyFile)?.id != nil && read(legacyFile)?.id == session.sessionID, "老文件打开后补上编号，写回原文件")

        check(store.delete(first, toTrash: false), "删掉第一场")
        session.recordDeleted(first)
        check(files().count == 2 && session.recordFile == legacyFile, "删别的会议不影响当前这场")
        check(store.delete(legacyFile, toTrash: false), "删掉当前这场")
        session.recordDeleted(legacyFile)
        check(session.recordFile == nil && session.hasUnsavedContent, "当前这场被删后变回没保存（内容还在）")
        await waitForList(1)
        check(store.items.map(\.file) == [second], "列表跟着更新")

        let markdown = firstRecord.markdown()
        check(markdown.contains("# Northwind 方案评审") && markdown.contains("December") && markdown.contains("十二月"),
              "导出的 Markdown 有会议名、原文和译文")
        check(firstRecord.suggestedFileName.hasPrefix("Northwind 方案评审 ") && !firstRecord.suggestedFileName.contains("/"),
              "导出文件名：会议名 + 日期")

        print(failures == 0 ? "会议记录：全部通过" : "会议记录：\(failures) 项没通过")
        return failures == 0 ? 0 : 1
    }
}
