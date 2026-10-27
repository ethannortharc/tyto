import SwiftUI

/// 悬浮窗的配色。底子都是深色玻璃（盖在会议视频上也看得清），区别在色调和强调色。
/// 只用一个强调色、不用渐变，说话人和高亮的颜色都压低饱和度，看起来像个工具而不是霓虹灯。
/// 原始值沿用最早的三个主题名，已经存下的设置不用迁移。
enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case graphite = "obsidian"
    case celadon = "aurora"
    case ochre = "champagne"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .graphite: tr("石墨：中性深灰，象牙白强调", "Graphite: neutral gray, ivory accent")
        case .celadon: tr("釉青：墨绿灰底，青瓷色强调", "Celadon: ink green, celadon accent")
        case .ochre: tr("赭石：暖炭底，赭橙强调", "Ochre: warm charcoal, ochre accent")
        }
    }
}

struct OverlayTheme {
    let id: ThemeID
    /// 浅色：悬浮窗盖在亮的画面上时，用浅色玻璃配黑字
    var light = false
    /// 玻璃的底色
    let tint: Color
    /// 唯一的强调色：主按钮、选中、回复卡片的竖条
    let accent: Color
    /// 强调色上的文字
    let onAccent: Color
    /// 远端说话人的颜色，按说话人编号轮换
    let remote: [Color]
    /// 本地说话人的颜色
    let local: [Color]
    /// 高亮：数字、日期、金额
    let number: Color
    /// 高亮：人名、地名、机构
    let entity: Color
    /// 高亮：会话里设的关键词
    let keyword: Color
    let translation: Color

    /// 正文颜色；次要的文字、图标、分隔线都用它加透明度
    var ink: Color { light ? Self.rgb(0x1C1B1A) : .white }
    /// 文字外面那圈细阴影：深色时是黑影，浅色时是白晕
    var halo: Color { light ? .white : .black }

    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static func of(_ id: ThemeID, light: Bool = false) -> OverlayTheme {
        light ? lightVariant(id) : dark(id)
    }

    /// 浅色版：底是纸一样的浅色，强调色和说话人颜色都压深，在白底上也够对比度
    private static func lightVariant(_ id: ThemeID) -> OverlayTheme {
        switch id {
        case .graphite:
            OverlayTheme(
                id: id, light: true,
                tint: rgb(0xF4F2EE),
                accent: rgb(0x2B2A28),
                onAccent: rgb(0xF4F2EE),
                remote: [rgb(0x3D6584), rgb(0x2E6C64), rgb(0x76663A)],
                local: [rgb(0x4A6E3E), rgb(0x9C4F37), rgb(0x86661F)],
                number: rgb(0x9A5F14),
                entity: rgb(0x38566F),
                keyword: rgb(0x1C1B1A),
                translation: rgb(0x5C5954))
        case .celadon:
            OverlayTheme(
                id: id, light: true,
                tint: rgb(0xEEF4F1),
                accent: rgb(0x2B6B55),
                onAccent: rgb(0xF1F7F4),
                remote: [rgb(0x2E6177), rgb(0x2B6B55), rgb(0x6C6842)],
                local: [rgb(0x87611F), rgb(0x974F43), rgb(0x526D37)],
                number: rgb(0x956515),
                entity: rgb(0x2E6177),
                keyword: rgb(0x2B6B55),
                translation: rgb(0x55625C))
        case .ochre:
            OverlayTheme(
                id: id, light: true,
                tint: rgb(0xF6EFE8),
                accent: rgb(0xB0561F),
                onAccent: rgb(0xFFF7EF),
                remote: [rgb(0x43617A), rgb(0x4B6B41), rgb(0x776541)],
                local: [rgb(0xA5501F), rgb(0x86661F), rgb(0x914C4C)],
                number: rgb(0x955F14),
                entity: rgb(0x43617A),
                keyword: rgb(0xB0561F),
                translation: rgb(0x675A4D))
        }
    }

