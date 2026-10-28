import SwiftUI

/// 会议记录页：左边是存下来的会议（最近的在上），右边是选中那场的完整记录
struct RecordsPage: View {
    @ObservedObject var records: MeetingRecords
    @ObservedObject var session: SessionModel
    @State private var selected: String?
    @State private var query = ""

    private var filtered: [MeetingRecords.Summary] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return records.items }
        return records.items.filter { item in words.allSatisfy(item.searchText.contains) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                TextField("", text: $query, prompt: Text(tr("搜索会议名或内容", "Search names or content")))
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                list
            }
            .frame(width: 250)
            Divider()
            detail.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay(alignment: .top) { Divider() }
        .padding(.top, 10)
        .onAppear {
            records.startWatching()
            pickDefault()
        }
        .onDisappear { records.stopWatching() }
        .onChange(of: records.items) { pickDefault() }
    }

    /// 没选、或选中的被删了：选当前会议，否则选最近的一场
    private func pickDefault() {
        guard selected == nil || !records.items.contains(where: { $0.file == selected }) else { return }
        selected = records.items.first { $0.file == session.recordFile }?.file ?? records.items.first?.file
    }

    @ViewBuilder
    private var list: some View {
        if records.items.isEmpty {
            VStack(spacing: 10) {
                if records.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "archivebox").font(.system(size: 26)).foregroundStyle(.tertiary)
                    Text(tr("还没有存下来的会议", "No saved meetings yet")).font(.system(size: 13, weight: .semibold))
                    Text(tr("在悬浮窗的 ⋯ 菜单里点「保存到会议记录」，或者在「会话」页保存。", "Choose Save to Meeting Records in the overlay's ⋯ menu, or save from the Session page."))
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(filtered, selection: $selected) { item in
                RecordListRow(item: item, current: item.file == session.recordFile, running: session.isRunning)
                    .tag(item.file)
            }
            .listStyle(.inset)
            .overlay {
                if filtered.isEmpty {
                    Text(tr("没有找到", "No matches")).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let item = records.items.first(where: { $0.file == selected }) {
            RecordDetail(summary: item, records: records, session: session)
                .id(item.file)
        } else {
            Text(records.items.isEmpty ? "" : tr("选一场会议", "Choose a meeting"))
                .foregroundStyle(.secondary)
        }
    }
}

private struct RecordListRow: View {
    let item: MeetingRecords.Summary
    let current: Bool
    let running: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if current {
                    Text(running ? tr("正在记", "Recording") : tr("当前", "Current"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Brand.accent.opacity(0.16)))
                        .foregroundStyle(Brand.accent)
                }
            }
            Text([MeetingTime.day(item.startedAt), MeetingTime.duration(from: item.startedAt, to: item.endedAt),
                  MeetingTime.lines(item.rowCount)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !item.speakers.isEmpty {
                Text(MeetingTime.names(item.speakers))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

/// 一场会议的完整记录：会议名可以改；接着记、导出、拷贝、在访达里看、删除
private struct RecordDetail: View {
    let summary: MeetingRecords.Summary
    @ObservedObject var records: MeetingRecords
    @ObservedObject var session: SessionModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var loaded: MeetingRecord?
    @State private var title = ""
    @State private var copied = false

    private var isCurrent: Bool { summary.file == session.recordFile }
    /// 都读文件：正在开的这场每隔两三秒自动存一次，文件一变这里跟着重读（不随每次音量刷新重算整场）
    private var record: MeetingRecord? { loaded }

    var body: some View {
        Group {
            if let record {
                content(record)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: summary.modifiedAt) {
            let url = records.url(summary.file)
            loaded = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(MeetingRecord.self, from: $0) }
            }.value
        }
        .onAppear { title = summary.title }
        .onChange(of: summary.title) { title = summary.title }
    }

    private func content(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(record)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let background = record.context.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !background.isEmpty {
                        DisclosureGroup(tr("背景", "Context")) {
                            Text(background).font(.system(size: 12.5)).foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 4)
                        }
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.bottom, 12)
                    }
                    if record.rows.isEmpty {
                        Text(tr("这场没有字幕", "No transcript in this meeting")).foregroundStyle(.secondary).padding(.vertical, 8)
                    }
                    ForEach(Array(record.rows.enumerated()), id: \.element.id) { index, row in
                        RecordRowView(row: row, speaker: record.speakerLabel(row), theme: theme,
                                      showHeader: Self.startsGroup(record.rows, index))
                    }
                    if !record.replies.isEmpty {
                        Text(tr("回复建议 · \(record.replies.count)", "Suggested Replies · \(record.replies.count)"))
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.top, 22)
                            .padding(.bottom, 8)
                        ForEach(record.replies) { reply in
                            RecordReplyView(reply: reply, followUp: record.followUp(for: reply))
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
            }
        }
    }

    private func header(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("", text: $title, prompt: Text(tr("会议名称", "Meeting Name")))
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .bold))
                    .onSubmit(rename)
                if isCurrent {
                    Text(session.isRunning ? tr("正在记", "Recording") : tr("当前会议", "Current Meeting"))
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Brand.accent.opacity(0.16)))
                        .foregroundStyle(Brand.accent)
                        .fixedSize()
                }
            }
            Text(meta(record)).font(.system(size: 11.5).monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if !isCurrent {
                    Button { MeetingCommands.open(summary.file, in: records, session: session) } label: {
                        Label(tr("接着记这场", "Continue This Meeting"), systemImage: "record.circle")
                    }
                    .help(tr("把这场设为当前会议，开始听以后接着记在这场里", "Make this the current meeting; listening continues in it"))
                }
                Button { MeetingCommands.export(record) } label: {
                    Label(tr("导出…", "Export…"), systemImage: "square.and.arrow.up")
                }
                // 不常用的只放图标，鼠标停上去有说明
                Button {
                    Clipboard.copy(record.markdown())
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copied = false
                    }
                } label: {
                    Label(tr("拷贝全文", "Copy All"), systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .labelStyle(.iconOnly)
                .help(tr("拷贝全文（Markdown）", "Copy all (Markdown)"))
                Button { NSWorkspace.shared.activateFileViewerSelecting([records.url(summary.file)]) } label: {
                    Label(tr("在访达中显示", "Show in Finder"), systemImage: "folder")
                }
                .labelStyle(.iconOnly)
                .help(tr("在访达中显示文件", "Show the file in Finder"))
                Spacer(minLength: 0)
                Button(role: .destructive) {
                    MeetingCommands.delete(summary.file, title: record.title, in: records, session: session)
                } label: {
                    Label(tr("删除", "Delete"), systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help(tr("删除这场（移到废纸篓）", "Delete this meeting (moves it to the Trash)"))
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
    }

    private func meta(_ record: MeetingRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        var parts: [String] = []
        if let start = record.startedAt {
            parts.append(MeetingTime.day(start) + (record.endedAt.map { " – \(formatter.string(from: $0))" } ?? ""))
        }
        if let duration = MeetingTime.duration(from: record.startedAt, to: record.endedAt) { parts.append(duration) }
        parts.append(MeetingTime.lines(record.rows.count))
        if !record.replies.isEmpty { parts.append(MeetingTime.replies(record.replies.count)) }
        let speakers = record.speakers
        if !speakers.isEmpty { parts.append(MeetingTime.names(speakers)) }
        return parts.joined(separator: " · ")
    }

    private func rename() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            title = summary.title
            return
        }
        if isCurrent {
            session.title = trimmed
            session.save()
        } else {
            records.rename(summary.file, to: trimmed)
        }
    }

    /// 字幕颜色和悬浮窗一致（默认主题）
    private var theme: OverlayTheme { OverlayTheme.of(.graphite, light: colorScheme == .light) }

    /// 同一个人连着说（间隔一分钟内）只在第一句显示名字
    static func startsGroup(_ rows: [Utterance], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = rows[index - 1]
        return previous.speakerKey != rows[index].speakerKey
            || rows[index].startedAt.timeIntervalSince(previous.updatedAt) > 60
    }
}

