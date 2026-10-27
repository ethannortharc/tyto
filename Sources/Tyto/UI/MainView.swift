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
                            Label { Text(page.title) } icon: { IconTile(symbol: page.symbol, colors: page.colors, size: 22) }
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
                PageHeader(page: current)
                pageView(current)
            }
            .frame(minWidth: 560)
        }
        .frame(minWidth: 820, minHeight: 620)
        // 和系统设置一样用滑动开关
        .toggleStyle(.switch)
        // 换界面语言时整棵重建，文字立即全部换过来（当前在哪一页不受影响）
        .id(settings.value.language)
    }

    @ViewBuilder
    private func pageView(_ current: SettingsPage) -> some View {
        switch current {
        case .session: SessionPage(session: session, skills: skills, page: $page)
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
        case .session: "会话"
        case .skills: "技能"
        case .listen: "听写"
        case .translation: "翻译"
        case .screenshot: "截屏回复"
        case .services: "模型与服务"
        case .appearance: "外观"
        case .shortcuts: "快捷键"
        case .permissions: "权限与关于"
        }
    }

    var subtitle: String {
        switch self {
        case .session: "这场会议的背景、关键词、技能和说话人。回复时都会带上。"
        case .skills: "写给大模型的做法说明，决定回复的语气和套路。"
        case .listen: "听哪些声音，怎么把声音变成文字。"
        case .translation: "每句话下面显示译文，悬浮窗顶部一键开关。"
        case .screenshot: "截下最前面的 App 或整个屏幕，读懂内容，写好能直接粘贴的回复。"
        case .services: "服务商只配一次，回复、看图、翻译、语音识别都从这里选。"
        case .appearance: "主题、透明度和字号。下面是实时预览。"
        case .shortcuts: "会议软件在前台时也能用。"
        case .permissions: "Tyto 用到的系统权限，以及数据放在哪。"
        }
    }

    var symbol: String {
        switch self {
        case .session: "person.2.wave.2.fill"
        case .skills: "wand.and.sparkles"
        case .listen: "waveform"
        case .translation: "character.bubble.fill"
        case .screenshot: "camera.viewfinder"
        case .services: "square.stack.3d.up.fill"
        case .appearance: "paintpalette.fill"
        case .shortcuts: "command"
        case .permissions: "lock.shield.fill"
        }
    }

    var colors: [Color] {
        switch self {
        case .session: [Color(red: 0.30, green: 0.62, blue: 1.0), Color(red: 0.16, green: 0.40, blue: 0.95)]
        case .skills: [Color(red: 0.78, green: 0.50, blue: 1.0), Color(red: 0.55, green: 0.30, blue: 0.95)]
        case .listen: [Color(red: 1.0, green: 0.42, blue: 0.55), Color(red: 0.92, green: 0.22, blue: 0.40)]
        case .translation: [Color(red: 0.32, green: 0.85, blue: 0.55), Color(red: 0.14, green: 0.66, blue: 0.40)]
        case .screenshot: [Color(red: 0.25, green: 0.82, blue: 0.85), Color(red: 0.10, green: 0.58, blue: 0.72)]
        case .services: [Color(red: 0.45, green: 0.50, blue: 1.0), Color(red: 0.30, green: 0.30, blue: 0.85)]
        case .appearance: [Color(red: 1.0, green: 0.55, blue: 0.75), Color(red: 0.85, green: 0.35, blue: 0.80)]
        case .shortcuts: [Color(red: 0.62, green: 0.64, blue: 0.70), Color(red: 0.42, green: 0.44, blue: 0.50)]
        case .permissions: [Color(red: 0.40, green: 0.75, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 0.90)]
        }
    }

    static let groups: [(title: String, pages: [SettingsPage])] = [
        ("会议", [.session, .skills]),
        ("功能", [.listen, .translation, .screenshot]),
        ("设置", [.services, .appearance, .shortcuts, .permissions]),
    ]
}

