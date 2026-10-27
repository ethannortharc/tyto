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

        let overlay = OverlayPanel(model: model)
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
        if let area = NSScreen.main?.visibleFrame {
            control.setFrameTopLeftPoint(NSPoint(x: area.minX + 40, y: area.maxY - 40))
        }
        control.makeKeyAndOrderFront(nil)
        controlWindow = control

        model.overlay = overlay
        model.controlWindow = control
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
