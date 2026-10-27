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
    private var mainWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private let hotKeys = HotKeys()
    private var subscriptions: Set<AnyCancellable> = []
    private var sweepTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SelfTest.runIfRequested(settings: settings) { return }

        NSApp.setActivationPolicy(.accessory)
        session.load()

        let panel = OverlayPanel(rootView: OverlayView(
            session: session, settings: settings, ui: overlayState,
            openMain: { [weak self] in self?.openMainWindow() },
            hide: { [weak self] in self?.toggleOverlay() }))
        panel.orderFrontRegardless()
        overlay = panel
        overlayState.$clickThrough
            .sink { [weak panel] on in panel?.clickThrough = on }
            .store(in: &subscriptions)

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

    private func openMainWindow() {
        if mainWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Tyto 听译 · 会话与设置"
            window.isReleasedWhenClosed = false
            // 会议背景和记录也不能被共享出去
            window.sharingType = .none
            window.contentView = NSHostingView(rootView: MainView(session: session, settings: settings, skills: skills))
            window.center()
            window.setFrameAutosaveName("TytoMain")
            mainWindow = window
        }
        NSApp.activate()
        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
    }

    private func toggleOverlay() {
        guard let overlay else { return }
        if overlay.isVisible { overlay.orderOut(nil) } else { overlay.orderFrontRegardless() }
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
        item.button?.image = NSImage(systemSymbolName: "ear", accessibilityDescription: "Tyto 听译")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(menuItem(session.isRunning ? "停止听（⌃⌥L）" : "开始听（⌃⌥L）", #selector(toggleListening)))
        menu.addItem(menuItem(overlay?.isVisible == true ? "隐藏悬浮窗（⌃⌥T）" : "显示悬浮窗（⌃⌥T）", #selector(toggleOverlayAction)))
        menu.addItem(menuItem("回复（⌃⌥R）", #selector(replyAction)))
        let translation = menuItem("翻译", #selector(toggleTranslation))
        translation.state = settings.value.translationEnabled ? .on : .off
        menu.addItem(translation)
        let clickThrough = menuItem("点击穿透（⌃⌥P）", #selector(toggleClickThrough))
        clickThrough.state = overlayState.clickThrough ? .on : .off
        menu.addItem(clickThrough)
        menu.addItem(.separator())
        menu.addItem(menuItem("会话与设置…", #selector(openMainAction)))
        menu.addItem(.separator())
        menu.addItem(menuItem("关于 Tyto 听译", #selector(about)))
        menu.addItem(menuItem("退出", #selector(quit)))
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleListening() { session.toggle() }
    @objc private func toggleOverlayAction() { toggleOverlay() }
    @objc private func replyAction() { reply() }
    @objc private func toggleTranslation() {
        settings.value.translationEnabled.toggle()
        session.translationToggled()
    }
    @objc private func toggleClickThrough() { overlayState.clickThrough.toggle() }
    @objc private func openMainAction() { openMainWindow() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(nil)
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
        hotKeys.register(keyCode: kVK_ANSI_L, modifiers: modifiers) { [weak self] in self?.session.toggle() }
    }
}
