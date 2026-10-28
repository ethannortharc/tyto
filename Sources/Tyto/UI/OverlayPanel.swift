import AppKit
import SwiftUI

/// 字幕悬浮窗：半透明、永远在最前面（盖得住全屏的会议软件），共享屏幕时对方看不见。
/// 不抢会议软件的焦点；改说话人名字时才临时拿键盘焦点。
/// 有三种大小（完整、字幕条、按钮条），每种各记各的位置和大小。
final class OverlayPanel: NSPanel {
    private let remembersFrame: Bool
    /// 记位置用的名字：完整大小用它本身，字幕条、按钮条在后面加 .captions / .buttons
    private let frameName: String
    private(set) var layout: OverlayLayout = .full

    /// - remembersFrame: false 时不读也不存窗口位置（测试用，不覆盖你拖好的位置）
    /// - frameName: 自测换个名字，不动真实的位置
    init<Content: View>(rootView: Content, remembersFrame: Bool = true, frameName: String = "TytoOverlay") {
        self.remembersFrame = remembersFrame
        self.frameName = frameName
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
        let host = NSHostingView(rootView: rootView)
        // 窗口大小只由我们和你拖的边决定，不跟着内容走：回复区的高度又按窗口高度算，
        // 让内容去撑窗口会互相推着长，实测撑到了 520×1041
        host.sizingOptions = []
        contentView = host

        guard remembersFrame else { return }
        if !setFrameUsingName(frameName), let screen = NSScreen.main {
            setFrame(Self.defaultFrame(on: screen), display: false)
        }
        setFrameAutosaveName(frameName)
    }

    /// 完整大小的默认值：高约为屏幕可用高度的 38%（360～560 点），宽约 26%（380～500 点），靠右、上下居中。
    /// 字幕窗是"边看边扫一眼"的辅助窗口：太高会挡住会议画面，太矮一屏看不了几句；
    /// 三分之一出头的高度能放下 8～12 句字幕加一条收起的回复。
    /// 例：2560×1440 的屏约 500×536；1920×1080 约 500×400；14 寸 MacBook Pro（1512×982）约 393×361。
    static func defaultFrame(on screen: NSScreen) -> NSRect {
        defaultFrame(.full, in: screen.visibleFrame, near: nil, captionLines: 2, fontSize: 14)
    }

    /// 每种大小第一次打开时放哪：
    /// - 完整：见上；
    /// - 字幕条：屏幕下方居中（和视频字幕一样的位置），宽约屏幕的 46%（480～860 点）；
    /// - 按钮条：放在原来悬浮窗的右上角，没有就放屏幕右上角。
    static func defaultFrame(_ layout: OverlayLayout, in area: NSRect, near current: NSRect?,
                             captionLines: Int, fontSize: Double) -> NSRect {
        switch layout {
        case .full:
            let width = min(500, max(380, area.width * 0.26))
            let height = min(560, max(360, area.height * 0.38))
            return NSRect(x: area.maxX - width - 24, y: area.midY - height / 2, width: width, height: height).integral
        case .captions:
            let width = min(860, max(480, area.width * 0.46))
            let height = CaptionBar.height(lines: captionLines, fontSize: fontSize)
            return NSRect(x: area.midX - width / 2, y: area.minY + 56, width: width, height: height).integral
        case .buttons:
            let size = ButtonBar.size
            let anchor = current.flatMap { area.intersects($0) ? $0 : nil }
            let maxX = anchor?.maxX ?? area.maxX - 24
            let maxY = anchor?.maxY ?? area.maxY - 12
            return clamp(NSRect(x: maxX - size.width, y: maxY - size.height, width: size.width, height: size.height), to: area)
        }
    }

