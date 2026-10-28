import AppKit
import ScreenCaptureKit
import SwiftUI

/// --selftest-sharing [截图文件夹]：共享屏幕时 Tyto 的东西会不会被截到。
/// 在主屏中间铺一块固定的背景，先截一张"什么都没有"的；再把悬浮窗、回复面板、提词器（网页内容）、
/// 外观弹出框、一个打开的下拉菜单放上去，用和会议软件一样的方式截整块屏幕，和第一张逐像素比，应该一样。
/// 对照：暂停 SharingGuard、让提词器可以被截，这时必须截得到（证明这个测试看得见东西）。
/// 会在屏幕上闪几秒，菜单打开的那一下会占住鼠标。
extension SelfTest {
    @MainActor
    static func sharing(to folder: String?) async -> Int32 {
        let settings = SettingsStore(persists: false)
        settings.value.showReplyPanel = true
        let session = SampleData.session(settings: settings)
        guard let screen = NSScreen.screens.first else { return 1 }
        let area = screen.visibleFrame
        let stage = NSRect(x: area.midX - 560, y: area.midY - 330, width: 1120, height: 660)
        let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: SampleBackdrop(light: false))
        backdrop.orderFrontRegardless()
        SharingGuard.exempt.insert(ObjectIdentifier(backdrop))

