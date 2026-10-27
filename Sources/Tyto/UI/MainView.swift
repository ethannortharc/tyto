@preconcurrency import AVFAudio
import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

/// "会话与设置"窗口：左边侧栏，右边分页。
struct MainView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var skills: SkillStore
    @State private var page: SettingsPage?

    init(session: SessionModel, settings: SettingsStore, skills: SkillStore, initialPage: SettingsPage = .session) {
        self.session = session
        self.settings = settings
        self.skills = skills
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(SettingsPage.groups, id: \.title) { group in
                    Section(group.title) {
                        ForEach(group.pages) { page in
                            Label { Text(page.title) } icon: { IconTile(symbol: page.symbol, colors: page.colors(settings.value.iconStyle), size: 22) }
                                .tag(page)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 205, max: 240)
        } detail: {
            let current = page ?? .session
            VStack(spacing: 0) {
                PageHeader(page: current, iconStyle: settings.value.iconStyle)
                pageView(current)
            }
            .frame(minWidth: 560)
        }
        .frame(minWidth: 820, minHeight: 620)
        // 和系统设置一样用滑动开关
        .toggleStyle(.switch)
        .tint(Brand.accent)
        // 换界面语言时整棵重建，文字立即全部换过来（当前在哪一页不受影响）
        .id(settings.value.language)
    }

    @ViewBuilder
    private func pageView(_ current: SettingsPage) -> some View {
        switch current {
        case .session: SessionPage(session: session, settings: settings, skills: skills, page: $page)
        case .skills: SkillsPage(skills: skills)
        case .listen: ListenPage(settings: settings)
        case .translation: TranslationPage(settings: settings, session: session)
        case .screenshot: ScreenshotPage(settings: settings)
        case .services: ServicesPage(settings: settings)
        case .appearance: AppearancePage(settings: settings)
        case .shortcuts: ShortcutsPage()
        case .permissions: PermissionsPage()
        }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case session, skills, listen, translation, screenshot, services, appearance, shortcuts, permissions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: tr("会话", "Session")
        case .skills: tr("技能", "Skills")
        case .listen: tr("听写", "Listening")
        case .translation: tr("翻译", "Translation")
        case .screenshot: tr("截屏回复", "Screenshot Reply")
        case .services: tr("模型与服务", "Models & Services")
        case .appearance: tr("外观", "Appearance")
        case .shortcuts: tr("快捷键", "Shortcuts")
        case .permissions: tr("权限与关于", "Permissions & About")
        }
    }

    var subtitle: String {
        switch self {
        case .session: tr("这场会议的背景、关键词、技能和说话人。回复时都会带上。", "Context, keywords, skills and speakers for this meeting. All of it goes into replies.")
        case .skills: tr("写给大模型的做法说明，决定回复的语气和套路。", "Instructions for the model that set the tone and approach of replies.")
        case .listen: tr("听哪些声音，怎么把声音变成文字。", "Which sounds to listen to, and how to turn them into text.")
        case .translation: tr("每句话下面显示译文，悬浮窗顶部一键开关。", "Shows a translation under each line. One-click toggle at the top of the overlay.")
        case .screenshot: tr("截下最前面的 App 或整个屏幕，读懂内容，写好能直接粘贴的回复。", "Capture the frontmost app or the whole screen, read it, and write a reply you can paste right away.")
        case .services: tr("服务商只配一次，回复、看图、翻译、语音识别都从这里选。", "Set up each provider once; Reply, Vision, Translation and Speech Recognition all pick from here.")
        case .appearance: tr("主题、透明度和字号。下面是实时预览。", "Theme, tint and font size. Live preview below.")
        case .shortcuts: tr("会议软件在前台时也能用。", "Works while the meeting app is in front.")
        case .permissions: tr("Tyto 用到的系统权限，以及数据放在哪。", "System permissions Tyto uses, and where your data is stored.")
        }
    }

    var symbol: String {
        switch self {
        case .session: "person.2.wave.2.fill"
        case .skills: "book.closed.fill"
        case .listen: "waveform"
        case .translation: "character.bubble.fill"
        case .screenshot: "camera.viewfinder"
        case .services: "square.stack.3d.up.fill"
        case .appearance: "paintpalette.fill"
        case .shortcuts: "command"
        case .permissions: "lock.shield.fill"
        }
    }

    /// 低饱和的页面色（彩色图标块用）
    private var muted: UInt32 {
        switch self {
        case .session: 0x5E7891
        case .skills: 0x9C7A4E
        case .listen: 0xA8625A
        case .translation: 0x6B8868
        case .screenshot: 0x5A8682
        case .services: 0x5C6573
        case .appearance: 0xAA7656
        case .shortcuts: 0x75736D
        case .permissions: 0x7A7C5C
        }
    }

    func colors(_ style: IconStyle) -> [Color] {
        style == .muted ? [Brand.rgb(muted)] : Brand.graphite
    }

    static var groups: [(title: String, pages: [SettingsPage])] { [
        (tr("会议", "Meeting"), [.session, .skills]),
        (tr("功能", "Features"), [.listen, .translation, .screenshot]),
        (tr("设置", "Settings"), [.services, .appearance, .shortcuts, .permissions]),
    ] }
}

// MARK: - 通用部件

/// 品牌色：取仓鸮（Tyto）背羽的赭黄。设置窗口里的选中、开关、链接都用它，不用系统蓝
enum Brand {
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.82, green: 0.64, blue: 0.42, alpha: 1)
            : NSColor(red: 0.61, green: 0.42, blue: 0.18, alpha: 1)
    })

    /// 图标块的石墨色
    static let graphite = [rgb(0x3A3A3D), rgb(0x26262A)]

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 图标块：象牙白图标，底色是石墨或低饱和的页面色
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: colors.count > 1 ? colors : [colors[0], colors[0]], startPoint: .top, endPoint: .bottom))
            // 上沿一道细亮边，有一点实物的厚度
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                               lineWidth: 0.5)
            Image(systemName: symbol)
                .font(.system(size: size * 0.48, weight: .medium))
                .foregroundStyle(Brand.rgb(0xEFE9DE))
        }
        .frame(width: size, height: size)
    }
}

