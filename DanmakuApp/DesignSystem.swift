import SwiftUI
import UIKit
import DanmakuCore

// アプリ全体の見た目の決まり(色・字体・形)。テーマは 3 つ(アーケード・幻想・従来)で、設定で選べる。下の説明は、アーケード。
// 従来は、一新する前の見た目(角の丸い札・ピンクのグラデーションのボタン・丸ゴシック)。これだけは、ぼかした影を使う
//
// - 形: 角は丸めず、ドット絵の角(2 段の階段)にする(ボスや自機のドット絵に合わせる)。`PixelRect`
// - 色: ぼかした光やグラデーションは使わず、べた塗り。いちばん大事なボタンと「選択中」は黄色に黒い文字
// - 厚み: ボタンや札は、下に 4pt の濃い色を敷いて、押せる厚みを出す。`KeyCap`
// - 字体: 見出し・ボタン・大きい数字は Dela Gothic One(`Font.display`)。小さい文字と、
//   プレイヤーが付けた名前(ステージ名・作者名)は、どの言語でも読めるように標準の字体のまま

/// メニューの見た目のテーマ。設定で選べる
enum UITheme: String, CaseIterable {
    /// 一新する前の見た目(角の丸い札・ピンクのグラデーションのボタン・丸ゴシック)。はじめの設定
    case classic
    /// ドット絵の角・黄色のボタン・太いゴシック
    case arcade
    /// 斜めに落とした角・金と朱・明朝の見出し
    case gensou

    var titleKey: String { "settings.theme.\(rawValue)" }

    private static let key = "ui.theme"

