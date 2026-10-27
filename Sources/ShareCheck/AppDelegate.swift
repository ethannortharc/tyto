import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CheckModel()
    private var overlay: OverlayPanel?
    private var controlWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installMenu()

        // --screen N：窗口开在第 N 块屏幕上（1 是主屏）。不给就开在当前活动的屏幕上。
        let screen = Self.requestedScreen()
        let overlay = OverlayPanel(model: model, screen: screen)
        overlay.orderFrontRegardless()
        self.overlay = overlay

        let control = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        control.title = "Tyto 共享测试"
        control.isReleasedWhenClosed = false
        control.contentView = NSHostingView(rootView: ControlView(model: model))
        // 放在屏幕左上，和右上角的悬浮窗分开，自检时两块标记不会重叠
        if let area = (screen ?? NSScreen.main)?.visibleFrame {
            control.setFrameTopLeftPoint(NSPoint(x: area.minX + 40, y: area.maxY - 40))
        }
        control.makeKeyAndOrderFront(nil)
        // 从终端启动时系统可能不让 app 抢到前台，窗口就会压在别的窗口下面；这里强制提到最前
        control.orderFrontRegardless()
        controlWindow = control

        model.overlay = overlay
        model.controlWindow = control
        // --no-protect：关掉共享保护启动，用来确认自检真的能认出"被截到"
        if CommandLine.arguments.contains("--no-protect") {
            model.protectOverlay = false
        }
        model.writeWindowFrames()
        NSApp.activate()

        // 命令行：open build/TytoShareCheck.app --args --self-check
        // 自检完把结果写进 latest.json 后退出，方便脚本调用。
        if CommandLine.arguments.contains("--self-check") {
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                await model.runSelfCheck()
                NSApp.terminate(nil)
            }
        }
    }

    private static func requestedScreen() -> NSScreen? {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--screen"), flag + 1 < arguments.count,
              let number = Int(arguments[flag + 1]), NSScreen.screens.indices.contains(number - 1)
        else { return nil }
        return NSScreen.screens[number - 1]
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controlWindow?.makeKeyAndOrderFront(nil)
        return true
    }

    private func installMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Tyto 共享测试",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Tyto 共享测试",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }
}
