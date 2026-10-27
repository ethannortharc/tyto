import SwiftUI

/// 回复面板：贴在悬浮窗旁边的一列，生成过的回复都留在这里（最新的在上面），可以删。
/// 会议里的回复下面接着显示"我实际说的"，和建议对比。
struct SidecarView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var ui: OverlayState
    var close: () -> Void = {}
    /// 画预览图时为 true：不用 ScrollView 和系统玻璃
    var flatForPreview = false

    private var theme: OverlayTheme { OverlayTheme.current(settings.value, backdropIsLight: ui.backdropIsLight) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline(ink: theme.ink)
            if session.replies.isEmpty {
                empty
            } else if flatForPreview {
                // 内容放在上面一层，多了从下面裁掉，不把面板撑高
                Color.clear.overlay(alignment: .top) { cards }.clipped()
            } else {
                ScrollViewReader { proxy in
                    ScrollView { cards }
                        // 字幕里点了"回应了建议"的小图标：滚到那条回复
                        .onChange(of: ui.focusReplyID) {
                            guard let id = ui.focusReplyID else { return }
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
                            Task {
                                try? await Task.sleep(for: .seconds(1.6))
                                if ui.focusReplyID == id { ui.focusReplyID = nil }
                            }
                        }
                        // 新的回复出来时回到最上面
                        .onChange(of: session.replies.last?.id) {
                            guard let id = session.replies.last?.id else { return }
                            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .top) }
                        }
                }
            }
        }
        .font(.system(size: 13))
        .overlaySurface(theme: theme, opacity: settings.value.overlayOpacity, flat: flatForPreview)
        .id(settings.value.language)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent)
            Text(tr("回复", "Replies")).font(.system(size: 13, weight: .semibold))
            if !session.replies.isEmpty {
                Text("\(session.replies.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.ink.opacity(0.5))
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", theme: theme, help: tr("收起回复面板（⌃⌥B）", "Hide Replies (⌃⌥B)"), size: 24, action: close)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(height: 49)
        .contentShape(Rectangle())
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "text.bubble").font(.system(size: 22)).foregroundStyle(theme.accent.opacity(0.8))
            Text(tr("点「回复」或按 ⌃⌥R，生成的回复会留在这里", "Click Reply or press ⌃⌥R; replies stay here"))
                .font(.system(size: 12))
                .foregroundStyle(theme.ink.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var cards: some View {
        let newest = session.replies.last?.id
        return LazyVStack(spacing: 10) {
            ForEach(session.replies.reversed()) { reply in
                ReplyCard(reply: reply, session: session, ui: ui, theme: theme, flat: flatForPreview,
                          expandedByDefault: reply.id == newest, focused: ui.focusReplyID == reply.id)
                    .id(reply.id)
            }
        }
        .padding(10)
    }
}

// MARK: - 一条回复

private struct ReplyCard: View {
    let reply: Reply
    @ObservedObject var session: SessionModel
    @ObservedObject var ui: OverlayState
    let theme: OverlayTheme
    let flat: Bool
    /// 最新的一条全部展开；旧的只显示建议回复和"我实际说的"，说明收起来
    let expandedByDefault: Bool
    let focused: Bool

    @State private var instruction = ""
    @State private var expanded: Bool?
    @State private var hovered = false

    private var isExpanded: Bool { expanded ?? expandedByDefault }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading
            if let status = reply.status {
                Text(status).font(.system(size: 12)).foregroundStyle(theme.ink.opacity(0.6))
            }
            sections
            if let error = reply.error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.orange)
            }
            if !reply.isStreaming, let followUp = session.followUp(for: reply) {
                FollowUpView(followUp: followUp, theme: theme)
            }
            if isExpanded, reply.isScreenshot, !reply.isStreaming, session.canRegenerate(reply.id) || flat {
                regenerate
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(focused ? theme.accent.opacity(theme.light ? 0.10 : 0.14) : theme.ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(theme.ink.opacity(0.09)))
        .animation(.easeOut(duration: 0.3), value: focused)
        .onHover { hovered = $0 }
        .onAppear { instruction = reply.instruction ?? "" }
    }

    // MARK: 抬头：回的是哪句（截屏回复是截图），时间，删除

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            if let data = reply.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(theme.ink.opacity(0.15)))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reply.isScreenshot ? tr("截屏回复", "Screenshot Reply") : (reply.quoteSpeaker ?? tr("回复建议", "Suggested Reply")))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.ink.opacity(0.75))
                        .lineLimit(1)
                    Text(reply.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                        .font(.system(size: 10.5).monospacedDigit())
                        .foregroundStyle(theme.ink.opacity(0.42))
                }
                if let quote = reply.quote, !quote.isEmpty {
                    // 对方的原话：点一下在字幕里找到它
                    Button { ui.focusRowID = reply.targetIDs?.last } label: {
                        Text("“\(quote)”")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.ink.opacity(0.68))
                            .lineLimit(isExpanded ? 4 : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .help(tr("在字幕里找到这句", "Show this line in the captions"))
                } else if reply.isScreenshot {
                    Text(reply.target).font(.system(size: 11)).foregroundStyle(theme.ink.opacity(0.5)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if reply.isStreaming {
                ProgressView().controlSize(.mini)
                PillButton(title: tr("停止", "Stop"), theme: theme, action: session.stopReply)
            } else {
                HStack(spacing: 2) {
                    IconButton(symbol: isExpanded ? "chevron.up" : "chevron.down", theme: theme,
                               help: isExpanded ? tr("收起说明", "Less") : tr("展开说明", "More"), size: 22) {
                        expanded = !isExpanded
                    }
                    IconButton(symbol: "trash", theme: theme, help: tr("删掉这条回复", "Delete This Reply"), size: 22) {
                        withAnimation(.easeOut(duration: 0.2)) { session.deleteReply(reply.id) }
                    }
                }
                .opacity(hovered || flat ? 1 : 0.55)
            }
        }
    }

    // MARK: 内容：可复制的回复一直显示，说明类的段落展开时才显示

    private var sections: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ReplyFormat.sections(reply.text)) { section in
                if section.isCopyable {
                    copyable(section)
                } else if isExpanded || reply.isStreaming {
                    VStack(alignment: .leading, spacing: 3) {
                        if !section.title.isEmpty {
                            Text(section.title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(theme.ink.opacity(0.5))
                        }
                        Text(section.body)
                            .font(.system(size: 12.5))
                            .foregroundStyle(theme.ink.opacity(0.82))
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
                        .foregroundStyle(copied ? theme.accent : theme.ink.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
            Text(section.body)
                .font(.system(size: 13.5))
                .foregroundStyle(theme.ink.opacity(0.96))
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
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(theme.ink.opacity(0.07)))
                .onSubmit { session.regenerateScreenshotReply(reply.id, instruction: instruction) }
            PillButton(title: tr("重新生成", "Regenerate"), symbol: "arrow.clockwise", theme: theme) {
                session.regenerateScreenshotReply(reply.id, instruction: instruction)
            }
        }
    }
}

// MARK: - 我实际说的

private struct FollowUpView: View {
    let followUp: ReplyFollowUp
    let theme: OverlayTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(tr("你实际说的", "What You Said"))
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(theme.ink.opacity(0.5))
                Text(followUp.verdict.label)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(tagColor.opacity(theme.light ? 0.12 : 0.18)))
                    .foregroundStyle(tagColor)
            }
            if followUp.rows.isEmpty {
                Text(followUp.verdict == .waiting
                     ? tr("你开口以后，这里会接上你说的话", "What you say next will show up here")
                     : tr("对方已经接着说别的了", "They moved on before you replied"))
                    .font(.system(size: 12))
                    .foregroundStyle(theme.ink.opacity(0.45))
            } else {
                Text(followUp.text)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.ink.opacity(0.85))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.ink.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: followUp.rows.isEmpty ? [3, 3] : [])))
    }

    private var tagColor: Color {
        switch followUp.verdict {
        case .followed: theme.accent
        case .rephrased: theme.ink.opacity(0.75)
        case .skipped, .waiting: theme.ink.opacity(0.5)
        }
    }
}
