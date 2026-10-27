import AppKit
import SwiftUI

/// 品红色标记块。悬浮窗和对照窗口左上角各有一块，自检时在截图里找它。
enum Marker {
    static let size: CGFloat = 40
    static let color = Color(.sRGB, red: 1, green: 0, blue: 1)
}

struct MarkerSquare: View {
    var body: some View {
        Rectangle().fill(Marker.color).frame(width: Marker.size, height: Marker.size)
    }
}

/// 透明悬浮窗：不抢焦点，跟随所有桌面和全屏 app，可以设成点击穿透。
/// 正式产品的字幕窗也会这样建，这里只是加了测试用的标记和时钟。
final class OverlayPanel: NSPanel {
    static let contentSize = NSSize(width: 460, height: 150)

    init(model: CheckModel) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        sharingType = .none
        contentView = NSHostingView(rootView: OverlayView(model: model))

        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            setFrameOrigin(NSPoint(x: area.maxX - Self.contentSize.width - 32,
                                   y: area.maxY - Self.contentSize.height - 32))
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct OverlayView: View {
    @ObservedObject var model: CheckModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MarkerSquare()
            VStack(alignment: .leading, spacing: 6) {
                Text("Tyto 听译 · 悬浮窗").font(.headline)
                Text("对方如果看得到这一块，说明悬浮窗被共享出去了。")
                    .font(.callout)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(context.date, format: .dateTime.hour().minute().second())
                        .font(.system(size: 22, weight: .semibold).monospacedDigit())
                }
                Text(model.protectOverlay ? "共享保护：开" : "共享保护：关")
                    .font(.caption)
                    .foregroundStyle(model.protectOverlay ? .green : .orange)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: OverlayPanel.contentSize.width, height: OverlayPanel.contentSize.height,
               alignment: .topLeading)
        .foregroundStyle(.white)
        .background(RoundedRectangle(cornerRadius: 14).fill(.black.opacity(0.6)))
    }
}
