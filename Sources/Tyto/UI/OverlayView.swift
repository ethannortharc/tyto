import SwiftUI

/// 悬浮窗里的内容：上面是开关，中间是原文/译文对照的记录，下面是回复建议。
struct OverlayView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: OverlayState
    let openMain: () -> Void
    let hide: () -> Void

    @State private var shownReplyID: UUID?
    @State private var replyCollapsed = false
    /// 画预览图时为 true：ImageRenderer 画不出 ScrollView 里的内容，换成普通排列
    var flatForPreview = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(.white.opacity(0.12))
            if let notice = session.notice { noticeBar(notice) }
            transcript
            Divider().overlay(.white.opacity(0.12))
            replyArea
        }
        .font(.system(size: settings.value.fontSize))
        .foregroundStyle(.white)
        .background(.black.opacity(settings.value.overlayOpacity), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12)))
        .environment(\.colorScheme, .dark)
        .onChange(of: session.replies.count) {
            shownReplyID = session.replies.last?.id
            replyCollapsed = false
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: session.toggle) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(session.isRunning ? Color.red : Color.white.opacity(0.35))
                        .frame(width: 10, height: 10)
                    Text(session.isStarting ? "启动中…" : session.isRunning ? "正在听" : "开始听")
                }
            }
            .buttonStyle(.plain)
            .disabled(session.isStarting)
            .help(session.isRunning ? "停止" : "开始听会议")

            ChannelBadge(label: "远端", on: settings.value.captureRemote, level: session.levels[.remote] ?? 0)
            ChannelBadge(label: "本地", on: settings.value.captureLocal, level: session.levels[.local] ?? 0)

            Toggle("翻译", isOn: Binding(
                get: { settings.value.translationEnabled },
                set: { settings.value.translationEnabled = $0; session.translationToggled() }))
                .toggleStyle(.button)
                .controlSize(.small)
                .help("显示 / 隐藏译文")

            Spacer(minLength: 0)
            if ui.clickThrough {
                Text("点击穿透中 · ⌃⌥P 恢复").font(.caption).foregroundStyle(.orange)
            }
            Menu {
                Button("会话与设置…", action: openMain)
                Button(ui.clickThrough ? "关闭点击穿透" : "点击穿透（⌃⌥P）") { ui.clickThrough.toggle() }
                Divider()
                Button("字大一点") { settings.value.fontSize = min(24, settings.value.fontSize + 1) }
                Button("字小一点") { settings.value.fontSize = max(10, settings.value.fontSize - 1) }
                Button("背景深一点") { settings.value.overlayOpacity = min(0.98, settings.value.overlayOpacity + 0.08) }
                Button("背景浅一点") { settings.value.overlayOpacity = max(0.3, settings.value.overlayOpacity - 0.08) }
                Divider()
                Button("隐藏悬浮窗（⌃⌥T）", action: hide)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private func noticeBar(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(notice).font(.callout).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            Button { session.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(8)
        .background(.orange.opacity(0.15))
    }

    // MARK: 记录

    @ViewBuilder
    private var transcript: some View {
        if flatForPreview {
            transcriptRows.frame(maxHeight: .infinity, alignment: .bottom).clipped()
        } else {
            ScrollView { transcriptRows }
                .defaultScrollAnchor(.bottom)
                .defaultScrollAnchor(.bottom, for: .sizeChanges)
        }
    }

    private var transcriptRows: some View {
            LazyVStack(alignment: .leading, spacing: 2) {
                if session.rows.isEmpty {
                    Text("点左上角「开始听」。\n远端 = 会议软件里对方的声音，本地 = 麦克风收到的声音（你和会议室里的人）。\n点一句选中它，可以多选；鼠标移到一句上会出现「回复」。")
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(12)
                }
                ForEach(session.rows) { row in
                    RowView(row: row, session: session,
                            showTranslation: settings.value.translationEnabled,
                            selected: session.selection.contains(row.id))
                        .id(row.id)
                }
            }
            .padding(.vertical, 6)
    }

    // MARK: 回复

    private var replyArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button(session.selection.isEmpty ? "回复最近的话" : "回复选中的 \(session.selection.count) 句") {
                    session.reply(to: session.selection.isEmpty ? nil : Array(session.selection))
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .help("⌃⌥R 也可以")
                if !session.selection.isEmpty {
                    Button("清除选择") { session.selection = [] }
                }
                Spacer(minLength: 0)
                if let reply = shownReply {
                    replyNavigation(reply)
                }
            }
            .controlSize(.small)

            if let reply = shownReply, !replyCollapsed {
                if flatForPreview {
                    replyBody(reply)
                } else {
                    ScrollView { replyBody(reply) }
                        .frame(maxHeight: 240)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(12)
    }

    private func replyBody(_ reply: Reply) -> some View {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("回复 · \(reply.target)").font(.caption).foregroundStyle(.white.opacity(0.5))
                        if reply.text.isEmpty, reply.isStreaming {
                            ProgressView().controlSize(.small)
                        }
                        Text(Self.markdown(reply.text)).textSelection(.enabled)
                        if let error = reply.error {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var shownReply: Reply? {
        session.replies.first { $0.id == shownReplyID } ?? session.replies.last
    }

    @ViewBuilder
    private func replyNavigation(_ reply: Reply) -> some View {
        let index = session.replies.firstIndex { $0.id == reply.id } ?? 0
        if session.replies.count > 1 {
            Button { shownReplyID = session.replies[max(0, index - 1)].id } label: { Image(systemName: "chevron.left") }
                .disabled(index == 0)
            Text("\(index + 1)/\(session.replies.count)").font(.caption).monospacedDigit()
            Button { shownReplyID = session.replies[min(session.replies.count - 1, index + 1)].id } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(index == session.replies.count - 1)
        }
        if reply.isStreaming {
            Button("停止", action: session.stopReply)
        } else {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(reply.text, forType: .string)
            } label: { Image(systemName: "doc.on.doc") }
            .help("复制")
        }
        Button { replyCollapsed.toggle() } label: {
            Image(systemName: replyCollapsed ? "chevron.up" : "chevron.down")
        }
        .help(replyCollapsed ? "展开回复" : "收起回复")
    }

    static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// 悬浮窗的界面状态（点击穿透），菜单栏和快捷键也会改它
@MainActor
final class OverlayState: ObservableObject {
    @Published var clickThrough = false
}

private struct ChannelBadge: View {
    let label: String
    let on: Bool
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption)
            Capsule()
                .fill(.white.opacity(0.15))
                .frame(width: 26, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(.green).frame(width: 26 * CGFloat(min(1, level)), height: 4)
                }
        }
        .opacity(on ? 1 : 0.35)
        .help(on ? "\(label)：在听（绿条是音量）" : "\(label)：没开（模型与服务 → 声音来源）")
    }
}

private struct RowView: View {
    let row: Utterance
    @ObservedObject var session: SessionModel
    let showTranslation: Bool
    let selected: Bool

    @State private var hovered = false
    @State private var renaming = false
    @State private var newName = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                newName = session.speakerNames[row.speakerKey] ?? ""
                renaming = true
            } label: {
                Text(session.speakerLabel(row))
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(SpeakerColor.of(row).opacity(0.35), in: Capsule())
            }
            .buttonStyle(.plain)
            // 标签列固定宽度，正文都从同一条线开始
            .frame(width: 92, alignment: .leading)
            .help("点一下改名字，比如改成「我」")
            .popover(isPresented: $renaming) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("给「\(session.defaultSpeakerLabel(row))」起个名字").font(.caption)
                    TextField("比如：我、Alice", text: $newName)
                        .frame(width: 180)
                        .onSubmit { commitRename() }
                    HStack {
                        Spacer()
                        Button("好") { commitRename() }.keyboardShortcut(.defaultAction)
                    }
                }
                .padding(12)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(originalText).fixedSize(horizontal: false, vertical: true)
                if showTranslation, let translation = row.translation {
                    Text(translation)
                        .foregroundStyle(Color(hue: 0.13, saturation: 0.45, brightness: 1))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            Spacer(minLength: 0)
            if hovered || selected {
                Button("回复") { session.reply(to: [row.id]) }
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(selected ? Color.accentColor.opacity(0.3) : hovered ? Color.white.opacity(0.06) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { session.toggleSelection(row.id) }
        .onHover { hovered = $0 }
    }

    private var originalText: AttributedString {
        var text = AttributedString(row.text)
        if !row.pending.isEmpty {
            var pending = AttributedString((row.text.isEmpty ? "" : " ") + row.pending)
            pending.foregroundColor = .white.opacity(0.5)
            text += pending
        }
        return text
    }

    private func commitRename() {
        session.rename(row.speakerKey, to: newName)
        renaming = false
    }
}

enum SpeakerColor {
    private static let remote: [Color] = [.cyan, .blue, .teal, .indigo, .mint]
    private static let local: [Color] = [.green, .orange, .yellow, .pink, .brown]

    static func of(_ row: Utterance) -> Color {
        let palette = row.channel == .remote ? remote : local
        return palette[(row.speaker ?? 0) % palette.count]
    }
}
