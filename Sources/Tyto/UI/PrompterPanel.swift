import AppKit
import SwiftUI

/// 提词器的窗口：和悬浮窗一样不抢焦点、永远在前、共享屏幕时看不见。
/// 自己一个窗口，可以拖到任何地方（比如摄像头底下，看稿时眼睛不偏）、改大小，位置会记住。
final class PrompterPanel: NSPanel {
    private static let autosaveName = "TytoPrompter"
    static let defaultWidth: CGFloat = 420

    /// - remembersFrame: false 时不读也不存位置（测试用）
    init<Content: View>(rootView: Content, remembersFrame: Bool = true) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.defaultWidth, height: 560),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        sharingType = .none
        minSize = NSSize(width: 300, height: 260)
        let host = NSHostingView(rootView: rootView)
        host.sizingOptions = []
        contentView = host
        if remembersFrame {
            hasSavedFrame = setFrameUsingName(Self.autosaveName)
            setFrameAutosaveName(Self.autosaveName)
        }
    }

    /// 有没有记住的位置；没有时第一次打开放到悬浮窗旁边
    private(set) var hasSavedFrame = false

    /// 第一次打开：放在悬浮窗（和回复面板）的另一侧，和悬浮窗一样高；两边都放不下就放在屏幕上方正中
    func place(beside overlay: NSWindow, sidecar: NSWindow?) {
        let frame = overlay.frame
        let area = (overlay.screen ?? NSScreen.main)?.visibleFrame ?? frame
        let gap = SidecarPanel.gap
        let occupied = [frame, sidecar?.isVisible == true ? sidecar?.frame : nil].compactMap { $0 }
        let minX = occupied.map(\.minX).min() ?? frame.minX
        let maxX = occupied.map(\.maxX).max() ?? frame.maxX
        let width = Self.defaultWidth
        let height = max(frame.height, 420)
        let y = min(max(frame.midY - height / 2, area.minY), area.maxY - height)
        let target: NSRect
        if minX - gap - width >= area.minX {
            target = NSRect(x: minX - gap - width, y: y, width: width, height: height)
        } else if maxX + gap + width <= area.maxX {
            target = NSRect(x: maxX + gap, y: y, width: width, height: height)
        } else {
            target = NSRect(x: area.midX - width / 2, y: area.maxY - height - 12, width: width, height: height)
        }
        setFrame(target.integral, display: true)
        hasSavedFrame = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
