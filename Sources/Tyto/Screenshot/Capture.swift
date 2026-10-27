import AppKit
import ScreenCaptureKit

/// 截到的图，以及它来自哪个 App
struct CapturedImage: Sendable {
    let png: Data
    /// 如 "Microsoft Teams"
    let appName: String?
    let bundleID: String?
    /// 窗口标题（有屏幕录制权限时才读得到）
    let windowTitle: String?

    /// 给模型和界面看的来源说明
    var source: String? {
        guard let appName else { return nil }
        if let windowTitle, !windowTitle.isEmpty, windowTitle != appName { return "\(appName)（\(windowTitle)）" }
        return appName
    }
}

enum Capture {
    /// 按设置的方式截图。返回 nil 表示取消了（框选时按了 Esc）。
    static func capture(_ target: AppSettings.CaptureTarget) async throws -> CapturedImage? {
        switch target {
        case .frontWindow: try await frontWindow()
        case .screen: try await currentScreen()
        case .region: await region()
        }
    }

    /// 截最前面那个 App 的窗口（不含 Tyto 自己）。按快捷键时最前面的就是你正在用的那个，比如 Teams。
    static func frontWindow() async throws -> CapturedImage {
        try ensurePermission()
        guard let target = frontmostWindowInfo() else { throw TytoError.server("找不到可以截的窗口") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.windowID == target.windowID }) else {
            throw TytoError.server("截不到「\(target.appName ?? "前台 App")」的窗口")
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let app = window.owningApplication
        return CapturedImage(png: try png(image), appName: app?.applicationName ?? target.appName,
                             bundleID: app?.bundleIdentifier, windowTitle: window.title ?? target.title)
    }

    /// 截鼠标所在的那块屏幕（Tyto 自己的窗口不会出现在截图里）
    static func currentScreen() async throws -> CapturedImage {
        try ensurePermission()
        let mouse = NSEvent.mouseLocation
        let displayID: CGDirectDisplayID? = await MainActor.run {
            let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            return (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw TytoError.server("找不到屏幕")
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let front = frontmostWindowInfo()
        return CapturedImage(png: try png(image), appName: front?.appName, bundleID: front?.bundleID, windowTitle: nil)
    }

    /// 框选（系统自带的十字线，和 ⌘⇧4 一样）
    static func region() async -> CapturedImage? {
        let front = frontmostWindowInfo()
        guard let png = await Screenshot.captureInteractive() else { return nil }
        return CapturedImage(png: png, appName: front?.appName, bundleID: front?.bundleID, windowTitle: nil)
    }

    struct WindowInfo {
        let windowID: CGWindowID
        let pid: pid_t
        let appName: String?
        let bundleID: String?
        let title: String?
    }

    /// 屏幕上从前往后数，第一个不属于 Tyto 的普通窗口。前台 App 是别人时只认它的窗口。
    static func frontmostWindowInfo() -> WindowInfo? {
        let me = getpid()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        for info in list {
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? CGWindowID,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  (bounds["Width"] as? Double ?? 0) > 120, (bounds["Height"] as? Double ?? 0) > 120
            else { continue }
            if let frontPID, frontPID != me, pid != frontPID { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            return WindowInfo(windowID: number, pid: pid,
                              appName: app?.localizedName ?? info[kCGWindowOwnerName as String] as? String,
                              bundleID: app?.bundleIdentifier,
                              title: info[kCGWindowName as String] as? String)
        }
        return nil
    }

    /// 截 App 窗口和整屏要"屏幕录制"权限；没有时请求一次，并告诉人去哪里打开
    static func ensurePermission() throws {
        guard !CGPreflightScreenCaptureAccess() else { return }
        CGRequestScreenCaptureAccess()
        throw TytoError.screenRecordingPermission
    }

    static func openPrivacySettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func png(_ image: CGImage) throws -> Data {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw TytoError.server("截图转不了 PNG")
        }
        return data
    }
}