    private static func clamp(_ frame: NSRect, to area: NSRect) -> NSRect {
        var frame = frame
        frame.origin.x = min(max(frame.minX, area.minX), area.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, area.minY), area.maxY - frame.height)
        return frame.integral
    }

    func frameName(_ layout: OverlayLayout) -> String {
        layout == .full ? frameName : "\(frameName).\(layout.rawValue)"
    }

    /// 换成另一种大小，或者字号、字幕行数变了时重新算高度。
    /// 先记下现在这种大小的位置；换过去的那种用过的话回到上次的位置，没用过放默认位置。
    func apply(_ layout: OverlayLayout, captionLines: Int, fontSize: Double) {
        let old = self.layout
        let switching = old != layout
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        // 先存好旧的位置，再断开自动记录：不然下面挪窗口时，新大小的位置会被记到旧名字下
        if remembersFrame, switching {
            saveFrame(usingName: frameName(old))
            setFrameAutosaveName("")
        }
        self.layout = layout
        setSizeLimits(captionLines: captionLines, fontSize: fontSize)
        if switching {
            if !(remembersFrame && setFrameUsingName(frameName(layout))) {
                setFrame(Self.defaultFrame(layout, in: area, near: frame, captionLines: captionLines, fontSize: fontSize),
                         display: true)
            }
        }
        // 字幕条按行数定高度，按钮条高度固定；都是上边不动
        let height: CGFloat? = switch layout {
        case .full: nil
        case .captions: CaptionBar.height(lines: captionLines, fontSize: fontSize)
        case .buttons: ButtonBar.size.height
        }
        if let height, frame.height != height {
            var target = frame
            target.origin.y = frame.maxY - height
            target.size.height = height
            setFrame(Self.clamp(target, to: area), display: true)
        }
        if remembersFrame, switching { setFrameAutosaveName(frameName(layout)) }
    }

    /// 字幕条：高度只能按整行变（拖下边时一行一行地跳），1～4 行；按钮条：高度固定
    private func setSizeLimits(captionLines: Int, fontSize: Double) {
        switch layout {
        case .full:
            minSize = NSSize(width: 340, height: 280)
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            resizeIncrements = NSSize(width: 1, height: 1)
        case .captions:
            minSize = NSSize(width: 320, height: CaptionBar.height(lines: 1, fontSize: fontSize))
            maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                             height: CaptionBar.height(lines: CaptionBar.maxLines, fontSize: fontSize))
            resizeIncrements = NSSize(width: 1, height: CaptionBar.lineHeight(fontSize))
        case .buttons:
            minSize = NSSize(width: ButtonBar.size.width - 40, height: ButtonBar.size.height)
            maxSize = NSSize(width: 900, height: ButtonBar.size.height)
            resizeIncrements = NSSize(width: 1, height: 1)
        }
    }

    func resetFrame(captionLines: Int, fontSize: Double) {
        let area = (screen ?? NSScreen.main)?.visibleFrame ?? frame
        setFrame(Self.defaultFrame(layout, in: area, near: nil, captionLines: captionLines, fontSize: fontSize),
                 display: true, animate: true)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    var clickThrough: Bool {
        get { ignoresMouseEvents }
        set { ignoresMouseEvents = newValue }
    }
}

/// 字幕条的尺寸：行高固定（中英文一样高），窗口高度 = 行数 × 行高 + 上下留白，拖下边时正好一行一行地变
enum CaptionBar {
    static let maxLines = 4
    static let padding: CGFloat = 7

    /// 字幕条里的字号：和完整悬浮窗里的原文一样
    static func fontSize(_ base: Double) -> CGFloat { CGFloat(base) + 1 }

    static func lineHeight(_ base: Double) -> CGFloat { (fontSize(base) * 1.32).rounded() }

    static func height(lines: Int, fontSize base: Double) -> CGFloat {
        CGFloat(min(max(lines, 1), maxLines)) * lineHeight(base) + padding * 2
    }

    /// 拖完下边以后是几行
    static func lines(forHeight height: CGFloat, fontSize base: Double) -> Int {
        min(max(Int(((height - padding * 2) / lineHeight(base)).rounded()), 1), maxLines)
    }
}

enum ButtonBar {
    static let size = NSSize(width: 420, height: 48)
}
