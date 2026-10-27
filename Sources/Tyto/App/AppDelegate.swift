import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = SettingsStore()
    private lazy var skills = SkillStore()
    private lazy var session = SessionModel(settings: settings, skills: skills)
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
    private var subscriptions: Set<AnyCancellable> = []
    private var sweepTask: Task<Void, Never>?
    private var optionTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested(settings: settings) { return }

        NSApp.setActivationPolicy(.accessory)
        session.load()

        let actions = OverlayActions(
            openMain: { [weak self] in self?.openMainWindow() },
            hide: { [weak self] in self?.toggleOverlay() },
            quit: { NSApp.terminate(nil) },
            resetSize: { [weak self] in self?.overlay?.resetFrame() },
            openTranslation: { [weak self] in self?.openMainWindow(page: .translation) })
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: overlayState,
                                                       actions: actions))
        panel.orderFrontRegardless()
        overlay = panel
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
        hideAllWindowsFromSharing()

        if !UserDefaults.standard.bool(forKey: "launchedBefore") {
            UserDefaults.standard.set(true, forKey: "launchedBefore")
            openMainWindow()
        }
        // --start：启动后直接开始听（自测和开机自启用）
        if CommandLine.arguments.contains("--start") { session.toggle() }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
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
            window.contentView = NSHostingView(rootView: MainView(session: session, settings: settings, skills: skills, initialPage: page))
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
                                                                  initialPage: page ?? .session))
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
        sidecar.place(beside: overlay)
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

    /// 弹出来的小窗口（改名字的气泡等）是另建的窗口，不会自动继承"不被共享"；定时把本 app 所有窗口都设上。
    private func hideAllWindowsFromSharing() {
        sweepTask = Task {
            while !Task.isCancelled {
                for window in NSApp.windows where window.sharingType != .none { window.sharingType = .none }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
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
        menu.addItem(item(tr("退出", "Quit"), "power", #selector(quit), key: "q"))
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

    // MARK: - 快捷键

    private func registerHotKeys() {
        let modifiers = controlKey | optionKey
        hotKeys.register(keyCode: kVK_ANSI_T, modifiers: modifiers) { [weak self] in self?.toggleOverlay() }
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
