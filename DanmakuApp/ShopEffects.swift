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

/// そのテーマの背景・弾・自機で、ゲームと同じ計算の渦巻きの弾幕が流れ続ける見本。
/// 大きさは実際のゲームと同じ比率(縦横同じ倍率)で、実際の画面(幅 360)の一部を中央に見せる
struct BulletBurstView: View {
    let theme: Theme
    @State private var engine = PatternDemoEngine(source: Point(x: 180, y: 120), player: Point(x: 180, y: 290), sweepPlayer: false)

    /// 5色の発射台が、同じ位置から回しながら撃つ渦巻き(Emitter の spiral)
    private static let emitters: [Emitter] = (0..<5).map { e in
        var m = Emitter.make(.swirl, end: 60)
        m.k = e; m.a = e * 72; m.c = 2; m.i = 0.09; m.v = 2; m.r = 15
        return m
    }

    var body: some View {
        let skin = Skin.of(theme)
        let images = SpriteFactory.bulletImages(theme)
        let ship = SpriteFactory.shipImage(theme)
        VisibleTimeline(interval: 1.0 / 30.0) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                engine.advance(to: timeline.date, emitters: Self.emitters, key: 0)
                // 見せる範囲の高さ(論理px)を枠に合わせる。幅 360 の画面を、枠の中央に置く
                let s = size.height / CGFloat(PatternDemoEngine.fieldHeight)
                let ox = (size.width - 360 * s) / 2
                // 背景
                let full = Path(CGRect(origin: .zero, size: size))
                let c = CGPoint(x: size.width * 0.5, y: engine.source.y * s)
                let glow = Gradient(colors: [Color(skin.star).opacity(0.95), Color(skin.background)])
                ctx.fill(full, with: .radialGradient(glow, center: c, startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
                // またたく星
                for i in 0..<24 {
                    let fx = fract(sin(Double(i) * 12.9898) * 43758.5453)
                    let fy = fract(sin(Double(i) * 78.233) * 12543.1)
                    let tw = 0.5 + 0.5 * sin(t * 2 + Double(i))
                    let d = CGFloat(1.5 + 2 * fract(Double(i) * 0.37)) * s * 2
                    let rect = CGRect(x: CGFloat(fx) * size.width, y: CGFloat(fy) * size.height, width: d, height: d)
                    ctx.fill(Path(ellipseIn: rect), with: .color(Color(skin.star).opacity(0.3 + 0.7 * tw)))
                }
                // 実際の画面の幅(360)の範囲。弾はこの外に出ると消える
                ctx.stroke(Path(CGRect(x: ox, y: 0, width: 360 * s, height: size.height)), with: .color(.white.opacity(0.12)), lineWidth: 1)
                // 弾(ゲームと同じ 12×12)
                let bs = 12 * s
                for b in engine.bullets {
                    ctx.draw(Image(uiImage: images[b.color % images.count]), in: CGRect(x: ox + b.x * s - bs / 2, y: b.y * s - bs / 2, width: bs, height: bs))
                }
                // ボス(中サイズの 48)と自機(20×24)
                let bossSide = EnemyArt.bossPoints(size: 1) * s
                let bossRect = CGRect(x: ox + engine.source.x * s - bossSide / 2, y: engine.source.y * s - bossSide / 2, width: bossSide, height: bossSide)
                ctx.fill(GameBossShape().path(in: bossRect), with: .color(GameStyle.pinkColor), style: FillStyle(eoFill: true))
                let p = engine.player
                ctx.draw(Image(uiImage: ship), in: CGRect(x: ox + p.x * s - 10 * s, y: p.y * s - 12 * s, width: 20 * s, height: 24 * s))
            }
        }
    }
}

/// 撃ち方ごとの、自機からボスへ向かう弾の見本。実際のゲームと同じ速さ・間隔・広がりで、縦横同じ倍率で描く
struct ShotPreviewView: View {
    let shot: ShotType

    var body: some View {
        let ship = SpriteFactory.shipImage(.classic)
        VisibleTimeline(interval: 1.0 / 30.0) { timeline in
            Canvas { ctx, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                // ゲームの画面は 360 幅。自機とボスの距離は、実際のゲームと同じ 約362(ボスは高さ18%、自機は85%の位置)
                let dist = 362.0
                let sc = min(Double(size.width) / 360.0, Double(size.height) * 0.78 / dist)
                let shipP = CGPoint(x: size.width * 0.5, y: size.height - 14)
                let bossP = CGPoint(x: size.width * 0.5, y: shipP.y - CGFloat(dist * sc))
                let life = dist / 600.0                      // 弾がボスに届くまでの時間(秒)
                let k1 = Int(floor(t / shot.interval))
                let k0 = k1 - Int(life / shot.interval) - 1
                for k in k0...k1 {
                    let age = t - Double(k) * shot.interval
                    if age < 0 || age > life { continue }
                    for v in shot.volley {
                        let x = Double(shipP.x) + (v.dx + v.vx * age) * sc
                        let y = Double(shipP.y) - 10 * sc - 600 * age * sc
                        let heavy = v.damage > 1
                        // ゲームの弾の大きさ(通常 3×10、ヘビー 6×14)。小さくなりすぎないように、見えるだけ太くする
                        let w = max(2.0, (heavy ? 6 : 3) * sc * 1.6), h = max(5.0, (heavy ? 14 : 10) * sc * 1.6)
                        let color: Color = heavy ? GameStyle.cyanColor : GameStyle.yellow
                        ctx.fill(Path(roundedRect: CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h), cornerRadius: 1.5), with: .color(color))
                    }
                }
                // ボスの当たる範囲(中)と同じ大きさ
                let r = DanmakuConfig.bossRadii[1] * sc
                let bossRect = CGRect(x: bossP.x - r, y: bossP.y - r, width: r * 2, height: r * 2)
                ctx.fill(GameBossShape().path(in: bossRect), with: .color(GameStyle.pinkColor), style: FillStyle(eoFill: true))
                ctx.draw(Image(uiImage: ship), in: CGRect(x: shipP.x - 10 * sc * 1.2, y: shipP.y - 12 * sc * 1.2, width: 20 * sc * 1.2, height: 24 * sc * 1.2))
            }
        }
    }
}

/// 画面に映っている間だけ動くアニメ(TimelineView と同じ使い方)。ショップやエディタには、動く見本が何十個も並ぶので、
/// 映っていないぶんは止めて、一覧を開いたときや、スクロールしたときに重くならないようにする
struct VisibleTimeline<Content: View>: View {
    let interval: Double
    @ViewBuilder let content: (TimelineViewDefaultContext) -> Content
    /// 画面に出ている数(onDisappear が、次の onAppear より後に届くことがあるため、真偽ではなく数で持つ。0 なら止める)
    @State private var shown = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: interval, paused: shown <= 0), content: content)
            .onAppear { shown += 1 }
            .onDisappear { shown = max(0, shown - 1) }
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
