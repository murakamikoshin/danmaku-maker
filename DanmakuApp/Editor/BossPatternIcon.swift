import SwiftUI
import UIKit
import DanmakuCore

/// ボスの専用の技の見本の絵(エディタのパターン選び用)。実際のゲームと同じ計算(Emit)で、初期値のまま少し撃って進めた弾を、
/// そのボスの専用の弾の絵で描く。上にボスの小さな絵を置く。技ごとに最初の 1 回だけ作って、使い回す
enum BossPatternIcon {
    private static var cache: [DanmakuCore.Pattern: UIImage] = [:]
    private static let lock = NSLock()

    static func image(_ p: DanmakuCore.Pattern) -> UIImage? {
        guard let boss = p.bossCharacter else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let c = cache[p] { return c }
        let img = render(p, boss: boss)
        cache[p] = img
        return img
    }

    /// 竜王の範囲攻撃を描く(技の絵・エディタの見本で同じ)。s は論理px → 描く点の倍率、ox は横のずらし、height は描く高さ
    static func drawZones(_ ctx: CGContext, _ zones: [DragonZone], scale s: CGFloat, ox: CGFloat, height: CGFloat) {
        guard !zones.isEmpty else { return }
        let c = UIColor(cgColor: DragonLayer.col(DragonLayer.FXC[0][1]))
        ctx.saveGState()
        ctx.setFillColor(c.withAlphaComponent(0.35).cgColor); ctx.setStrokeColor(c.cgColor); ctx.setLineWidth(1)
        for z in zones {
            let zx = ox + CGFloat(z.x) * s, zy = CGFloat(z.y) * s
            switch z.shape {
            case .rect: ctx.fill(CGRect(x: ox + CGFloat(z.x) * s, y: zy, width: CGFloat(z.w) * s, height: CGFloat(z.h) * s))
            case .circle: ctx.fillEllipse(in: CGRect(x: zx - CGFloat(z.r) * s, y: zy - CGFloat(z.r) * s, width: CGFloat(z.r) * 2 * s, height: CGFloat(z.r) * 2 * s))
            case .ring: ctx.strokeEllipse(in: CGRect(x: zx - CGFloat(z.r) * s, y: zy - CGFloat(z.r) * s, width: CGFloat(z.r) * 2 * s, height: CGFloat(z.r) * 2 * s))
            case .beam:
                ctx.saveGState(); ctx.translateBy(x: zx, y: zy); ctx.rotate(by: CGFloat(z.a))
                ctx.fill(CGRect(x: 0, y: -CGFloat(z.w) * s / 2, width: CGFloat(z.len) * s, height: CGFloat(z.w) * s)); ctx.restoreGState()
            case .safe:
                // 安全な輪の外側を塗る(輪の中だけ抜く)
                ctx.beginTransparencyLayer(auxiliaryInfo: nil)
                ctx.fill(CGRect(x: ox, y: 0, width: CGFloat(DanmakuConfig.width) * s, height: height))
                ctx.setBlendMode(.clear)
                for c in z.safe { ctx.fillEllipse(in: CGRect(x: ox + CGFloat(c.x - c.r) * s, y: CGFloat(c.y - c.r) * s, width: CGFloat(c.r) * 2 * s, height: CGFloat(c.r) * 2 * s)) }
                ctx.setBlendMode(.normal)
                ctx.endTransparencyLayer()
            }
        }
        ctx.restoreGState()
    }

    private static func render(_ p: DanmakuCore.Pattern, boss: BossCharacter) -> UIImage {
        // ゲームと同じ場所: ボスはキャラクターの定位置、自機は画面の下のほう
        var home = boss.position(waveT: 0)
        let px = DanmakuConfig.width / 2, py = DanmakuConfig.height * 0.85
        var m = Emitter.make(p, end: 60)
        m.k = 0
        var bullets: [Bullet] = []
        var zones: [DragonZone] = []
        if let dm = p.dragonMove {
            // 竜王の技は、本体が動き、範囲攻撃もある。ゲームと同じ計算(Simulation)で少し進めて、そのときの弾と範囲攻撃を描く
            var st = Stage(name: "", mode: .boss, durationSec: 60, bossHp: 9999, emitters: [m], lifeMode: .lives, lifeCount: 9, bossLook: boss.rawValue)
            st = st.sanitized()
            var sim = Simulation(stage: st)
            sim.invincible = true
            let frames = DragonArt.iconFrames(dm)
            for _ in 0..<Int((DanmakuConfig.readySeconds + Double(frames) / 60) / DanmakuConfig.step) { sim.step(.zero) }
            bullets = sim.bullets.filter { !$0.isHiddenBody }
            zones = sim.dragon.zones
            home = sim.bossPosition
        } else {
            var rng = Mulberry32(seed: 7)
            let dt = 1.0 / 60
            let span = 1.6   // 撃ってから少し進んだところを描く
            var t = 0.0, k = 0, next = 0.0
            while t < span {
                if t + 1e-9 >= next {
                    Emit.emit(m, shot: k, cx: home.x, cy: home.y, px: px, py: py, rng: &rng, into: &bullets, awakened: false, salt: 3)
                    k += 1; next += max(0.05, m.i)
                }
                var kept: [Bullet] = []
                for var b in bullets {
                    if b.advance(dt: dt, width: DanmakuConfig.width, playerX: px, playerY: py) != .gone { kept.append(b) }
                }
                bullets = kept
                t += dt
            }
        }
        // 縦長の画面(360×540)を、正方形の絵に収める
        let side: CGFloat = 120
        let s = side / CGFloat(DanmakuConfig.height)
        let ox = (side - CGFloat(DanmakuConfig.width) * s) / 2
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 2; fmt.opaque = false
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: fmt).image { r in
            let ctx = r.cgContext
            ctx.interpolationQuality = .none
            // ボス(小さく)
            if let art = BossSprites.shopArt(boss, awakened: false) {
                let w = art.size.width * 2 * s, h = art.size.height * 2 * s
                UIImage(cgImage: art.frames[0]).draw(in: CGRect(x: ox + CGFloat(home.x) * s - w / 2, y: CGFloat(home.y) * s - h / 2, width: w, height: h), blendMode: .normal, alpha: 0.55)
            }
            // 竜王の範囲攻撃(予告も当たっている間も、うすい色で)
            drawZones(ctx, zones, scale: s, ox: ox, height: side)
            // 弾(待機中のものは描かない)。小さすぎると見えないので、少し大きめに描く
            for b in bullets.prefix(220) where !b.isDormant {
                let x = ox + CGFloat(b.x) * s, y = CGFloat(b.y) * s
                guard x > -4, x < side + 4, y > -4, y < side + 4 else { continue }
                if let img = BulletArt.image(look: b.look) {
                    let w = max(5, img.size.width * s * 1.6), h = max(5, img.size.height * s * 1.6)
                    ctx.saveGState()
                    ctx.translateBy(x: x, y: y)
                    if let kd = BulletLook.kind(of: b.look), BulletLook.isOriented(kd) { ctx.rotate(by: CGFloat(atan2(b.vy, b.vx)) + .pi / 2) }
                    img.draw(in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
                    ctx.restoreGState()
                } else {
                    Palette.bullets[Int(b.color) % Palette.bullets.count].setFill()
                    ctx.fillEllipse(in: CGRect(x: x - 2.2, y: y - 2.2, width: 4.4, height: 4.4))
                }
            }
        }
    }
}
