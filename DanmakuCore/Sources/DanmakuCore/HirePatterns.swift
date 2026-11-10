import Foundation

/// 金魚姫(金魚すくいの金魚娘)の5つの技の弾の出し方。サーバー(hire.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を px/秒に直したもの。(cx, cy) はボスの中心。絵は 112×112
extension Emit {
    /// ポイ(絵の中の (39,33))、金魚をのせた手 (73,42)
    static func hirePoi(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx - 34, cy - 46) }
    static func hireHand(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx + 34, cy - 28) }

    static func emitHire(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                         rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        func angDiff(_ a: Double, _ b: Double) -> Double {
            var d = (a - b).truncatingRemainder(dividingBy: twoPi)
            if d > Double.pi { d -= twoPi }
            if d < -Double.pi { d += twoPi }
            return abs(d)
        }
        switch m.t {
        case .hireSukui:
            // 金魚「すくい上げ」: 手のひらから金魚の群れが扇に泳ぎ出す。尾をふってゆらゆら曲がり、少しだけ自機を追う。3回(覚醒は4回)で休む
            let volleys = awakened ? 4 : 3
            guard k % (volleys + 1) < volleys else { return }
            let o = hireHand(cx, cy)
            let count = awakened ? (n * 3 + 1) / 2 : n
            let a0 = atan2(py - o.y, px - o.x) + off
            for i in 0..<count {
                let ph = rng.next() * 9
                guard room() else { continue }
                let a = a0 + (Double(i) - Double(count - 1) / 2) * 0.16
                var b = Bullet(x: o.x, y: o.y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                b.look = look(.kingyo)
                b.script = Bullet.wobbleScript
                b.u0 = 3; b.u1 = 9; b.u2 = ph; b.u3 = 1.0; b.turn = awakened ? 1.32 : 0.9
                out.append(b)
            }
        case .hireYoyo:
            // 水風船「ヨーヨー釣り」: 上から水ヨーヨーが落ちてきて、止まって、上へはずむ。1.67秒ではじけて泡の輪になる(覚醒は自機のほうを向く)
            let count = awakened ? (n * 3 + 1) / 2 : n
            let pieces = awakened ? 12 : 8
            for i in 0..<count {
                let x = 20 + (Double(i) + 0.5) * (W - 40) / Double(count) + (rng.next() - 0.5) * 10
                let a0 = rng.next() * twoPi
                guard room() else { continue }
                let delay = Double(i) * 8 / 60
                var b = Bullet(x: x, y: -8, vx: 0, vy: 0, color: m.k)
                b.look = look(.yoyo)
                b.script = Bullet.yoyoScript; b.fuse = delay
                out.append(b)
                // はじけた場所(同じ動きを、同じ刻みで進めた先)に、泡を待機させておく
                var yy = -8.0, tt = 0.0
                let dt = 1.0 / 120
                while true {
                    tt += dt
                    if tt >= 100.0 / 60 { break }
                    let vy = tt <= 0.75 ? (2.6 * (1 - tt / 0.75) + 0.2) * 60 : (tt <= 1.0 ? 0 : -90)
                    yy += vy * dt
                }
                for j in 0..<pieces where room() {
                    out.append(holdBullet(x: x, y: yy, delay: delay + 100.0 / 60, speed: sp, angle: (awakened ? 0 : a0) + Double(j) * twoPi / Double(pieces),
                                          aim: awakened, look: look(.awa), color: m.k))
                }
            }
        case .hireHanabi:
            // 夏祭り「打ち上げ花火」: ポイの先から花火の玉が打ち上がり、0.58秒で空で開く。火花は重力でゆっくり落ちる(しだれ柳)
            let shells = awakened ? 6 : 4
            guard k % (shells + 4) < shells else { return }
            let o = hirePoi(cx, cy)
            let tx = 40 + rng.next() * 280, ty = 60 + rng.next() * 140
            let a = atan2(ty - o.y, tx - o.x)
            guard room() else { return }
            let dist = ((tx - o.x) * (tx - o.x) + (ty - o.y) * (ty - o.y)).squareRoot() * 0.8   // 狙った場所の手前で開く
            let life = 35.0 / 60
            out.append(holdBullet(x: o.x, y: o.y, delay: 0, speed: dist / life, angle: a, look: look(.spark), color: m.k, lifetime: life))
            let bx = o.x + cos(a) * dist, by = o.y + sin(a) * dist
            let count = awakened ? 24 : 18
            for j in 0..<count where room() {
                out.append(holdBullet(x: bx, y: by, delay: life, speed: sp * 1.6 / 4.0, angle: Double(j) * twoPi / Double(count), look: look(.spark), color: m.k, gravity: 0.025 * 3600))
            }
        case .hireRipple:
            // 水面「波紋」: 自機の近く(70px以上はなれた所)に波紋の印が出て、0.5秒後、そこから泡の輪が広がる(覚醒は2か所・輪が大きい)
            guard k % 6 < 4 else { return }
            for _ in 0..<(awakened ? 2 : 1) {
                let a = rng.next() * twoPi, d = 70 + rng.next() * 60
                let x = min(W - 16, max(16, px + cos(a) * d)), y = min(H - 16, max(240, py + sin(a) * d))
                let count = awakened ? (n * 10 + 6) / 7 : n
                for i in 0..<count where room() {
                    out.append(holdBullet(x: x, y: y, delay: 0.5, speed: sp, angle: Double(i) * twoPi / Double(count), look: look(.awa), color: m.k))
                }
            }
        default:
            // 金魚鉢「ぐるぐる回遊」: 自機のまわりを金魚の輪が回りながら縮み、最後に外へ散る。輪には3匹ぶんのすき間(覚醒は輪が2重で逆回り)
            let gapAt = rng.next() * twoPi
            for (ri, dir) in (awakened ? [(0, 1.0), (1, -1.0)] : [(0, 1.0)]) {
                let r0 = 150.0 + Double(ri) * 40
                for i in 0..<20 {
                    let a0 = Double(i) * twoPi / 20
                    if angDiff(a0, gapAt + Double(ri) * Double.pi) < twoPi / 20 * 1.6 { continue }
                    guard room() else { continue }
                    var b = Bullet(x: px + cos(a0) * r0, y: py + sin(a0) * r0, vx: 0, vy: 0, color: m.k)
                    b.look = look(.kingyo)
                    b.script = Bullet.kaiyuScript; b.fuse = 100.0 / 60
                    b.u0 = px; b.u1 = py; b.u2 = a0; b.maxSpeed = r0; b.accel = 60 + Double(ri) * 30; b.turn = dir * 1.2
                    out.append(b)
                }
            }
        }
    }
}
