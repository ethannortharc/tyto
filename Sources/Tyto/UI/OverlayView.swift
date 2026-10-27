import SwiftUI

/// 悬浮窗外部要做的事（窗口级别的操作由 AppDelegate 提供）
struct OverlayActions {
    var openMain: () -> Void = {}
    var hide: () -> Void = {}
    var quit: () -> Void = {}
    var resetSize: () -> Void = {}
    /// 打开设置窗口的翻译页（下载语言包）
    var openTranslation: () -> Void = {}
}

/// 悬浮窗：顶部控制栏，中间是原文/译文对照的字幕，底部是回复。
struct OverlayView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: OverlayState
    var actions = OverlayActions()
    /// 画预览图时为 true：ImageRenderer 画不出 ScrollView 和系统玻璃，换成普通排列和纯色底
    var flatForPreview = false

    @State private var shownReplyID: UUID?
    @State private var replyCollapsed = false
    @State private var showAppearance = false

    private var theme: OverlayTheme { OverlayTheme.of(settings.value.theme) }

    var body: some View {
        GeometryReader { geometry in
            content(height: geometry.size.height)
        }
        // 换界面语言时整棵重建，文字立即全部换过来
        .id(settings.value.language)
    }

    private func content(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ZStack(alignment: .top) {
                transcript
                if let notice = session.notice { noticeBanner(notice) }
            }
            footer(height: height)
        }
        .font(.system(size: settings.value.fontSize))
        .foregroundStyle(.white)
        // 底色调得很淡时，文字加一圈细阴影，盖在亮的画面上也看得清
        .shadow(color: .black.opacity(GlassBackground.textShadow(settings.value.overlayOpacity)), radius: 1.4, y: 0.5)
        .background(GlassBackground(theme: theme, opacity: settings.value.overlayOpacity, flat: flatForPreview))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .environment(\.colorScheme, .dark)
        .tint(theme.accent)
        .onChange(of: session.replies.count) {
            shownReplyID = session.replies.last?.id
            replyCollapsed = false
        }
    }

    // MARK: - 顶部控制栏

    private var header: some View {
        HStack(spacing: 10) {
            ListenButton(session: session, theme: theme)
            SourceDot(label: tr("远端", "Remote"), on: settings.value.captureRemote, level: session.levels[.remote] ?? 0,
                      color: theme.remote[0])
            SourceDot(label: tr("本地", "Local"), on: settings.value.captureLocal, level: session.levels[.local] ?? 0,
                      color: theme.local[0])
            Spacer(minLength: 4)
            if ui.clickThrough {
                Text(ui.peeking ? tr("可以点了 · 松开 ⌥ 恢复", "Clickable · release ⌥")
                                : tr("穿透中 · 按住 ⌥ 可点 · ⌃⌥P 关闭", "Click-through · hold ⌥ · ⌃⌥P off"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ui.peeking ? .green : .orange)
                    .lineLimit(1)
            }
            IconButton(symbol: "character.bubble", active: settings.value.translationEnabled, accent: theme.accent,
                       help: settings.value.translationEnabled ? tr("隐藏译文", "Hide Translation") : tr("显示译文", "Show Translation")) {
                settings.value.translationEnabled.toggle()
                session.translationToggled()
            }
            captureMenu
            IconButton(symbol: "paintpalette", active: showAppearance, accent: theme.accent, help: tr("外观：主题、透明度、字号", "Appearance: theme, tint, font size")) {
                showAppearance.toggle()
            }
            .popover(isPresented: $showAppearance, arrowEdge: .bottom) {
                AppearancePopover(settings: settings, ui: ui)
            }
            moreMenu
            IconButton(symbol: "xmark", accent: theme.accent, help: tr("退出 Tyto（⌃⌥Q）", "Quit Tyto (⌃⌥Q)"), action: actions.quit)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    /// 点一下按设置的方式截图；旁边的小箭头可以选别的方式
    private var captureMenu: some View {
        Menu {
            Section(tr("截屏回复", "Screenshot Reply")) {
                ForEach(AppSettings.CaptureTarget.allCases) { target in
                    Button { session.captureAndReply(target) } label: {
                        Label(target == settings.value.captureTarget ? "\(target.title) ⌃⌥S"
                                : target == .region ? "\(target.title) ⌃⌥A" : target.title,
                              systemImage: target.symbol)
                    }
                }
            }
            Button(action: session.replyToClipboardImage) {
                Label(tr("用剪贴板里的图片", "Use Image on Clipboard"), systemImage: "doc.on.clipboard")
            }
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        } primaryAction: {
            session.captureAndReply()
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.visible)
        .fixedSize()
        .help(tr("截屏回复：\(settings.value.captureTarget.title)（⌃⌥S），小箭头选别的方式", "Screenshot Reply: \(settings.value.captureTarget.title) (⌃⌥S); use the arrow for other options"))
    }

    /// 更多：先是"去哪里"（设置的几个常用页），再是窗口操作
    private var moreMenu: some View {
        Menu {
            Section {
                Button(action: actions.openMain) { Label(tr("会话与设置…", "Session & Settings…"), systemImage: "gearshape") }
                Button(action: session.replyToClipboardImage) { Label(tr("用剪贴板里的图片回复", "Reply with Image on Clipboard"), systemImage: "doc.on.clipboard") }
            }
            Section {
                Button { ui.clickThrough.toggle() } label: {
                    Label(ui.clickThrough ? tr("关闭点击穿透 ⌃⌥P", "Turn Off Click-Through ⌃⌥P") : tr("点击穿透 ⌃⌥P", "Click-Through ⌃⌥P"), systemImage: "cursorarrow.motionlines")
                }
                Button(action: actions.resetSize) { Label(tr("恢复默认大小和位置", "Reset Size & Position"), systemImage: "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left") }
                Button(action: actions.hide) { Label(tr("隐藏悬浮窗 ⌃⌥T", "Hide Overlay ⌃⌥T"), systemImage: "eye.slash") }
            }
            Section {
                Button(action: actions.quit) { Label(tr("退出 Tyto ⌃⌥Q", "Quit Tyto ⌃⌥Q"), systemImage: "power") }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, height: 28)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(tr("更多", "More"))
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text(notice).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if session.noticeOpensTranslation {
                    PillButton(title: tr("去下载", "Download"), symbol: "arrow.down.circle", prominent: true, theme: theme) {
                        actions.openTranslation()
                    }
                }
            }
            Spacer(minLength: 0)
            Button { session.notice = nil } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        // 提示条盖在字幕上面，底要实，不然下面的字会透出来
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.tint.opacity(0.96)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.orange.opacity(0.35)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(10)
    }

    // MARK: - 字幕

    @ViewBuilder
    private var transcript: some View {
        if session.rows.isEmpty {
            emptyState
        } else if flatForPreview {
            transcriptRows.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).clipped()
        } else {
            ScrollView { transcriptRows }
                // 内容少时从顶部排；变长后贴着底部、自动跟到最新一句
                .defaultScrollAnchor(.top, for: .alignment)
                .defaultScrollAnchor(.bottom, for: .initialOffset)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }

    private var transcriptRows: some View {
        let rows = session.rows
        let keywords = session.keywordList
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RowView(row: row, session: session, theme: theme, keywords: keywords,
                        showHeader: Self.startsGroup(rows, index),
                        showTranslation: settings.value.translationEnabled,
                        selected: session.selection.contains(row.id),
                        fontSize: settings.value.fontSize)
                    .transition(.opacity.combined(with: .offset(y: 8)))
            }
        }
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.22), value: rows.count)
    }

    /// 同一个人连着说（间隔一分钟内）只在第一句显示名字
    private static func startsGroup(_ rows: [Utterance], _ index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = rows[index - 1]
        return previous.speakerKey != rows[index].speakerKey
            || rows[index].startedAt.timeIntervalSince(previous.updatedAt) > 60
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(theme.accent.opacity(0.10)).frame(width: 64, height: 64)
                    .overlay(Circle().strokeBorder(theme.accent.opacity(0.22), lineWidth: 1))
                Image(systemName: "waveform").font(.system(size: 24, weight: .regular)).foregroundStyle(theme.accent)
            }
            VStack(spacing: 6) {
                Text(tr("准备好了", "Ready")).font(.system(size: 16, weight: .semibold))
                Text(tr("点「开始听」或按 ⌃⌥L", "Click Start Listening or press ⌃⌥L")).font(.system(size: 12.5)).foregroundStyle(.white.opacity(0.6))
            }
            VStack(alignment: .leading, spacing: 6) {
                hint("waveform", tr("远端是会议软件里的声音，本地是麦克风", "Remote is the meeting app's audio; Local is the microphone"))
                hint("hand.tap", tr("点一句选中它，可以多选，再点「回复」", "Click a line to select it (several are fine), then click Reply"))
                hint("camera.viewfinder", tr("⌃⌥S 框选一块屏幕，帮你写好回复", "⌃⌥S selects part of the screen and drafts a reply"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private func hint(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(theme.accent).frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.55))
        }
    }

    // MARK: - 底部：回复

    /// 回复区最高占窗口的四成（没有字幕时，比如只用截屏回复，可以占到六成五）
    private func footer(height: CGFloat) -> some View {
        VStack(spacing: 10) {
            if let reply = shownReply, !replyCollapsed {
                ReplyCard(reply: reply, session: session, theme: theme, flat: flatForPreview,
                          maxHeight: max(120, height * (session.rows.isEmpty ? 0.65 : 0.4) - 60))
            }
            HStack(spacing: 8) {
                PillButton(title: session.selection.isEmpty ? tr("回复最近的话", "Reply to Latest") : tr("回复选中的 \(session.selection.count) 句", "Reply to \(session.selection.count) Selected"),
                           symbol: "arrowshape.turn.up.left.fill", prominent: true, theme: theme, help: "⌃⌥R") {
                    session.reply(to: session.selection.isEmpty ? nil : Array(session.selection))
                }
                if !session.selection.isEmpty {
                    PillButton(title: tr("清除选择", "Clear Selection"), theme: theme) { session.selection = [] }
                }
                Spacer(minLength: 0)
                if let reply = shownReply { replyNavigation(reply) }
            }
        }
        .padding(12)
        .overlay(alignment: .top) { Hairline() }
    }

    private var shownReply: Reply? {
        session.replies.first { $0.id == shownReplyID } ?? session.replies.last
    }

    @ViewBuilder
    private func replyNavigation(_ reply: Reply) -> some View {
        let index = session.replies.firstIndex { $0.id == reply.id } ?? 0
        HStack(spacing: 2) {
            if session.replies.count > 1 {
                IconButton(symbol: "chevron.left", accent: theme.accent, help: tr("上一条回复", "Previous Reply"), size: 24) {
                    shownReplyID = session.replies[max(0, index - 1)].id
                }
                .disabled(index == 0)
                Text("\(index + 1)/\(session.replies.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                IconButton(symbol: "chevron.right", accent: theme.accent, help: tr("下一条回复", "Next Reply"), size: 24) {
                    shownReplyID = session.replies[min(session.replies.count - 1, index + 1)].id
                }
                .disabled(index == session.replies.count - 1)
            }
            IconButton(symbol: replyCollapsed ? "chevron.up" : "chevron.down", accent: theme.accent,
                       help: replyCollapsed ? tr("展开回复", "Show Reply") : tr("收起回复", "Hide Reply"), size: 24) { replyCollapsed.toggle() }
        }
    }
}