private struct PageHeader: View {
    let page: SettingsPage
    let iconStyle: IconStyle

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: page.symbol, colors: page.colors(iconStyle), size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).font(.system(size: 20, weight: .bold))
                Text(page.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 6)
    }
}

/// 一行设置：前面一个彩色小图标，标题，可选的说明，右边是控件
private struct Row<Content: View>: View {
    let symbol: String
    let title: String
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        LabeledContent {
            content
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// 可选卡片：图标 + 标题 + 说明，选中时描边高亮
private struct OptionCard: View {
    let symbol: String
    let title: String
    var detail: String?
    let selected: Bool
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(selected ? Color.white : Brand.accent)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Brand.accent : Brand.accent.opacity(0.12)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    if let detail {
                        Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(selected ? Brand.accent : Color.secondary.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.06 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// 状态小标签
private struct StatusPill: View {
    let text: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

// MARK: - 会话

private struct SessionPage: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var skills: SkillStore
    @Binding var page: SettingsPage?

    var body: some View {
        Form {
            Section {
                Row(symbol: "textformat", title: tr("会议名称", "Meeting Name")) {
                    TextField("", text: $session.title, prompt: Text(tr("新会议", "New Meeting"))).frame(maxWidth: 280)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label { Text(tr("背景", "Context")) } icon: {
                        Image(systemName: "doc.text").foregroundStyle(.secondary)
                    }
                    TextEditor(text: $session.context)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .overlay(alignment: .topLeading) {
                            if session.context.isEmpty {
                                Text(tr("会议目的和议程；参会的人、他们的角色和关心的事；我的角色和立场；要用到的术语、数字、日期。", "Meeting purpose and agenda; who is attending, their roles and concerns; my role and position; terms, numbers and dates to use."))
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(13)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Row(symbol: "highlighter", title: tr("关键词", "Keywords"), detail: tr("字幕里高亮，逗号分隔。数字、日期、人名会自动高亮。", "Highlighted in captions, comma-separated. Numbers, dates and names are highlighted automatically.")) {
                    TextField("", text: $session.keywords, prompt: Text(tr("launch, budget, 上线", "launch, budget, deadline"))).frame(maxWidth: 280)
                }
            } header: {
                Text(tr("这场会议", "This Meeting"))
            }

            Section {
                ForEach(skills.skills) { skill in
                    Toggle(isOn: Binding(
                        get: { session.activeSkillIDs.contains(skill.id) },
                        set: { on in
                            if on { session.activeSkillIDs.insert(skill.id) } else { session.activeSkillIDs.remove(skill.id) }
                        })) {
                        HStack(spacing: 10) {
                            Image(systemName: "book.closed").foregroundStyle(.secondary).frame(width: 20)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                if !skill.description.isEmpty {
                                    Text(skill.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            } header: {
                HStack {
                    Text(tr("用到的技能", "Skills in Use"))
                    Spacer()
                    Button(tr("编辑技能", "Edit Skills")) { page = .skills }.buttonStyle(.plain).foregroundStyle(Brand.accent).font(.caption)
                }
            }

            Section {
                if session.knownSpeakers.isEmpty {
                    Label(tr("开始听以后，出现的说话人会列在这里", "Speakers will be listed here once listening starts"), systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                ForEach(session.knownSpeakers, id: \.key) { speaker in
                    Row(symbol: speaker.key.hasPrefix("local") ? "mic.circle.fill" : "person.wave.2.fill",
                        title: speaker.label) {
                        TextField("", text: Binding(
                            get: { session.speakerNames[speaker.key] ?? "" },
                            set: { session.rename(speaker.key, to: $0) }),
                                  prompt: Text(tr("名字，比如：我、Alice", "Name, e.g. Me, Alice")))
                            .frame(maxWidth: 220)
                    }
                }
            } header: {
                Text(tr("说话人", "Speakers"))
            }

            Section {
                Row(symbol: "text.bubble", title: tr("解释用的语言", "Explain In"),
                    detail: tr("回复里说明「对方的意思」用的语言；留空跟界面语言一致", "Language for \"what they mean\"; empty follows the interface")) {
                    TextField("", text: $settings.value.explainLanguage, prompt: Text(tr("跟界面语言一致", "Same as interface")))
                        .frame(maxWidth: 200)
                }
                Row(symbol: "quote.bubble", title: tr("回复用的语言", "Reply In"),
                    detail: tr("建议回复用的语言；留空跟对方说话的语言一致", "Language of the suggested reply; empty matches the other side")) {
                    TextField("", text: $settings.value.replyLanguage, prompt: Text(tr("跟对方一致", "Same as theirs")))
                        .frame(maxWidth: 200)
                }
                Row(symbol: "questionmark.bubble", title: tr("对方提问时自动回复", "Auto-Reply to Questions"),
                    detail: tr("远端说完一句问句，自动生成回复建议", "Draft a reply automatically when the remote side asks a question")) {
                    Toggle("", isOn: $settings.value.autoReplyOnQuestion).labelsHidden()
                }
            } header: {
                Text(tr("回复", "Replies"))
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        session.toggle()
                    } label: {
                        Label(session.isRunning ? tr("停止听", "Stop Listening") : tr("开始听", "Start Listening"),
                              systemImage: session.isRunning ? "stop.circle.fill" : "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isStarting)
                    Button(action: export) { Label(tr("导出记录", "Export Transcript"), systemImage: "square.and.arrow.up") }
                        .disabled(session.rows.isEmpty)
                    Spacer()
                    Button { Task { await session.newSession() } } label: {
                        Label(tr("开始新会议", "New Meeting"), systemImage: "plus.bubble")
                    }
                    .help(tr("当前记录存档后清空；背景、关键词和技能保留", "Archives the current transcript and clears it; context, keywords and skills are kept"))
                }
            } footer: {
                Text(tr("记录自动保存在 ~/Library/Application Support/Tyto/sessions/", "Transcripts are saved automatically in ~/Library/Application Support/Tyto/sessions/")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func export() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "\(session.title).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? session.markdown().write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - 技能

private struct SkillsPage: View {
    @ObservedObject var skills: SkillStore
    @State private var selectedID: String?
    @State private var draft: Skill?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(skills.skills, selection: $selectedID) { skill in
                    Label { Text(skill.name) } icon: { Image(systemName: "book.closed").foregroundStyle(.secondary) }
                        .tag(skill.id)
                }
                .listStyle(.inset)
                Divider()
                HStack(spacing: 4) {
                    Button { selectedID = skills.create().id } label: { Image(systemName: "plus") }
                        .help(tr("新建技能", "New Skill"))
                    Button {
                        if let draft {
                            skills.delete(draft)
                            selectedID = nil
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(draft == nil)
                        .help(tr("删除", "Delete"))
                    Spacer()
                    Button(action: skills.openFolder) { Image(systemName: "folder") }.help(tr("在 Finder 中打开技能文件夹", "Open Skills Folder in Finder"))
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            if let binding = Binding($draft) {
                Form {
                    Row(symbol: "textformat", title: tr("名称", "Name")) {
                        TextField("", text: binding.name).frame(maxWidth: 260)
                    }
                    Row(symbol: "questionmark.bubble", title: tr("什么时候用", "When to Use")) {
                        TextField("", text: binding.description).frame(maxWidth: 260)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text(tr("做法说明（Markdown，原样交给大模型）", "Instructions (Markdown, passed to the model as-is)")) } icon: {
                            Image(systemName: "text.alignleft").foregroundStyle(.secondary)
                        }
                        TextEditor(text: binding.body)
                            .font(.system(size: 12.5, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 280)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                    }
                    HStack {
                        Spacer()
                        Button { if let draft { skills.save(draft) } } label: { Label(tr("保存", "Save"), systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(draft == skills.skills.first { $0.id == draft?.id })
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView(tr("选一个技能", "Select a Skill"), systemImage: "book.closed",
                                       description: Text(tr("左边选一个编辑，或者点 + 新建", "Pick one on the left to edit, or click + to create one")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedID) { draft = skills.skills.first { $0.id == selectedID } }
    }
}

// MARK: - 听写（声音来源 + 语音识别）

private struct ListenPage: View {
    @ObservedObject var settings: SettingsStore
    @State private var inputDevices: [InputDevice] = []

    var body: some View {
        Form {
            Section {
                Row(symbol: "person.wave.2.fill", title: tr("远端", "Remote"), detail: tr("会议软件里对方的声音（录系统声音）", "The other side's audio from the meeting app (system audio)")) {
                    Toggle("", isOn: $settings.value.captureRemote).labelsHidden()
                }
                Row(symbol: "mic.fill", title: tr("本地", "Local"), detail: tr("麦克风收到的声音：你和会议室里的人", "Sound from the microphone: you and people in the room")) {
                    Toggle("", isOn: $settings.value.captureLocal).labelsHidden()
                }
                Row(symbol: "mic.badge.plus", title: tr("麦克风", "Microphone"), detail: tr("自动：跟系统默认走，跳过 BlackHole 这类虚拟声卡", "Auto: follows the system default, skipping virtual devices like BlackHole")) {
                    Picker("", selection: $settings.value.localInputDeviceUID) {
                        Text(tr("自动", "Auto")).tag("")
                        ForEach(inputDevices) { device in
                            Text(device.isVirtual ? tr("\(device.name)（虚拟声卡）", "\(device.name) (virtual)") : device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
                Row(symbol: "ear.and.waveform", title: tr("去掉回声", "Remove Echo"), detail: tr("外放开会时，麦克风收到的对方声音不重复显示", "With speakers on, the other side's voice picked up by the mic isn't shown twice")) {
                    Toggle("", isOn: $settings.value.echoCancellation).labelsHidden()
                }
            } header: {
                Text(tr("听哪些声音", "Audio Sources"))
            }

            Section {
                SpeechMethodCards(settings: settings)
            } header: {
                Text(tr("怎么把声音变成文字", "How Audio Becomes Text"))
            }

            Section {
                SpeechDetails(settings: settings)
            } header: {
                Text(settings.value.speechMethod == .apple ? tr("语言", "Language") : tr("服务", "Service"))
            } footer: {
                Text(tr("改了以后停止再开始听才生效。", "Changes take effect the next time you start listening.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { inputDevices = InputDevices.all() }
    }
}

private struct SpeechMethodCards: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(SpeechMethod.allCases) { method in
                OptionCard(symbol: method.symbol, title: method.title, detail: method.detail,
                           selected: settings.value.speechMethod == method) { choose(method) }
            }
        }
        .padding(.vertical, 2)
    }

    /// 换方式时，如果原来选的服务商干不了这个，自动换成第一个能干的
    private func choose(_ method: SpeechMethod) {
        settings.value.speechMethod = method
        guard let capability = method.capability else { return }
        let usable = settings.value.providers(for: capability)
        if !usable.contains(where: { $0.id == settings.value.speechSlot.providerID }), let first = usable.first {
            settings.value.speechSlot = ModelSlot(providerID: first.id, model: first.info.suggested[capability]?.first ?? "")
        }
    }
}

/// 语音识别的细节：本机选语言；云端选服务商、模型和可能出现的语言
private struct SpeechDetails: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        if let capability = settings.value.speechMethod.capability {
            Row(symbol: "server.rack", title: tr("服务商和模型", "Provider & Model")) {
                ModelPicker(settings: settings, slot: $settings.value.speechSlot, capability: capability)
            }
            Row(symbol: "globe", title: tr("可能出现的语言", "Expected Languages"), detail: tr("逗号分隔，如 en,zh；只填一种识别更准", "Comma-separated, e.g. en,zh; a single language is more accurate")) {
                TextField("", text: $settings.value.speechLanguageHints).frame(maxWidth: 200)
            }
        } else {
            Row(symbol: "person.wave.2.fill", title: tr("远端说的语言", "Remote Language")) {
                LanguageField(code: $settings.value.remoteLocale, choices: Languages.speechChoices)
            }
            Row(symbol: "mic.fill", title: tr("本地说的语言", "Local Language")) {
                LanguageField(code: $settings.value.localLocale, choices: Languages.speechChoices)
            }
        }
    }
}

// MARK: - 模型与服务

private struct ServicesPage: View {
    @ObservedObject var settings: SettingsStore
    @State private var expanded: String?

    var body: some View {
        Form {
            Section {
                ForEach($settings.value.providers) { $provider in
                    ProviderRow(provider: $provider, expanded: expanded == provider.id,
                                toggle: { expanded = expanded == provider.id ? nil : provider.id },
                                remove: { remove(provider.id) })
                }
                if settings.value.providers.isEmpty {
                    Label(tr("还没有服务商，点右上角「添加」", "No providers yet. Click Add at top right."), systemImage: "tray").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text(tr("服务商", "Providers"))
                    Spacer()
                    AddProviderMenu { add($0) }
                }
            } footer: {
                Text(tr("每个服务商只要配一次（地址、key），下面各个用途从里面选。key 存在钥匙串里。", "Set up each provider once (address, key); the uses below pick from them. Keys are stored in the Keychain.")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Row(symbol: "text.bubble.fill", title: tr("回复", "Reply"), detail: tr("会议回复、截屏回复", "Meeting replies and screenshot replies")) {
                    VStack(alignment: .trailing, spacing: 6) {
                        ModelPicker(settings: settings, slot: $settings.value.replySlot, capability: .chat)
                        Picker("", selection: $settings.value.replySlot.effort) {
                            Text(tr("思考：低", "Effort: Low")).tag("low")
                            Text(tr("中", "Medium")).tag("medium")
                            Text(tr("高", "High")).tag("high")
                            Text(tr("不传", "Default")).tag("")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                }
                Row(symbol: "eye.fill", title: tr("看图", "Vision"), detail: tr("截屏回复选「先用看图模型读图」时用", "Used when Screenshot Reply is set to “Vision Model First”")) {
                    ModelPicker(settings: settings, slot: $settings.value.visionSlot, capability: .vision)
                }
                Row(symbol: "character.bubble.fill", title: tr("翻译", "Translation"), detail: tr("翻译方式选「大模型翻译」时用", "Used when the translation method is “LLM Translation”")) {
                    ModelPicker(settings: settings, slot: $settings.value.translationSlot, capability: .chat, sameAsReply: true)
                }
                Row(symbol: "waveform", title: tr("语音识别", "Speech Recognition"), detail: settings.value.speechMethod.title) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Picker("", selection: $settings.value.speechMethod) {
                            ForEach(SpeechMethod.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 200)
                        if let capability = settings.value.speechMethod.capability {
                            ModelPicker(settings: settings, slot: $settings.value.speechSlot, capability: capability)
                        }
                    }
                }
            } header: {
                Text(tr("各个用途", "Uses"))
            } footer: {
                Text(tr("每一行左边选服务商，右边选模型；点 ⌄ 从服务商读模型列表，也可以直接输入。", "Pick a provider on the left and a model on the right; click ⌄ to load the provider's model list, or type one in.")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func add(_ template: ProviderTemplate) {
        var id = template.id
        var number = 2
        while settings.value.providers.contains(where: { $0.id == id }) {
            id = "\(template.id)-\(number)"
            number += 1
        }
        let name = id == template.id ? template.name : "\(template.name) \(number - 1)"
        settings.value.providers.append(Provider(id: id, name: name, kind: template.kind, baseURL: template.baseURL,
                                                 template: template.id))
        expanded = id
    }

    private func remove(_ id: String) {
        settings.value.providers.removeAll { $0.id == id }
        Keychain.set("", for: "provider.\(id)")
    }
}

/// 添加服务商：从模板里选
private struct AddProviderMenu: View {
    let add: (ProviderTemplate) -> Void

    var body: some View {
        Menu {
            Section(tr("大模型", "Language Models")) {
                ForEach(["anthropic", "openai", "openrouter", "gemini", "deepseek", "dashscope", "siliconflow", "groq"], id: \.self) { item($0) }
            }
            Section(tr("本机", "Local")) { ForEach(["ollama", "lmstudio"], id: \.self) { item($0) } }
            Section(tr("语音识别", "Speech Recognition")) { ForEach(["soniox", "deepgram"], id: \.self) { item($0) } }
            Section { item("custom") }
        } label: {
            Label(tr("添加", "Add"), systemImage: "plus.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func item(_ id: String) -> some View {
        if let template = ProviderTemplate.find(id) {
            Button { add(template) } label: { Label(template.name, systemImage: template.symbol) }
        }
    }
}

/// 一个服务商：收起时一行，展开后改名字、地址、key，测连通
private struct ProviderRow: View {
    @Binding var provider: Provider
    let expanded: Bool
    let toggle: () -> Void
    let remove: () -> Void

    @State private var key = ""
    @State private var test: String?
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    IconTile(symbol: provider.info.symbol, colors: provider.info.colors, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                        Text(provider.info.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !provider.needsKey {
                        StatusPill(text: tr("本机", "Local"), color: Brand.accent, symbol: "desktopcomputer")
                    } else if provider.key != nil {
                        StatusPill(text: tr("已填 key", "Key Set"), color: .green, symbol: "checkmark")
                    } else {
                        StatusPill(text: tr("缺 key", "No Key"), color: .orange, symbol: "key")
                    }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 8) {
                    Row(symbol: "tag", title: tr("名字", "Name")) {
                        TextField("", text: $provider.name).frame(maxWidth: 280)
                    }
                    Row(symbol: "link", title: tr("接口地址", "Endpoint")) {
                        TextField("", text: $provider.baseURL, prompt: Text(provider.info.baseURL)).frame(maxWidth: 280)
                    }
                    if provider.needsKey {
                        Row(symbol: "key.fill", title: "API key") {
                            HStack(spacing: 6) {
                                SecureField("", text: $key).frame(maxWidth: 220)
                                    .onChange(of: key) { provider.setKey(key) }
                                if let page = provider.info.keyPage, let url = URL(string: page) {
                                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help(tr("去拿 key", "Get a key"))
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button(role: .destructive, action: remove) { Label(tr("删除", "Delete"), systemImage: "trash") }
                        Spacer()
                        if testing { ProgressView().controlSize(.small) }
                        if let test { Text(test).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled) }
                        Button(action: runTest) { Label(tr("测试连接", "Test Connection"), systemImage: "bolt.horizontal.circle") }.disabled(testing)
                    }
                }
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 2)
        .onAppear { key = Keychain.get("provider.\(provider.id)") ?? "" }
    }

    private func runTest() {
        testing = true
        test = nil
        let provider = provider
        Task {
            defer { testing = false }
            if provider.kind == .soniox || provider.kind == .deepgram {
                test = provider.key == nil ? tr("还没填 key", "No key yet") : tr("key 已保存，开始听时连接", "Key saved; connects when listening starts")
                return
            }
            do {
                let models = try await ModelList.fetch(provider)
                test = tr("通了，有 \(models.count) 个模型", "Connected, \(models.count) models")
            } catch {
                test = error.localizedDescription
            }
        }
    }
}

/// 选模型：左边选服务商（只列能干这件事的），右边填或选模型
struct ModelPicker: View {
    @ObservedObject var settings: SettingsStore
    @Binding var slot: ModelSlot
    let capability: Capability
    /// 翻译可以选"跟回复一样"
    var sameAsReply = false

    @State private var fetched: [String] = []
    @State private var loading = false

    private var usable: [Provider] { settings.value.providers(for: capability) }

    var body: some View {
        HStack(spacing: 6) {
            // 这里要写成闭包：直接传方法（set: chooseProvider）会让 Swift 6.2 编译器在生成代码时崩溃
            Picker("", selection: Binding(get: { slot.providerID }, set: { chooseProvider($0) })) {
                if sameAsReply { Text(tr("跟回复一样", "Same as Reply")).tag("") }
                if !sameAsReply && !usable.contains(where: { $0.id == slot.providerID }) {
                    Text(slot.providerID.isEmpty ? tr("选服务商", "Select Provider") : tr("（已删除）", "(Deleted)")).tag(slot.providerID)
                }
                ForEach(usable) { provider in
                    Label(provider.displayName, systemImage: provider.info.symbol).tag(provider.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            if !slot.providerID.isEmpty {
                TextField("", text: $slot.model, prompt: Text(tr("模型", "Model"))).frame(width: 170)
                Menu {
                    ForEach(choices, id: \.self) { model in Button(model) { slot.model = model } }
                    Divider()
                    Button(loading ? tr("读取中…", "Loading…") : tr("从服务商读取列表", "Load List from Provider"), action: load).disabled(loading)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(tr("推荐的模型，或者从服务商读取", "Suggested models, or load from the provider"))
            }
        }
    }

    private var choices: [String] {
        let suggested = settings.value.provider(slot.providerID)?.info.suggested[capability] ?? []
        return suggested + fetched.filter { !suggested.contains($0) }
    }

    private func chooseProvider(_ id: String) {
        guard id != slot.providerID else { return }
        slot.providerID = id
        fetched = []
        slot.model = settings.value.provider(id)?.info.suggested[capability]?.first ?? ""
    }

    private func load() {
        guard let provider = settings.value.provider(slot.providerID) else { return }
        loading = true
        Task {
            defer { loading = false }
            fetched = (try? await ModelList.fetch(provider)) ?? []
        }
    }
}

/// 常用语言下拉 + 可以手填代码
private struct LanguageField: View {
    @Binding var code: String
    let choices: [(code: String, name: String)]

    var body: some View {
        Picker("", selection: $code) {
            ForEach(choices, id: \.code) { Text($0.name).tag($0.code) }
            if !choices.contains(where: { $0.code == code }) { Text(code).tag(code) }
        }
        .labelsHidden()
        .frame(maxWidth: 200)
    }
}

extension Languages {
    static var speechChoices: [(code: String, name: String)] { [
        ("en-US", tr("英语（美国）", "English (US)")), ("en-GB", tr("英语（英国）", "English (UK)")), ("en-IN", tr("英语（印度）", "English (India)")), ("zh-CN", tr("中文（普通话）", "Chinese (Mandarin)")),
        ("zh-TW", tr("中文（台湾）", "Chinese (Taiwan)")), ("ja-JP", tr("日语", "Japanese")), ("ko-KR", tr("韩语", "Korean")), ("de-DE", tr("德语", "German")), ("fr-FR", tr("法语", "French")),
        ("es-ES", tr("西班牙语", "Spanish")),
    ] }
    static var translationChoices: [(code: String, name: String)] { [
        ("zh-Hans", tr("简体中文", "Simplified Chinese")), ("zh-Hant", tr("繁體中文", "Traditional Chinese")), ("en", tr("英语", "English")), ("ja", tr("日语", "Japanese")), ("ko", tr("韩语", "Korean")),
        ("de", tr("德语", "German")), ("fr", tr("法语", "French")), ("es", tr("西班牙语", "Spanish")),
    ] }
}

// MARK: - 翻译

private struct TranslationPage: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var session: SessionModel

    var body: some View {
        Form {
            Section {
                Row(symbol: "character.bubble.fill", title: tr("显示译文", "Show Translation")) {
                    Toggle("", isOn: Binding(get: { settings.value.translationEnabled },
                                             set: { settings.value.translationEnabled = $0; session.translationToggled() }))
                        .labelsHidden()
                }
                Row(symbol: "arrow.right.circle.fill", title: tr("主语言", "Main Language"),
                    detail: tr("别的语言的句子，下面会多一行小字译文；本来就是主语言的句子不翻译", "Lines in other languages get a smaller translation underneath; lines already in this language are left as is")) {
                    LanguageField(code: $settings.value.targetLanguage, choices: Languages.translationChoices)
                }
            }
            Section {
                OptionCard(symbol: "apple.logo", title: tr("Apple 本机翻译", "Apple On-Device Translation"), detail: tr("免费、不联网、快。第一次要下载语言包。", "Free, offline and fast. The first use needs a language pack download."),
                           selected: settings.value.translationProvider == .apple) { settings.value.translationProvider = .apple }
                OptionCard(symbol: "text.bubble", title: tr("大模型翻译", "LLM Translation"), detail: tr("更懂上下文和术语。默认用回复的模型，也可以单独选。", "Better with context and terminology. Uses the Reply model by default, or pick a separate one."),
                           selected: settings.value.translationProvider == .llm) { settings.value.translationProvider = .llm }
            } header: {
                Text(tr("翻译方式", "Translation Method"))
            }
            Section {
                if settings.value.translationProvider == .apple {
                    TranslationDownload(source: settings.value.remoteLocale, target: settings.value.targetLanguage)
                    if settings.value.localLocale != settings.value.remoteLocale {
                        TranslationDownload(source: settings.value.localLocale, target: settings.value.targetLanguage)
                    }
                } else {
                    Row(symbol: "server.rack", title: tr("翻译用的模型", "Translation Model")) {
                        ModelPicker(settings: settings, slot: $settings.value.translationSlot, capability: .chat, sameAsReply: true)
                    }
                }
            } header: {
                Text(settings.value.translationProvider == .apple ? tr("语言包", "Language Packs") : tr("模型", "Model"))
            }
        }
        .formStyle(.grouped)
    }
}

/// 下载 Apple 本机翻译的语言包（系统会弹出下载确认）
private struct TranslationDownload: View {
    let source: String
    let target: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var installed: Bool?
    @State private var message = ""

    var body: some View {
        Row(symbol: "arrow.down.circle.fill",
            title: "\(Languages.name(source)) → \(Languages.name(target))", detail: message.isEmpty ? nil : message) {
            if installed == true {
                StatusPill(text: tr("已就绪", "Ready"), color: .green, symbol: "checkmark")
            } else {
                Button(tr("下载", "Download")) {
                    if configuration == nil {
                        configuration = .init(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
                    } else {
                        configuration?.invalidate()
                    }
                }
            }
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                installed = true
            } catch {
                message = error.localizedDescription
            }
        }
        .task(id: "\(source)>\(target)") {
            let status = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                             to: Locale.Language(identifier: target))
            installed = status == .installed
            message = status == .unsupported ? tr("不支持这对语言", "This language pair isn't supported") : ""
        }
    }
}

// MARK: - 截屏回复

private struct ScreenshotPage: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    ForEach(AppSettings.CaptureTarget.allCases) { target in
                        CaptureChip(target: target, selected: settings.value.captureTarget == target) {
                            settings.value.captureTarget = target
                        }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(tr("⌃⌥S 截哪里", "What ⌃⌥S Captures"))
            } footer: {
                Text(tr("最前面的 App：按快捷键时你正在用的那个窗口（比如 Teams），Tyto 会认出是哪个 App。⌃⌥A 总是框选。截图要「屏幕录制」权限。", "Frontmost App: the window you're using when you press the shortcut (e.g. Teams); Tyto recognizes which app it is. ⌃⌥A always selects an area. Screenshots need the Screen Recording permission."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(AppSettings.ScreenshotMode.allCases) { mode in
                    OptionCard(symbol: mode.symbol, title: mode.title, detail: mode.detail,
                               selected: settings.value.screenshotMode == mode) { settings.value.screenshotMode = mode }
                }
                if settings.value.screenshotMode == .visionModel {
                    Row(symbol: "eye.fill", title: tr("看图模型", "Vision Model")) {
                        ModelPicker(settings: settings, slot: $settings.value.visionSlot, capability: .vision)
                    }
                }
            } header: {
                Text(tr("怎么读懂截图", "How to Read the Screenshot"))
            }

            Section {
                OllamaCatalog(settings: settings)
            } header: {
                Text(tr("文字识别和本机看图模型", "Text Recognition & On-Device Vision Models"))
            } footer: {
                Text(tr("系统自带的文字识别不用下载，最小最快。想让截图不出这台 Mac 又能看懂版面，就下载一个本机看图模型（通过 Ollama），点「用这个」。这几个模型 16 GB 内存的笔记本也跑得动。", "Built-in text recognition needs no download and is the smallest and fastest. To keep screenshots on this Mac and still understand the layout, download an on-device vision model (via Ollama) and click “Use This”. These models run on a laptop with 16 GB of memory."))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Row(symbol: "doc.on.clipboard.fill", title: tr("自动复制第一个回复", "Copy First Reply Automatically"), detail: tr("生成好后直接 ⌘V 粘贴发送", "Paste and send with ⌘V once it's ready")) {
                    Toggle("", isOn: $settings.value.copyFirstScreenshotReply).labelsHidden()
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CaptureChip: View {
    let target: AppSettings.CaptureTarget
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: target.symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(selected ? Brand.accent : Color.secondary)
                    .frame(height: 30)
                Text(target.title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Brand.accent.opacity(0.1) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Brand.accent : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 文字识别引擎和本机看图模型：系统自带的 OCR + Ollama 上推荐的模型，可以直接下载
private struct OllamaCatalog: View {
    @ObservedObject var settings: SettingsStore
    @State private var version: String?
    @State private var checked = false
    @State private var installed: [String] = []
    @State private var downloading: [String: Double] = [:]
    @State private var error: String?

    var body: some View {
        Group {
            HStack(spacing: 12) {
                IconTile(symbol: "text.viewfinder", colors: Brand.graphite, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("系统文字识别（Apple Vision）", "System Text Recognition (Apple Vision)")).font(.system(size: 13, weight: .semibold))
                    Text(tr("系统自带，不用下载；中英日文；聊天截图约 0.3 秒，整个 5K 屏约 0.6 秒", "Built in, no download; Chinese, English, Japanese; about 0.3 s for a chat screenshot, 0.6 s for a full 5K screen")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: tr("已就绪", "Ready"), color: .green, symbol: "checkmark")
            }

            HStack(spacing: 12) {
                IconTile(symbol: "shippingbox.fill", colors: Brand.graphite, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama").font(.system(size: 13, weight: .semibold))
                    Text(version.map { tr("\($0) 正在运行", "\($0) running") } ?? (checked ? tr("没检测到。装好并打开后点「重新检测」", "Not detected. Install and open it, then click Check Again") : tr("检测中…", "Checking…")))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if version == nil, checked {
                    Button(tr("下载 Ollama", "Download Ollama")) { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(tr("重新检测", "Check Again"))
            }

            ForEach(Ollama.recommended) { model in
                modelRow(model)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
        }
        .task { await refresh() }
    }

    private func modelRow(_ model: Ollama.Recommended) -> some View {
        let isInstalled = installed.contains(model.id) || installed.contains("\(model.id):latest")
        let inUse = settings.value.provider(settings.value.visionSlot.providerID)?.kind == .ollama
            && settings.value.visionSlot.model == model.id
        return HStack(spacing: 12) {
            IconTile(symbol: model.symbol, colors: Brand.graphite, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name).font(.system(size: 13, weight: .semibold))
                    Text(model.size).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.06)))
                }
                Text(model.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let progress = downloading[model.id] {
                    ProgressView(value: progress).controlSize(.small).frame(maxWidth: 260)
                }
            }
            Spacer()
            if inUse {
                StatusPill(text: tr("正在用", "In Use"), color: Brand.accent, symbol: "checkmark")
            } else if isInstalled {
                Button(tr("用这个", "Use This")) { use(model.id) }
            } else if downloading[model.id] != nil {
                Text("\(Int((downloading[model.id] ?? 0) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Button { download(model.id) } label: { Label(tr("下载", "Download"), systemImage: "arrow.down.circle") }
                    .disabled(version == nil)
            }
        }
    }

    /// 用本机模型看图：没有 Ollama 服务商就加一个
    private func use(_ model: String) {
        if !settings.value.providers.contains(where: { $0.kind == .ollama }), let template = ProviderTemplate.find("ollama") {
            settings.value.providers.append(Provider(id: template.id, name: template.name, kind: template.kind,
                                                     baseURL: template.baseURL, template: template.id))
        }
        let ollama = settings.value.providers.first { $0.kind == .ollama }!
        settings.value.visionSlot = ModelSlot(providerID: ollama.id, model: model)
        settings.value.screenshotMode = .visionModel
    }

    private func refresh() async {
        version = await Ollama.version()
        installed = version == nil ? [] : (try? await Ollama.installed()) ?? []
        checked = true
    }

    private func download(_ model: String) {
        downloading[model] = 0
        error = nil
        Task {
            do {
                for try await progress in Ollama.pull(model) {
                    if let fraction = progress.fraction { downloading[model] = fraction }
                }
                downloading[model] = nil
                await refresh()
            } catch {
                downloading[model] = nil
                self.error = error.localizedDescription
            }
        }
    }
}

// MARK: - 外观

private struct AppearancePage: View {
    @ObservedObject var settings: SettingsStore
    @State private var preview: SessionModel?
    /// 预览的背景换成白底页面，看黑字的效果
    @State private var previewOnLight = false
    @StateObject private var previewState = OverlayState()

    var body: some View {
        Form {
            Section {
                Row(symbol: "globe", title: tr("界面语言 · Language", "Language")) {
                    Picker("", selection: $settings.value.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Row(symbol: "square.grid.2x2", title: tr("侧栏图标", "Sidebar Icons"),
                    detail: tr("设置窗口左边的图标块：统一石墨色，或每页一个颜色", "Icon tiles in this window's sidebar: all graphite, or one color per page")) {
                    Picker("", selection: $settings.value.iconStyle) {
                        ForEach(IconStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 160)
                }
            }
            Section {
                HStack(spacing: 12) {
                    ForEach(ThemeID.allCases) { theme in
                        ThemeSwatch(theme: theme, selected: settings.value.theme == theme) { settings.value.theme = theme }
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(tr("主题", "Theme"))
            }
            Section {
                Row(symbol: "circle.lefthalf.filled", title: tr("底色浓度", "Tint"), detail: tr("最左边完全透明；往右先出现玻璃，再加深底色", "Fully transparent at the far left; moving right adds glass first, then a darker tint")) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                        Slider(value: $settings.value.overlayOpacity, in: 0...0.95).frame(width: 200)
                        Image(systemName: "circle.fill").foregroundStyle(.secondary)
                        Text("\(Int(settings.value.overlayOpacity * 100))%").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    }
                }
                Row(symbol: "character", title: tr("字色", "Text Color"),
                    detail: tr("自动：悬浮窗后面的画面亮时换黑字配浅色玻璃，暗时用白字（要录屏权限，只看亮度，不存图）",
                               "Auto: black text on light glass over bright content, white otherwise (needs Screen Recording; reads brightness only, saves nothing)")) {
                    Picker("", selection: $settings.value.overlayTextColor) {
                        ForEach(OverlayTextColor.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 190)
                }
                Row(symbol: "text.alignleft", title: tr("字幕样式", "Caption Style"),
                    detail: tr("头像：名字前一个圆形头像；细线：左边一条说话人颜色的线", "Avatar: a round badge before the name; Line: a speaker-colored line on the left")) {
                    Picker("", selection: $settings.value.transcriptStyle) {
                        ForEach(TranscriptStyle.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 140)
                }
                Row(symbol: "textformat.size", title: tr("字号", "Font Size")) {
                    HStack(spacing: 8) {
                        Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
                        Slider(value: $settings.value.fontSize, in: 11...24, step: 1).frame(width: 200)
                        Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
                        Text("\(Int(settings.value.fontSize))").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    }
                }
            }
            Section {
                ZStack {
                    SampleBackdrop(light: previewOnLight)
                    if let preview {
                        OverlayView(session: preview, settings: settings, ui: previewState)
                            .frame(width: 440, height: 470)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 510)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } header: {
                HStack {
                    Text(tr("预览", "Preview"))
                    Spacer()
                    Picker("", selection: $previewOnLight) {
                        Text(tr("会议画面", "Meeting")).tag(false)
                        Text(tr("白底文档", "White Page")).tag(true)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { if preview == nil { preview = SampleData.session(settings: settings) } }
        .onChange(of: previewOnLight, initial: true) { previewState.backdropIsLight = previewOnLight }
    }
}

private struct ThemeSwatch: View {
    let theme: ThemeID
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let colors = OverlayTheme.of(theme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(colors.tint)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(colors.accent).frame(width: 46, height: 7)
                        Capsule().fill(.white.opacity(0.8)).frame(width: 70, height: 5)
                        Capsule().fill(colors.translation.opacity(0.6)).frame(width: 56, height: 5)
                        HStack(spacing: 4) {
                            Circle().fill(colors.remote[0]).frame(width: 7)
                            Circle().fill(colors.local[0]).frame(width: 7)
                            Circle().fill(colors.number).frame(width: 7)
                            Circle().fill(colors.keyword).frame(width: 7)
                        }
                    }
                    .padding(10)
                }
                .frame(height: 74)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12)))
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Brand.accent : Color.secondary)
                    Text(theme.label.components(separatedBy: CharacterSet(charactersIn: "：:")).first ?? "").font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? Brand.accent : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷键

private struct ShortcutsPage: View {
    private let items: [(keys: [String], title: String, symbol: String)] = [
        (["⌃", "⌥", "L"], tr("开始 / 停止听", "Start / Stop Listening"), "record.circle"),
        (["⌃", "⌥", "R"], tr("回复（选中的句子，或最近的话）", "Reply (selected lines, or the latest)"), "arrowshape.turn.up.left.fill"),
        (["⌃", "⌥", "S"], tr("截屏回复（按设置截最前面的 App 或整个屏幕）", "Screenshot Reply (frontmost app or entire screen, per settings)"), "camera.viewfinder"),
        (["⌃", "⌥", "A"], tr("截屏回复：框选一块", "Screenshot Reply: Select Area"), "rectangle.dashed"),
        (["⌃", "⌥", "T"], tr("显示 / 隐藏悬浮窗", "Show / Hide Overlay"), "macwindow"),
        (["⌃", "⌥", "B"], tr("打开 / 收起回复面板", "Show / Hide Replies Panel"), "sidebar.left"),
        (["⌃", "⌥", "P"], tr("点击穿透开 / 关", "Click-Through On / Off"), "cursorarrow.motionlines"),
        (["⌃", "⌥", "Q"], tr("退出 Tyto", "Quit Tyto"), "power"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(items, id: \.title) { item in
                    Row(symbol: item.symbol, title: item.title) {
                        HStack(spacing: 4) {
                            ForEach(item.keys, id: \.self) { Keycap(label: $0) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(minWidth: 24, minHeight: 22)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.primary.opacity(0.15)))
            .shadow(color: .black.opacity(0.08), radius: 0, y: 1)
    }
}

// MARK: - 权限与关于

private struct PermissionsPage: View {
    @State private var microphone = AVAudioApplication.shared.recordPermission
    @State private var screen = CGPreflightScreenCaptureAccess()

    var body: some View {
        Form {
            Section {
                Row(symbol: "mic.fill", title: tr("麦克风", "Microphone"), detail: tr("本地那一路", "The Local channel")) {
                    HStack(spacing: 8) {
                        switch microphone {
                        case .granted: StatusPill(text: tr("已允许", "Allowed"), color: .green, symbol: "checkmark")
                        case .denied: StatusPill(text: tr("被拒绝", "Denied"), color: .red, symbol: "xmark")
                        default: StatusPill(text: tr("还没问过", "Not Asked"), color: .secondary)
                        }
                        Button(tr("打开设置", "Open Settings")) { Capture.openPrivacySettings("Privacy_Microphone") }
                    }
                }
                Row(symbol: "speaker.wave.2.fill", title: tr("系统录音", "System Audio Recording"), detail: tr("远端那一路，第一次开始听时询问", "The Remote channel; asked the first time you start listening")) {
                    Button(tr("打开设置", "Open Settings")) { Capture.openPrivacySettings("Privacy_ScreenCapture") }
                }
                Row(symbol: "camera.viewfinder", title: tr("屏幕录制", "Screen Recording"), detail: tr("截屏回复", "Screenshot Reply")) {
                    HStack(spacing: 8) {
                        StatusPill(text: screen ? tr("已允许", "Allowed") : tr("未允许", "Not Allowed"), color: screen ? .green : .orange,
                                   symbol: screen ? "checkmark" : "exclamationmark")
                        Button(tr("打开设置", "Open Settings")) { Capture.openPrivacySettings("Privacy_ScreenCapture") }
                    }
                }
            } header: {
                Text(tr("权限", "Permissions"))
            } footer: {
                Text(tr("在系统设置里打开权限后，要退出再打开 Tyto 才生效。", "After enabling a permission in System Settings, quit and reopen Tyto for it to take effect.")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                folderRow(tr("会话记录", "Session Transcripts"), symbol: "tray.full.fill", url: SessionModel.folder)
                folderRow(tr("技能", "Skills"), symbol: "book.closed", url: SkillStore.folder)
                folderRow(tr("运行日志", "Run Log"), symbol: "doc.text.magnifyingglass", url: URL.libraryDirectory.appending(path: "Logs/Tyto.log"))
            } header: {
                Text(tr("数据放在哪", "Where Data Is Stored"))
            } footer: {
                Text(tr("设置存在 defaults 的 com.giomni.tyto 里，API key 存在钥匙串（服务名 com.giomni.tyto）。", "Settings are stored in defaults under com.giomni.tyto; API keys are in the Keychain (service com.giomni.tyto).")).font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: "ear.fill", colors: Brand.graphite, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(tr("Tyto 听译", "Tyto")).font(.system(size: 16, weight: .bold))
                        Text(tr("版本 \(version)", "Version \(version)"))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("© 2026 Ethan H.B. Zhou").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            microphone = AVAudioApplication.shared.recordPermission
            screen = CGPreflightScreenCaptureAccess()
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? tr("开发版", "dev build")
    }

    private func folderRow(_ title: String, symbol: String, url: URL) -> some View {
        Row(symbol: symbol, title: title, detail: url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
            Button(tr("在 Finder 中显示", "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
