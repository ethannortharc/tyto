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

/// 悬浮窗：顶部控制栏，中间是原文/译文对照的字幕，底部是回复按钮。生成的回复在旁边的回复面板里（SidecarView）。
struct OverlayView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: OverlayState
    var actions = OverlayActions()
    /// 画预览图时为 true：ImageRenderer 画不出 ScrollView 和系统玻璃，换成普通排列和纯色底
    var flatForPreview = false

    @State private var showAppearance = false

    private var theme: OverlayTheme { OverlayTheme.current(settings.value, backdropIsLight: ui.backdropIsLight) }

    var body: some View {
        content
            // 换界面语言时整棵重建，文字立即全部换过来
            .id(settings.value.language)
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Hairline(ink: theme.ink)
            ZStack(alignment: .top) {
                transcript
                if let notice = session.notice { noticeBanner(notice) }
            }
            footer
        }
        .font(.system(size: settings.value.fontSize))
        .overlaySurface(theme: theme, opacity: settings.value.overlayOpacity, flat: flatForPreview)
    }

    // MARK: - 顶部控制栏

    private var header: some View {
        HStack(spacing: 10) {
            ListenButton(session: session, theme: theme)
            SourceDot(ink: theme.ink, label: tr("远端", "Remote"), on: settings.value.captureRemote, level: session.levels[.remote] ?? 0,
                      color: theme.remote[0])
            SourceDot(ink: theme.ink, label: tr("本地", "Local"), on: settings.value.captureLocal, level: session.levels[.local] ?? 0,
                      color: theme.local[0])
            Spacer(minLength: 4)
            if ui.clickThrough {
                Text(ui.peeking ? tr("可以点了 · 松开 ⌥ 恢复", "Clickable · release ⌥")
                                : tr("穿透中 · 按住 ⌥ 可点 · ⌃⌥P 关闭", "Click-through · hold ⌥ · ⌃⌥P off"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ui.peeking ? .green : .orange)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                IconButton(symbol: "translate", active: settings.value.translationEnabled, theme: theme,
                           help: settings.value.translationEnabled ? tr("隐藏译文", "Hide Translation") : tr("显示译文", "Show Translation"),
                           size: 26) {
                    settings.value.translationEnabled.toggle()
                    session.translationToggled()
                }
                captureMenu
                IconButton(symbol: "paintpalette", active: showAppearance, theme: theme,
                           help: tr("外观：主题、字色、透明度、字号", "Appearance: theme, text color, tint, font size"), size: 26) {
                    showAppearance.toggle()
                }
                .popover(isPresented: $showAppearance, arrowEdge: .bottom) {
                    AppearancePopover(settings: settings, ui: ui)
                }
                moreMenu
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(theme.ink.opacity(0.06)))
            .overlay(Capsule().strokeBorder(theme.ink.opacity(0.08), lineWidth: 0.5))
            IconButton(symbol: "xmark", theme: theme, help: tr("退出 Tyto（⌃⌥Q）", "Quit Tyto (⌃⌥Q)"), size: 24, action: actions.quit)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.8))
                .padding(.leading, 4)
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
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.ink.opacity(0.8))
                .frame(width: 26, height: 26)
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
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.ink.opacity(0.6))
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
            // 内容放在上面一层，多了从下面裁掉，不把悬浮窗撑高
            Color.clear.overlay(alignment: .top) { transcriptRows }.clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView { transcriptRows }
                    // 内容少时从顶部排；变长后贴着底部、自动跟到最新一句
                    .defaultScrollAnchor(.top, for: .alignment)
                    .defaultScrollAnchor(.bottom, for: .initialOffset)
                    .defaultScrollAnchor(.bottom, for: .sizeChanges)
                    // 回复面板里点了"回的是哪句"：滚过去，闪一下
                    .onChange(of: ui.focusRowID) {
                        guard let id = ui.focusRowID else { return }
                        withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
                        Task {
                            try? await Task.sleep(for: .seconds(1.6))
                            if ui.focusRowID == id { ui.focusRowID = nil }
                        }
                    }
            }
        }
    }

    private var transcriptRows: some View {
        let rows = session.rows
        let keywords = session.keywordList
        let answered = session.answeredRows
        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RowView(row: row, session: session, theme: theme, keywords: keywords,
                        style: settings.value.transcriptStyle,
                        showHeader: Self.startsGroup(rows, index),
                        endsGroup: index == rows.count - 1 || Self.startsGroup(rows, index + 1),
                        showTranslation: settings.value.translationEnabled,
                        selected: session.selection.contains(row.id),
                        flashed: ui.focusRowID == row.id,
                        answers: answered[row.id],
                        fontSize: settings.value.fontSize,
                        showReply: { id in
                            settings.value.showReplyPanel = true
                            ui.focusReplyID = id
                        })
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
                Text(tr("点「开始听」或按 ⌃⌥L", "Click Start Listening or press ⌃⌥L")).font(.system(size: 12.5)).foregroundStyle(theme.ink.opacity(0.6))
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
            Text(text).font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.55))
        }
    }

    // MARK: - 底部：回复

    /// 底部：回复按钮；右边是回复面板的开关和条数
    private var footer: some View {
        HStack(spacing: 8) {
            PillButton(title: session.selection.isEmpty ? tr("回复最近的话", "Reply to Latest") : tr("回复选中的 \(session.selection.count) 句", "Reply to \(session.selection.count) Selected"),
                       symbol: "arrowshape.turn.up.left.fill", prominent: true, theme: theme, help: "⌃⌥R") {
                session.reply(to: session.selection.isEmpty ? nil : Array(session.selection))
            }
            if !session.selection.isEmpty {
                PillButton(title: tr("清除选择", "Clear Selection"), theme: theme) { session.selection = [] }
            }
            Spacer(minLength: 0)
            PanelToggle(symbol: "doc.text", title: nil, on: settings.value.showPrompter, theme: theme,
                        help: settings.value.showPrompter ? tr("收起提词器（⌃⌥N）", "Hide Prompter (⌃⌥N)")
                                                          : tr("提词器：会前准备的材料（⌃⌥N）", "Prompter: your prepared notes (⌃⌥N)")) {
                settings.value.showPrompter.toggle()
            }
            PanelToggle(symbol: "sidebar.left",
                        title: session.replies.isEmpty ? tr("回复", "Replies") : tr("回复 \(session.replies.count)", "Replies \(session.replies.count)"),
                        on: settings.value.showReplyPanel, theme: theme,
                        help: settings.value.showReplyPanel ? tr("收起回复面板（⌃⌥B）", "Hide Replies (⌃⌥B)") : tr("打开回复面板（⌃⌥B）", "Show Replies (⌃⌥B)")) {
                settings.value.showReplyPanel.toggle()
            }
        }
        .padding(12)
        .overlay(alignment: .top) { Hairline(ink: theme.ink) }
    }
}