// MARK: - 通用部件

/// 系统设置风格的彩色图标块
struct IconTile: View {
    let symbol: String
    let colors: [Color]
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
            Image(systemName: symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 0.5, y: 0.5)
        }
        .frame(width: size, height: size)
    }
}

private struct PageHeader: View {
    let page: SettingsPage

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: page.symbol, colors: page.colors, size: 44)
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
    var tint: Color = .accentColor
    let title: String
    var detail: String?
    @ViewBuilder let content: Content

    var body: some View {
        LabeledContent {
            content
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tint)
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
                    .foregroundStyle(selected ? Color.white : Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(selected ? Color.accentColor : Color.accentColor.opacity(0.12)))
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
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(hovered ? 0.06 : 0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
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
    @ObservedObject var skills: SkillStore
    @Binding var page: SettingsPage?

    var body: some View {
        Form {
            Section {
                Row(symbol: "textformat", tint: .blue, title: "会议名称") {
                    TextField("", text: $session.title, prompt: Text("新会议")).frame(maxWidth: 280)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Label { Text("背景") } icon: {
                        Image(systemName: "doc.text").foregroundStyle(.blue)
                    }
                    TextEditor(text: $session.context)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 120)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                        .overlay(alignment: .topLeading) {
                            if session.context.isEmpty {
                                Text("会议目的和议程；参会的人、他们的角色和关心的事；我的角色和立场；要用到的术语、数字、日期。")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(13)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                Row(symbol: "highlighter", tint: .pink, title: "关键词", detail: "字幕里高亮，逗号分隔。数字、日期、人名会自动高亮。") {
                    TextField("", text: $session.keywords, prompt: Text("launch, budget, 上线")).frame(maxWidth: 280)
                }
            } header: {
                Text("这场会议")
            }

            Section {
                ForEach(skills.skills) { skill in
                    Toggle(isOn: Binding(
                        get: { session.activeSkillIDs.contains(skill.id) },
                        set: { on in
                            if on { session.activeSkillIDs.insert(skill.id) } else { session.activeSkillIDs.remove(skill.id) }
                        })) {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkle").foregroundStyle(.purple).frame(width: 20)
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
                    Text("用到的技能")
                    Spacer()
                    Button("编辑技能") { page = .skills }.buttonStyle(.link).font(.caption)
                }
            }

            Section {
                if session.knownSpeakers.isEmpty {
                    Label("开始听以后，出现的说话人会列在这里", systemImage: "person.crop.circle.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                ForEach(session.knownSpeakers, id: \.key) { speaker in
                    Row(symbol: speaker.key.hasPrefix("local") ? "mic.circle.fill" : "person.wave.2.fill",
                        tint: speaker.key.hasPrefix("local") ? .green : .blue, title: speaker.label) {
                        TextField("", text: Binding(
                            get: { session.speakerNames[speaker.key] ?? "" },
                            set: { session.rename(speaker.key, to: $0) }),
                                  prompt: Text("名字，比如：我、Alice"))
                            .frame(maxWidth: 220)
                    }
                }
            } header: {
                Text("说话人")
            }

            Section {
                HStack(spacing: 10) {
                    Button {
                        session.toggle()
                    } label: {
                        Label(session.isRunning ? "停止听" : "开始听",
                              systemImage: session.isRunning ? "stop.circle.fill" : "record.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(session.isStarting)
                    Button(action: export) { Label("导出记录", systemImage: "square.and.arrow.up") }
                        .disabled(session.rows.isEmpty)
                    Spacer()
                    Button { Task { await session.newSession() } } label: {
                        Label("开始新会议", systemImage: "plus.bubble")
                    }
                    .help("当前记录存档后清空；背景、关键词和技能保留")
                }
            } footer: {
                Text("记录自动保存在 ~/Library/Application Support/Tyto/sessions/").font(.caption).foregroundStyle(.secondary)
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
                    Label { Text(skill.name) } icon: { Image(systemName: "sparkle").foregroundStyle(.purple) }
                        .tag(skill.id)
                }
                .listStyle(.inset)
                Divider()
                HStack(spacing: 4) {
                    Button { selectedID = skills.create().id } label: { Image(systemName: "plus") }
                        .help("新建技能")
                    Button {
                        if let draft {
                            skills.delete(draft)
                            selectedID = nil
                        }
                    } label: { Image(systemName: "minus") }
                        .disabled(draft == nil)
                        .help("删除")
                    Spacer()
                    Button(action: skills.openFolder) { Image(systemName: "folder") }.help("在 Finder 中打开技能文件夹")
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            if let binding = Binding($draft) {
                Form {
                    Row(symbol: "textformat", tint: .purple, title: "名称") {
                        TextField("", text: binding.name).frame(maxWidth: 260)
                    }
                    Row(symbol: "questionmark.bubble", tint: .purple, title: "什么时候用") {
                        TextField("", text: binding.description).frame(maxWidth: 260)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text("做法说明（Markdown，原样交给大模型）") } icon: {
                            Image(systemName: "text.alignleft").foregroundStyle(.purple)
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
                        Button { if let draft { skills.save(draft) } } label: { Label("保存", systemImage: "checkmark") }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(draft == skills.skills.first { $0.id == draft?.id })
                    }
                }
                .formStyle(.grouped)
            } else {
                ContentUnavailableView("选一个技能", systemImage: "wand.and.sparkles",
                                       description: Text("左边选一个编辑，或者点 + 新建"))
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
                Row(symbol: "person.wave.2.fill", tint: .blue, title: "远端", detail: "会议软件里对方的声音（录系统声音）") {
                    Toggle("", isOn: $settings.value.captureRemote).labelsHidden()
                }
                Row(symbol: "mic.fill", tint: .green, title: "本地", detail: "麦克风收到的声音：你和会议室里的人") {
                    Toggle("", isOn: $settings.value.captureLocal).labelsHidden()
                }
                Row(symbol: "mic.badge.plus", tint: .green, title: "麦克风", detail: "自动：跟系统默认走，跳过 BlackHole 这类虚拟声卡") {
                    Picker("", selection: $settings.value.localInputDeviceUID) {
                        Text("自动").tag("")
                        ForEach(inputDevices) { device in
                            Text(device.isVirtual ? "\(device.name)（虚拟声卡）" : device.name).tag(device.uid)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 240)
                }
                Row(symbol: "ear.and.waveform", tint: .orange, title: "去掉回声", detail: "外放开会时，麦克风收到的对方声音不重复显示") {
                    Toggle("", isOn: $settings.value.echoCancellation).labelsHidden()
                }
            } header: {
                Text("听哪些声音")
            }

            Section {
                SpeechMethodCards(settings: settings)
            } header: {
                Text("怎么把声音变成文字")
            }

            Section {
                SpeechDetails(settings: settings)
            } header: {
                Text(settings.value.speechMethod == .apple ? "语言" : "服务")
            } footer: {
                Text("改了以后停止再开始听才生效。").font(.caption).foregroundStyle(.secondary)
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
            Row(symbol: "server.rack", tint: .indigo, title: "服务商和模型") {
                ModelPicker(settings: settings, slot: $settings.value.speechSlot, capability: capability)
            }
            Row(symbol: "globe", tint: .blue, title: "可能出现的语言", detail: "逗号分隔，如 en,zh；只填一种识别更准") {
                TextField("", text: $settings.value.speechLanguageHints).frame(maxWidth: 200)
            }
        } else {
            Row(symbol: "person.wave.2.fill", tint: .blue, title: "远端说的语言") {
                LanguageField(code: $settings.value.remoteLocale, choices: Languages.speechChoices)
            }
            Row(symbol: "mic.fill", tint: .green, title: "本地说的语言") {
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
                    Label("还没有服务商，点右上角「添加」", systemImage: "tray").foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("服务商")
                    Spacer()
                    AddProviderMenu { add($0) }
                }
            } footer: {
                Text("每个服务商只要配一次（地址、key），下面各个用途从里面选。key 存在钥匙串里。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Row(symbol: "text.bubble.fill", tint: .blue, title: "回复", detail: "会议回复、截屏回复") {
                    VStack(alignment: .trailing, spacing: 6) {
                        ModelPicker(settings: settings, slot: $settings.value.replySlot, capability: .chat)
                        Picker("", selection: $settings.value.replySlot.effort) {
                            Text("思考：低").tag("low")
                            Text("中").tag("medium")
                            Text("高").tag("high")
                            Text("不传").tag("")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 300)
                    }
                }
                Row(symbol: "eye.fill", tint: .teal, title: "看图", detail: "截屏回复选「先用看图模型读图」时用") {
                    ModelPicker(settings: settings, slot: $settings.value.visionSlot, capability: .vision)
                }
                Row(symbol: "character.bubble.fill", tint: .green, title: "翻译", detail: "翻译方式选「大模型翻译」时用") {
                    ModelPicker(settings: settings, slot: $settings.value.translationSlot, capability: .chat, sameAsReply: true)
                }
                Row(symbol: "waveform", tint: .pink, title: "语音识别", detail: settings.value.speechMethod.title) {
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
                Text("各个用途")
            } footer: {
                Text("每一行左边选服务商，右边选模型；点 ⌄ 从服务商读模型列表，也可以直接输入。").font(.caption).foregroundStyle(.secondary)
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
            Section("大模型") {
                ForEach(["anthropic", "openai", "openrouter", "gemini", "deepseek", "dashscope", "siliconflow", "groq"], id: \.self) { item($0) }
            }
            Section("本机") { ForEach(["ollama", "lmstudio"], id: \.self) { item($0) } }
            Section("语音识别") { ForEach(["soniox", "deepgram"], id: \.self) { item($0) } }
            Section { item("custom") }
        } label: {
            Label("添加", systemImage: "plus.circle.fill")
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
                        Text(provider.name).font(.system(size: 13, weight: .semibold))
                        Text(provider.info.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if !provider.needsKey {
                        StatusPill(text: "本机", color: .blue, symbol: "desktopcomputer")
                    } else if provider.key != nil {
                        StatusPill(text: "已填 key", color: .green, symbol: "checkmark")
                    } else {
                        StatusPill(text: "缺 key", color: .orange, symbol: "key")
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
                    Row(symbol: "tag", tint: .gray, title: "名字") {
                        TextField("", text: $provider.name).frame(maxWidth: 280)
                    }
                    Row(symbol: "link", tint: .blue, title: "接口地址") {
                        TextField("", text: $provider.baseURL, prompt: Text(provider.info.baseURL)).frame(maxWidth: 280)
                    }
                    if provider.needsKey {
                        Row(symbol: "key.fill", tint: .orange, title: "API key") {
                            HStack(spacing: 6) {
                                SecureField("", text: $key).frame(maxWidth: 220)
                                    .onChange(of: key) { provider.setKey(key) }
                                if let page = provider.info.keyPage, let url = URL(string: page) {
                                    Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("去拿 key")
                                }
                            }
                        }
                    }
                    HStack(spacing: 10) {
                        Button(role: .destructive, action: remove) { Label("删除", systemImage: "trash") }
                        Spacer()
                        if testing { ProgressView().controlSize(.small) }
                        if let test { Text(test).font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled) }
                        Button(action: runTest) { Label("测试连接", systemImage: "bolt.horizontal.circle") }.disabled(testing)
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
                test = provider.key == nil ? "还没填 key" : "key 已保存，开始听时连接"
                return
            }
            do {
                let models = try await ModelList.fetch(provider)
                test = "通了，有 \(models.count) 个模型"
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
                if sameAsReply { Text("跟回复一样").tag("") }
                if !sameAsReply && !usable.contains(where: { $0.id == slot.providerID }) {
                    Text(slot.providerID.isEmpty ? "选服务商" : "（已删除）").tag(slot.providerID)
                }
                ForEach(usable) { provider in
                    Label(provider.name, systemImage: provider.info.symbol).tag(provider.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)
            if !slot.providerID.isEmpty {
                TextField("", text: $slot.model, prompt: Text("模型")).frame(width: 170)
                Menu {
                    ForEach(choices, id: \.self) { model in Button(model) { slot.model = model } }
                    Divider()
                    Button(loading ? "读取中…" : "从服务商读取列表", action: load).disabled(loading)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("推荐的模型，或者从服务商读取")
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
    static let speechChoices: [(code: String, name: String)] = [
        ("en-US", "英语（美国）"), ("en-GB", "英语（英国）"), ("en-IN", "英语（印度）"), ("zh-CN", "中文（普通话）"),
        ("zh-TW", "中文（台湾）"), ("ja-JP", "日语"), ("ko-KR", "韩语"), ("de-DE", "德语"), ("fr-FR", "法语"),
        ("es-ES", "西班牙语"),
    ]
    static let translationChoices: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"), ("zh-Hant", "繁體中文"), ("en", "英语"), ("ja", "日语"), ("ko", "韩语"),
        ("de", "德语"), ("fr", "法语"), ("es", "西班牙语"),
    ]
}

// MARK: - 翻译

private struct TranslationPage: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var session: SessionModel

    var body: some View {
        Form {
            Section {
                Row(symbol: "character.bubble.fill", tint: .green, title: "显示译文") {
                    Toggle("", isOn: Binding(get: { settings.value.translationEnabled },
                                             set: { settings.value.translationEnabled = $0; session.translationToggled() }))
                        .labelsHidden()
                }
                Row(symbol: "arrow.right.circle.fill", tint: .green, title: "译成") {
                    LanguageField(code: $settings.value.targetLanguage, choices: Languages.translationChoices)
                }
            }
            Section {
                OptionCard(symbol: "apple.logo", title: "Apple 本机翻译", detail: "免费、不联网、快。第一次要下载语言包。",
                           selected: settings.value.translationProvider == .apple) { settings.value.translationProvider = .apple }
                OptionCard(symbol: "sparkles", title: "大模型翻译", detail: "更懂上下文和术语。默认用回复的模型，也可以单独选。",
                           selected: settings.value.translationProvider == .llm) { settings.value.translationProvider = .llm }
            } header: {
                Text("翻译方式")
            }
            Section {
                if settings.value.translationProvider == .apple {
                    TranslationDownload(source: settings.value.remoteLocale, target: settings.value.targetLanguage)
                    if settings.value.localLocale != settings.value.remoteLocale {
                        TranslationDownload(source: settings.value.localLocale, target: settings.value.targetLanguage)
                    }
                } else {
                    Row(symbol: "server.rack", tint: .indigo, title: "翻译用的模型") {
                        ModelPicker(settings: settings, slot: $settings.value.translationSlot, capability: .chat, sameAsReply: true)
                    }
                }
            } header: {
                Text(settings.value.translationProvider == .apple ? "语言包" : "模型")
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
        Row(symbol: "arrow.down.circle.fill", tint: .green,
            title: "\(Languages.name(source)) → \(Languages.name(target))", detail: message.isEmpty ? nil : message) {
            if installed == true {
                StatusPill(text: "已就绪", color: .green, symbol: "checkmark")
            } else {
                Button("下载") {
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
            message = status == .unsupported ? "不支持这对语言" : ""
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
                Text("⌃⌥S 截哪里")
            } footer: {
                Text("最前面的 App：按快捷键时你正在用的那个窗口（比如 Teams），Tyto 会认出是哪个 App。⌃⌥A 总是框选。截图要「屏幕录制」权限。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(AppSettings.ScreenshotMode.allCases) { mode in
                    OptionCard(symbol: mode.symbol, title: mode.title, detail: mode.detail,
                               selected: settings.value.screenshotMode == mode) { settings.value.screenshotMode = mode }
                }
                if settings.value.screenshotMode == .visionModel {
                    Row(symbol: "eye.fill", tint: .teal, title: "看图模型") {
                        ModelPicker(settings: settings, slot: $settings.value.visionSlot, capability: .vision)
                    }
                }
            } header: {
                Text("怎么读懂截图")
            }

            Section {
                OllamaCatalog(settings: settings)
            } header: {
                Text("文字识别和本机看图模型")
            } footer: {
                Text("系统自带的文字识别不用下载，最小最快。想让截图不出这台 Mac 又能看懂版面，就下载一个本机看图模型（通过 Ollama），点「用这个」。这几个模型 16 GB 内存的笔记本也跑得动。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Row(symbol: "doc.on.clipboard.fill", tint: .teal, title: "自动复制第一个回复", detail: "生成好后直接 ⌘V 粘贴发送") {
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
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .frame(height: 30)
                Text(target.title).font(.system(size: 12, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.1) : Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 1.5 : 1))
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
                IconTile(symbol: "text.viewfinder", colors: [Color(red: 0.55, green: 0.58, blue: 0.65), Color(red: 0.35, green: 0.37, blue: 0.45)], size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("系统文字识别（Apple Vision）").font(.system(size: 13, weight: .semibold))
                    Text("系统自带，不用下载；中英日文；聊天截图约 0.3 秒，整个 5K 屏约 0.6 秒").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(text: "已就绪", color: .green, symbol: "checkmark")
            }

            HStack(spacing: 12) {
                IconTile(symbol: "shippingbox.fill", colors: [Color(red: 0.25, green: 0.25, blue: 0.28), Color(red: 0.08, green: 0.08, blue: 0.10)], size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ollama").font(.system(size: 13, weight: .semibold))
                    Text(version.map { "\($0) 正在运行" } ?? (checked ? "没检测到。装好并打开后点「重新检测」" : "检测中…"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if version == nil, checked {
                    Button("下载 Ollama") { NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!) }
                }
                Button { Task { await refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help("重新检测")
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
            IconTile(symbol: model.symbol, colors: [Color(red: 0.36, green: 0.62, blue: 1.0), Color(red: 0.42, green: 0.36, blue: 0.95)], size: 30)
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
                StatusPill(text: "正在用", color: .accentColor, symbol: "checkmark")
            } else if isInstalled {
                Button("用这个") { use(model.id) }
            } else if downloading[model.id] != nil {
                Text("\(Int((downloading[model.id] ?? 0) * 100))%").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Button { download(model.id) } label: { Label("下载", systemImage: "arrow.down.circle") }
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

    var body: some View {
        Form {
            Section {
                Row(symbol: "globe", tint: .blue, title: "界面语言 · Language") {
                    Picker("", selection: $settings.value.language) {
                        ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
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
                Text("主题")
            }
            Section {
                Row(symbol: "circle.lefthalf.filled", tint: .pink, title: "底色浓度", detail: "最左边完全透明；往右先出现玻璃，再加深底色") {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted").foregroundStyle(.secondary)
                        Slider(value: $settings.value.overlayOpacity, in: 0...0.95).frame(width: 200)
                        Image(systemName: "circle.fill").foregroundStyle(.secondary)
                        Text("\(Int(settings.value.overlayOpacity * 100))%").font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary).frame(width: 34, alignment: .trailing)
                    }
                }
                Row(symbol: "textformat.size", tint: .pink, title: "字号") {
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
                    SampleBackdrop()
                    if let preview {
                        OverlayView(session: preview, settings: settings, ui: OverlayState())
                            .frame(width: 440, height: 470)
                            .allowsHitTesting(false)
                    }
                }
                .frame(height: 510)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } header: {
                Text("预览（背景是模拟的会议画面）")
            }
        }
        .formStyle(.grouped)
        .onAppear { if preview == nil { preview = SampleData.session(settings: settings) } }
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
                        .fill(LinearGradient(colors: [colors.tint.opacity(0.9), colors.tint], startPoint: .top, endPoint: .bottom))
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(colors.accentGradient).frame(width: 46, height: 7)
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
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    Text(theme.label.components(separatedBy: "：").first ?? "").font(.system(size: 12, weight: .semibold))
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 快捷键

private struct ShortcutsPage: View {
    private let items: [(keys: [String], title: String, symbol: String)] = [
        (["⌃", "⌥", "L"], "开始 / 停止听", "record.circle"),
        (["⌃", "⌥", "R"], "回复（选中的句子，或最近的话）", "arrowshape.turn.up.left.fill"),
        (["⌃", "⌥", "S"], "截屏回复（按设置截最前面的 App 或整个屏幕）", "camera.viewfinder"),
        (["⌃", "⌥", "A"], "截屏回复：框选一块", "rectangle.dashed"),
        (["⌃", "⌥", "T"], "显示 / 隐藏悬浮窗", "macwindow"),
        (["⌃", "⌥", "P"], "点击穿透开 / 关", "cursorarrow.motionlines"),
        (["⌃", "⌥", "Q"], "退出 Tyto", "power"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(items, id: \.title) { item in
                    Row(symbol: item.symbol, tint: .gray, title: item.title) {
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
                Row(symbol: "mic.fill", tint: .green, title: "麦克风", detail: "本地那一路") {
                    HStack(spacing: 8) {
                        switch microphone {
                        case .granted: StatusPill(text: "已允许", color: .green, symbol: "checkmark")
                        case .denied: StatusPill(text: "被拒绝", color: .red, symbol: "xmark")
                        default: StatusPill(text: "还没问过", color: .secondary)
                        }
                        Button("打开设置") { Capture.openPrivacySettings("Privacy_Microphone") }
                    }
                }
                Row(symbol: "speaker.wave.2.fill", tint: .blue, title: "系统录音", detail: "远端那一路，第一次开始听时询问") {
                    Button("打开设置") { Capture.openPrivacySettings("Privacy_ScreenCapture") }
                }
                Row(symbol: "camera.viewfinder", tint: .teal, title: "屏幕录制", detail: "截屏回复") {
                    HStack(spacing: 8) {
                        StatusPill(text: screen ? "已允许" : "未允许", color: screen ? .green : .orange,
                                   symbol: screen ? "checkmark" : "exclamationmark")
                        Button("打开设置") { Capture.openPrivacySettings("Privacy_ScreenCapture") }
                    }
                }
            } header: {
                Text("权限")
            } footer: {
                Text("在系统设置里打开权限后，要退出再打开 Tyto 才生效。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                folderRow("会话记录", symbol: "tray.full.fill", url: SessionModel.folder)
                folderRow("技能", symbol: "wand.and.sparkles", url: SkillStore.folder)
                folderRow("运行日志", symbol: "doc.text.magnifyingglass", url: URL.libraryDirectory.appending(path: "Logs/Tyto.log"))
            } header: {
                Text("数据放在哪")
            } footer: {
                Text("设置存在 defaults 的 com.giomni.tyto 里，API key 存在钥匙串（服务名 com.giomni.tyto）。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 14) {
                    IconTile(symbol: "ear.fill", colors: SettingsPage.session.colors, size: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tyto 听译").font(.system(size: 16, weight: .bold))
                        Text("版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")")
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

    private func folderRow(_ title: String, symbol: String, url: URL) -> some View {
        Row(symbol: symbol, tint: .blue, title: title, detail: url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")) {
            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
}
