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

    private static func render(_ p: DanmakuCore.Pattern, boss: BossCharacter) -> UIImage {
        // ゲームと同じ場所: ボスはキャラクターの定位置、自機は画面の下のほう
        let home = boss.position(waveT: 0)
        let px = DanmakuConfig.width / 2, py = DanmakuConfig.height * 0.85
        var m = Emitter.make(p, end: 60)
        m.k = 0
        var rng = Mulberry32(seed: 7)
        var bullets: [Bullet] = []
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
