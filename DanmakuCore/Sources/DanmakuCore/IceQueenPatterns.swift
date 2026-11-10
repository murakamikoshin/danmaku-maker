import Foundation

/// 雪の女王の5つの技の弾の出し方。サーバー(icequeen.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を、px/秒に直したもの。(cx, cy) はボスの中心
extension Emit {
    /// 胸の氷の宝石(絵の中の (56,48))。新しい絵(2026-11-11)の位置
    static func iceCenter(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx, cy - 16) }

    static func emitIceQueen(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                             rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let c = iceCenter(cx, cy)
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        func plain(_ x: Double, _ y: Double, _ a: Double, _ speed: Double, _ kind: BulletLook.Kind) -> Bullet {
            var b = Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: m.k)
            b.look = look(kind)
            return b
        }
        switch m.t {
        case .iceCage:
            // 六花「結晶の檻」: 六方向の氷片が、0.5秒ごとに2つへ枝分かれする(2回)。覚醒は、ずらしたもう1組が加わる
            let v = Double(k % 4)
            for set in 0..<(awakened ? 2 : 1) {
                for i in 0..<6 where room() {
                    let a = set == 0 ? Double.pi / 2 + Double(i) * Double.pi / 3 + v * 0.17 + off
                                     : Double.pi / 2 + Double.pi / 6 + Double(i) * Double.pi / 3 - v * 0.17 + off
                    var b = plain(c.x, c.y, a, sp, .shard)
                    b.script = Bullet.branchScript; b.homeLeft = 2; b.u0 = 0.5; b.u1 = 0.5
                    out.append(b)
                }
            }
        case .iceIcicles:
            // 氷柱「アイシクル・フォール」: 画面の上で0.5秒待ってから、だんだん速く落ちてくる。v が落ちる加速の倍率
            var xs: [Double] = []
            for _ in 0..<(awakened ? (n * 3 + 1) / 2 : n) { xs.append(16 + rng.next() * 328) }
            let g = (awakened ? 0.12 : 0.08) * 3600 * m.v
            for x in xs where room() {
                out.append(holdBullet(x: x, y: -6, delay: 0.5, speed: 30, angle: Double.pi / 2, look: look(.icicle), color: m.k, gravity: g))
            }
        case .iceBlizzard:
            // 吹雪「ホワイトアウト」: 風に流される雪の結晶。風向きは2秒ごとに入れ替わる(覚醒は降る量が1.5倍)
            let frame = Double(k) * m.i * 60
            let idx = Int((frame / 120).rounded(.down))
            let wind = idx % 2 == 0 ? -1.0 : 1.0
            let untilFlip = (Double(idx + 1) * 120 - frame) / 60
            for _ in 0..<(awakened ? (k % 2 == 0 ? 2 : 1) : 1) {
                let side = rng.next() < 0.3
                let x = side ? (wind > 0 ? -6.0 : DanmakuConfig.width + 6) : rng.next() * DanmakuConfig.width
                let y = side ? rng.next() * 300 : -6.0
                let ph = rng.next() * 9
                guard room() else { continue }
                var b = Bullet(x: x, y: y, vx: wind * 72, vy: sp, color: m.k)
                b.look = look(.flake)
                b.script = Bullet.windScript; b.u0 = wind * 72; b.u1 = ph; b.u2 = untilFlip; b.u3 = sp
                out.append(b)
            }
        case .iceFreeze:
            // 凍結「時の氷結」: 氷片の輪が広がって、0.67秒で止まって結晶になり、1.33秒で砕けて3つの氷片が散る(覚醒は自機のほうへ)
            let count = awakened ? (n * 7 + 2) / 5 : n
            for i in 0..<count where room() {
                let a = Double(i) * twoPi / Double(count) + Double(k) * 0.1 + off
                var b = plain(c.x, c.y, a, sp, .shard)
                b.script = Bullet.freezeScript; b.u0 = 40.0 / 60; b.u1 = 80.0 / 60
                out.append(b)
                let fx = c.x + cos(a) * sp * 40 / 60, fy = c.y + sin(a) * sp * 40 / 60
                for j in 0..<3 {
                    let ang = awakened ? Double(j - 1) * 0.35 : rng.next() * twoPi
                    guard room() else { continue }
                    out.append(holdBullet(x: fx, y: fy, delay: 80.0 / 60, speed: 96, angle: ang, aim: awakened, look: look(.shard), color: m.k))
                }
            }
        default:
            // 氷鏡「ダイヤモンドダスト」: 自機狙いの氷片の扇。左右の壁で2回まで跳ね返る
            let count = awakened ? n + 2 : n
            let a0 = atan2(py - c.y, px - c.x) + off
            for i in 0..<count where room() {
                let a = a0 + (Double(i) - Double(count - 1) / 2) * 0.22
                var b = plain(c.x, c.y, a, sp, .shard)
                b.bounces = 2
                out.append(b)
            }
        }
    }
}