    private static func dark(_ id: ThemeID) -> OverlayTheme {
        switch id {
        case .graphite:
            OverlayTheme(
                id: id,
                tint: rgb(0x131314),
                accent: rgb(0xECE5D8),
                onAccent: rgb(0x1A1918),
                remote: [rgb(0x9DB4C8), rgb(0x8FBFB6), rgb(0xC4BB9E)],
                local: [rgb(0xA9C49A), rgb(0xD9A088), rgb(0xD8C08C)],
                number: rgb(0xE2BC7E),
                entity: rgb(0xB9C8D6),
                keyword: rgb(0xF2EBDD),
                translation: rgb(0xB4B1AB))
        case .celadon:
            OverlayTheme(
                id: id,
                tint: rgb(0x0C1513),
                accent: rgb(0x9CCBB6),
                onAccent: rgb(0x0E1A16),
                remote: [rgb(0x96BFCB), rgb(0x9CCBB6), rgb(0xC2C1A6)],
                local: [rgb(0xDDBB84), rgb(0xD69C8E), rgb(0xB9C79A)],
                number: rgb(0xE3C285),
                entity: rgb(0xA9CCD6),
                keyword: rgb(0xB5DDCB),
                translation: rgb(0xAEBBB5))
        case .ochre:
            OverlayTheme(
                id: id,
                tint: rgb(0x16120F),
                accent: rgb(0xE4935F),
                onAccent: rgb(0x1C120B),
                remote: [rgb(0xA4B6C6), rgb(0xA9C29F), rgb(0xCDBFA2)],
                local: [rgb(0xE4A27A), rgb(0xE0C38C), rgb(0xD39C9C)],
                number: rgb(0xEAC88A),
                entity: rgb(0xB4C4D2),
                keyword: rgb(0xF0A878),
                translation: rgb(0xC2B6AA))
        }
    }

    func color(for row: Utterance) -> Color {
        let palette = row.channel == .remote ? remote : local
        // 说话人编号从 1 开始，说话人 1 用第一个颜色
        return palette[max(0, (row.speaker ?? 1) - 1) % palette.count]
    }
}

/// 悬浮窗的底。底色浓度 opacity（0～0.95）分三段：
/// - 0：什么都没有，完全透明，只剩文字（文字自带阴影）和一圈很淡的边；
/// - 0～0.25：玻璃逐渐出现（清透的那种）；
/// - 0.25 以上：玻璃上再叠主题底色，越往右越深，0.4 以上换成磨砂玻璃。
/// 系统玻璃几乎不理会染色的透明度，所以深浅靠单独一层底色。
struct GlassBackground: View {
    let theme: OverlayTheme
    let opacity: Double
    /// 画预览图时为 true：ImageRenderer 画不出系统玻璃，只画底色（模糊由预览自己叠在下面）
    var flat = false
    var cornerRadius: CGFloat = 22

    static let glassFullAt = 0.25

    var glassAmount: Double { min(1, opacity / Self.glassFullAt) }
    var tintAmount: Double { max(0, (opacity - Self.glassFullAt) / (0.95 - Self.glassFullAt)) * 0.9 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if !flat, glassAmount > 0 {
                Color.clear
                    .glassEffect(opacity < 0.4 ? .clear : .regular, in: shape)
                    .opacity(glassAmount)
            }
            shape.fill(theme.tint.opacity(flat ? max(tintAmount, opacity * 0.5) : tintAmount))
            if opacity > 0.1 {
                // 顶部一层很淡的反光，让玻璃有厚度
                shape.fill(LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center))
            }
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.24 * max(0.45, glassAmount)), .white.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
            if theme.light {
                shape.strokeBorder(Color.black.opacity(0.10), lineWidth: 0.5)
            }
        }
    }

    /// 背景越透明，文字阴影越重，盖在亮的画面上也看得清
    static func textShadow(_ opacity: Double) -> Double {
        min(0.9, max(0, 0.6 - opacity) * 1.4 + (opacity < 0.08 ? 0.15 : 0))
    }
}
