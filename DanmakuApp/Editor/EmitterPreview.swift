import SwiftUI
import DanmakuCore

/// 発射台カード用のループプレビュー。DanmakuCore の emit をそのまま使い、ダミー自機が左右に動く
final class PreviewEngine {
    static let height = 330.0
    private var t = 0.0
    private var next = 0.0
    private var shot = 0
    private var rng = Mulberry32(seed: 1)
    private var last: Date?
    private(set) var bullets: [Bullet] = []
    private(set) var player = Point(x: 180, y: PreviewEngine.height - 40)

    func advance(to now: Date, emitter m: Emitter, boss: Bool) {
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        t += dt
        player = Point(x: 180 + sin(t * 0.9) * 90, y: PreviewEngine.height - 40)
        let cx = boss ? 180 : m.x * DanmakuConfig.width
        let cy = boss ? DanmakuConfig.height * 0.18 : m.y * DanmakuConfig.height
        while t >= next {
            Emit.emit(m, shot: shot, cx: cx, cy: cy, px: player.x, py: player.y, rng: &rng, into: &bullets)
            shot += 1
            next += max(0.05, m.i)
        }
        var w = 0
        for i in 0..<bullets.count {
            var b = bullets[i]
            b.x += b.vx * dt; b.y += b.vy * dt
            if b.x < -20 || b.x > DanmakuConfig.width + 20 || b.y < -20 || b.y > PreviewEngine.height + 20 { continue }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
    }
}

struct EmitterPreview: View {
    let emitter: Emitter
    let isBoss: Bool
    @State private var engine = PreviewEngine()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                engine.advance(to: timeline.date, emitter: emitter, boss: isBoss)
                let s = size.width / DanmakuConfig.width
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(Palette.background)))
                ctx.scaleBy(x: s, y: s)
                drawSource(&ctx)
                drawShip(&ctx, engine.player)
                for b in engine.bullets {
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 6, y: b.y - 6, width: 12, height: 12)),
                             with: .color(Color(Palette.bullets[b.color])))
                }
                for b in engine.bullets {
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 3, y: b.y - 3, width: 6, height: 6)), with: .color(.white))
                }
            }
        }
        .aspectRatio(DanmakuConfig.width / PreviewEngine.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func drawSource(_ ctx: inout GraphicsContext) {
        if isBoss {
            var p = Path()
            let c = CGPoint(x: 180, y: DanmakuConfig.height * 0.18)
            for i in 0..<12 {
                let a = Double(i) * .pi / 6, r: Double = i % 2 == 1 ? 14 : 22
                let pt = CGPoint(x: c.x + cos(a) * r, y: c.y + sin(a) * r)
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.closeSubpath()
            ctx.fill(p, with: .color(Color(Palette.pink)))
        } else if emitter.t != .rain {
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - 8)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + 8)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y)); p.closeSubpath()
            ctx.stroke(p, with: .color(Color(Palette.bullets[emitter.k])), lineWidth: 2)
        }
    }

    private func drawShip(_ ctx: inout GraphicsContext, _ pt: Point) {
        var p = Path()
        p.move(to: CGPoint(x: pt.x, y: pt.y - 11)); p.addLine(to: CGPoint(x: pt.x + 8, y: pt.y + 8))
        p.addLine(to: CGPoint(x: pt.x, y: pt.y + 4)); p.addLine(to: CGPoint(x: pt.x - 8, y: pt.y + 8)); p.closeSubpath()
        ctx.fill(p, with: .color(Color(UIColor(hex: 0x5CE1E6))))
        ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(.white))
    }
}
