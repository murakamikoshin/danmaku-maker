import SpriteKit
import UIKit
import DanmakuCore

/// ボスと雑魚(発射点にいる小さな敵)の見た目。種類は 0〜4(0 が標準)。大きさは小・中・大の3段階。
/// 見た目と大きさだけで、計算には関わらない。ただしボスの大きさは、弾が当たる範囲(DanmakuConfig.bossRadii)と同じ比率にする
enum EnemyArt {
    static let looks = DanmakuConfig.enemyLooks
    /// エディタで選べるボスの見た目の番号。専用の絵を持つボスは、課金などの仕組みができるまで開発用ビルドだけ
    static var bossLookChoices: [Int] {
        Array(0..<BossCharacter.firstCharacterLook) + (BossCharacter.editorEnabled ? BossCharacter.allCases.map(\.rawValue) : [])
    }

    /// ボスの絵の一辺(ポイント)。当たる半径の2倍にそろえて、見た目と当たり判定がずれないようにする
    static func bossPoints(size: Int) -> CGFloat { CGFloat(DanmakuConfig.bossRadii[min(max(size, 0), 2)] * 2) }
    /// 雑魚の絵の一辺(ポイント)。見た目だけ
    static func mookPoints(size: Int) -> CGFloat { [18, 26, 36][min(max(size, 0), 2)] }

    private static var cache: [String: UIImage] = [:]

