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
        var born: [Bullet] = []
        for i in 0..<bullets.count {
            var b = bullets[i]
            // ゲーム本体と同じ動き(止まる・分裂・追尾・加速・反射)
            let motion = b.advance(dt: dt, width: DanmakuConfig.width, playerX: player.x, playerY: player.y)
            if motion == .burst {
                born.append(contentsOf: b.fragments())
                continue
            }
            if motion == .gone { continue }   // 撃ち終わったチャージビーム
            if b.x < -20 || b.x > DanmakuConfig.width + 20 || b.y < -20 || b.y > PreviewEngine.height + 20 { continue }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        bullets.append(contentsOf: born)
    }
}

struct EmitterPreview: View {
    let emitter: Emitter
    let isBoss: Bool
    let look: PreviewLook
    @State private var engine = PreviewEngine()
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        // 作者が選んだ見た目(弾の色と形・背景・自機)と、じぶんの画像を、そのまま使う
        let _ = cosmetics.customImageRevision
        let skin = Skin.of(look.bullets)
        let bg = Skin.of(look.background)
        let bulletImages = SpriteFactory.bulletImages(look.bullets)
        let own = cosmetics.ownership.hasCustomImages
        let customBullet = (own && look.customs.bullet) ? CustomImageStore.load(.bullet) : nil
        let customShip = (own && look.customs.ship) ? CustomImageStore.load(.ship) : nil
        let shipImage = customShip ?? SpriteFactory.shipImage(look.ship)
        let bossImage = (own && look.customs.boss) ? CustomImageStore.load(.boss) : nil
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
                let custom = customShip != nil
                let shipRect = CGRect(x: pt.x - (custom ? 12 : sw / 2), y: pt.y - (custom ? 12 : sh / 2), width: custom ? 24 : sw, height: custom ? 24 : sh)
                ctx.draw(Image(uiImage: shipImage), in: shipRect)
                if custom { ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(.white)) }
                // 弾
                for b in engine.bullets {
                    if b.isBeam { ctx.drawBeam(b, color: Color(skin.bulletColors[min(max(b.color, 0), skin.bulletColors.count - 1)])); continue }
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
            // ボスの大きさは、当たる範囲と同じ比率(小・中・大)
            let side = EnemyArt.bossPoints(size: look.bossSize)
            let rect = CGRect(x: 180 - side / 2, y: DanmakuConfig.height * 0.18 - side / 2, width: side, height: side)
            if let bossImage { ctx.draw(Image(uiImage: bossImage), in: rect) }
            else { ctx.draw(Image(uiImage: EnemyArt.bossImage(look: look.bossLook, size: look.bossSize, flash: false)), in: rect) }
        }
        if let mooks = look.mooks, (!isBoss || emitter.firesFromPoint) && ![.rain, .sideL, .sideR, .corner].contains(emitter.t) {
            let side = EnemyArt.mookPoints(size: mooks)
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            ctx.draw(Image(uiImage: EnemyArt.mookImage(look: look.mookLook, size: mooks)), in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
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

/// チャージビームの見た目(ゲーム本体・エディタの見本で同じ)。当たる太さ(DanmakuConfig.beamHitRadiusSquared)に近い太さで描く
struct BeamLook {
    /// 光線の長さ(画面の外まで届く長さ)
    static let length = 900.0
    let firing: Bool
    let width: CGFloat
    let coreWidth: CGFloat
    let alpha: CGFloat

    init(_ b: Bullet) {
        if b.beamFiring {
            // 撃っている間: 太い光線。終わりぎわに薄くなって消える
            let f = (b.age - DanmakuConfig.beamCharge) / DanmakuConfig.beamFire
            firing = true
            width = 18
            coreWidth = 6
            alpha = CGFloat(f > 0.75 ? max(0, (1 - f) / 0.25) : 1)
        } else {
            // ためている間: 細い予告線が、だんだん太く濃くなる(当たらない)
            let p = b.beamChargeProgress
            firing = false
            width = CGFloat(1 + 3 * p)
            coreWidth = 0
            alpha = CGFloat(0.25 + 0.5 * p)
        }
    }
}

extension GraphicsContext {
    /// チャージビームを描く(エディタの見本・パターンの絵)
    func drawBeam(_ b: Bullet, color: Color, scale: CGFloat = 1) {
        let look = BeamLook(b)
        var p = Path()
        p.move(to: CGPoint(x: b.x * scale, y: b.y * scale))
        p.addLine(to: CGPoint(x: (b.x + b.vx * BeamLook.length) * scale, y: (b.y + b.vy * BeamLook.length) * scale))
        let style = StrokeStyle(lineWidth: look.width * scale, lineCap: .round)
        stroke(p, with: .color(color.opacity(look.alpha)), style: style)
        if look.firing {
            stroke(p, with: .color(.white.opacity(look.alpha)), style: StrokeStyle(lineWidth: look.coreWidth * scale, lineCap: .round))
        }
    }
}