        let state = OverlayState()
        let overlay = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state), remembersFrame: false)
        overlay.setFrame(NSRect(x: stage.midX - 60, y: stage.minY + 40, width: 440, height: 560), display: true)
        let sidecar = SidecarPanel(rootView: SidecarView(session: session, settings: settings, ui: state))
        let notes = FileManager.default.temporaryDirectory.appending(path: "tyto-sharing-\(UUID().uuidString).md")
        try? SampleNotes.english.write(to: notes, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: notes) }
        let prompter = PrompterModel(settings: settings, session: session)
        let occlusion = Selector(("_setWindowOcclusionDetectionEnabled:"))
        if prompter.web.view.responds(to: occlusion) { prompter.web.view.perform(occlusion, with: false) }
        let prompterPanel = PrompterPanel(rootView: PrompterView(model: prompter, settings: settings), remembersFrame: false)
        prompterPanel.setFrame(NSRect(x: stage.minX + 30, y: stage.minY + 40, width: 400, height: 560), display: true)
        defer {
            for window in [overlay, sidecar, prompterPanel, backdrop] as [NSWindow] { window.orderOut(nil) }
        }

        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String) {
            print("\(ok ? "✓" : "✗") \(name)  \(detail)")
            if !ok { failures += 1 }
        }
        let out = folder.map { URL(filePath: $0) }
        if let out { try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true) }
        func save(_ image: CGImage?, _ name: String) {
            guard let out, let image else { return }
            try? ImageFile.writePNG(image, to: out.appending(path: "sharing-\(name).png"))
        }

        // 1. 什么都没有
        try? await Task.sleep(for: .seconds(1))
        guard let baseline = await captureDisplay(stage, screen: screen) else {
            print("截不了屏（要屏幕录制权限）")
            return 1
        }
        save(baseline, "0-baseline")

        // 2. 放上 Tyto 的窗口（和正式运行时一样由 SharingGuard 管）
        SharingGuard.install()
        overlay.orderFrontRegardless()
        overlay.addChildWindow(sidecar, ordered: .above)
        sidecar.place(beside: overlay)
        sidecar.orderFrontRegardless()
        prompterPanel.orderFrontRegardless()
        prompter.open(notes)
        let deadline = Date.now.addingTimeInterval(8)
        while prompter.blocks.isEmpty, Date.now < deadline { try? await Task.sleep(for: .milliseconds(100)) }
        let popover = NSPopover()
        popover.contentViewController = NSHostingController(rootView: AppearancePopover(settings: settings, ui: state))
        if let anchor = overlay.contentView {
            popover.show(relativeTo: NSRect(x: anchor.bounds.maxX - 120, y: anchor.bounds.maxY - 40, width: 20, height: 20),
                         of: anchor, preferredEdge: .minY)
        }
        try? await Task.sleep(for: .seconds(1.5))
        let windows = await captureDisplay(stage, screen: screen)
        save(windows, "1-windows")
        let shown = difference(baseline, windows)
        check("悬浮窗、回复面板、提词器、外观弹出框都截不到", shown.changed < 50,
              "和空白比有 \(shown.changed) 个像素不同（窗口在的话会有几十万个）")
        popover.close()

        // 3. 打开一个下拉菜单（悬浮窗里的「⋯」「截屏」菜单、提词器的目录都是这种系统菜单）
        let menu = NSMenu()
        for title in ["Session & Settings…", "Click-Through ⌃⌥P", "Reset Size & Position", "Hide Overlay ⌃⌥T", "Quit Tyto"] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        // 菜单打开时主线程在"事件跟踪"模式里：主队列不跑，所以在后台线程截图，用计时器（这个模式下也跑）关菜单
        func menuCapture() -> CGImage? {
            let shot = CaptureBox()
            let rect = displayRect(stage, screen: screen)
            let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            Task.detached {
                try? await Task.sleep(for: .seconds(0.8))
                shot.finish(await captureRect(rect, display: displayID))
            }
            nonisolated(unsafe) let tracked = menu
            let started = Date.now
            let closer = Timer(timeInterval: 0.1, repeats: true) { timer in
                guard shot.isDone || Date.now.timeIntervalSince(started) > 10 else { return }
                timer.invalidate()
                MainActor.assumeIsolated { tracked.cancelTracking() }
            }
            RunLoop.main.add(closer, forMode: .common)
            menu.popUp(positioning: nil, at: NSPoint(x: 520, y: 520), in: backdrop.contentView)
            return shot.image
        }
        // 截图没拿到（刚解锁时截屏服务可能还没响应）两项都算没通过，不能当成"截不到"或"截得到"
        let noShot = "没截到图（截屏服务没响应，再跑一次）"
        let menuShot = menuCapture()
        save(menuShot, "2-menu")
        let menuDiff = difference(baseline, menuShot)
        check("打开的下拉菜单截不到", menuShot != nil && menuDiff.changed < 50,
              menuShot == nil ? noShot : "和空白比有 \(menuDiff.changed) 个像素不同")
        SharingGuard.paused = true
        let menuControl = menuCapture()
        SharingGuard.paused = false
        save(menuControl, "2-menu-control")
        let menuVisible = difference(baseline, menuControl)
        check("对照：不设保护时截得到菜单", menuControl != nil && menuVisible.changed > 2_000,
              menuControl == nil ? noShot : "和空白比有 \(menuVisible.changed) 个像素不同")

        // 4. 对照：暂停 SharingGuard，提词器设成可以被截，必须截得到
        SharingGuard.paused = true
        prompterPanel.sharingType = .readOnly
        try? await Task.sleep(for: .seconds(1))
        let control = await captureDisplay(stage, screen: screen)
        save(control, "3-control")
        let visible = difference(baseline, control)
        check("对照：不设保护时截得到提词器", visible.changed > 20_000, "和空白比有 \(visible.changed) 个像素不同")
        SharingGuard.paused = false

        print(failures == 0 ? "共享屏幕：全部通过" : "共享屏幕：\(failures) 项没通过")
        return failures == 0 ? 0 : 1
    }

    /// 像会议软件共享整块屏幕那样截：整块显示器、所有窗口，不排除任何 App
    @MainActor
    private static func captureDisplay(_ stage: NSRect, screen: NSScreen) async -> CGImage? {
        guard let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        else { return nil }
        return await captureRect(displayRect(stage, screen: screen), display: displayID)
    }

    /// 屏幕坐标（左下角原点）换成显示器里的区域（左上角原点）
    @MainActor
    private static func displayRect(_ stage: NSRect, screen: NSScreen) -> CGRect {
        CGRect(x: stage.minX - screen.frame.minX, y: screen.frame.maxY - stage.maxY, width: stage.width, height: stage.height)
    }

    /// 不用主线程（菜单打开时主线程忙着跟踪鼠标）
    nonisolated private static func captureRect(_ rect: CGRect, display displayID: CGDirectDisplayID) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let display = content.displays.first(where: { $0.displayID == displayID })
        else { return nil }
        let config = SCStreamConfiguration()
        config.sourceRect = rect
        config.width = Int(rect.width)
        config.height = Int(rect.height)
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: []),
                                                           configuration: config)
    }

    /// 两张图有多少像素明显不同（任一通道差 24 以上）
    private static func difference(_ a: CGImage, _ b: CGImage?) -> (changed: Int, total: Int) {
        guard let b, let left = pixels(a), let right = pixels(b), left.count == right.count else { return (Int.max, 0) }
        var changed = 0
        var index = 0
        while index < left.count {
            if abs(Int(left[index]) - Int(right[index])) > 24 || abs(Int(left[index + 1]) - Int(right[index + 1])) > 24
                || abs(Int(left[index + 2]) - Int(right[index + 2])) > 24 {
                changed += 1
            }
            index += 4
        }
        return (changed, left.count / 4)
    }

    private static func pixels(_ image: CGImage) -> [UInt8]? {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }
}

/// 后台线程截好的图，主线程上的计时器来取
private final class CaptureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: CGImage?
    private var done = false

    func finish(_ image: CGImage?) {
        lock.lock()
        result = image
        done = true
        lock.unlock()
    }

    var isDone: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    var image: CGImage? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
