import SwiftUI
import UniformTypeIdentifiers

/// 提词器：顶上是材料名和几个开关，下面一条是"现在在哪一节"（点开是目录），中间是材料本身。
/// 对方提到稿子里的某一节时，底下出一条提示。
struct PrompterView: View {
    @ObservedObject var model: PrompterModel
    @ObservedObject var settings: SettingsStore
    var close: () -> Void = {}

    @State private var dropping = false

    private var theme: OverlayTheme { OverlayTheme.current(settings.value, backdropIsLight: model.backdropIsLight) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline(ink: theme.ink)
            if model.document != nil {
                if !model.sections.isEmpty { sectionBar }
                PrompterWebHost(web: model.web)
                if let suggestion = model.suggestion { hint(suggestion) }
            } else {
                empty
            }
        }
        .font(.system(size: 13))
        .overlaySurface(theme: theme, opacity: settings.value.overlayOpacity, flat: false)
        .overlay {
            if dropping {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropping) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url, PrompterDocument.canOpen(url) else { return }
                Task { @MainActor in model.open(url) }
            }
            return true
        }
        .onAppear { model.applyStyle(theme: theme) }
        .onChange(of: StyleKey(settings.value, light: model.backdropIsLight)) { model.applyStyle(theme: theme) }
        .id(settings.value.language)
    }

    /// 换了这些才要重新给网页上色
    private struct StyleKey: Equatable {
        let theme: ThemeID
        let light: Bool
        let opacity: Double
        let fontSize: Double

        init(_ settings: AppSettings, light: Bool) {
            theme = settings.theme
            self.light = OverlayTheme.current(settings, backdropIsLight: light).light
            opacity = settings.overlayOpacity
            fontSize = settings.prompterFontSize
        }
    }

    // MARK: - 顶栏

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.text").font(.system(size: 12, weight: .medium)).foregroundStyle(theme.accent)
                .padding(.trailing, 2)
            documentMenu
            Spacer(minLength: 4)
            if model.document != nil {
                IconButton(symbol: "textformat.size.smaller", theme: theme, help: tr("字小一点", "Smaller Text"), size: 24) {
                    settings.value.prompterFontSize = max(12, settings.value.prompterFontSize - 1)
                }
                IconButton(symbol: "textformat.size.larger", theme: theme, help: tr("字大一点", "Larger Text"), size: 24) {
                    settings.value.prompterFontSize = min(34, settings.value.prompterFontSize + 1)
                }
                IconButton(symbol: "waveform", active: settings.value.prompterFollow, theme: theme,
                           help: settings.value.prompterFollow
                               ? tr("跟读开着：你照着稿子说，它滚到说到的地方。点一下关掉", "Follow is on: as you speak, the notes scroll to where you are. Click to turn off")
                               : tr("跟读关着：点一下打开，你照着稿子说时自动滚动", "Follow is off: click to scroll along as you speak"),
                           size: 24) {
                    settings.value.prompterFollow.toggle()
                }
            }
            IconButton(symbol: "xmark", theme: theme, help: tr("收起提词器（⌃⌥N）", "Hide Prompter (⌃⌥N)"), size: 24, action: close)
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(height: 49)
        .contentShape(Rectangle())
        .gesture(WindowDragGesture())
    }

    private var documentMenu: some View {
        Menu {
            Section {
                Button(action: model.choose) { Label(tr("打开材料…", "Open Notes…"), systemImage: "folder") }
                if model.document != nil {
                    Button(action: model.revealInFinder) { Label(tr("在访达中显示", "Show in Finder"), systemImage: "magnifyingglass") }
                }
            }
            let others = model.recent.filter { $0 != model.document?.url }
            if !others.isEmpty {
                Section(tr("最近用过", "Recent")) {
                    ForEach(others, id: \.self) { url in
                        Button { model.open(url) } label: { Label(url.lastPathComponent, systemImage: "doc.text") }
                    }
                }
            }
            if model.document != nil {
                Section {
                    Toggle(tr("跟读：照着稿子说时自动滚动", "Follow Along as I Speak"), isOn: $settings.value.prompterFollow)
                    Toggle(tr("对方提到某一节时提示", "Hint When They Mention a Section"), isOn: $settings.value.prompterHints)
                }
                Section {
                    Button(role: .destructive, action: model.close) { Label(tr("关掉这份材料", "Close These Notes"), systemImage: "xmark.circle") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(model.document?.name ?? tr("提词器", "Prompter"))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).opacity(0.55)
            }
            .foregroundStyle(theme.ink)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
        .help(tr("换材料、最近用过的、跟读设置", "Change notes, recent files, follow settings"))
    }

    // MARK: - 现在在哪一节

    private var sectionBar: some View {
        let here = model.currentSection
        return HStack(spacing: 4) {
            Menu {
                ForEach(Array(model.sections.enumerated()), id: \.offset) { index, section in
                    Button { model.goToSection(index) } label: {
                        let indent = section.level > (model.sections.map(\.level).min() ?? 1) ? "    " : ""
                        if index == here {
                            Label(indent + section.title, systemImage: "checkmark")
                        } else {
                            Text(indent + section.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(theme.accent)
                    Text(here.map { model.sections[$0].title } ?? tr("开头", "Start"))
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .bold)).opacity(0.5)
                }
                .foregroundStyle(theme.ink.opacity(0.88))
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .help(tr("目录：点一节跳过去", "Outline: click a section to jump"))
            Spacer(minLength: 6)
            Text("\((here ?? -1) + 1)/\(model.sections.count)")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.ink.opacity(0.5))
            IconButton(symbol: "chevron.up", theme: theme, help: tr("上一节（⌃⌥↑）", "Previous Section (⌃⌥↑)"), size: 22) { model.step(-1) }
            IconButton(symbol: "chevron.down", theme: theme, help: tr("下一节（⌃⌥↓）", "Next Section (⌃⌥↓)"), size: 22) { model.step(1) }
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(height: 34)
        .background(theme.ink.opacity(0.035))
        .overlay(alignment: .bottom) { Hairline(ink: theme.ink) }
    }

    // MARK: - 对方提到

    private func hint(_ suggestion: PrompterModel.Suggestion) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.turn.down.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(tr("对方提到", "They mentioned")).font(.system(size: 11)).foregroundStyle(theme.ink.opacity(0.6))
                Text(suggestion.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            }
            Spacer(minLength: 4)
            PillButton(title: tr("跳过去", "Go"), symbol: "arrow.down.to.line", prominent: true, theme: theme,
                       help: "⌃⌥J", action: model.jumpToSuggestion)
            IconButton(symbol: "xmark", theme: theme, help: tr("不用了", "Dismiss"), size: 22) { model.suggestion = nil }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(theme.accent.opacity(theme.light ? 0.08 : 0.10))
        .overlay(alignment: .top) { Hairline(ink: theme.ink) }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - 还没有材料

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text").font(.system(size: 26, weight: .light)).foregroundStyle(theme.accent.opacity(0.9))
            Text(tr("把会前准备的材料拖到这里", "Drop your meeting notes here")).font(.system(size: 14, weight: .semibold))
            Text(tr("Markdown、HTML、纯文本都行。文件改了会自动刷新；开着跟读时，你照着稿子说，它就滚到你说到的地方。",
                    "Markdown, HTML or plain text. Edits to the file show up right away; with Follow on, the notes scroll to wherever you are as you speak."))
                .font(.system(size: 12))
                .foregroundStyle(theme.ink.opacity(0.62))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            PillButton(title: tr("打开材料…", "Open Notes…"), symbol: "folder", prominent: true, theme: theme, action: model.choose)
                .padding(.top, 2)
            if let error = model.error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.orange).multilineTextAlignment(.center)
            }
            let recent = model.recent.prefix(4)
            if !recent.isEmpty {
                VStack(spacing: 4) {
                    Text(tr("最近用过", "Recent")).font(.system(size: 11)).foregroundStyle(theme.ink.opacity(0.5))
                    ForEach(Array(recent), id: \.self) { url in
                        Button { model.open(url) } label: {
                            Label(url.lastPathComponent, systemImage: "doc.text")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.ink.opacity(0.85))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 把 PrompterWeb 的网页视图放进 SwiftUI。网页视图归 PrompterModel 所有，这里只是个容器，
/// 界面重建（换语言）时网页不用重新载入
struct PrompterWebHost: NSViewRepresentable {
    let web: PrompterWeb

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attach(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        if web.view.superview !== container { attach(to: container) }
    }

    private func attach(to container: NSView) {
        web.view.removeFromSuperview()
        web.view.frame = container.bounds
        web.view.autoresizingMask = [.width, .height]
        container.addSubview(web.view)
    }
}
