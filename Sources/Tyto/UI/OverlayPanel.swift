import AppKit
import SwiftUI

/// 字幕悬浮窗：半透明、永远在最前面（盖得住全屏的会议软件），共享屏幕时对方看不见。
/// 不抢会议软件的焦点；改说话人名字时才临时拿键盘焦点。
final class OverlayPanel: NSPanel {
    private static let autosaveName = "TytoOverlay"

    /// - remembersFrame: false 时不读也不存窗口位置（测试用，不覆盖你拖好的位置）
    init<Content: View>(rootView: Content, remembersFrame: Bool = true) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        // 阴影交给系统玻璃自己画，窗口阴影会在圆角外多出一圈方框
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        minSize = NSSize(width: 340, height: 280)
        contentView = NSHostingView(rootView: rootView)

        guard remembersFrame else { return }
        if !setFrameUsingName(Self.autosaveName), let screen = NSScreen.main {
            setFrame(Self.defaultFrame(on: screen), display: false)
        }
        setFrameAutosaveName(Self.autosaveName)
    }

    /// 默认大小：高约为屏幕可用高度的 38%（360～560 点），宽约 26%（380～500 点），靠右、上下居中。
    /// 字幕窗是"边看边扫一眼"的辅助窗口：太高会挡住会议画面，太矮一屏看不了几句；
    /// 三分之一出头的高度能放下 8～12 句字幕加一条收起的回复。
    /// 例：2560×1440 的屏约 500×536；1920×1080 约 500×400；14 寸 MacBook Pro（1512×982）约 393×361。
    static func defaultFrame(on screen: NSScreen) -> NSRect {
        let area = screen.visibleFrame
        let width = min(500, max(380, area.width * 0.26))
        let height = min(560, max(360, area.height * 0.38))
        return NSRect(x: area.maxX - width - 24, y: area.midY - height / 2, width: width, height: height).integral
    }

    func resetFrame() {
        guard let screen = screen ?? NSScreen.main else { return }
        setFrame(Self.defaultFrame(on: screen), display: true, animate: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var clickThrough: Bool {
        get { ignoresMouseEvents }
        set { ignoresMouseEvents = newValue }
    }
}
