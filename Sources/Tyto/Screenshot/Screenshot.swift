import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// 截屏回复用到的图片处理：框选截图、剪贴板里的图片、本机 OCR、缩图。
enum Screenshot {
    /// 系统的框选截图（和 ⌘⇧4 一样拖一块区域，Esc 取消）。截图本身要"屏幕录制"权限，第一次会弹窗。
    /// Tyto 的窗口不会出现在截图里（共享保护对截图同样生效）。
    static func captureInteractive() async -> Data? {
        let url = FileManager.default.temporaryDirectory.appending(path: "tyto-shot-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let status: Int32 = await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(filePath: "/usr/sbin/screencapture")
            process.arguments = ["-i", "-x", "-o", url.path]
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
        guard status == 0 else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 剪贴板里的图片（比如用 ⌘⌃⇧4 截到剪贴板），转成 PNG
    @MainActor
    static func clipboardImage() -> Data? {
        let pasteboard = NSPasteboard.general
        if let png = pasteboard.data(forType: .png) { return png }
        if let tiff = pasteboard.data(forType: .tiff), let bitmap = NSBitmapImageRep(data: tiff) {
            return bitmap.representation(using: .png, properties: [:])
        }
        if let url = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first,
           let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image),
           let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff) {
            return bitmap.representation(using: .png, properties: [:])
        }
        return nil
    }

    struct TextLine: Sendable {
        let text: String
        /// 归一化坐标（0～1），原点在左下
        let box: CGRect
    }

    /// 本机 OCR（Apple Vision 准确模式，中英文）。实测 M4 Pro：聊天窗口大小约 0.3 秒，整个 5K 屏约 0.6 秒。
    static func recognizeText(_ png: Data) async -> [TextLine] {
        guard let image = cgImage(png) else { return [] }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US", "ja-JP"].map { Locale.Language(identifier: $0) }
        request.usesLanguageCorrection = true
        guard let observations = try? await request.perform(on: image) else { return [] }
        return observations
            .compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return TextLine(text: text, box: observation.boundingBox.cgRect)
            }
            .sorted { $0.box.midY > $1.box.midY }
    }

    /// 给模型看的 OCR 文字：从上到下，标出每行在左半边还是右半边（聊天里一般右边是我发的）
    static func layoutText(_ lines: [TextLine]) -> String {
        lines.map { line in
            let side = line.box.midX < 0.42 ? "左" : line.box.midX > 0.58 ? "右" : "中"
            return "[\(side)] \(line.text)"
        }
        .joined(separator: "\n")
    }

    /// 发给模型前缩一下：长边不超过 2000 像素，文字仍然清楚，请求小很多
    static func forModel(_ png: Data) -> Data {
        resized(png, maxSide: 2_000) ?? png
    }

    /// 界面上显示的小图
    static func thumbnail(_ png: Data) -> Data? {
        resized(png, maxSide: 360)
    }

    static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    private static func resized(_ png: Data, maxSide: CGFloat) -> Data? {
        guard let image = cgImage(png) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(image.width, image.height)))
        guard scale < 1 else { return png }
        let width = Int(CGFloat(image.width) * scale)
        let height = Int(CGFloat(image.height) * scale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let output = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, output, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
