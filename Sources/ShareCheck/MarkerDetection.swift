import CoreGraphics

/// 截图里某个窗口所在的那一块，已经统一转成 sRGB、每个通道 8 位。
struct PixelRegion {
    let width: Int
    let height: Int
    /// 每个像素 4 个字节：r, g, b, a，按行排列
    let rgba: [UInt8]
    /// 标记块在这张截图里应该占多少个像素（截图可能比屏幕分辨率低，按实际缩放算）
    let expectedMarkerPixels: Int

    var pixelCount: Int { width * height }

    func rgb(at index: Int) -> (r: Int, g: Int, b: Int) {
        let i = index * 4
        return (Int(rgba[i]), Int(rgba[i + 1]), Int(rgba[i + 2]))
    }

    /// - screenRect: 窗口在全局坐标里的位置（点，原点在左下）
    /// - screenFrame: 截图对应的那块屏幕在全局坐标里的位置
    init?(image: CGImage, screenRect: CGRect, screenFrame: CGRect) {
        let scale = CGFloat(image.width) / screenFrame.width
        // 截图的原点在左上，要把 y 翻过来
        let crop = CGRect(x: (screenRect.minX - screenFrame.minX) * scale,
                          y: (screenFrame.maxY - screenRect.maxY) * scale,
                          width: screenRect.width * scale,
                          height: screenRect.height * scale)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard !crop.isEmpty, let part = image.cropping(to: crop),
              let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        let w = part.width, h = part.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(part, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }

        let side = Int((Marker.size * scale).rounded())
        width = w
        height = h
        rgba = buffer
        expectedMarkerPixels = side * side
    }
}

/// 判断截图里这个窗口的区域中，有没有出现品红色标记块 (255, 0, 255)。
///
/// - 返回 true：看见了标记，说明这个窗口被截进去了。
/// - 返回 false：没看见。
/// - 返回 nil：判断不了。
///
/// 要权衡的：
/// - 颜色不会正好是 (255, 0, 255)：截图要经过显示器色彩空间（多半是 Display P3）转换，
///   视频流还可能有压缩，所以要留容差。
/// - 视频流的分辨率可能比屏幕低，标记块的像素数会变少，
///   所以门槛用 region.expectedMarkerPixels 的比例来定，别写死一个数。
/// - 门槛太低，偶然出现的品红色像素会误报"被截到"；
///   门槛太高，标记被别的窗口挡住一部分时会漏报，让人误以为"隐藏成功"。
///   对这个工具来说，哪种错更要不得？
func markerVisible(in region: PixelRegion) -> Bool? {
    guard region.pixelCount > 0, region.expectedMarkerPixels > 0 else { return nil }
    var hits = 0
    for index in 0..<region.pixelCount {
        let pixel = region.rgb(at: index)
        // 红、蓝都高，绿低。实测截图里是精确的 (255, 0, 255)，容差留给视频流的色彩转换。
        if pixel.r > 200, pixel.b > 200, pixel.g < 70 { hits += 1 }
    }
    // 露出四分之一就算看见：宁可误报"被截到"，也不能把露出来的窗口判成"隐藏成功"。
    return hits * 4 >= region.expectedMarkerPixels
}
