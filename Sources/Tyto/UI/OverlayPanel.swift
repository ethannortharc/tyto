import AppKit
import SwiftUI

/// 字幕悬浮窗：半透明、永远在最前面（盖得住全屏的会议软件），共享屏幕时对方看不见。
/// 不抢会议软件的焦点；改说话人名字时才临时拿键盘焦点。
final class OverlayPanel: NSPanel {
    private static let autosaveName = "TytoOverlay"

    init<Content: View>(rootView: Content) {
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
        minSize = NSSize(width: 360, height: 260)
        contentView = NSHostingView(rootView: rootView)

        if !setFrameUsingName(Self.autosaveName), let area = NSScreen.main?.visibleFrame {
            setFrame(NSRect(x: area.maxX - 500, y: area.minY + 40, width: 480, height: min(600, area.height - 80)),
                     display: false)
        }
        setFrameAutosaveName(Self.autosaveName)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var clickThrough: Bool {
        get { ignoresMouseEvents }
        set { ignoresMouseEvents = newValue }
    }
}
