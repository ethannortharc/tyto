import SwiftUI
@preconcurrency import Translation
import UniformTypeIdentifiers

/// "会话与设置"窗口
struct MainView: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var skills: SkillStore

    var body: some View {
        TabView {
            SessionTab(session: session, skills: skills)
                .tabItem { Label("会话", systemImage: "person.2.wave.2") }
            SkillsTab(skills: skills)
                .tabItem { Label("技能", systemImage: "list.bullet.rectangle") }
            ModelsTab(settings: settings, session: session)
                .tabItem { Label("模型与服务", systemImage: "cpu") }
        }
        .frame(minWidth: 640, minHeight: 560)
    }
}

// MARK: - 会话

private struct SessionTab: View {
    @ObservedObject var session: SessionModel
    @ObservedObject var skills: SkillStore

    var body: some View {
        Form {
            Section("这场会议") {
                TextField("会议名称", text: $session.title)
                VStack(alignment: .leading, spacing: 4) {
                    Text("背景（生成回复时会带上）").font(.callout)
                    TextEditor(text: $session.context)
                        .font(.body)
                        .frame(minHeight: 140)
                        .overlay(alignment: .topLeading) {
                            if session.context.isEmpty {
                                Text("比如：会议目的和议程；参会的人、他们的角色和关心的事；我的角色和立场；要用到的术语、数字、日期。")
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 1)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            Section {
                ForEach(skills.skills) { skill in
                    Toggle(isOn: Binding(
                        get: { session.activeSkillIDs.contains(skill.id) },
                        set: { on in
                            if on { session.activeSkillIDs.insert(skill.id) } else { session.activeSkillIDs.remove(skill.id) }
                        })) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(skill.name)
                            if !skill.description.isEmpty {
                                Text(skill.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("这场会议用的技能")
            } footer: {
                Text("技能是写给大模型的做法说明，在「技能」页编辑。").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if session.knownSpeakers.isEmpty {
                    Text("开始听以后，出现的说话人会列在这里。").foregroundStyle(.secondary)
                }
                ForEach(session.knownSpeakers, id: \.key) { speaker in
                    TextField(speaker.label, text: Binding(
                        get: { session.speakerNames[speaker.key] ?? "" },
                        set: { session.rename(speaker.key, to: $0) }),
                        prompt: Text("名字，比如：我、Alice"))
                }
            } header: {
                Text("说话人")
            } footer: {
                Text("远端是会议软件里的声音，本地是麦克风。用云端识别时同一路里还会分出说话人 1、2……；在悬浮窗里点说话人标签也能改名。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button(session.isRunning ? "停止听" : "开始听", action: session.toggle)
                        .disabled(session.isStarting)
                    Button("导出记录（Markdown）…", action: export)
                        .disabled(session.rows.isEmpty)
                    Spacer()
                    Button("开始新会议") { Task { await session.newSession() } }
                        .help("当前记录存档后清空；背景和技能保留")
                }
            } footer: {
                Text("记录自动保存在 ~/Library/Application Support/Tyto/sessions/。").font(.caption).foregroundStyle(.secondary)
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

private struct SkillsTab: View {
    @ObservedObject var skills: SkillStore
    @State private var selectedID: String?
    @State private var draft: Skill?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(skills.skills, selection: $selectedID) { skill in
                    Text(skill.name).tag(skill.id)
                }
                HStack {
                    Button { selectedID = skills.create().id } label: { Image(systemName: "plus") }
                    Button { if let draft { skills.delete(draft); selectedID = nil } } label: { Image(systemName: "minus") }
                        .disabled(draft == nil)
                    Spacer()
                    Button("打开文件夹", action: skills.openFolder)
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(width: 200)
            Divider()
            if let binding = Binding($draft) {
                Form {
                    TextField("名称", text: binding.name)
                    TextField("什么时候用", text: binding.description)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("做法说明（Markdown，原样交给大模型）").font(.callout)
                        TextEditor(text: binding.body).font(.body.monospaced()).frame(minHeight: 260)
                    }
                    HStack {
                        Spacer()
                        Button("保存") { if let draft { skills.save(draft) } }
                            .keyboardShortcut("s", modifiers: .command)
                            .disabled(draft == skills.skills.first { $0.id == draft?.id })
                    }
                }
                .formStyle(.grouped)
            } else {
                Text("选一个技能编辑，或者点 + 新建。").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onChange(of: selectedID) { draft = skills.skills.first { $0.id == selectedID } }
    }
}

// MARK: - 模型与服务

private struct ModelsTab: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var session: SessionModel
    @State private var sonioxKey = Keychain.get("soniox") ?? ""
    @State private var llmKey = ""
    @State private var testResult = ""
    @State private var inputDevices: [InputDevice] = []
    @State private var testing = false

    var body: some View {
        Form {
            Section {
                Picker("识别服务", selection: $settings.value.speechProvider) {
                    ForEach(AppSettings.SpeechProvider.allCases) { Text($0.label).tag($0) }
                }
                switch settings.value.speechProvider {
                case .apple:
                    TextField("远端说的语言", text: $settings.value.remoteLocale)
                    TextField("本地说的语言", text: $settings.value.localLocale)
                    Text("语言代码，如 en-US 英语、zh-CN 中文、ja-JP 日语。本机识别一路只认一种语言。")
                        .font(.caption).foregroundStyle(.secondary)
                case .soniox:
                    SecureField("Soniox API key", text: $sonioxKey)
                        .onChange(of: sonioxKey) { Keychain.set(sonioxKey, for: "soniox") }
                    TextField("可能出现的语言（逗号分隔）", text: $settings.value.sonioxLanguageHints)
                    TextField("模型", text: $settings.value.sonioxModel)
                }
            } header: {
                Text("语音识别")
            }

            Section {
                Toggle("远端：会议软件里的声音（录系统声音）", isOn: $settings.value.captureRemote)
                Toggle("本地：麦克风（会议室里的人和你）", isOn: $settings.value.captureLocal)
                Picker("本地用的麦克风", selection: $settings.value.localInputDeviceUID) {
                    Text("自动（系统默认，避开 BlackHole 这类虚拟声卡）").tag("")
                    ForEach(inputDevices) { device in
                        Text(device.isVirtual ? "\(device.name)（虚拟声卡）" : device.name).tag(device.uid)
                    }
                }
                .onAppear { inputDevices = InputDevices.all() }
                Toggle("去掉回声：本地收到的远端声音不重复显示（用外放开会时打开）", isOn: $settings.value.echoCancellation)
            } header: {
                Text("声音来源")
            } footer: {
                Text("改了识别服务或声音来源，停止再开始听才生效。").font(.caption).foregroundStyle(.secondary)
            }

            Section("翻译") {
                Toggle("显示译文", isOn: $settings.value.translationEnabled)
                Picker("翻译方式", selection: $settings.value.translationProvider) {
                    ForEach(AppSettings.TranslationProvider.allCases) { Text($0.label).tag($0) }
                }
                TextField("译成", text: $settings.value.targetLanguage)
                Text("语言代码：zh-Hans 简体中文、zh-Hant 繁体中文、en 英语、ja 日语。")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.value.translationProvider == .apple {
                    TranslationDownload(source: settings.value.remoteLocale, target: settings.value.targetLanguage)
                    if settings.value.localLocale != settings.value.remoteLocale {
                        TranslationDownload(source: settings.value.localLocale, target: settings.value.targetLanguage)
                    }
                } else {
                    TextField("翻译用的模型（留空和回复用同一个）", text: $settings.value.translationModel)
                }
            }

            Section {
                Picker("接口", selection: Binding(
                    get: { settings.value.llm.provider },
                    set: { provider in
                        settings.value.llm.provider = provider
                        settings.value.llm.baseURL = provider.defaultBaseURL
                        llmKey = Keychain.get(provider.keychainAccount) ?? ""
                    })) {
                    ForEach(LLMConfig.Provider.allCases) { Text($0.label).tag($0) }
                }
                TextField("接口地址", text: $settings.value.llm.baseURL)
                TextField("模型", text: $settings.value.llm.model)
                TextField("思考深度（low / medium / high，留空不传）", text: $settings.value.llm.effort)
                SecureField("API key", text: $llmKey)
                    .onChange(of: llmKey) { Keychain.set(llmKey, for: settings.value.llm.provider.keychainAccount) }
                HStack {
                    Button(testing ? "测试中…" : "测试连接", action: test).disabled(testing)
                    Text(testResult).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } header: {
                Text("大模型（回复建议）")
            } footer: {
                Text("模型之后再定。思考深度越高回复越好，但越慢；开会时 low 比较合适。").font(.caption).foregroundStyle(.secondary)
            }

            Section("回复") {
                TextField("解释对方意思用的语言", text: $settings.value.explainLanguage)
                TextField("建议回复用的语言（留空跟对方一致）", text: $settings.value.replyLanguage)
                Toggle("对方问问题时自动生成回复", isOn: $settings.value.autoReplyOnQuestion)
            }

            Section {
                LabeledContent("背景深浅") {
                    Slider(value: $settings.value.overlayOpacity, in: 0.3...0.98)
                }
                Stepper("字号 \(Int(settings.value.fontSize))", value: $settings.value.fontSize, in: 10...24)
            } header: {
                Text("悬浮窗")
            } footer: {
                Text("快捷键：⌃⌥T 显示/隐藏悬浮窗，⌃⌥R 回复（选中的句子或最近的话），⌃⌥P 点击穿透，⌃⌥L 开始/停止听。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { llmKey = Keychain.get(settings.value.llm.provider.keychainAccount) ?? "" }
    }

    private func test() {
        testing = true
        testResult = ""
        let config = settings.value.llm
        Task {
            defer { testing = false }
            do {
                let client = try LLMFactory.make(config)
                let answer = try await client.complete(system: "只回答一个词。", user: "说「好」", maxTokens: 2_000)
                testResult = "通了：\(answer.prefix(40))"
            } catch {
                testResult = error.localizedDescription
            }
        }
    }
}

/// 下载 Apple 本机翻译的语言包（系统会弹出下载确认）
private struct TranslationDownload: View {
    let source: String
    let target: String
    @State private var configuration: TranslationSession.Configuration?
    @State private var status = ""

    var body: some View {
        HStack {
            Button("下载本机翻译语言：\(Languages.name(source)) → \(Languages.name(target))") {
                if configuration == nil {
                    configuration = .init(source: Locale.Language(identifier: source), target: Locale.Language(identifier: target))
                } else {
                    configuration?.invalidate()
                }
            }
            Text(status).font(.caption).foregroundStyle(.secondary)
        }
        .translationTask(configuration) { session in
            do {
                try await session.prepareTranslation()
                status = "已就绪"
            } catch {
                status = error.localizedDescription
            }
        }
        .task(id: "\(source)>\(target)") {
            let state = await LanguageAvailability().status(from: Locale.Language(identifier: source),
                                                            to: Locale.Language(identifier: target))
            status = switch state {
            case .installed: "已就绪"
            case .supported: "还没下载"
            case .unsupported: "不支持这对语言"
            @unknown default: ""
            }
        }
    }
}
