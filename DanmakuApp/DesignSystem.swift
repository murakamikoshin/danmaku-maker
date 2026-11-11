import SwiftUI
import UIKit
import DanmakuCore

// アプリ全体の見た目の決まり(色・字体・形)。
//
// - 形: 角は丸めず、ドット絵の角(2 段の階段)にする(ボスや自機のドット絵に合わせる)。`PixelRect`
// - 色: ぼかした光やグラデーションは使わず、べた塗り。いちばん大事なボタンと「選択中」は黄色に黒い文字
// - 厚み: ボタンや札は、下に 4pt の濃い色を敷いて、押せる厚みを出す。`KeyCap`
// - 字体: 見出し・ボタン・大きい数字は Dela Gothic One(`Font.display`)。小さい文字と、
//   プレイヤーが付けた名前(ステージ名・作者名)は、どの言語でも読めるように標準の字体のまま

enum GameStyle {
    /// 黄色の上に乗せる文字の色(背景と同じ、黒に近い紺)
    static let ink = Color(Palette.background)
    static let panel = Color(UIColor(hex: 0x16132E))
    /// パネルの上に乗せる、一段明るい面(選べる札・入力欄など)
    static let panelHi = Color(UIColor(hex: 0x231F4A))
    static let edge = Color(UIColor(hex: 0x35306A))
    static let dim = Color(UIColor(hex: 0xA49DCB))
    static let yellow = Color(Palette.gold)
    static let pinkColor = Color(Palette.pink)
    static let cyanColor = Color(UIColor(hex: 0x5CE1E6))
    static let green = Color(Palette.bullets[4])
    static let violet = Color(Palette.bullets[3])
    /// 厚みのある文字の、下に敷く濃い色
    static let yellowShade = Color(UIColor(hex: 0x9A4A12))
    static let pinkShade = Color(UIColor(hex: 0x8E2148))

    /// べた塗り(以前はグラデーションだった。呼び出し側の型を変えないため、同じ色 2 つのグラデーションにしてある)
    static func solid(_ c: Color) -> LinearGradient { LinearGradient(colors: [c, c], startPoint: .leading, endPoint: .trailing) }
    /// いちばん大事なボタン・選択中
    static let accent = solid(yellow)
    static let cyan = solid(cyanColor)
    static let gold = solid(yellow)
    /// 広告を見てもらう・無料でもらう
    static let reward = solid(green)

    /// クリア条件ごとの色
    static func tint(_ mode: Mode) -> Color {
        switch mode {
        case .survive: return cyanColor
        case .boss: return pinkColor
        case .damage: return yellow
        case .sequence: return violet
        }
    }

    /// 見出しの字体(Dela Gothic One)が使える言語か。韓国語・中国語は文字が足りないので、標準の太字にする
    static let usesDisplayFont: Bool = {
        let lang = Bundle.main.preferredLocalizations.first ?? "ja"
        return !(lang.hasPrefix("ko") || lang.hasPrefix("zh"))
    }()
}

extension Font {
    /// 見出し・ボタン・大きい数字の字体
    static func display(_ size: CGFloat) -> Font {
        GameStyle.usesDisplayFont ? .custom("DelaGothicOne-Regular", fixedSize: size) : .system(size: size, weight: .black)
    }
}

/// ドット絵の角の四角(角を 2 段の階段で落とす)。`RoundedRectangle(cornerRadius:)` と同じ書き方で使える
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
        let u = unit(in: r)
        guard u > 0 else { return Path(r) }
        let x0 = r.minX, x1 = r.maxX, y0 = r.minY, y1 = r.maxY
        var p = Path()
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
        ZStack {
            shape.fill(fill).offset(y: depth)
            shape.fill(Color.black.opacity(0.4)).offset(y: depth)
            shape.fill(fill)
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
        background(PixelRect(cornerRadius: radius).fill(color).offset(y: depth))
    }

    /// 文字の下に濃い色をずらして重ね、厚みを出す(ロゴ・結果の見出し)。色は、ここで付ける
    func thick(_ front: Color, shade: Color, depth: CGFloat = 3) -> some View {
        ZStack {
            self.foregroundStyle(shade).offset(y: depth).accessibilityHidden(true)
            self.foregroundStyle(front)
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
