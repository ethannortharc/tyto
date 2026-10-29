import ScreenCaptureKit
import SwiftUI

// Included only in the disposable documentation build by capture.py.
// Uses the shipping views and their existing sample data; no model/audio calls.
extension SelfTest {
    @MainActor static func readmeCapture(to folder: String) async -> Int32 {
        guard let screen = NSScreen.screens.first else { return 1 }
        let settings = SettingsStore(persists: false)
        settings.value.language = .zh
        settings.value.theme = .graphite
        settings.value.overlayOpacity = 0.5
        settings.value.showReplyPanel = true
        L10n.set(.zh)
        let session = SampleData.session(settings: settings)
        let state = OverlayState()
        let rows = SampleData.rows()
        let output = URL(filePath: folder)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for shot in ["meeting", "screenshot-replies"] {
            let meeting = shot == "meeting"
            let size = NSSize(width: meeting ? 960 : 520, height: meeting ? 720 : 540)
            let area = screen.visibleFrame
            let stage = NSRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                               width: size.width, height: size.height)
            guard area.contains(stage) else { print("Display too small for the capture stage"); return 1 }
            session.showSample(rows: meeting ? rows : [],
                replies: meeting ? [SampleData.meetingReply(answering: rows)] : [SampleData.screenshotReply(thumbnail: nil)],
                selection: meeting ? [rows[3].id] : [])
            let backdrop = NSWindow(contentRect: stage, styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.level = .floating
            backdrop.contentView = NSHostingView(rootView: SampleBackdrop())
            let sidecar = SidecarPanel(rootView: SidecarView(session: session, settings: settings, ui: state))
            sidecar.setFrame(NSRect(x: stage.minX + 40, y: stage.minY + 40,
                                   width: meeting ? 360 : 440, height: meeting ? 640 : 460), display: true)
            var windows: [NSWindow] = [backdrop, sidecar]
            if meeting {
                let overlay = OverlayPanel(rootView: OverlayView(session: session, settings: settings, ui: state), remembersFrame: false)
                overlay.setFrame(NSRect(x: stage.minX + 408, y: stage.minY + 40, width: 512, height: 640), display: true)
                windows.append(overlay)
            }
            for window in windows {
                window.sharingType = .readOnly
                SharingGuard.exempt.insert(ObjectIdentifier(window))
                window.orderFrontRegardless()
            }
            defer {
                for window in windows { window.orderOut(nil); SharingGuard.exempt.remove(ObjectIdentifier(window)) }
            }
            try? await Task.sleep(for: .seconds(2))
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return 1 }
                let numbers = Set(windows.map(\.windowNumber))
                let sources = content.windows.filter { numbers.contains(Int($0.windowID)) }
                guard sources.count == windows.count else { print("Capture window missing"); return 1 }
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: stage.minX - screen.frame.minX, y: screen.frame.maxY - stage.maxY,
                                           width: stage.width, height: stage.height)
                config.width = Int(stage.width * 2)
                config.height = Int(stage.height * 2)
                config.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: SCContentFilter(display: display, including: sources), configuration: config)
                let file = output.appending(path: "\(shot).png")
                try ImageFile.writePNG(image, to: file)
                print(file.path)
            } catch { print(error.localizedDescription); return 1 }
        }
        return 0
    }
}
