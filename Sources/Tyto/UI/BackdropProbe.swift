import AppKit
import ScreenCaptureKit

/// 字色选"自动"时，隔几秒看一眼悬浮窗后面的画面有多亮：亮就换黑字配浅色玻璃，暗就白字。
/// 只取悬浮窗那块区域，缩到 16×16 算平均亮度，不存图；悬浮窗自己不会出现在截图里（sharingType = .none）。
/// 没有录屏权限时不看，保持白字。
@MainActor
final class BackdropProbe {
    private let panel: NSWindow
    private let settings: SettingsStore
    private let state: OverlayState
    private var task: Task<Void, Never>?
    /// 连续两次看到同样的结论才切换，画面闪一下不会来回换
    private var streak = 0

    /// 相对亮度高于它换黑字，低于 darkBelow 换回白字；中间不动，免得在临界处来回跳
    static let lightAbove = 0.28
    static let darkBelow = 0.16

    init(panel: NSWindow, settings: SettingsStore, state: OverlayState) {
        self.panel = panel
        self.settings = settings
        self.state = state
    }

    func start() {
        task?.cancel()
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.probe()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
    }

    private func probe() async {
        guard settings.value.overlayTextColor == .auto, panel.isVisible, panel.occlusionState.contains(.visible),
              CGPreflightScreenCaptureAccess(), let screen = panel.screen,
              let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return }
        let frame = panel.frame
        let rect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                          width: frame.width, height: frame.height)
        guard let luminance = try? await Self.luminance(of: rect, display: displayID) else { return }
        let wantsLight = Self.isLight(luminance, current: state.backdropIsLight)
        guard wantsLight != state.backdropIsLight else {
            streak = 0
            return
        }
        streak += 1
        if streak >= 2 {
            streak = 0
            state.backdropIsLight = wantsLight
        }
    }

    static func isLight(_ luminance: Double, current: Bool) -> Bool {
        current ? luminance > darkBelow : luminance > lightAbove
    }

    /// 屏幕上一块区域（坐标原点在显示器左上角）的平均相对亮度：0 是黑，1 是白。不含 Tyto 自己的窗口
    nonisolated static func luminance(of rect: CGRect, display displayID: CGDirectDisplayID) async throws -> Double {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw TytoError.server(tr("找不到显示器", "Display not found"))
        }
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = 16
        config.height = 16
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(display: display, excludingWindows: []), configuration: config)
        return averageLuminance(image)
    }

    /// 按 sRGB 转成线性光再算相对亮度（和 WCAG 对比度的算法一致）
    nonisolated static func averageLuminance(_ image: CGImage) -> Double {
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return 0 }
        func linear(_ value: UInt8) -> Double {
            let c = Double(value) / 255
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        var total = 0.0
        for index in stride(from: 0, to: pixels.count, by: 4) {
            total += 0.2126 * linear(pixels[index]) + 0.7152 * linear(pixels[index + 1]) + 0.0722 * linear(pixels[index + 2])
        }
        return total / Double(side * side)
    }
}