/// 悬浮窗的界面状态（点击穿透），菜单栏和快捷键也会改它
@MainActor
final class OverlayState: ObservableObject {
    @Published var clickThrough = false
    /// 点击穿透时按住 ⌥ 临时可点
    @Published var peeking = false
}

// MARK: - 小部件

private struct Hairline: View {
    var body: some View {
        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
    }
}

/// 开始/停止：没在听时是"开始听"，在听时是跳动的音量条和时长
private struct ListenButton: View {
    @ObservedObject var session: SessionModel
    let theme: OverlayTheme

    var body: some View {
        Button(action: session.toggle) {
            HStack(spacing: 8) {
                if session.isRunning {
                    LevelBars(level: max(session.levels[.remote] ?? 0, session.levels[.local] ?? 0), color: theme.accent)
                    if let since = session.listeningSince {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Self.elapsed(from: since, to: context.date)).monospacedDigit()
                        }
                    }
                } else {
                    Circle().fill(Color(red: 1, green: 0.38, blue: 0.40)).frame(width: 8, height: 8)
                    Text(session.isStarting ? tr("启动中…", "Starting…") : tr("开始听", "Listen"))
                }
            }
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(Capsule().fill(session.isRunning ? theme.accent.opacity(0.16) : .white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(session.isRunning ? theme.accent.opacity(0.5) : .white.opacity(0.12)))
        }
        .buttonStyle(.plain)
        .disabled(session.isStarting)
        .help(session.isRunning ? tr("停止（⌃⌥L）", "Stop (⌃⌥L)") : tr("开始听（⌃⌥L）", "Start Listening (⌃⌥L)"))
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// 跳动的音量条
private struct LevelBars: View {
    let level: Float
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 15)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { bar in
                    let wobble = (sin(time * 9 + Double(bar) * 1.7) + 1) / 2
                    let height = 3 + CGFloat(min(1, Double(level) * 2.2)) * 11 * CGFloat(0.45 + 0.55 * wobble)
                    Capsule().fill(color).frame(width: 2.5, height: height)
                }
            }
            .frame(height: 14)
        }
    }
}

