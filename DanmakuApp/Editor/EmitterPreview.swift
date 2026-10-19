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
        let atBoss = boss && !m.firesFromPoint
        let cx = atBoss ? 180 : m.x * DanmakuConfig.width
        let cy = atBoss ? DanmakuConfig.height * 0.18 : m.y * DanmakuConfig.height
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
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        // いま装備している見た目(弾の色と形・背景・自機・自分の画像)を、そのまま使う
        let _ = cosmetics.customImageRevision
        let look = cosmetics.effective
        let bulletTheme = look.bullets
        let skin = Skin.of(bulletTheme)
        let bg = Skin.of(look.background)
        let bulletImages = SpriteFactory.bulletImages(bulletTheme)
        let customBullet = look.customBullet ? CustomImageStore.load(.bullet) : nil
        let shipImage = (look.customShip ? CustomImageStore.load(.ship) : nil) ?? SpriteFactory.shipImage(look.ship)
        let bossImage = look.customBoss ? CustomImageStore.load(.boss) : nil
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                engine.advance(to: timeline.date, emitter: emitter, boss: isBoss)
                let s = size.width / DanmakuConfig.width
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(bg.background)))
                ctx.scaleBy(x: s, y: s)
                drawSource(&ctx, skin: skin, bossImage: bossImage)
                // 自機(当たる場所の白い点つき)
                let sw: CGFloat = 20, sh: CGFloat = 24
                let pt = engine.player
                let shipRect = CGRect(x: pt.x - sw / 2, y: pt.y - sh / 2, width: look.customShip ? 24 : sw, height: look.customShip ? 24 : sh)
                    .offsetBy(dx: look.customShip ? -2 : 0, dy: look.customShip ? 0 : 0)
                ctx.draw(Image(uiImage: shipImage), in: shipRect)
                if look.customShip { ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(.white)) }
                // 弾
                for b in engine.bullets {
                    let rect = CGRect(x: b.x - 6, y: b.y - 6, width: 12, height: 12)
                    if let customBullet { ctx.draw(Image(uiImage: customBullet), in: rect) }
                    else { ctx.draw(Image(uiImage: bulletImages[min(max(b.color, 0), bulletImages.count - 1)]), in: rect) }
                }
            }
        }
        .aspectRatio(DanmakuConfig.width / PreviewEngine.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func drawSource(_ ctx: inout GraphicsContext, skin: Skin, bossImage: UIImage?) {
        if isBoss {
            if let bossImage {
                ctx.draw(Image(uiImage: bossImage), in: CGRect(x: 180 - 24, y: DanmakuConfig.height * 0.18 - 24, width: 48, height: 48))
            } else {
                let c = CGPoint(x: 180, y: DanmakuConfig.height * 0.18)
                ctx.fill(GameBossShape().path(in: CGRect(x: c.x - 24, y: c.y - 24, width: 48, height: 48)), with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
            }
        }
        if (!isBoss || emitter.firesFromPoint) && ![.rain, .sideL, .sideR, .corner].contains(emitter.t) {
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - 8)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + 8)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y)); p.closeSubpath()
            ctx.stroke(p, with: .color(Color(skin.bulletColors[min(max(emitter.k, 0), skin.bulletColors.count - 1)])), lineWidth: 2)
        }
    }

}
