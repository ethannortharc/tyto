// 画 Tyto 的程序图标（1024×1024 PNG）。
//   swift scripts/make-icon.swift <样式> <输出.png>
// 样式：owl（仓鸮头像，石墨底）、line（线条仓鸮，石墨底）、line-light（线条仓鸮，象牙白底）、captions（字幕卡）
// 再用 scripts/build-icon.sh 转成 Resources/AppIcon.icns。
// 图形按 macOS 图标网格画：1024 画布里 824×824 的圆角方块，四周留 100 点给系统阴影。
import AppKit
import SwiftUI

let graphite = [Color(hex: 0x2B2A28), Color(hex: 0x151514)]
let ivory = Color(hex: 0xF1EADC)
let ink = Color(hex: 0x1B1A19)
let ochreAccent = Color(hex: 0xC97B3F)

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// 仓鸮的脸盘：上沿平、中间微微凹下去，两颊圆，往下收成下巴（不画成爱心那样深的凹口）
struct FacialDisc: Shape {
    func path(in rect: CGRect) -> Path {
        // 按 500×520 的设计稿画，再缩放到 rect
        let sx = rect.width / 500, sy = rect.height / 520
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy) }
        var path = Path()
        path.move(to: p(250, 52))
        path.addCurve(to: p(52, 40), control1: p(200, 12), control2: p(100, 6))
        path.addCurve(to: p(34, 318), control1: p(-2, 82), control2: p(-6, 220))
        path.addCurve(to: p(250, 520), control1: p(78, 420), control2: p(168, 492))
        path.addCurve(to: p(466, 318), control1: p(332, 492), control2: p(422, 420))
        path.addCurve(to: p(448, 40), control1: p(506, 220), control2: p(502, 82))
        path.addCurve(to: p(250, 52), control1: p(400, 6), control2: p(300, 12))
        path.closeSubpath()
        return path
    }
}

/// 脸盘中间那道竖脊，从上沿凹口到喙
struct Ridge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        return path
    }
}

struct Tile<Content: View>: View {
    let colors: [Color]
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 186, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            // 顶上一层很淡的高光，像玻璃的厚度
            shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center))
            content
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 3)
        }
        .frame(width: 824, height: 824)
        .clipShape(shape)
        .frame(width: 1024, height: 1024)
    }
}

/// 仓鸮头像：赭黄的头、象牙白的脸盘、中间一道脊、深色杏仁眼、浅色小喙
struct OwlFace: View {
    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [Color(hex: 0xCF9A62), Color(hex: 0xA9703D)], startPoint: .top, endPoint: .bottom))
                .frame(width: 640, height: 640)
                .offset(y: -6)
                .shadow(color: .black.opacity(0.3), radius: 20, y: 12)
            FacialDisc()
                .fill(LinearGradient(colors: [ivory, Color(hex: 0xE6DCCB)], startPoint: .top, endPoint: .bottom))
                .overlay(FacialDisc().stroke(Color(hex: 0x9C6A3C), lineWidth: 9))
                .frame(width: 500, height: 520)
                .offset(y: 26)
            Ridge().stroke(Color(hex: 0xD7C6AA), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 20, height: 190)
                .offset(y: 4)
            HStack(spacing: 118) {
                Ellipse().fill(ink).frame(width: 66, height: 60)
                Ellipse().fill(ink).frame(width: 66, height: 60)
            }
            .offset(y: 30)
            Capsule().fill(Color(hex: 0xCDAE86)).frame(width: 26, height: 58).offset(y: 118)
        }
    }
}

/// 线条仓鸮：一笔脸盘轮廓、一道脊、两点眼睛
struct LineOwl: View {
    let stroke: Color
    let eyes: Color

    var body: some View {
        ZStack {
            FacialDisc().stroke(stroke, style: StrokeStyle(lineWidth: 30, lineJoin: .round))
                .frame(width: 520, height: 540)
            Ridge().stroke(stroke, style: StrokeStyle(lineWidth: 22, lineCap: .round))
                .frame(width: 30, height: 250)
                .offset(y: -36)
            HStack(spacing: 150) {
                Circle().fill(eyes).frame(width: 66)
                Circle().fill(eyes).frame(width: 66)
            }
            .offset(y: 10)
        }
        .offset(y: 8)
    }
}

/// 字幕卡：悬浮窗本身——说话人头像、原文一行、译文一行（淡一点）
struct Captions: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 70, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 4))
                .frame(width: 560, height: 520)
                .offset(x: 40, y: -40)
            VStack(alignment: .leading, spacing: 64) {
                line(avatar: ochreAccent, first: 300, second: 220)
                line(avatar: Color(hex: 0x9DB4C8), first: 250, second: 180)
            }
            .offset(x: 10, y: 30)
        }
    }

    private func line(avatar: Color, first: CGFloat, second: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 34) {
            Circle().fill(avatar).frame(width: 92)
            VStack(alignment: .leading, spacing: 22) {
                Capsule().fill(ivory).frame(width: first, height: 44)
                Capsule().fill(ivory.opacity(0.42)).frame(width: second, height: 30)
            }
            .padding(.top, 8)
        }
    }
}

@MainActor
func render(_ style: String) -> NSImage? {
    let view: AnyView = switch style {
    case "owl": AnyView(Tile(colors: graphite) { OwlFace() })
    case "line": AnyView(Tile(colors: graphite) { LineOwl(stroke: ivory, eyes: ochreAccent) })
    case "line-light": AnyView(Tile(colors: [Color(hex: 0xF7F3EC), Color(hex: 0xE8E1D5)]) { LineOwl(stroke: ink, eyes: ochreAccent) })
    case "captions": AnyView(Tile(colors: graphite) { Captions() })
    default: AnyView(EmptyView())
    }
    let renderer = ImageRenderer(content: view.frame(width: 1024, height: 1024))
    renderer.scale = 1
    return renderer.nsImage
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("用法：swift scripts/make-icon.swift <owl|line|line-light|captions> <输出.png>")
    exit(1)
}
MainActor.assumeIsolated {
    guard let image = render(arguments[1]), let tiff = image.tiffRepresentation,
          let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
    else {
        print("不认识的样式：\(arguments[1])")
        exit(1)
    }
    try? png.write(to: URL(filePath: arguments[2]))
    print(arguments[2])
}