private struct SourceDot: View {
    let label: String
    let on: Bool
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? color : .white.opacity(0.25))
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(on && level > 0.02 ? 0.95 : 0), radius: 4)
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(on ? 0.8 : 0.35))
        }
        .help(on ? tr("\(label)：在听（亮起来表示有声音）", "\(label): listening (lit when there is sound)") : tr("\(label)：没开（会话与设置 → 模型与服务 → 声音来源）", "\(label): off (Session & Settings → Listening → Audio Sources)"))
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    let accent: Color
    let help: String
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(active ? accent : .white.opacity(hovered ? 0.95 : 0.65))
                .frame(width: size, height: size)
                .background(Circle().fill(.white.opacity(hovered ? 0.12 : active ? 0.07 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

struct PillButton: View {
    let title: String
    var symbol: String?
    var prominent = false
    let theme: OverlayTheme
    var help = ""
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10.5, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(prominent ? theme.onAccent : .white.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if prominent {
                    Capsule().fill(theme.accent).brightness(hovered ? 0.06 : 0)
                } else {
                    Capsule().fill(.white.opacity(hovered ? 0.14 : 0.08))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

// MARK: - 一句字幕

private struct RowView: View {
    let row: Utterance
    @ObservedObject var session: SessionModel
    let theme: OverlayTheme
    let keywords: [String]
    let showHeader: Bool
    let showTranslation: Bool
    let selected: Bool
    let fontSize: Double

    @State private var hovered = false
    @State private var renaming = false
    @State private var newName = ""

    private var color: Color { theme.color(for: row) }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if showHeader { header }
            Text(originalText)
                .font(.system(size: fontSize + 1))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            if showTranslation, let translation = row.translation {
                Text(Highlighter.text(translation, keywords: keywords, theme: theme,
                                      base: theme.translation.opacity(0.72), entities: false))
                    .font(.system(size: fontSize - 1.5))
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, showHeader ? 9 : 3)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? theme.accent.opacity(0.14) : hovered ? Color.white.opacity(0.05) : .clear)
                    .padding(.horizontal, 6)
                Capsule()
                    .fill(color.opacity(selected ? 1 : 0.6))
                    .frame(width: 3)
                    .padding(.leading, 10)
                    .padding(.vertical, showHeader ? 9 : 3)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovered || selected {
                PillButton(title: tr("回复", "Reply"), symbol: "arrowshape.turn.up.left.fill", prominent: true, theme: theme) {
                    session.reply(to: [row.id])
                }
                .scaleEffect(0.86)
                .padding(.trailing, 8)
                .padding(.top, showHeader ? 4 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { session.toggleSelection(row.id) }
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Button {
                newName = session.speakerNames[row.speakerKey] ?? ""
                renaming = true
            } label: {
                Text(session.speakerLabel(row))
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(color)
            }
            .buttonStyle(.plain)
            .help(tr("点一下改名字，比如改成「我」", "Click to rename, e.g. to “Me”"))
            .popover(isPresented: $renaming) { renameField }
            Text(row.startedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(.white.opacity(0.32))
            if TextJoin.isQuestion(row.text) {
                Text(tr("提问", "Question"))
                    .font(.system(size: 9.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(theme.accent.opacity(0.2)))
                    .foregroundStyle(theme.accent)
            }
        }
    }

    private var renameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("给「\(session.defaultSpeakerLabel(row))」起个名字", "Name for “\(session.defaultSpeakerLabel(row))”")).font(.caption)
            TextField(tr("比如：我、Alice", "e.g. Me, Alice"), text: $newName)
                .frame(width: 180)
                .onSubmit(commitRename)
            HStack {
                Spacer()
                Button(tr("好", "OK"), action: commitRename).keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private var originalText: AttributedString {
        var text = row.isClosed || row.pending.isEmpty
            ? Highlighter.text(row.text, keywords: keywords, theme: theme, base: .white.opacity(0.95))
            : AttributedString(row.text)
        if !row.isClosed { text.foregroundColor = .white.opacity(0.95) }
        if !row.pending.isEmpty {
            var pending = AttributedString((row.text.isEmpty ? "" : " ") + row.pending)
            pending.foregroundColor = .white.opacity(0.42)
            text += pending
        }
        return text
    }

    private func commitRename() {
        session.rename(row.speakerKey, to: newName)
        renaming = false
    }
}

// MARK: - 回复卡片

private struct ReplyCard: View {
    let reply: Reply
    @ObservedObject var session: SessionModel
    let theme: OverlayTheme
    let flat: Bool
    let maxHeight: CGFloat

    @State private var instruction = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading
            if let status = reply.status {
                Text(status).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            }
            if flat {
                sections
            } else {
                ScrollView { sections }
                    .frame(maxHeight: maxHeight)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = reply.error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.orange)
            }
            if reply.isScreenshot, !reply.isStreaming, session.canRegenerate(reply.id) || flat {
                regenerate
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.09)))
        .onAppear { instruction = reply.instruction ?? "" }
    }

    private var heading: some View {
        HStack(spacing: 10) {
            if let data = reply.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 38, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.15)))
            } else {
                Image(systemName: "text.bubble")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.accent.opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(reply.isScreenshot ? tr("截屏回复", "Screenshot Reply") : tr("回复建议", "Suggested Reply")).font(.system(size: 12.5, weight: .semibold))
                Text("\(reply.target) · \(reply.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 0)
            if reply.isStreaming {
                ProgressView().controlSize(.mini)
                PillButton(title: tr("停止", "Stop"), theme: theme, action: session.stopReply)
            } else if reply.isScreenshot, let copied = reply.copiedSection {
                Label(tr("已复制「\(copied)」· ⌘V 粘贴", "Copied “\(copied)” · ⌘V"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }
        }
    }

    private var sections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ReplyFormat.sections(reply.text)) { section in
                if section.isCopyable {
                    copyable(section)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Text(section.body)
                            .font(.system(size: 12.5))
                            .foregroundStyle(.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copyable(_ section: ReplySection) -> some View {
        let copied = reply.copiedSection == section.title
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(section.title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(theme.accent)
                Spacer()
                Button { session.copy(section, of: reply.id) } label: {
                    Label(copied ? tr("已复制", "Copied") : tr("复制", "Copy"), systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(copied ? theme.accent : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Text(section.body)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.96))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .padding(.leading, 4)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent.opacity(copied ? 0.14 : 0.08)))
        .overlay(alignment: .leading) {
            Capsule().fill(theme.accent.opacity(0.85)).frame(width: 3).padding(.vertical, 10).padding(.leading, 5)
        }
    }

    private var regenerate: some View {
        HStack(spacing: 8) {
            TextField(tr("想怎么回？比如：婉拒、用中文、更正式", "How to reply? e.g. decline, in English, more formal"), text: $instruction)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.07)))
                .onSubmit { session.regenerateScreenshotReply(reply.id, instruction: instruction) }
            PillButton(title: tr("重新生成", "Regenerate"), symbol: "arrow.clockwise", theme: theme) {
                session.regenerateScreenshotReply(reply.id, instruction: instruction)
            }
        }
    }
}

/// 悬浮窗里的外观小面板：主题、透明度、字号、点击穿透
private struct AppearancePopover: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: OverlayState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("外观", "Appearance")).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 10) {
                ForEach(ThemeID.allCases) { id in
                    let theme = OverlayTheme.of(id)
                    Button { settings.value.theme = id } label: {
                        VStack(spacing: 5) {
                            Circle()
                                .fill(theme.accent)
                                .frame(width: 26, height: 26)
                                .overlay(Circle().strokeBorder(theme.tint, lineWidth: 5).opacity(0.9))
                                .overlay(Circle().strokeBorder(settings.value.theme == id ? Color.white : .clear, lineWidth: 2)
                                    .padding(-3))
                            Text(id.label.components(separatedBy: CharacterSet(charactersIn: "：:")).first ?? "").font(.system(size: 10.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(tr("底色浓度", "Tint"), systemImage: "circle.lefthalf.filled").font(.system(size: 11.5))
                    Spacer()
                    Text("\(Int(settings.value.overlayOpacity * 100))%").font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $settings.value.overlayOpacity, in: 0...0.95)
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label(tr("字号", "Font Size"), systemImage: "textformat.size").font(.system(size: 11.5))
                    Spacer()
                    Text("\(Int(settings.value.fontSize))").font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: $settings.value.fontSize, in: 11...24, step: 1)
            }
            Toggle(isOn: $ui.clickThrough) {
                Label(tr("点击穿透（⌃⌥P）", "Click-Through (⌃⌥P)"), systemImage: "cursorarrow.motionlines").font(.system(size: 11.5))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
        }
        .padding(14)
        .frame(width: 250)
    }
}
