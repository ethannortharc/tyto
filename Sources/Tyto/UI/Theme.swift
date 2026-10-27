import SwiftUI

/// 悬浮窗的配色。底子都是深色玻璃（盖在会议视频上也看得清），区别在色调和强调色。
enum ThemeID: String, Codable, CaseIterable, Identifiable {
    case obsidian
    case aurora
    case champagne

    var id: String { rawValue }
    var label: String {
        switch self {
        case .obsidian: "曜石：石墨底，青紫强调"
        case .aurora: "极光：深蓝底，青绿强调"
        case .champagne: "香槟：暖黑底，金色强调"
        }
    }
}

struct OverlayTheme {
    let id: ThemeID
    /// 玻璃的底色
    let tint: Color
    let accent: Color
    let accentEnd: Color
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

    var accentGradient: LinearGradient {
        LinearGradient(colors: [accent, accentEnd], startPoint: .leading, endPoint: .trailing)
    }

    static func of(_ id: ThemeID) -> OverlayTheme {
        switch id {
        case .obsidian:
            OverlayTheme(
                id: id,
                tint: Color(red: 0.05, green: 0.055, blue: 0.07),
                accent: Color(red: 0.36, green: 0.80, blue: 1.0),
                accentEnd: Color(red: 0.62, green: 0.50, blue: 1.0),
                remote: [Color(red: 0.42, green: 0.80, blue: 1.0), Color(red: 0.70, green: 0.60, blue: 1.0),
                         Color(red: 0.32, green: 0.88, blue: 0.80)],
                local: [Color(red: 0.48, green: 0.93, blue: 0.64), Color(red: 1.0, green: 0.76, blue: 0.38),
                        Color(red: 1.0, green: 0.55, blue: 0.65)],
                number: Color(red: 1.0, green: 0.80, blue: 0.40),
                entity: Color(red: 0.58, green: 0.84, blue: 1.0),
                keyword: Color(red: 1.0, green: 0.48, blue: 0.78),
                translation: Color(red: 0.80, green: 0.83, blue: 0.92))
        case .aurora:
            OverlayTheme(
                id: id,
                tint: Color(red: 0.02, green: 0.06, blue: 0.13),
                accent: Color(red: 0.30, green: 0.96, blue: 0.74),
                accentEnd: Color(red: 0.22, green: 0.70, blue: 1.0),
                remote: [Color(red: 0.38, green: 0.90, blue: 1.0), Color(red: 0.62, green: 0.68, blue: 1.0),
                         Color(red: 0.45, green: 1.0, blue: 0.72)],
                local: [Color(red: 0.78, green: 1.0, blue: 0.48), Color(red: 1.0, green: 0.62, blue: 0.52),
                        Color(red: 0.88, green: 0.68, blue: 1.0)],
                number: Color(red: 1.0, green: 0.86, blue: 0.42),
                entity: Color(red: 0.48, green: 0.96, blue: 1.0),
                keyword: Color(red: 1.0, green: 0.52, blue: 0.86),
                translation: Color(red: 0.76, green: 0.89, blue: 0.93))
        case .champagne:
            OverlayTheme(
                id: id,
                tint: Color(red: 0.09, green: 0.075, blue: 0.06),
                accent: Color(red: 0.98, green: 0.82, blue: 0.50),
                accentEnd: Color(red: 0.95, green: 0.60, blue: 0.48),
                remote: [Color(red: 0.98, green: 0.82, blue: 0.52), Color(red: 0.92, green: 0.70, blue: 0.56),
                         Color(red: 0.80, green: 0.78, blue: 0.95)],
                local: [Color(red: 0.70, green: 0.90, blue: 0.66), Color(red: 0.62, green: 0.82, blue: 1.0),
                        Color(red: 1.0, green: 0.66, blue: 0.70)],
                number: Color(red: 1.0, green: 0.72, blue: 0.42),
                entity: Color(red: 0.72, green: 0.86, blue: 1.0),
                keyword: Color(red: 1.0, green: 0.56, blue: 0.56),
                translation: Color(red: 0.93, green: 0.87, blue: 0.79))
        }
    }

    func color(for row: Utterance) -> Color {
        let palette = row.channel == .remote ? remote : local
        // 说话人编号从 1 开始，说话人 1 用第一个颜色
        return palette[max(0, (row.speaker ?? 1) - 1) % palette.count]
    }
}

/// 悬浮窗的底：macOS 26 的玻璃（真模糊后面的画面），压一层主题色保证文字看得清，再加一圈细的高光描边。
struct GlassBackground: View {
    let theme: OverlayTheme
    let opacity: Double
    /// 画预览图时为 true：ImageRenderer 画不出系统玻璃，只画底色（模糊由预览自己叠在下面）
    var flat = false
    var cornerRadius: CGFloat = 22

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack {
            if !flat {
                // 系统玻璃几乎不理会染色的透明度，所以玻璃本身不染色，深浅靠上面单独一层底色。
                // 拉到最左时换成更清透的玻璃，磨砂感更少。
                Color.clear.glassEffect(opacity < 0.05 ? .clear : .regular, in: shape)
            }
            shape.fill(theme.tint.opacity(opacity))
            shape.fill(LinearGradient(colors: [theme.accent.opacity(0.08), .clear], startPoint: .top, endPoint: .center))
            shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.24), .white.opacity(0.05)],
                                              startPoint: .top, endPoint: .bottom), lineWidth: 1)
        }
    }
}