/// 悬浮窗的界面状态（点击穿透），菜单栏和快捷键也会改它
@MainActor
final class OverlayState: ObservableObject {
    @Published var clickThrough = false
    /// 点击穿透时按住 ⌥ 临时可点
    @Published var peeking = false
    /// 悬浮窗后面的画面是亮的（字色自动时换黑字），由 BackdropProbe 定时看一眼
    @Published var backdropIsLight = false
    /// 字幕里要滚到并闪一下的那一句（回复面板里点了"回的是哪句"）
    @Published var focusRowID: UUID?
    /// 回复面板里要滚到的那条回复（字幕里点了"回应了建议"的小图标）
    @Published var focusReplyID: UUID?
}

// MARK: - 小部件

struct Hairline: View {
    let ink: Color

    var body: some View {
        Rectangle().fill(ink.opacity(0.08)).frame(height: 1)
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
            .background(Capsule().fill(session.isRunning ? theme.accent.opacity(0.16) : theme.ink.opacity(0.08)))
            .overlay(Capsule().strokeBorder(session.isRunning ? theme.accent.opacity(0.5) : theme.ink.opacity(0.12)))
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
    let ink: Color
    let label: String
    let on: Bool
    let level: Float
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(on ? color : ink.opacity(0.25))
                .frame(width: 6, height: 6)
                .shadow(color: color.opacity(on && level > 0.02 ? 0.95 : 0), radius: 4)
            Text(label).font(.system(size: 11.5, weight: .medium)).foregroundStyle(ink.opacity(on ? 0.8 : 0.35))
        }
        .help(on ? tr("\(label)：在听（亮起来表示有声音）", "\(label): listening (lit when there is sound)") : tr("\(label)：没开（会话与设置 → 模型与服务 → 声音来源）", "\(label): off (Session & Settings → Listening → Audio Sources)"))
    }
}

