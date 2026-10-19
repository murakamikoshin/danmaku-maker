import SwiftUI
import UIKit
import DanmakuCore

// ショップとタブで使う、ゲームの部品の形と、動く見本

/// ゲームの自機と同じ三角形(20x24 の絵を、枠に合わせて拡大)
struct GameShipShape: Shape {
    func path(in r: CGRect) -> Path {
        let u = min(r.width / 20, r.height / 24)
        let ox = r.midX - 10 * u, oy = r.midY - 12 * u
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * u, y: oy + y * u) }
        var p = Path()
        p.move(to: pt(10, 1)); p.addLine(to: pt(18, 20)); p.addLine(to: pt(10, 16)); p.addLine(to: pt(2, 20))
        p.closeSubpath()
        return p
    }
}

/// ゲームのボスと同じ星(頂点12個、中央に穴)。塗るときは eoFill: true にする
struct GameBossShape: Shape {
    func path(in r: CGRect) -> Path {
        let u = min(r.width, r.height) / 48
        let c = CGPoint(x: r.midX, y: r.midY)
        var p = Path()
        for i in 0..<12 {
            let a = Double(i) * Double.pi / 6
            let rad = CGFloat(i % 2 == 1 ? 14 : 22) * u
            let pt = CGPoint(x: c.x + CGFloat(cos(a)) * rad, y: c.y + CGFloat(sin(a)) * rad)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        p.addEllipse(in: CGRect(x: c.x - 7 * u, y: c.y - 7 * u, width: 14 * u, height: 14 * u))
        return p
    }
}

private func fract(_ x: Double) -> Double { x - floor(x) }

/// そのテーマの背景・弾・自機で、ゲームと同じ渦巻きの弾幕が流れ続ける見本
struct BulletBurstView: View {
    let theme: Theme

    var body: some View {
        let skin = Skin.of(theme)
        let images = SpriteFactory.bulletImages(theme)
        let ship = SpriteFactory.shipImage(theme)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let s = min(size.width, size.height * 1.7) / 240
                let c = CGPoint(x: size.width * 0.5, y: size.height * 0.42)
                // 背景
                let full = Path(CGRect(origin: .zero, size: size))
                let glow = Gradient(colors: [Color(skin.star).opacity(0.95), Color(skin.background)])
                ctx.fill(full, with: .radialGradient(glow, center: c, startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
                // またたく星
                for i in 0..<24 {
                    let fx = fract(sin(Double(i) * 12.9898) * 43758.5453)
                    let fy = fract(sin(Double(i) * 78.233) * 12543.1)
                    let tw = 0.5 + 0.5 * sin(t * 2 + Double(i))
                    let d = CGFloat(1.5 + 2 * fract(Double(i) * 0.37)) * s
                    let rect = CGRect(x: CGFloat(fx) * size.width, y: CGFloat(fy) * size.height, width: d, height: d)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color(skin.star).opacity(0.3 + 0.7 * tw)))
                }
                // 渦巻きの弾(5色の発射台が、同じ位置から回しながら撃つ)
                let interval = 0.09, ageMax = 1.7, speed = 62.0
                let k1 = Int(floor(t / interval))
                let k0 = k1 - Int(ageMax / interval)
                let bs = 12.0 * s * 1.1
                for k in k0...k1 {
                    let age = t - Double(k) * interval
                    if age < 0 || age > ageMax { continue }
                    let r = speed * age * s * 1.25
                    for e in 0..<5 {
                        for j in 0..<2 {
                            let deg = Double(e) * 72 + Double(j) * 180 + Double(k) * 15
                            let a = deg * Double.pi / 180
                            let x = c.x + CGFloat(cos(a) * r)
                            let y = c.y + CGFloat(sin(a) * r) * 0.9
                            if x < -bs || x > size.width + bs || y < -bs || y > size.height + bs { continue }
                            ctx.draw(Image(uiImage: images[e]), in: CGRect(x: x - bs / 2, y: y - bs / 2, width: bs, height: bs))
                        }
                    }
                }
                // ボスと自機
                let bossSide = 44 * s
                let bossRect = CGRect(x: c.x - bossSide / 2, y: c.y - bossSide / 2, width: bossSide, height: bossSide)
                ctx.fill(GameBossShape().path(in: bossRect), with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                let sw = 20 * s * 1.3, sh = 24 * s * 1.3
                ctx.draw(Image(uiImage: ship), in: CGRect(x: size.width * 0.5 - sw / 2, y: size.height * 0.88 - sh / 2, width: sw, height: sh))
            }
        }
    }
}

/// 撃ち方ごとの、自機からボスへ向かう弾の見本
struct ShotPreviewView: View {
    let shot: ShotType

    var body: some View {
        let ship = SpriteFactory.shipImage(.classic)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let shipP = CGPoint(x: size.width * 0.5, y: size.height * 0.86)
                let bossP = CGPoint(x: size.width * 0.5, y: size.height * 0.2)
                let sc = (shipP.y - bossP.y) / 362.0            // 実際の距離(約362)を、見本の大きさに縮める
                let life = 362.0 / 600.0
                let k1 = Int(floor(t / shot.interval))
                let k0 = k1 - Int(life / shot.interval) - 1
                for k in k0...k1 {
                    let age = t - Double(k) * shot.interval
                    if age < 0 || age > life { continue }
                    for v in shot.volley {
                        let x = shipP.x + CGFloat(v.dx + v.vx * age * 3.2) * 1.4
                        let y = shipP.y - CGFloat(600 * age) * sc
                        let heavy = v.damage > 1
                        let w: CGFloat = heavy ? 7 : 3, h: CGFloat = heavy ? 16 : 9
                        let color: Color = heavy ? Color(UIColor(hex: 0x5CE1E6)) : Color(Palette.gold)
                        ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: 1.5), with: .color(color))
                    }
                }
                let bossRect = CGRect(x: bossP.x - 15, y: bossP.y - 15, width: 30, height: 30)
                ctx.fill(GameBossShape().path(in: bossRect), with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                ctx.draw(Image(uiImage: ship), in: CGRect(x: shipP.x - 8, y: shipP.y - 10, width: 16, height: 20))
            }
        }
    }
}

/// 買ったときの紙吹雪
struct ConfettiView: View {
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSince(start)
                for i in 0..<110 {
                    let fi = Double(i)
                    let x0 = fract(sin(fi * 91.7) * 43758.5) * Double(size.width)
                    let drift = (fract(sin(fi * 12.3) * 999.1) - 0.5) * 90
                    let fall = 160 + fract(sin(fi * 7.7) * 5555.5) * 240
                    let y = -24 + fall * t
                    if y > Double(size.height) + 24 { continue }
                    let x = x0 + drift * t + sin(t * 4 + fi) * 14
                    var c = ctx
                    c.translateBy(x: CGFloat(x), y: CGFloat(y))
                    c.rotate(by: .radians(t * (3 + fract(fi * 0.17) * 5) + fi))
                    let col = Color(Palette.bullets[i % Palette.bullets.count])
                    c.fill(Path(CGRect(x: -4, y: -2.5, width: 8, height: 5)), with: .color(col))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
