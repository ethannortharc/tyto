import AppKit
import CoreImage
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// 要截的那块屏幕。只放值，方便交给后台线程。
struct CaptureTarget: Sendable {
    let displayID: CGDirectDisplayID
    /// 屏幕在全局坐标里的位置（单位是点，原点在左下）
    let frame: CGRect
    let pixelWidth: Int
    let pixelHeight: Int
    /// screencapture -D 用的屏幕编号，从 1 开始
    let screencaptureIndex: Int

    @MainActor init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        displayID = number?.uint32Value ?? CGMainDisplayID()
        frame = screen.frame
        pixelWidth = Int(screen.frame.width * screen.backingScaleFactor)
        pixelHeight = Int(screen.frame.height * screen.backingScaleFactor)
        screencaptureIndex = (NSScreen.screens.firstIndex(of: screen) ?? 0) + 1
    }
}

/// 几种截屏方式。会议软件共享"整个屏幕"时用的就是 ScreenCaptureKit，
/// 但具体怎么建过滤条件各家不同，所以几种都试。
enum CaptureMethod: CaseIterable, Sendable {
    case screenshotExcludingWindows
    case screenshotExcludingApps
    case stream
    case screencaptureTool

    var title: String {
        switch self {
        case .screenshotExcludingWindows: "ScreenCaptureKit 截图（整屏，按窗口排除）"
        case .screenshotExcludingApps: "ScreenCaptureKit 截图（整屏，按应用排除）"
        case .stream: "ScreenCaptureKit 视频流（会议软件的做法）"
        case .screencaptureTool: "系统截图命令 screencapture"
        }
    }

    var fileName: String {
        switch self {
        case .screenshotExcludingWindows: "sck-screenshot-windows"
        case .screenshotExcludingApps: "sck-screenshot-apps"
        case .stream: "sck-stream"
        case .screencaptureTool: "screencapture"
        }
    }
}

enum ScreenGrabError: LocalizedError {
    case displayNotFound
    case noFrame
    case toolFailed(Int32)
    case unreadableImage
    case cannotWriteImage

    var errorDescription: String? {
        switch self {
        case .displayNotFound: "ScreenCaptureKit 里找不到这块屏幕"
        case .noFrame: "视频流两秒内没有送来完整的画面"
        case .toolFailed(let status): "screencapture 退出码 \(status)"
        case .unreadableImage: "读不了截图文件"
        case .cannotWriteImage: "存不了截图文件"
        }
    }
}

enum ScreenGrab {
    static func capture(_ method: CaptureMethod, target: CaptureTarget) async throws -> CGImage {
        switch method {
        case .screenshotExcludingWindows:
            let display = try await findDisplay(target.displayID)
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration(for: target))
        case .screenshotExcludingApps:
            let display = try await findDisplay(target.displayID)
            return try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, excludingApplications: [], exceptingWindows: []),
                configuration: configuration(for: target))
        case .stream:
            let display = try await findDisplay(target.displayID)
            return try await grabStreamFrame(
                filter: SCContentFilter(display: display, excludingWindows: []),
                configuration: configuration(for: target))
        case .screencaptureTool:
            return try await runScreencapture(displayIndex: target.screencaptureIndex)
        }
    }

    /// 会议软件让你选"共享哪个窗口"时，列表来自这里。
    static func isWindowListed(_ windowID: CGWindowID) async throws -> Bool {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.windows.contains { $0.windowID == windowID }
    }

    private static func findDisplay(_ id: CGDirectDisplayID) async throws -> SCDisplay {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw ScreenGrabError.displayNotFound
        }
        return display
    }

    private static func configuration(for target: CaptureTarget) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.width = target.pixelWidth
        config.height = target.pixelHeight
        config.showsCursor = false
        return config
    }

    /// 像会议软件那样开一条视频流，跑两秒后取最新的一帧。
    private static func grabStreamFrame(filter: SCContentFilter,
                                        configuration: SCStreamConfiguration) async throws -> CGImage {
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        let output = LatestFrame()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(output, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "tyto.sharecheck.stream"))
        try await stream.startCapture()
        try? await Task.sleep(for: .seconds(2))
        try? await stream.stopCapture()
        guard let image = output.image() else { throw ScreenGrabError.noFrame }
        return image
    }

    private static func runScreencapture(displayIndex: Int) async throws -> CGImage {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "tyto-sharecheck-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-x", "-D", String(displayIndex), url.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
        guard status == 0 else { throw ScreenGrabError.toolFailed(status) }
        guard let image = ImageFile.read(at: url) else { throw ScreenGrabError.unreadableImage }
        return image
    }
}

/// 视频流的输出：只留最新的一帧完整画面。
private final class LatestFrame: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .screen,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        lock.withLock { latest = pixelBuffer }
    }

    func image() -> CGImage? {
        guard let buffer = lock.withLock({ latest }) else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        return CIContext().createCGImage(ciImage, from: ciImage.extent)
    }
}

enum ImageFile {
    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw ScreenGrabError.cannotWriteImage }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ScreenGrabError.cannotWriteImage }
    }

    static func read(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