/// 回复面板的开关：图标 + 条数，打开时用强调色
/// 底部右边打开旁边窗口（提词器、回复面板）的开关；开着时是强调色
private struct PanelToggle: View {
    let symbol: String
    /// nil 时只有图标
    let title: String?
    let on: Bool
    let theme: OverlayTheme
    let help: String
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11.5, weight: .medium))
                if let title {
                    Text(title).font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(on ? theme.accent : theme.ink.opacity(hovered ? 1 : 0.8))
            .padding(.horizontal, title == nil ? 8 : 10)
            .frame(height: 26)
            .background(Capsule().fill(on ? theme.accent.opacity(theme.light ? 0.14 : 0.18) : theme.ink.opacity(hovered ? 0.12 : 0.07)))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
    }
}

struct IconButton: View {
    let symbol: String
    var active = false
    let theme: OverlayTheme
    let help: String
    var size: CGFloat = 28
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundStyle(active ? theme.accent : theme.ink.opacity(hovered ? 1 : 0.8))
                .frame(width: size, height: size)
                .background(Circle().fill(active ? theme.accent.opacity(theme.light ? 0.14 : 0.18) : theme.ink.opacity(hovered ? 0.10 : 0)))
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
            .foregroundStyle(prominent ? theme.onAccent : theme.ink.opacity(0.85))
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background {
                if prominent {
                    Capsule().fill(theme.accent).brightness(hovered ? 0.06 : 0)
                } else {
                    Capsule().fill(theme.ink.opacity(hovered ? 0.14 : 0.08))
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
    let style: TranscriptStyle
    let showHeader: Bool
    /// 同一个人连着说的最后一句（细线样式里竖线到这里收尾）
    let endsGroup: Bool
    let showTranslation: Bool
    let selected: Bool
    /// 回复面板里点了"回的是哪句"，这一句闪一下
    let flashed: Bool
    /// 这一句是在回应哪条回复建议（"我实际说的"）
    let answers: UUID?
    let fontSize: Double
    let showReply: (UUID) -> Void

    @State private var hovered = false
    @State private var renaming = false
    @State private var newName = ""

    private var color: Color { theme.color(for: row) }
    /// 正文离左边的距离：头像样式和名字对齐，细线样式在竖线右边
    private var textInset: CGFloat { style == .avatar ? 36 : 12 }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if showHeader { header }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(originalText)
                        .font(.system(size: fontSize + 1))
                        .lineSpacing(fontSize * 0.22)
                        .fixedSize(horizontal: false, vertical: true)
                    if let answers {
                        Spacer(minLength: 0)
                        Button { showReply(answers) } label: {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(theme.accent.opacity(0.85))
                        }
                        .buttonStyle(.plain)
                        .help(tr("这句在回应一条回复建议，点一下看对比", "This answers a suggested reply; click to compare"))
                    }
                }
                if showTranslation, let translation = row.translation {
                    Text(Highlighter.text(translation, keywords: keywords, theme: theme,
                                          base: theme.translation.opacity(theme.light ? 0.92 : 0.8), entities: false))
                        .font(.system(size: fontSize - 1.5))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, textInset)
        }
        .textSelection(.enabled)
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.top, showHeader ? 11 : 3)
        .padding(.bottom, endsGroup ? 7 : 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected || flashed ? theme.accent.opacity(theme.light ? 0.10 : 0.14) : hovered ? theme.ink.opacity(0.05) : .clear)
                    .animation(.easeOut(duration: 0.3), value: flashed)
                    .padding(.horizontal, 6)
                if style == .bar {
                    // 一个人连着说的几句共用一条线，不再一句一段
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(selected ? 1 : 0.55))
                        .frame(width: 2)
                        .padding(.leading, 16)
                        .padding(.top, showHeader ? 13 : 0)
                        .padding(.bottom, endsGroup ? 9 : 0)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovered || selected {
                PillButton(title: tr("回复", "Reply"), symbol: "arrowshape.turn.up.left.fill", prominent: true, theme: theme) {
                    session.reply(to: [row.id])
                }
                .scaleEffect(0.86)
                .padding(.trailing, 8)
                .padding(.top, showHeader ? 6 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { session.toggleSelection(row.id) }
        .onHover { hovered = $0 }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button {
                newName = session.speakerNames[row.speakerKey] ?? ""
                renaming = true
            } label: {
                HStack(spacing: style == .avatar ? 8 : 0) {
                    if style == .avatar { avatar }
                    Text(session.speakerLabel(row))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(style == .avatar ? theme.ink.opacity(0.88) : color)
                }
            }
            .buttonStyle(.plain)
            .help(tr("点一下改名字，比如改成「我」", "Click to rename, e.g. to “Me”"))
            .popover(isPresented: $renaming) { renameField }
            Text(row.startedAt, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute().second())
                .font(.system(size: 10.5).monospacedDigit())
                .foregroundStyle(theme.ink.opacity(0.42))
            if TextJoin.isQuestion(row.text) {
                Text(tr("提问", "Question"))
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.accent.opacity(theme.light ? 0.12 : 0.18)))
                    .foregroundStyle(theme.accent)
            }
        }
        .padding(.leading, style == .avatar ? 6 : 12)
    }

    /// 说话人头像：起了名字用名字的第一个字，没起用编号
    private var avatar: some View {
        let initial: String = {
            if let name = session.speakerNames[row.speakerKey], let first = name.first { return String(first).uppercased() }
            if let speaker = row.speaker { return "\(speaker)" }
            return row.channel == .remote ? tr("远", "R") : tr("本", "L")
        }()
        return Text(initial)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 22, height: 22)
            .background(Circle().fill(color.opacity(theme.light ? 0.14 : 0.18)))
            .overlay(Circle().strokeBorder(color.opacity(0.45), lineWidth: 0.75))
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
            ? Highlighter.text(row.text, keywords: keywords, theme: theme, base: theme.ink.opacity(0.95))
            : AttributedString(row.text)
        if !row.isClosed { text.foregroundColor = theme.ink.opacity(0.95) }
        if !row.pending.isEmpty {
            var pending = AttributedString((row.text.isEmpty ? "" : " ") + row.pending)
            pending.foregroundColor = theme.ink.opacity(0.42)
            text += pending
        }
        return text
    }

    private func commitRename() {
        session.rename(row.speakerKey, to: newName)
        renaming = false
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
                                .overlay(Circle().strokeBorder(settings.value.theme == id ? Color.primary : .clear, lineWidth: 2)
                                    .padding(-3))
                            Text(id.label.components(separatedBy: CharacterSet(charactersIn: "：:")).first ?? "").font(.system(size: 10.5))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Label(tr("字色", "Text Color"), systemImage: "character").font(.system(size: 11.5))
                Picker("", selection: $settings.value.overlayTextColor) {
                    ForEach(OverlayTextColor.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
