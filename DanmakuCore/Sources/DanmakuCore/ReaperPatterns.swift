import Foundation

/// 死神の5つの技の弾の出し方。サーバー(reaper.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を、px/秒に直したもの。(cx, cy) はボスの中心
extension Emit {
    /// フードのドクロ(絵の中の (66,30))。新しい絵(2026-11-11)の位置
    static func reaperSkull(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx + 20 * Emit.anchorScale, cy - 52 * Emit.anchorScale) }

    static func emitReaper(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                           rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let W = DanmakuConfig.width
        let skull = reaperSkull(cx, cy)
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        switch m.t {
        case .reaperScythe:
            // 刈取「三日月の大鎌」: 大鎌の跡に刃が弧の形に並んで止まり、あとでいっせいに落ちる。ゆっくり追う魂も2つ。覚醒は弧が2重で、刃の列に隙間が2か所
            let release = awakened ? 64.0 / 60 : 44.0 / 60
            let a0 = 160.0 * Double.pi / 180, a1 = 20.0 * Double.pi / 180
            let ax = cx, ay = cy + 20 * Emit.anchorScale
            for radius in (awakened ? [150.0, 215.0] : [150.0]) {
                let count = Int((radius * (a0 - a1) / 13).rounded(.down))
                var gaps: [Int] = []
                if awakened {
                    gaps = [Int((Double(count) * (0.2 + rng.next() * 0.25)).rounded(.down)), Int((Double(count) * (0.55 + rng.next() * 0.25)).rounded(.down))]
                }
                for i in 0...count {
                    if gaps.contains(where: { i >= $0 && i < $0 + 4 }) { continue }
                    let a = a0 - (a0 - a1) * Double(i) / Double(count)
                    let vx = (rng.next() - 0.5) * 36
                    guard room() else { continue }
                    out.append(holdBullet(x: ax + cos(a) * radius, y: ay + sin(a) * radius, delay: release, speed: (vx * vx + 900).squareRoot(),
                                          angle: atan2(30, vx), look: look(.blade), color: m.k, gravity: 160))
                }
            }
            let aim = atan2(py - skull.y, px - skull.x) + off
            for d in [-0.5, 0.5] where room() {
                var b = Bullet(x: skull.x, y: skull.y, vx: cos(aim + d) * 72, vy: sin(aim + d) * 72, color: m.k, turn: 1.2, homeLeft: 2.5)
                b.look = look(.soul)
                out.append(b)
            }
        case .reaperSouls:
            // 魂魄「さまよう魂」: 死神のまわりを回りながら広がり、0.67秒後に自機のほうへ漂ってくる
            let count = awakened ? (n * 8 + 4) / 5 : n
            for i in 0..<count where room() {
                var b = Bullet(x: skull.x, y: skull.y, vx: 0, vy: 0, color: m.k)
                b.look = look(.soul)
                b.script = Bullet.orbitScript
                b.fuse = 40.0 / 60; b.u0 = skull.x; b.u1 = skull.y; b.u2 = Double(i) * twoPi / Double(count) + off; b.u3 = 3
                out.append(b)
            }
        case .reaperChains:
            // 冥府の鎖: 画面の端から、自機のいた場所へ向けて鎖が伸びる。伸びる前に薄い線で予告する。覚醒は5本
            let origins: [(Double, Double)] = [(0, 0), (W, 0), (W / 2, -4), (0, 220), (W, 220)]
            for o in origins.prefix(awakened ? 5 : 3) {
                let a = atan2(py - o.1, px - o.0)
                var d = 0.0, j = 0
                while d < 760 {
                    let x = o.0 + cos(a) * d, y = o.1 + sin(a) * d
                    if x < -10 || x > W + 10 || y > DanmakuConfig.height + 10 { break }
                    if room() {
                        out.append(holdBullet(x: x, y: y, delay: Double(20 + 2 * j) / 60, speed: 0, angle: a, look: look(.chain), color: m.k, lifetime: 1.0))
                    }
                    d += 8; j += 1
                }
            }
        case .reaperDeadline:
            // 宣告「デッドライン」: 刃の横一列がゆっくり下りてくる。通り道は1か所。合間に自機狙いの魂。v は 1.0 で、元の 0.8 の速さ
            let rows = awakened ? 6 : 4
            let row = k % rows, cycle = k / rows
            var r = Mulberry32(seed: salt ^ 0x00DE_AD11 ^ (UInt32(truncatingIfNeeded: cycle) &* 0x9E37_79B1))
            var gx = 180.0
            for _ in 0...row {
                let dir = r.next() < 0.5 ? -1.0 : 1.0
                gx = min(310, max(50, gx + dir * (40 + r.next() * 40)))
            }
            let gap = (m.r == 0 ? 56.0 : abs(m.r)) * (awakened ? 48.0 / 56 : 1)
            var x = 10.0
            while x < W {
                defer { x += 14 }
                if abs(x - gx) < gap / 2 || !room() { continue }
                var b = Bullet(x: x, y: 150, vx: 0, vy: m.v * 48, color: m.k)
                b.look = look(.blade)
                out.append(b)
            }
            for j in 0..<max(1, Int((m.i * 60 / 30).rounded(.up))) where room() {
                out.append(holdBullet(x: skull.x, y: skull.y, delay: Double(j) * 0.5, speed: 120, angle: 0, aim: true, look: look(.soul), color: m.k))
            }
        default:
            // 冥途「三途の渡し」: 画面の下半分に、魂の流れが5本。1本ごとに逆向きに流れ、ところどころ途切れる。覚醒は速く、上下に波打つ
            let lanes: [Double] = [330, 380, 430, 480, 530]
            for (i, y) in lanes.enumerated() {
                if (k + i * 3) % 7 < 2 { continue }
                let dir = i % 2 == 1 ? -1.0 : 1.0
                guard room() else { continue }
                let speed = awakened ? sp * 3.0 / 2.4 : sp
                var b = Bullet(x: dir > 0 ? -6 : W + 6, y: y, vx: dir * speed, vy: 0, color: m.k)
                b.look = look(.soul)
                if awakened { b.script = Bullet.swayScript; b.u0 = 0; b.u1 = 0.05; b.u2 = 36; b.u3 = 1 }
                out.append(b)
            }
        }
    }
}
