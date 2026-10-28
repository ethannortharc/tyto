import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let settings = SettingsStore()
    private lazy var skills = SkillStore()
    private lazy var session = SessionModel(settings: settings, skills: skills)
    private lazy var records = MeetingRecords()
    private let overlayState = OverlayState()
    private var overlay: OverlayPanel?
    private var backdropProbe: BackdropProbe?
    private var sidecar: SidecarPanel?
    private lazy var prompter = PrompterModel(settings: settings, session: session)
    private var prompterPanel: PrompterPanel?
    private var prompterProbe: BackdropProbe?
    /// 提词器开着时才要的快捷键（上一节、下一节、跳到对方提到的那节）
    private var prompterKeys: [UInt32] = []
    private var lastReplyCount = 0
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private var updater: Updater?
    /// 会话载入了没有。没载入就退出（自测、移到「应用程序」后重开）时不存会话，免得把真实记录盖成空的
    private var sessionLoaded = false
    private var subscriptions: Set<AnyCancellable> = []
    private var optionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested(settings: settings) { return }
        SharingGuard.install()
        // 从下载文件夹、磁盘映像里打开的：先问要不要移到「应用程序」（移了就从那里重开，这一份直接退出）
        Installer.offerMoveToApplications()

        updater = Updater()
        applyDockPolicy()
        setupMainMenu()
        session.load()
        sessionLoaded = true

        let actions = OverlayActions(
            openMain: { [weak self] in self?.openMainWindow() },
            hide: { [weak self] in self?.toggleOverlay() },
            quit: { NSApp.terminate(nil) },
            resetSize: { [weak self] in
                guard let self else { return }
                overlay?.resetFrame(captionLines: settings.value.captionLines, fontSize: settings.value.fontSize)
            },
            openTranslation: { [weak self] in self?.openMainWindow(page: .translation) },
            openRecords: { [weak self] in self?.openMainWindow(page: .records) })
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: overlayState,
                                                       actions: actions))
        overlay = panel
        setupLayout(panel)
        panel.orderFrontRegardless()
        backdropProbe = BackdropProbe(panel: panel, settings: settings, state: overlayState)
        backdropProbe?.start()
        setupSidecar(beside: panel)
        setupPrompter()
        overlayState.$clickThrough
            .sink { [weak self] _ in self?.updateClickThrough() }
            .store(in: &subscriptions)
        watchOptionKey()

        setupStatusItem()
        registerHotKeys()
        updateIconsWhileListening()
        settings.$value.map(\.showInDock).removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyDockPolicy(refocus: true) } }
            .store(in: &subscriptions)
        settings.$value.map(\.language).removeDuplicates().dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.setupMainMenu() } }
            .store(in: &subscriptions)

        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            openMainWindow()
        }
        // --start：启动后直接开始听（自测和开机自启用）
        if CommandLine.arguments.contains("--start") { session.toggle() }
    }

    /// 点程序坞图标（或再次打开 Tyto）：悬浮窗收起来了就把它放回来，否则打开设置窗口
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if overlay?.isVisible == false {
            toggleOverlay()
        } else if mainWindow?.isVisible != true || mainWindow?.isMiniaturized == true {
            openMainWindow()
        }
        return true
    }

    /// 右键程序坞图标
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(item(session.isRunning ? tr("停止听", "Stop Listening") : tr("开始听", "Start Listening"),
                          "waveform", #selector(toggleListening)))
        menu.addItem(item(overlay?.isVisible == true ? tr("隐藏悬浮窗", "Hide Overlay") : tr("显示悬浮窗", "Show Overlay"),
                          "macwindow", #selector(toggleOverlayAction)))
        let prompterItem = item(tr("提词器", "Prompter"), "doc.text", #selector(togglePrompterAction))
        prompterItem.state = settings.value.showPrompter ? .on : .off
        menu.addItem(prompterItem)
        return menu
    }

    /// 正在听、且设了听的时候藏图标
    private var iconsHidden: Bool { session.isRunning && settings.value.hideIconsWhileListening }

    /// 在程序坞显示图标（普通 App），或者只在菜单栏（关掉程序坞图标时）
    /// - refocus: 在设置窗口里拨开关时为 true，把被系统藏到后面的设置窗口拉回来；开始听时自动藏图标不抢会议软件的焦点
    private func applyDockPolicy(refocus: Bool = false) {
        let policy: NSApplication.ActivationPolicy = settings.value.showInDock && !iconsHidden ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
        // 从程序坞模式换到只在菜单栏时，系统会把设置窗口藏到后面，拉回来
        if refocus, mainWindow?.isVisible == true {
            DispatchQueue.main.async {
                NSApp.activate()
                self.mainWindow?.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard sessionLoaded else { return .terminateNow }
        guard session.isRunning else {
            session.save()
            return .terminateNow
        }
        Task {
            await session.stop()
            session.save()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    // MARK: - 窗口

    private func openMainWindow(page: SettingsPage? = nil) {
        if let page, let window = mainWindow {
            // 窗口里当前是哪一页是 MainView 自己的状态，要跳到指定的页就整个换掉
            window.contentView = NSHostingView(rootView: MainView(session: session, settings: settings, skills: skills,
                                                                  records: records, updater: updater, initialPage: page))
        }
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = Self.windowTitle
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            // 会议背景和记录也不能被共享出去
            window.sharingType = .none
            window.contentView = NSHostingView(rootView: MainView(session: session, settings: settings, skills: skills,
                                                                  records: records, updater: updater, initialPage: page ?? .session))
            window.center()
            window.setFrameAutosaveName("TytoMain")
            mainWindow = window
        }
        mainWindow?.title = Self.windowTitle  // 语言可能改过
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
    }

    private static var windowTitle: String { tr("Tyto 听译", "Tyto") }

    /// 悬浮窗的三种大小：设置里换了（菜单、⌃⌥M、展开按钮），或字号、字幕行数变了，窗口跟着变；
    /// 拖字幕条的下边改了行数，记到设置里
    private func setupLayout(_ panel: OverlayPanel) {
        applyLayout()
        settings.$value
            .map { [$0.overlayLayout.rawValue, "\($0.captionLines)", "\($0.fontSize)"] }
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyLayout() } }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSWindow.didEndLiveResizeNotification, object: panel)
            .sink { [weak self] _ in
                guard let self, let overlay, overlay.layout == .captions else { return }
                let lines = CaptionBar.lines(forHeight: overlay.frame.height, fontSize: settings.value.fontSize)
                if settings.value.captionLines != lines { settings.value.captionLines = lines }
            }
            .store(in: &subscriptions)
    }

    private func applyLayout() {
        let current = settings.value
        overlay?.apply(current.overlayLayout, captionLines: current.captionLines, fontSize: current.fontSize)
        placeSidecar()
    }

    private func toggleOverlay() {
        guard let overlay else { return }
        if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() }
        updateSidecar()
    }

    // MARK: - 回复面板

    private func setupSidecar(beside overlay: OverlayPanel) {
        let panel = SidecarPanel(rootView: SidecarView(session: session, settings: settings, ui: overlayState,
                                                       close: { [weak self] in self?.settings.value.showReplyPanel = false }))
        sidecar = panel
        lastReplyCount = session.replies.count
        // 悬浮窗改大小、拖到别处：面板跟着换高度，必要时换到另一边
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.publisher(for: name, object: overlay)
                .sink { [weak self] _ in self?.placeSidecar() }
                .store(in: &subscriptions)
        }
        settings.$value.map(\.showReplyPanel).removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateSidecar() } }
            .store(in: &subscriptions)
        // 生成新回复时自动打开
        session.$replies.map(\.count).removeDuplicates()
            .sink { [weak self] count in
                guard let self else { return }
                if count > lastReplyCount, !settings.value.showReplyPanel { settings.value.showReplyPanel = true }
                lastReplyCount = count
            }
            .store(in: &subscriptions)
    }

    /// 悬浮窗显示、且面板打开时才显示；作为子窗口贴在悬浮窗旁边，拖悬浮窗时一起走
    private func updateSidecar() {
        guard let overlay, let sidecar else { return }
        if overlay.isVisible, settings.value.showReplyPanel {
            placeSidecar()
            if sidecar.parent == nil { overlay.addChildWindow(sidecar, ordered: .above) }
            sidecar.orderFrontRegardless()
        } else {
            if sidecar.parent != nil { overlay.removeChildWindow(sidecar) }
            sidecar.orderOut(nil)
        }
        updateClickThrough()
    }

    private func placeSidecar() {
        guard let overlay, let sidecar, sidecar.isVisible || settings.value.showReplyPanel else { return }
        sidecar.place(beside: overlay, compact: overlay.layout != .full)
    }

    // MARK: - 提词器

    private func setupPrompter() {
        let panel = PrompterPanel(rootView: PrompterView(model: prompter, settings: settings,
                                                         close: { [weak self] in self?.settings.value.showPrompter = false }))
        prompterPanel = panel
        prompterProbe = BackdropProbe(panel: panel, settings: settings, state: prompter)
        prompterProbe?.start()
        prompter.start()
        settings.$value.map(\.showPrompter).removeDuplicates()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updatePrompter() } }
            .store(in: &subscriptions)
    }

    private func updatePrompter() {
        guard let panel = prompterPanel else { return }
        if settings.value.showPrompter {
            if !panel.hasSavedFrame, let overlay { panel.place(beside: overlay, sidecar: sidecar) }
            panel.orderFrontRegardless()
            if prompterKeys.isEmpty {
                let modifiers = controlKey | optionKey
                prompterKeys = [
                    hotKeys.register(keyCode: kVK_UpArrow, modifiers: modifiers) { [weak self] in self?.prompter.step(-1) },
                    hotKeys.register(keyCode: kVK_DownArrow, modifiers: modifiers) { [weak self] in self?.prompter.step(1) },
                    hotKeys.register(keyCode: kVK_ANSI_J, modifiers: modifiers) { [weak self] in self?.prompter.jumpToSuggestion() },
                ]
            }
        } else {
            panel.orderOut(nil)
            prompterKeys.forEach(hotKeys.unregister)
            prompterKeys = []
        }
        updateClickThrough()
    }

    /// 点击穿透时鼠标会穿过悬浮窗，悬浮窗本身就点不了。按住 ⌥ 并把鼠标移到悬浮窗上，临时恢复可点，松开又穿透。
    private func watchOptionKey() {
        optionTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                updateClickThrough()
            }
        }
    }

    private func updateClickThrough() {
        guard let overlay else { return }
        let mouse = NSEvent.mouseLocation
        let over = [overlay, sidecar, prompterPanel].contains { $0?.isVisible == true && $0?.frame.contains(mouse) == true }
        let peeking = overlayState.clickThrough && NSEvent.modifierFlags.contains(.option) && over
        if overlayState.peeking != peeking { overlayState.peeking = peeking }
        let ignores = overlayState.clickThrough && !peeking
        if overlay.ignoresMouseEvents != ignores { overlay.ignoresMouseEvents = ignores }
        for panel in [sidecar, prompterPanel] as [NSPanel?] {
            if let panel, panel.ignoresMouseEvents != ignores { panel.ignoresMouseEvents = ignores }
        }
    }

    /// 「开始听时隐藏程序坞和菜单栏图标」：整屏共享时对方能看到程序坞和菜单栏，听的时候把 Tyto 的两个图标都藏起来
    private func updateIconsWhileListening() {
        Publishers.CombineLatest(session.$isRunning, settings.$value.map(\.hideIconsWhileListening))
            .map { $0 && $1 }
            .removeDuplicates()
            .sink { [weak self] hide in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.statusItem?.isVisible = !hide
                    self.applyDockPolicy()
                }
            }
            .store(in: &subscriptions)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "ear", accessibilityDescription: "Tyto")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// 菜单栏菜单：按"听 → 回复 → 截屏 → 悬浮窗 → 设置 → 退出"排，每项带图标和快捷键
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = session.isRunning
        let current = settings.value
        let status = NSMenuItem(title: running ? tr("正在听", "Listening") : tr("没在听", "Not Listening"),
                                action: nil, keyEquivalent: "")
        status.image = symbol(running ? "record.circle.fill" : "record.circle")
        status.isEnabled = false
        let sources = [current.captureRemote ? tr("远端", "Remote") : nil, current.captureLocal ? tr("本地", "Local") : nil]
            .compactMap { $0 }
        status.subtitle = "\(sources.isEmpty ? tr("没开声音来源", "No audio source") : sources.joined(separator: " + ")) · \(current.speechMethod.title)"
        menu.addItem(status)
        menu.addItem(item(running ? tr("停止听", "Stop Listening") : tr("开始听", "Start Listening"), "waveform",
                          #selector(toggleListening), key: "l"))
        menu.addItem(.separator())

        menu.addItem(item(session.selection.isEmpty
                            ? tr("回复最近的话", "Reply to Latest")
                            : tr("回复选中的 \(session.selection.count) 句", "Reply to \(session.selection.count) Selected"),
                          "arrowshape.turn.up.left.fill", #selector(replyAction), key: "r"))
        let capture = item(tr("截屏回复", "Screenshot Reply"), "camera.viewfinder", nil)
        let submenu = NSMenu()
        for target in AppSettings.CaptureTarget.allCases {
            let key = target == current.captureTarget ? "s" : (target == .region ? "a" : "")
            let entry = item(target.title, target.symbol, #selector(captureAction(_:)), key: key)
            entry.representedObject = target.rawValue
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item(tr("用剪贴板里的图片", "Use Image on Clipboard"), "doc.on.clipboard", #selector(clipboardImageAction)))
        capture.submenu = submenu
        menu.addItem(capture)
        menu.addItem(.separator())

        menu.addItem(item(overlay?.isVisible == true ? tr("隐藏悬浮窗", "Hide Overlay") : tr("显示悬浮窗", "Show Overlay"),
                          "macwindow", #selector(toggleOverlayAction), key: "t"))
        menu.addItem(layoutMenuItem())
        let translation = item(tr("显示译文", "Show Translation"), "character.bubble", #selector(toggleTranslation))
        translation.state = current.translationEnabled ? .on : .off
        menu.addItem(translation)
        let replies = item(tr("回复面板", "Replies Panel"), "sidebar.left", #selector(toggleSidecarAction), key: "b")
        replies.state = current.showReplyPanel ? .on : .off
        menu.addItem(replies)
        let prompterItem = item(tr("提词器", "Prompter"), "doc.text", #selector(togglePrompterAction), key: "n")
        prompterItem.state = current.showPrompter ? .on : .off
        menu.addItem(prompterItem)
        let clickThrough = item(tr("点击穿透", "Click-Through"), "cursorarrow.motionlines", #selector(toggleClickThrough), key: "p")
        clickThrough.state = overlayState.clickThrough ? .on : .off
        menu.addItem(clickThrough)
        menu.addItem(.separator())

        let recordsItem = item(tr("会议记录", "Meeting Records"), "archivebox", nil)
        let recordsMenu = NSMenu()
        recordsMenu.autoenablesItems = false
        let save = item(session.recordFile == nil ? tr("保存到会议记录", "Save to Meeting Records") : tr("已在会议记录里，自动保存", "In Meeting Records, saved automatically"),
                        session.recordFile == nil ? "tray.and.arrow.down" : "checkmark.circle", #selector(saveRecordAction))
        save.isEnabled = !session.isEmpty && session.recordFile == nil
        recordsMenu.addItem(save)
        let clear = item(tr("清空，开始新会议", "Clear, New Meeting"), "plus.bubble", #selector(clearSessionAction))
        clear.isEnabled = !session.isEmpty
        recordsMenu.addItem(clear)
        let export = item(tr("导出记录…", "Export Transcript…"), "square.and.arrow.up", #selector(exportSessionAction))
        export.isEnabled = !session.isEmpty
        recordsMenu.addItem(export)
        recordsMenu.addItem(.separator())
        recordsMenu.addItem(item(tr("查看会议记录…", "Show Meeting Records…"), "archivebox", #selector(openRecordsAction)))
        recordsItem.submenu = recordsMenu
        menu.addItem(recordsItem)
        menu.addItem(.separator())

        let settingsItem = item(tr("会话与设置…", "Session & Settings…"), "gearshape", #selector(openMainAction))
        settingsItem.keyEquivalent = ","
        settingsItem.keyEquivalentModifierMask = [.command]
        menu.addItem(settingsItem)
        let languageItem = item("语言 · Language", "globe", nil)
        let languages = NSMenu()
        for language in AppLanguage.allCases {
            let entry = item(language.label, language == .system ? "gearshape.2" : "character", #selector(languageAction(_:)))
            entry.representedObject = language.rawValue
            entry.state = current.language == language ? .on : .off
            languages.addItem(entry)
        }
        languageItem.submenu = languages
        menu.addItem(languageItem)
        menu.addItem(item(tr("关于 Tyto 听译", "About Tyto"), "info.circle", #selector(about)))
        if let updater, updater.isEnabled {
            let check = item(tr("检查更新…", "Check for Updates…"), "arrow.triangle.2.circlepath", #selector(Updater.checkForUpdates(_:)))
            check.target = updater
            menu.addItem(check)
        }
        menu.addItem(item(tr("退出", "Quit"), "power", #selector(quit), key: "q"))
    }

    /// 「悬浮窗大小」子菜单：三种大小，当前的打勾；⌃⌥M 按顺序换
    private func layoutMenuItem() -> NSMenuItem {
        let parent = item(tr("悬浮窗大小", "Overlay Size"), settings.value.overlayLayout.symbol, nil)
        let submenu = NSMenu()
        for layout in OverlayLayout.allCases {
            let entry = item(layout.label, layout.symbol, #selector(layoutAction(_:)))
            entry.representedObject = layout.rawValue
            entry.state = settings.value.overlayLayout == layout ? .on : .off
            entry.toolTip = layout.detail
            submenu.addItem(entry)
        }
        submenu.addItem(.separator())
        submenu.addItem(item(tr("换下一种", "Next Size"), "arrow.triangle.2.circlepath", #selector(nextLayoutAction), key: "m"))
        parent.submenu = submenu
        return parent
    }

    @objc private func layoutAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let layout = OverlayLayout(rawValue: raw) else { return }
        showLayout(layout)
    }

    @objc private func nextLayoutAction() { showLayout(settings.value.overlayLayout.next) }

    /// 换大小；悬浮窗收着的话顺便放出来
    private func showLayout(_ layout: OverlayLayout) {
        settings.value.overlayLayout = layout
        if overlay?.isVisible == false { toggleOverlay() }
    }

    @objc private func languageAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = AppLanguage(rawValue: raw) else { return }
        settings.value.language = language
    }

    private func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// - key: 全局快捷键 ⌃⌥ + 这个键（只是在菜单里显示出来；真正响应的是全局热键）
    private func item(_ title: String, _ symbolName: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        if !key.isEmpty { item.keyEquivalentModifierMask = [.control, .option] }
        item.target = self
        item.image = symbol(symbolName)
        return item
    }

    @objc private func captureAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = AppSettings.CaptureTarget(rawValue: raw) else { return }
        screenshotReply(target)
    }

    @objc private func toggleListening() { session.toggle() }
    @objc private func toggleOverlayAction() { toggleOverlay() }
    @objc private func replyAction() { reply() }
    @objc private func clipboardImageAction() {
        session.replyToClipboardImage()
        if overlay?.isVisible == false { overlay?.orderFrontRegardless() }
    }
    @objc private func toggleTranslation() {
        settings.value.translationEnabled.toggle()
        session.translationToggled()
    }
    @objc private func toggleClickThrough() { overlayState.clickThrough.toggle() }
    @objc private func toggleSidecarAction() { settings.value.showReplyPanel.toggle() }
    @objc private func togglePrompterAction() { settings.value.showPrompter.toggle() }
    @objc private func openMainAction() { openMainWindow() }
    @objc private func openRecordsAction() { openMainWindow(page: .records) }
    @objc private func saveRecordAction() { session.saveToRecords() }
    @objc private func clearSessionAction() { MeetingCommands.clear(session) }
    @objc private func exportSessionAction() { MeetingCommands.export(session.snapshot()) }
    @objc private func openNotesAction() {
        settings.value.showPrompter = true
        prompter.choose()
    }
    @objc private func helpAction() {
        let readme = tr("https://github.com/ethannortharc/tyto/blob/main/README.zh-CN.md", "https://github.com/ethannortharc/tyto#readme")
        if let url = URL(string: readme) { NSWorkspace.shared.open(url) }
    }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    private func screenshotReply(_ target: AppSettings.CaptureTarget? = nil) {
        session.captureAndReply(target)
        if overlay?.isVisible == false { overlay?.orderFrontRegardless() }
    }

    private func reply() {
        session.reply(to: session.selection.isEmpty ? nil : Array(session.selection))
        if overlay?.isVisible == false { overlay?.orderFrontRegardless() }
    }

    // MARK: - 主菜单

    /// 屏幕顶上的菜单（Tyto 在前台时）：标准的 App、文件、编辑、显示、窗口、帮助。
    /// 编辑菜单不能少：没有它，设置窗口的输入框里 ⌘C / ⌘V 不起作用
    private func setupMainMenu() {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(item(tr("关于 Tyto 听译", "About Tyto"), "info.circle", #selector(about)))
        if let updater, updater.isEnabled {
            let check = NSMenuItem(title: tr("检查更新…", "Check for Updates…"), action: #selector(Updater.checkForUpdates(_:)),
                                   keyEquivalent: "")
            check.target = updater
            app.addItem(check)
        }
        app.addItem(.separator())
        app.addItem(command(tr("设置…", "Settings…"), #selector(openMainAction), ",", target: self))
        app.addItem(.separator())
        let services = NSMenu()
        let servicesItem = NSMenuItem(title: tr("服务", "Services"), action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        app.addItem(servicesItem)
        app.addItem(.separator())
        app.addItem(command(tr("隐藏 Tyto", "Hide Tyto"), #selector(NSApplication.hide(_:)), "h"))
        app.addItem(command(tr("隐藏其他", "Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h",
                            modifiers: [.command, .option]))
        app.addItem(command(tr("全部显示", "Show All"), #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(command(tr("退出 Tyto", "Quit Tyto"), #selector(quit), "q", target: self))
        add(app, titled: "Tyto", to: main)

        let file = NSMenu(title: tr("文件", "File"))
        // ⌘S 留给技能页的「保存」
        file.addItem(command(tr("保存到会议记录", "Save to Meeting Records"), #selector(saveRecordAction), "s",
                             modifiers: [.command, .shift], target: self))
        file.addItem(command(tr("清空，开始新会议", "Clear, New Meeting"), #selector(clearSessionAction), "n", target: self))
        file.addItem(command(tr("导出记录…", "Export Transcript…"), #selector(exportSessionAction), "e",
                             modifiers: [.command, .shift], target: self))
        file.addItem(command(tr("会议记录", "Meeting Records"), #selector(openRecordsAction), "y", target: self))
        file.addItem(.separator())
        file.addItem(command(tr("打开提词材料…", "Open Notes…"), #selector(openNotesAction), "o", target: self))
        file.addItem(.separator())
        file.addItem(command(tr("关闭窗口", "Close Window"), #selector(NSWindow.performClose(_:)), "w"))
        add(file, to: main)

        let edit = NSMenu(title: tr("编辑", "Edit"))
        edit.addItem(command(tr("撤销", "Undo"), Selector(("undo:")), "z"))
        edit.addItem(command(tr("重做", "Redo"), Selector(("redo:")), "z", modifiers: [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(command(tr("剪切", "Cut"), #selector(NSText.cut(_:)), "x"))
        edit.addItem(command(tr("拷贝", "Copy"), #selector(NSText.copy(_:)), "c"))
        edit.addItem(command(tr("粘贴", "Paste"), #selector(NSText.paste(_:)), "v"))
        edit.addItem(command(tr("全选", "Select All"), #selector(NSText.selectAll(_:)), "a"))
        add(edit, to: main)

        // 这些在会议软件在前台时也能用（全局快捷键），菜单里只是列出来
        let view = NSMenu(title: tr("显示", "View"))
        view.addItem(item(tr("开始 / 停止听", "Start / Stop Listening"), "waveform", #selector(toggleListening), key: "l"))
        view.addItem(.separator())
        view.addItem(item(tr("悬浮窗", "Overlay"), "macwindow", #selector(toggleOverlayAction), key: "t"))
        view.addItem(layoutMenuItem())
        view.addItem(item(tr("回复面板", "Replies Panel"), "sidebar.left", #selector(toggleSidecarAction), key: "b"))
        view.addItem(item(tr("提词器", "Prompter"), "doc.text", #selector(togglePrompterAction), key: "n"))
        view.addItem(item(tr("显示译文", "Show Translation"), "character.bubble", #selector(toggleTranslation)))
        view.addItem(item(tr("点击穿透", "Click-Through"), "cursorarrow.motionlines", #selector(toggleClickThrough), key: "p"))
        add(view, to: main)

        let window = NSMenu(title: tr("窗口", "Window"))
        window.addItem(command(tr("最小化", "Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        window.addItem(command(tr("缩放", "Zoom"), #selector(NSWindow.performZoom(_:)), ""))
        window.addItem(.separator())
        window.addItem(command(tr("前置全部窗口", "Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)), ""))
        add(window, to: main)

        let help = NSMenu(title: tr("帮助", "Help"))
        help.addItem(command(tr("Tyto 使用说明", "Tyto Help"), #selector(helpAction), "?", target: self))
        add(help, to: main)

        NSApp.mainMenu = main
        NSApp.servicesMenu = services
        NSApp.windowsMenu = window
        NSApp.helpMenu = help
    }

    /// 主菜单「显示」里的开关打勾（每次打开菜单时问一次）
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard menuItem.menu?.supermenu === NSApp.mainMenu else { return true }
        switch menuItem.action {
        case #selector(saveRecordAction), #selector(clearSessionAction), #selector(exportSessionAction):
            return !session.isEmpty
        case #selector(toggleOverlayAction): menuItem.state = overlay?.isVisible == true ? .on : .off
        case #selector(toggleSidecarAction): menuItem.state = settings.value.showReplyPanel ? .on : .off
        case #selector(togglePrompterAction): menuItem.state = settings.value.showPrompter ? .on : .off
        case #selector(toggleTranslation): menuItem.state = settings.value.translationEnabled ? .on : .off
        case #selector(toggleClickThrough): menuItem.state = overlayState.clickThrough ? .on : .off
        case #selector(toggleListening): menuItem.state = session.isRunning ? .on : .off
        case #selector(layoutAction(_:)): menuItem.state = menuItem.representedObject as? String == settings.value.overlayLayout.rawValue ? .on : .off
        default: break
        }
        return true
    }

    private func add(_ menu: NSMenu, titled title: String? = nil, to main: NSMenu) {
        let item = NSMenuItem(title: title ?? menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        main.addItem(item)
    }

    /// 普通的 ⌘ 菜单项；target 为 nil 时交给当前窗口（拷贝、粘贴、关闭窗口这类）
    private func command(_ title: String, _ action: Selector, _ key: String,
                         modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey
        hotKeys.register(keyCode: kVK_ANSI_T, modifiers: modifiers) { [weak self] in self?.toggleOverlay() }
        hotKeys.register(keyCode: kVK_ANSI_M, modifiers: modifiers) { [weak self] in self?.nextLayoutAction() }
        hotKeys.register(keyCode: kVK_ANSI_R, modifiers: modifiers) { [weak self] in self?.reply() }
        hotKeys.register(keyCode: kVK_ANSI_P, modifiers: modifiers) { [weak self] in self?.overlayState.clickThrough.toggle() }
        hotKeys.register(keyCode: kVK_ANSI_B, modifiers: modifiers) { [weak self] in self?.settings.value.showReplyPanel.toggle() }
        hotKeys.register(keyCode: kVK_ANSI_N, modifiers: modifiers) { [weak self] in self?.settings.value.showPrompter.toggle() }
        hotKeys.register(keyCode: kVK_ANSI_L, modifiers: modifiers) { [weak self] in self?.session.toggle() }
        hotKeys.register(keyCode: kVK_ANSI_S, modifiers: modifiers) { [weak self] in self?.screenshotReply() }
        hotKeys.register(keyCode: kVK_ANSI_A, modifiers: modifiers) { [weak self] in self?.screenshotReply(.region) }
        hotKeys.register(keyCode: kVK_ANSI_Q, modifiers: modifiers) { NSApp.terminate(nil) }
    }
}
