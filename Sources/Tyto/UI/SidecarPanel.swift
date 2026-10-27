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

    /// 贴到悬浮窗旁边：左边放得下就放左边（悬浮窗默认靠屏幕右边），放不下放右边
    func place(beside overlay: NSWindow) {
        let frame = overlay.frame
        let area = (overlay.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let left = frame.minX - Self.gap - Self.width
        let x = left >= area.minX ? left : frame.maxX + Self.gap
        setFrame(NSRect(x: x, y: frame.minY, width: Self.width, height: frame.height), display: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