private struct RecordRowView: View {
    let row: Utterance
    let speaker: String
    let theme: OverlayTheme
    let showHeader: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(speaker).font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.color(for: row))
                    Text(row.startedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
            Text(row.displayText).font(.system(size: 13.5)).lineSpacing(2)
            if let translation = row.translation {
                Text(translation).font(.system(size: 12.5)).foregroundStyle(.secondary).lineSpacing(1.5)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, showHeader ? 12 : 4)
    }
}

private struct RecordReplyView: View {
    let reply: Reply
    let followUp: ReplyFollowUp?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: reply.isScreenshot ? "camera.viewfinder" : "arrowshape.turn.up.left.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Brand.accent)
                Text(reply.createdAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(reply.target).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .top, spacing: 10) {
                if let data = reply.thumbnail, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 6) {
                    if let quote = reply.quote {
                        Text("\(reply.quoteSpeaker.map { "\($0)：" } ?? "")\(quote)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .overlay(alignment: .leading) { Rectangle().fill(Color.secondary.opacity(0.4)).frame(width: 2) }
                    }
                    Text(reply.text).font(.system(size: 12.5))
                    if let followUp, !followUp.rows.isEmpty {
                        Text(tr("我实际说的（\(followUp.verdict.label)）：\(followUp.text)",
                                "What I actually said (\(followUp.verdict.label)): \(followUp.text)"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04)))
        .padding(.bottom, 8)
    }
}
