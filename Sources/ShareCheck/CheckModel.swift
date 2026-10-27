import AppKit
import SwiftUI

struct CaptureResult: Identifiable, Codable {
    var id: String { method }
    let method: String
    let verdict: String
    var overlayVisible: Bool?
    var controlVisible: Bool?
    var imagePath: String?
    var error: String?

    init(method: String, overlayVisible: Bool?, controlVisible: Bool?, imagePath: String) {
        self.method = method
        self.overlayVisible = overlayVisible
        self.controlVisible = controlVisible
        self.imagePath = imagePath
        verdict = switch (controlVisible, overlayVisible) {
        case (nil, _), (_, nil): "未判断，请看截图"
        case (false?, _): "无效：截图里也没有对照窗口（检查屏幕录制权限）"
        case (true?, true?): "❌ 悬浮窗被截到了"
        case (true?, false?): "✅ 悬浮窗被隐藏"
        }
    }

    init(method: String, error: String) {
        self.method = method
        self.error = error
        verdict = "出错：\(error)"
    }
}

struct CheckReport: Codable {
    let date: Date
    let macOS: String
    let overlayProtected: Bool
    let overlayListed: Bool?
    let note: String
    let results: [CaptureResult]
}

@MainActor
final class CheckModel: ObservableObject {
    weak var overlay: NSPanel?
    weak var controlWindow: NSWindow?

    @Published var protectOverlay = true {
        didSet { overlay?.sharingType = protectOverlay ? .none : .readOnly }
    }
    @Published var clickThrough = false {
        didSet { overlay?.ignoresMouseEvents = clickThrough }
    }
    @Published private(set) var running = false
    @Published private(set) var results: [CaptureResult] = []
    @Published private(set) var overlayListed: Bool?
    @Published private(set) var note = ""
    @Published private(set) var lastOutputFolder: URL?

    func runSelfCheck() async {
        guard let overlay, let controlWindow, let screen = overlay.screen else {
            note = "找不到悬浮窗所在的屏幕。"
            return
        }
        guard controlWindow.screen == screen else {
            note = "请把对照窗口拖到悬浮窗所在的那块屏幕上，再自检。"
            return
        }
        guard !overlay.frame.intersects(controlWindow.frame) else {
            note = "悬浮窗和对照窗口重叠了，先把它们拖开，再自检。"
            return
        }

        let folder: URL
        do {
            folder = try Self.makeOutputFolder()
        } catch {
            note = "建不了截图文件夹：\(error.localizedDescription)"
            return
        }

        running = true
        defer { running = false }
        results = []
        note = "正在截屏…"

        let target = CaptureTarget(screen: screen)
        let overlayRect = overlay.frame
        let controlRect = controlWindow.frame
        overlayListed = try? await ScreenGrab.isWindowListed(CGWindowID(overlay.windowNumber))

        for method in CaptureMethod.allCases {
            do {
                let image = try await ScreenGrab.capture(method, target: target)
                let url = folder.appending(path: "\(method.fileName).png")
                try ImageFile.writePNG(image, to: url)
                let overlayRegion = PixelRegion(image: image, screenRect: overlayRect, screenFrame: target.frame)
                let controlRegion = PixelRegion(image: image, screenRect: controlRect, screenFrame: target.frame)
                results.append(CaptureResult(
                    method: method.title,
                    overlayVisible: overlayRegion.flatMap(markerVisible(in:)),
                    controlVisible: controlRegion.flatMap(markerVisible(in:)),
                    imagePath: url.path))
            } catch {
                results.append(CaptureResult(method: method.title, error: error.localizedDescription))
            }
        }

        lastOutputFolder = folder
        note = "截图存在 \(folder.path)"
        writeReport(to: folder)
    }

    func openOutputFolder() {
        if let lastOutputFolder { NSWorkspace.shared.open(lastOutputFolder) }
    }

    private func writeReport(to folder: URL) {
        let report = CheckReport(date: .now,
                                 macOS: ProcessInfo.processInfo.operatingSystemVersionString,
                                 overlayProtected: protectOverlay,
                                 overlayListed: overlayListed,
                                 note: note,
                                 results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(report) else { return }
        try? data.write(to: folder.appending(path: "report.json"))
        try? data.write(to: folder.deletingLastPathComponent().appending(path: "latest.json"))
    }

    /// ~/Library/Application Support/Tyto/share-check/<时间>/
    private static func makeOutputFolder() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let folder = URL.applicationSupportDirectory
            .appending(path: "Tyto/share-check/\(formatter.string(from: .now))")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
