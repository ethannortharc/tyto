import AppKit
import SwiftUI

/// 回复面板的窗口：和悬浮窗一样不抢焦点、永远在前、共享屏幕时看不见。
/// 作为悬浮窗的子窗口贴在它旁边，拖悬浮窗时一起走；高度和悬浮窗一样。
final class SidecarPanel: NSPanel {
    static let width: CGFloat = 340
    static let gap: CGFloat = 8

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 600),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
    }

    /// 贴到悬浮窗旁边：左边放得下就放左边（悬浮窗默认靠屏幕右边），放不下放右边。
    /// 悬浮窗缩成字幕条、按钮条时太矮，放不下回复：改成放在它下面（下面放不下就放上面），右边对齐
    func place(beside overlay: NSWindow, compact: Bool = false) {
        setFrame(Self.frame(beside: overlay.frame, in: (overlay.screen ?? NSScreen.main)?.visibleFrame ?? overlay.frame,
                            compact: compact), display: true)
    }

    static func frame(beside frame: NSRect, in area: NSRect, compact: Bool) -> NSRect {
        guard compact else {
            let left = frame.minX - gap - width
            let x = left >= area.minX ? left : frame.maxX + gap
            return NSRect(x: x, y: frame.minY, width: width, height: frame.height)
        }
        let height = min(460, area.height * 0.6).rounded()
        let x = min(max(frame.maxX - width, area.minX), area.maxX - width)
        let below = frame.minY - gap - height
        let y = below >= area.minY ? below : min(frame.maxY + gap, area.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
