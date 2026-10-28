import ScreenCaptureKit
import SwiftUI

extension SelfTest {
    /// 悬浮窗的三种大小：窗口尺寸、按整行变高、换字号重算、回复面板放哪、每种大小各记各的位置。
    /// 给了文件夹时，再把三种大小真的放到屏幕上（盖在模拟的会议画面上）各截一张（要录屏权限、屏幕不能锁着）
    @MainActor
    static func layouts(to folder: String?) async -> Int32 {
        var failures = 0
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "✓ " : "✗ ") + what)
            if !ok { failures += 1 }
        }
        guard let screen = NSScreen.main else { return 1 }
        let area = screen.visibleFrame
        let settings = SettingsStore(persists: false)
        let session = SampleData.session(settings: settings)
        let state = OverlayState()
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state), remembersFrame: false)
        let full = OverlayPanel.defaultFrame(on: screen)
        panel.setFrame(full, display: false)

        let mismatches = (1...CaptionBar.maxLines).flatMap { lines in
            stride(from: 11.0, through: 24, by: 1).filter { font in
                CaptionBar.lines(forHeight: CaptionBar.height(lines: lines, fontSize: font), fontSize: font) != lines
            }
        }
        check(mismatches.isEmpty, "字幕条高度和行数能互相换算（1～4 行，字号 11～24）")
        check(CaptionBar.lines(forHeight: 10, fontSize: 14) == 1 && CaptionBar.lines(forHeight: 900, fontSize: 14) == CaptionBar.maxLines,
              "行数限在 1～\(CaptionBar.maxLines) 行")

        panel.apply(.captions, captionLines: 2, fontSize: 14)
        let bar = panel.frame
        check(bar.height == CaptionBar.height(lines: 2, fontSize: 14), "字幕条 2 行：高 \(Int(bar.height)) 点")
        check(area.contains(bar) && abs(bar.midX - area.midX) <= 1 && bar.minY - area.minY < 80, "第一次打开放在屏幕下方居中")
        check(panel.resizeIncrements.height == CaptionBar.lineHeight(14) && panel.minSize.height == CaptionBar.height(lines: 1, fontSize: 14)
              && panel.maxSize.height == CaptionBar.height(lines: CaptionBar.maxLines, fontSize: 14),
              "拖下边时一行一行地变，最少 1 行、最多 \(CaptionBar.maxLines) 行")

        panel.apply(.captions, captionLines: 3, fontSize: 14)
        check(panel.frame.height == CaptionBar.height(lines: 3, fontSize: 14) && panel.frame.maxY == bar.maxY, "改成 3 行：变高，上边不动")
        panel.apply(.captions, captionLines: 3, fontSize: 18)
        check(panel.frame.height == CaptionBar.height(lines: 3, fontSize: 18) && panel.frame.maxY == bar.maxY,
              "换大字号：还是 3 行，高度跟着变")

        let side = SidecarPanel.frame(beside: panel.frame, in: area, compact: true)
        check(side.minY >= panel.frame.maxY && area.contains(side) && side.height >= 300,
              "字幕条在屏幕下方时，回复面板放在它上面（\(Int(side.width))×\(Int(side.height))）")
        let topBar = NSRect(x: area.midX - 300, y: area.maxY - 60, width: 600, height: 54)
        let below = SidecarPanel.frame(beside: topBar, in: area, compact: true)
        check(below.maxY <= topBar.minY && area.contains(below), "放在屏幕上方时，回复面板放在它下面")
        let edge = SidecarPanel.frame(beside: NSRect(x: area.minX, y: area.midY, width: 200, height: 48), in: area, compact: true)
        check(edge.minX >= area.minX, "贴着屏幕左边时，回复面板不出屏幕")

        let captionsFrame = panel.frame
        panel.apply(.buttons, captionLines: 3, fontSize: 18)
        check(panel.frame.size == ButtonBar.size, "按钮条：\(Int(ButtonBar.size.width))×\(Int(ButtonBar.size.height))")
        check(abs(panel.frame.maxX - captionsFrame.maxX) <= 1 && abs(panel.frame.maxY - captionsFrame.maxY) <= 1,
              "第一次打开放在原来那个窗口的右上角")
        check(panel.minSize.height == panel.maxSize.height, "按钮条高度不能拖")

        panel.apply(.full, captionLines: 3, fontSize: 18)
        check(panel.frame.height >= 280 && panel.minSize == NSSize(width: 340, height: 280), "换回完整大小")
        check([OverlayLayout.full.next, OverlayLayout.captions.next, OverlayLayout.buttons.next] == [.captions, .buttons, .full],
              "⌃⌥M 的顺序：完整 → 字幕条 → 按钮条 → 完整")

        // 每种大小各记各的位置。只在不是正式 App 的时候测（正式 App 会写进你的设置里）
        if Bundle.main.bundleIdentifier == nil {
            let name = "TytoLayoutTest\(UUID().uuidString.prefix(6))"
            let remembering = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state), frameName: name)
            remembering.setFrame(full, display: false)
            remembering.apply(.captions, captionLines: 2, fontSize: 14)
            var moved = remembering.frame
            moved.origin.x -= 100
            moved.origin.y += 120
            remembering.setFrame(moved, display: false)
            remembering.apply(.full, captionLines: 2, fontSize: 14)
            check(remembering.frame == full, "从字幕条换回完整：回到原来的位置和大小")
            remembering.apply(.captions, captionLines: 2, fontSize: 14)
            check(remembering.frame == moved, "再换成字幕条：回到上次拖到的位置")
            remembering.apply(.full, captionLines: 2, fontSize: 14)
            remembering.apply(.captions, captionLines: 2, fontSize: 18)
            check(remembering.frame.height == CaptionBar.height(lines: 2, fontSize: 18) && remembering.frame.maxY == moved.maxY,
                  "在完整大小里换了字号再换回字幕条：高度按新字号算，上边还在原处")
            for layout in OverlayLayout.allCases {
                UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(remembering.frameName(layout))")
            }
        } else {
            print("· 记位置的检查跳过（正式 App 里测会写进你的设置；用 .build/debug/Tyto --selftest-layouts 测）")
        }

        if let folder {
            failures += await layoutShots(to: folder, session: session, settings: settings)
        }
        print(failures == 0 ? "悬浮窗大小：全部通过" : "悬浮窗大小：\(failures) 项没通过")
        return failures == 0 ? 0 : 1
    }

    /// 三种大小真的放到屏幕上，盖在模拟的会议画面上截图（只截这两个窗口）
    @MainActor
    private static func layoutShots(to folder: String, session: SessionModel, settings: SettingsStore) async -> Int {
        guard let screen = NSScreen.screens.first else { return 1 }
        let area = screen.visibleFrame
        let stage = NSRect(x: area.midX - 380, y: area.midY - 300, width: 760, height: 600)
        let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.level = .floating
        backdrop.contentView = NSHostingView(rootView: SampleBackdrop())
        backdrop.orderFrontRegardless()
        let state = OverlayState()
        let panel = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state), remembersFrame: false)
        panel.sharingType = .readOnly
        SharingGuard.exempt.insert(ObjectIdentifier(panel))
        SharingGuard.exempt.insert(ObjectIdentifier(backdrop))
        defer {
            panel.orderOut(nil)
            backdrop.orderOut(nil)
            SharingGuard.exempt.removeAll()
        }
        let folderURL = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        let shots: [(String, OverlayLayout, Int, Bool)] = [
            ("full", .full, 2, true), ("captions-1", .captions, 1, false), ("captions-2", .captions, 2, true), ("buttons", .buttons, 2, true),
        ]
        var failures = 0
        for (name, layout, lines, translation) in shots {
            settings.value.overlayLayout = layout
            settings.value.captionLines = lines
            settings.value.translationEnabled = translation
            panel.setFrame(NSRect(x: stage.minX + 60, y: stage.minY + 60, width: 480, height: 480), display: false)
            panel.apply(layout, captionLines: lines, fontSize: settings.value.fontSize)
            if layout != .full {
                // 第一次打开会放到默认位置；拉回画面里来截
                var frame = panel.frame
                frame.origin = NSPoint(x: stage.minX + 40, y: stage.maxY - 60 - frame.height)
                frame.size.width = min(frame.width, stage.width - 80)
                panel.setFrame(frame, display: false)
            }
            panel.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(1.2))
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let ours = content.windows.filter { [backdrop.windowNumber, panel.windowNumber].contains(Int($0.windowID)) }
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return failures + 1 }
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: stage.minX - screen.frame.minX, y: screen.frame.maxY - stage.maxY,
                                           width: stage.width, height: stage.height)
                config.width = Int(stage.width * 2)
                config.height = Int(stage.height * 2)
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, including: ours), configuration: config)
                let url = folderURL.appending(path: "layout-\(name).png")
                try ImageFile.writePNG(image, to: url)
                print(url.path)
            } catch {
                print("✗ 截不了：\(error.localizedDescription)")
                failures += 1
            }
        }
        return failures
    }
}