    /// 今のテーマ。色や字体は、ここを見て決まる(変えたら、画面全体を作り直す。`UIThemeStore`)
    static var current: UITheme {
        get { stored }
        set { stored = newValue; UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    private static var stored: UITheme = load()

    private static func load() -> UITheme {
        #if DEBUG
        // 画面確認用: -ui-theme gensou
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ui-theme"), args.indices.contains(i + 1), let t = UITheme(rawValue: args[i + 1]) { return t }
        #endif
        return UserDefaults.standard.string(forKey: key).flatMap { UITheme(rawValue: $0) } ?? .classic   // はじめは従来(いまの本番の見た目)。新しいテーマは、設定で選ぶ
    }
}

/// テーマの切り替え。変わると、いちばん外側の画面を作り直して、すべての色と字体を新しくする
final class UIThemeStore: ObservableObject {
    static let shared = UIThemeStore()
    @Published private(set) var theme = UITheme.current
    /// 作り直した直後に、設定のタブへ戻すための印(テーマは設定の画面で変えるので)
    private var returnToSettings = false

    func select(_ t: UITheme) {
        guard t != theme else { return }
        UITheme.current = t
        returnToSettings = true
        theme = t
    }

    func consumeReturnToSettings() -> Bool {
        defer { returnToSettings = false }
        return returnToSettings
    }
}

enum GameStyle {
    static var classic: Bool { UITheme.current == .classic }
    private static func pick(_ arcade: UInt32, _ gensouHex: UInt32, _ classicHex: UInt32? = nil) -> Color {
        switch UITheme.current {
        case .arcade: return Color(UIColor(hex: arcade))
        case .gensou: return Color(UIColor(hex: gensouHex))
        case .classic: return Color(UIColor(hex: classicHex ?? arcade))
        }
    }

    /// 画面の地の色
    static var night: Color { pick(0x0A0818, 0x0B0E22) }
    /// 地より一段暗い面(下のタブ・見出しの絵の後ろ)
    static var nightDeep: Color { pick(0x0D0B1F, 0x080A1A) }
    /// 主役の色(黄・金)の上に乗せる文字の色
    static var ink: Color { pick(0x0A0818, 0x14101C, 0xFFFFFF) }
    static var text: Color { pick(0xEFEAFF, 0xF4EEDD) }
    static var panel: Color { pick(0x16132E, 0x151935, 0x1C1740) }
    /// パネルの上に乗せる、一段明るい面(選べる札・入力欄など)
    static var panelHi: Color { pick(0x231F4A, 0x21264D, 0x2A2358) }
    static var edge: Color { pick(0x35306A, 0x4A4368, 0x3A3568) }
    static var dim: Color { pick(0xA49DCB, 0xA9A7C4) }
    /// 主役の色: いちばん大事なボタンと「選択中」。アーケードは黄色、幻想は金
    static var yellow: Color { pick(0xFFD23F, 0xE6BE6A, 0xFF6B9D) }
    /// 脇役の色: ボス・ハート・注意。アーケードはピンク、幻想は朱
    static var pinkColor: Color { pick(0xFF6B9D, 0xE8554E) }
    static var cyanColor: Color { pick(0x5CE1E6, 0x7FD3CF) }
    static var green: Color { pick(0x7CF29C, 0x9AD8A0) }
    static var violet: Color { pick(0xB28DFF, 0xB7A3F2) }
    /// 厚みのある文字の、下に敷く濃い色
    static var yellowShade: Color { pick(0x9A4A12, 0x6E4F1C, 0x8E2148) }
    static var pinkShade: Color { pick(0x8E2148, 0x7A2226) }

    /// べた塗り(以前はグラデーションだった。呼び出し側の型を変えないため、同じ色 2 つのグラデーションにしてある)
    static func solid(_ c: Color) -> LinearGradient { LinearGradient(colors: [c, c], startPoint: .leading, endPoint: .trailing) }
    /// いちばん大事なボタン・選択中
    static var accent: LinearGradient { classic ? grad(0xFF6B9D, 0xFF8A5C) : solid(yellow) }
    static var cyan: LinearGradient { classic ? grad(0x5CE1E6, 0x5C8AFF) : solid(cyanColor) }
    static var gold: LinearGradient { classic ? grad(0xFFD23F, 0xFF9F5C) : solid(yellow) }
    /// 広告を見てもらう・無料でもらう
    static var reward: LinearGradient { classic ? grad(0x7CF29C, 0x5CE1A6) : solid(green) }
    /// 従来のテーマだけが使う、2 色のグラデーション
    private static func grad(_ a: UInt32, _ b: UInt32) -> LinearGradient {
        LinearGradient(colors: [Color(UIColor(hex: a)), Color(UIColor(hex: b))], startPoint: .leading, endPoint: .trailing)
    }

    /// クリア条件ごとの色(4つとも、どのテーマでも違う色にする)
    static func tint(_ mode: Mode) -> Color {
        switch mode {
        case .survive: return cyanColor
        case .boss: return pinkColor
        // テーマ「従来」の yellow はピンク(ボスと同じ色になる)なので、ダメージ勝負は金色にする
        case .damage: return pick(0xFFD23F, 0xE6BE6A, 0xFFD23F)
        case .sequence: return violet
        }
    }

    /// 端末の言語
    static let language: String = Bundle.main.preferredLocalizations.first ?? "ja"
}

extension Font {
    /// 見出し・ボタン・大きい数字の字体。
    /// アーケード: Dela Gothic One(韓国語・中国語は文字が足りないので、標準の太字)。
    /// 幻想: 明朝(日本語はヒラギノ明朝、ほかの言語は標準のセリフ体)
    static func display(_ size: CGFloat) -> Font {
        let lang = GameStyle.language
        switch UITheme.current {
        case .arcade:
            return lang.hasPrefix("ko") || lang.hasPrefix("zh") ? .system(size: size, weight: .black) : .custom("DelaGothicOne-Regular", fixedSize: size)
        case .gensou:
            return lang.hasPrefix("ja") ? .custom("HiraMinProN-W6", fixedSize: size * 1.06) : .system(size: size, weight: .heavy, design: .serif)
        case .classic:
            return .system(size: size, weight: .heavy, design: .rounded)
        }
    }
}

/// 角を落とした四角。アーケードは 2 段の階段(ドット絵の角)、幻想は斜め。`RoundedRectangle(cornerRadius:)` と同じ書き方で使える
struct PixelRect: InsettableShape {
    var cornerRadius: CGFloat
    private var insetAmount: CGFloat = 0

    init(cornerRadius: CGFloat) { self.cornerRadius = cornerRadius }

    /// 階段 1 段の大きさ。小さい部品ほど細かく、ごく小さいもの(細い棒など)は、ただの四角
    private func unit(in r: CGRect) -> CGFloat {
        if cornerRadius < 4 { return 0 }
        let u: CGFloat = cornerRadius >= 14 ? 3 : (cornerRadius >= 8 ? 2 : 1.5)
        return min(u, min(r.width, r.height) / 6)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard r.width > 0, r.height > 0 else { return Path() }
        // 従来: ふつうの丸い角
        if UITheme.current == .classic { return RoundedRectangle(cornerRadius: cornerRadius).path(in: r) }
        let u = unit(in: r)
        guard u > 0 else { return Path(r) }
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        var p = Path()
        if UITheme.current == .gensou {
            // 幻想: 角を斜めに落とす(額やお札の形)
            let k = u * 2.5
            p.move(to: CGPoint(x: x0 + k, y: y0))
            p.addLine(to: CGPoint(x: x1 - k, y: y0))
            p.addLine(to: CGPoint(x: x1, y: y0 + k))
            p.addLine(to: CGPoint(x: x1, y: y1 - k))
            p.addLine(to: CGPoint(x: x1 - k, y: y1))
            p.addLine(to: CGPoint(x: x0 + k, y: y1))
            p.addLine(to: CGPoint(x: x0, y: y1 - k))
            p.addLine(to: CGPoint(x: x0, y: y0 + k))
            p.closeSubpath()
            return p
        }
        p.move(to: CGPoint(x: x0 + 2 * u, y: y0))
        p.addLine(to: CGPoint(x: x1 - 2 * u, y: y0))
        p.addLine(to: CGPoint(x: x1 - 2 * u, y: y0 + u))
        p.addLine(to: CGPoint(x: x1 - u, y: y0 + u))
        p.addLine(to: CGPoint(x: x1 - u, y: y0 + 2 * u))
        p.addLine(to: CGPoint(x: x1, y: y0 + 2 * u))
        p.addLine(to: CGPoint(x: x1, y: y1 - 2 * u))
        p.addLine(to: CGPoint(x: x1 - u, y: y1 - 2 * u))
        p.addLine(to: CGPoint(x: x1 - u, y: y1 - u))
        p.addLine(to: CGPoint(x: x1 - 2 * u, y: y1 - u))
        p.addLine(to: CGPoint(x: x1 - 2 * u, y: y1))
        p.addLine(to: CGPoint(x: x0 + 2 * u, y: y1))
        p.addLine(to: CGPoint(x: x0 + 2 * u, y: y1 - u))
        p.addLine(to: CGPoint(x: x0 + u, y: y1 - u))
        p.addLine(to: CGPoint(x: x0 + u, y: y1 - 2 * u))
        p.addLine(to: CGPoint(x: x0, y: y1 - 2 * u))
        p.addLine(to: CGPoint(x: x0, y: y0 + 2 * u))
        p.addLine(to: CGPoint(x: x0 + u, y: y0 + 2 * u))
        p.addLine(to: CGPoint(x: x0 + u, y: y0 + u))
        p.addLine(to: CGPoint(x: x0 + 2 * u, y: y0 + u))
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> PixelRect {
        var s = self
        s.insetAmount += amount
        return s
    }
}

/// 厚みのあるボタンの面: 上の面と、その下に敷いた濃い色(ぼかさない影)
struct KeyCap<S: ShapeStyle>: View {
    let fill: S
    var radius: CGFloat = 14
    var depth: CGFloat = 4

    var body: some View {
        let shape = PixelRect(cornerRadius: radius)
        if UITheme.current == .classic {
            // 従来: 厚みではなく、ふちの白い線とぼかした影
            shape.fill(fill)
                .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        } else {
        ZStack {
            shape.fill(fill).offset(y: depth)
            shape.fill(Color.black.opacity(0.4)).offset(y: depth)
            shape.fill(fill)
        }
        }
    }
}

extension View {
    /// 板(パネル): べた塗りと、2pt のふち
    func gamePanel(radius: CGFloat = 16, fill: Color = GameStyle.panel, edge: Color = GameStyle.edge, lineWidth: CGFloat = 2) -> some View {
        background(fill, in: PixelRect(cornerRadius: radius))
            .overlay(PixelRect(cornerRadius: radius).strokeBorder(edge, lineWidth: lineWidth))
    }

    /// 札の下に落とす、ぼかさない影
    func hardShadow(radius: CGFloat = 16, depth: CGFloat = 4, color: Color = Color.black.opacity(0.55)) -> some View {
        Group {
            if UITheme.current == .classic { shadow(color: .black.opacity(0.3), radius: 6, y: 3) }
            else { background(PixelRect(cornerRadius: radius).fill(color).offset(y: depth)) }
        }
    }

    /// 文字の下に濃い色をずらして重ね、厚みを出す(ロゴ・結果の見出し)。色は、ここで付ける
    func thick(_ front: Color, shade: Color, depth: CGFloat = 3) -> some View {
        Group {
            if UITheme.current == .classic {
                self.foregroundStyle(front)
            } else {
                ZStack {
                    self.foregroundStyle(shade).offset(y: depth).accessibilityHidden(true)
                    self.foregroundStyle(front)
                }
            }
        }
    }

    /// 黄色のボタン面(小さめのボタン・値段など)。文字は黒
    func keyCap<S: ShapeStyle>(_ fill: S = GameStyle.yellow, radius: CGFloat = 10, depth: CGFloat = 3) -> some View {
        foregroundStyle(GameStyle.ink)
            .background(KeyCap(fill: fill, radius: radius, depth: depth))
            .padding(.bottom, depth)
    }
}

/// クリア条件の絵(自機・ボスの形)。色を 1 色で指定できる(黄色の札の上では黒、など)
struct ModeGlyph: View {
    let mode: Mode
    var size: CGFloat = 30
    /// nil なら、クリア条件の色
    var color: Color? = nil
    /// 自機の芯・稲妻の色
    var core: Color = .white

    var body: some View {
        let c = color ?? GameStyle.tint(mode)
        ZStack {
            switch mode {
            case .survive:
                ZStack {
                    GameShipShape().fill(c)
                    Circle().fill(core).frame(width: size * 0.2, height: size * 0.2).offset(y: size * 0.08)
                }
                .frame(width: size * 0.76, height: size * 0.9)
            case .boss:
                GameBossShape().fill(c, style: FillStyle(eoFill: true)).frame(width: size, height: size)
            case .sequence:
                ZStack {
                    GameBossShape().fill(c.opacity(0.55), style: FillStyle(eoFill: true))
                        .frame(width: size * 0.8, height: size * 0.8).offset(x: size * 0.18, y: size * 0.12)
                    GameBossShape().fill(c, style: FillStyle(eoFill: true))
                        .frame(width: size * 0.72, height: size * 0.72).offset(x: -size * 0.2, y: -size * 0.1)
                }
            case .damage:
                ZStack {
                    GameBossShape().fill(c, style: FillStyle(eoFill: true)).frame(width: size, height: size)
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.36, weight: .black)).foregroundStyle(core)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
