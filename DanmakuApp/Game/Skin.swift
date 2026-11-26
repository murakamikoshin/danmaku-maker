import SpriteKit
import DanmakuCore

/// テーマごとの見た目。当たり判定や計算には一切関わらない
enum BulletShape { case circle, petal, bubble, diamond, star }
enum ShipShape { case arrow, wings, manta, star }

struct Skin {
    var bulletColors: [UIColor]
    var bulletShape: BulletShape
    var background: UIColor
    var star: UIColor
    var shipColor: UIColor
    var shipShape: ShipShape

    /// 弾の色(6つ: テーマの5色と、1.4.3 からの黒っぽい暗い色)。暗い色は、背景に溶けないよう明るい縁をつけて描く(SpriteFactory)
    static func of(_ theme: Theme) -> Skin {
        var s = base(theme)
        s.bulletColors.append(UIColor(hex: darkBullet(theme)))
        return s
    }

    /// 黒っぽい暗い色(サーバーの palette.ts の6つ目と同じ値)
    static func darkBullet(_ theme: Theme) -> UInt32 {
        switch theme {
        case .classic: return 0x2A1838
        case .sakura: return 0x3D1028
        case .ocean: return 0x0B2238
        case .aurora: return 0x10261C
        case .gold: return 0x2E2208
        case .neon: return 0x1A0A2E
        case .rainbow: return 0x1C1C2C
        case .xmas: return 0x2A0C12
        }
    }

    /// 縁をつける暗い色か(明るさが低い色)
    static func isDark(_ c: UIColor) -> Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        c.getRed(&r, green: &g, blue: &b, alpha: &a)
        return 0.299 * r + 0.587 * g + 0.114 * b < 0.25
    }

    private static func base(_ theme: Theme) -> Skin {
        switch theme {
        case .classic:
            return Skin(bulletColors: Palette.bullets, bulletShape: .circle, background: Palette.background, star: Palette.star,
                        shipColor: UIColor(hex: 0x5CE1E6), shipShape: .arrow)
        case .sakura:
            return Skin(bulletColors: [0xFF8FB8, 0xFFC4DD, 0xFF5C8A, 0xFFB38A, 0xF2E6FF].map { UIColor(hex: $0) }, bulletShape: .petal,
                        background: UIColor(hex: 0x1A0A14), star: UIColor(hex: 0x6B3A55),
                        shipColor: UIColor(hex: 0xFFB3D1), shipShape: .wings)
        case .ocean:
            return Skin(bulletColors: [0x3DD6D0, 0x5AA9FF, 0x9FE8FF, 0x2F6FE0, 0x7CF2C8].map { UIColor(hex: $0) }, bulletShape: .bubble,
                        background: UIColor(hex: 0x04101F), star: UIColor(hex: 0x1F4A78),
                        shipColor: UIColor(hex: 0x7CF2C8), shipShape: .manta)
        case .aurora:
            return Skin(bulletColors: [0x7CF29C, 0xB28DFF, 0x5CE1E6, 0xE8FF7A, 0xFF8AE2].map { UIColor(hex: $0) }, bulletShape: .diamond,
                        background: UIColor(hex: 0x07120F), star: UIColor(hex: 0x2E5C46),
                        shipColor: UIColor(hex: 0xB28DFF), shipShape: .star)
        case .gold:
            return Skin(bulletColors: [0xFFD54A, 0xFFB300, 0xFFF0A0, 0xFF8F00, 0xFFE082].map { UIColor(hex: $0) }, bulletShape: .star,
                        background: UIColor(hex: 0x1A1405), star: UIColor(hex: 0x6B5420),
                        shipColor: UIColor(hex: 0xFFD54A), shipShape: .wings)
        case .neon:
            return Skin(bulletColors: [0xFF2E93, 0x00F0FF, 0xB6FF00, 0xFF9E00, 0x9D4DFF].map { UIColor(hex: $0) }, bulletShape: .diamond,
                        background: UIColor(hex: 0x06001A), star: UIColor(hex: 0x3A1F6B),
                        shipColor: UIColor(hex: 0x00F0FF), shipShape: .arrow)
        case .xmas:
            // クリスマス(1.5.0): 赤・緑・金・白・水色の星の弾。深い緑がかった夜に、雪の色の星
            return Skin(bulletColors: [0xE83A3A, 0x3FC46B, 0xFFD54A, 0xF4F8FF, 0x8FD8FF].map { UIColor(hex: $0) }, bulletShape: .star,
                        background: UIColor(hex: 0x08141C), star: UIColor(hex: 0x4A6A80),
                        shipColor: UIColor(hex: 0xE83A3A), shipShape: .star)
        case .rainbow:
            return Skin(bulletColors: [0xFF5C5C, 0xFFB347, 0xFFF06A, 0x6CE08A, 0x6AA8FF].map { UIColor(hex: $0) }, bulletShape: .petal,
                        background: UIColor(hex: 0x0B0B1E), star: UIColor(hex: 0x35356B),
                        shipColor: UIColor(hex: 0xFFFFFF), shipShape: .manta)
        }
    }
}

/// 画面に出す名前（String Catalog のキー）
extension Theme {
    var nameKey: String { "theme.\(rawValue)" }
}
extension ThemePart {
    var nameKey: String { "part.\(rawValue)" }
}
extension ShotType {
    var nameKey: String { "shot.\(rawValue)" }
    var detailKey: String { "shot.\(rawValue).detail" }
}