    private static func render(points: CGFloat, _ draw: (CGContext, CGFloat) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let size = CGSize(width: points, height: points)
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext, points) }
    }

    static func bossImage(look: Int, size: Int, flash: Bool) -> UIImage {
        // 専用の絵を持つボス: エディタの選択肢・プレビュー用に、1コマ目の絵を返す
        if let c = BossCharacter.of(look: look), let art = BossSprites.art(c, awakened: false) { return art.still }
        let key = "b\(look).\(size).\(flash)"
        if let c = cache[key] { return c }
        let color = flash ? UIColor.white : Palette.pink
        let accent = flash ? UIColor.white : Palette.background
        let img = render(points: bossPoints(size: size)) { c, s in
            let u = s / 48   // 48 を基準に描いて、大きさに合わせて拡大する
            c.scaleBy(x: u, y: u)
            c.setFillColor(color.cgColor)
            switch look {
            case 1: // 目玉
                c.fillEllipse(in: CGRect(x: 2, y: 8, width: 44, height: 32))
                c.setFillColor(flash ? UIColor.white.cgColor : UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: 10, y: 13, width: 28, height: 22))
                c.setFillColor(flash ? UIColor(white: 0.8, alpha: 1).cgColor : Palette.bullets[1].cgColor)
                c.fillEllipse(in: CGRect(x: 17, y: 16, width: 14, height: 16))
                c.setFillColor(accent.cgColor)
                c.fillEllipse(in: CGRect(x: 21, y: 20, width: 6, height: 8))
            case 2: // クリスタル
                poly(c, [(24, 1), (44, 16), (36, 46), (12, 46), (4, 16)])
                c.setFillColor(accent.withAlphaComponent(0.35).cgColor)
                poly(c, [(24, 1), (36, 46), (24, 30)])
                c.setFillColor(accent.cgColor)
                c.fillEllipse(in: CGRect(x: 19, y: 19, width: 10, height: 10))
            case 3: // 円盤
                c.fillEllipse(in: CGRect(x: 2, y: 20, width: 44, height: 18))
                c.setFillColor((flash ? UIColor.white : Palette.bullets[1]).cgColor)
                c.fillEllipse(in: CGRect(x: 14, y: 8, width: 20, height: 20))
                c.setFillColor(accent.cgColor)
                for i in 0..<4 { c.fillEllipse(in: CGRect(x: 9 + Double(i) * 9.5, y: 27, width: 4, height: 4)) }
            case 4: // とげとげ
                var pts: [(Double, Double)] = []
                for i in 0..<16 {
                    let a = Double(i) * Double.pi / 8
                    let r: Double = i % 2 == 0 ? 23 : 12
                    pts.append((24 + cos(a) * r, 24 + sin(a) * r))
                }
                poly(c, pts)
                c.setFillColor(accent.cgColor)
                c.fillEllipse(in: CGRect(x: 17, y: 17, width: 14, height: 14))
            default: // 標準(歯車の花)
                for i in 0..<12 {
                    let a = Double(i) * Double.pi / 6
                    let r: Double = i % 2 == 1 ? 14 : 22
                    let p = CGPoint(x: 24 + cos(a) * r, y: 24 + sin(a) * r)
                    i == 0 ? c.move(to: p) : c.addLine(to: p)
                }
                c.closePath(); c.fillPath()
                c.setFillColor(accent.cgColor)
                c.fillEllipse(in: CGRect(x: 17, y: 17, width: 14, height: 14))
            }
        }
        cache[key] = img
        return img
    }

    static func mookImage(look: Int, size: Int) -> UIImage {
        let key = "m\(look).\(size)"
        if let c = cache[key] { return c }
        let body = Palette.bullets[1]
        let dark = Palette.background
        let img = render(points: mookPoints(size: size)) { c, s in
            let u = s / 32
            c.scaleBy(x: u, y: u)
            c.setFillColor(body.cgColor)
            switch look {
            case 1: // 円盤
                c.fillEllipse(in: CGRect(x: 1, y: 14, width: 30, height: 12))
                c.setFillColor(Palette.bullets[2].cgColor)
                c.fillEllipse(in: CGRect(x: 9, y: 6, width: 14, height: 14))
            case 2: // コウモリ
                poly(c, [(16, 8), (22, 12), (31, 6), (28, 20), (22, 18), (16, 28), (10, 18), (4, 20), (1, 6), (10, 12)])
                c.setFillColor(dark.cgColor)
                c.fillEllipse(in: CGRect(x: 11, y: 13, width: 3, height: 3)); c.fillEllipse(in: CGRect(x: 18, y: 13, width: 3, height: 3))
            case 3: // とげ玉
                var pts: [(Double, Double)] = []
                for i in 0..<12 {
                    let a = Double(i) * Double.pi / 6
                    let r: Double = i % 2 == 0 ? 15 : 9
                    pts.append((16 + cos(a) * r, 16 + sin(a) * r))
                }
                poly(c, pts)
                c.setFillColor(dark.cgColor)
                c.fillEllipse(in: CGRect(x: 11, y: 12, width: 4, height: 4)); c.fillEllipse(in: CGRect(x: 18, y: 12, width: 4, height: 4))
            case 4: // おばけ
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 3, y: 30))
                p.addLine(to: CGPoint(x: 3, y: 14))
                p.addCurve(to: CGPoint(x: 29, y: 14), control1: CGPoint(x: 3, y: -4), control2: CGPoint(x: 29, y: -4))
                p.addLine(to: CGPoint(x: 29, y: 30))
                p.addLine(to: CGPoint(x: 23, y: 25)); p.addLine(to: CGPoint(x: 16, y: 30)); p.addLine(to: CGPoint(x: 9, y: 25))
                p.closeSubpath()
                c.addPath(p); c.fillPath()
                c.setFillColor(dark.cgColor)
                c.fillEllipse(in: CGRect(x: 9, y: 11, width: 4, height: 5)); c.fillEllipse(in: CGRect(x: 19, y: 11, width: 4, height: 5))
            default: // 標準(まるい子)
                c.fillEllipse(in: CGRect(x: 2, y: 4, width: 28, height: 24))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: 8, y: 11, width: 6, height: 7)); c.fillEllipse(in: CGRect(x: 18, y: 11, width: 6, height: 7))
                c.setFillColor(dark.cgColor)
                c.fillEllipse(in: CGRect(x: 10, y: 13, width: 3, height: 4)); c.fillEllipse(in: CGRect(x: 20, y: 13, width: 3, height: 4))
            }
        }
        cache[key] = img
        return img
    }

    private static func poly(_ c: CGContext, _ pts: [(Double, Double)]) {
        for (i, p) in pts.enumerated() {
            let q = CGPoint(x: p.0, y: p.1)
            i == 0 ? c.move(to: q) : c.addLine(to: q)
        }
        c.closePath(); c.fillPath()
    }
}
