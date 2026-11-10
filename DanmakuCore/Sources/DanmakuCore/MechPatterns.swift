import Foundation

/// 機神の5つの技の弾の出し方。サーバー(mech.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を、px/秒に直したもの。(cx, cy) はボスの中心
extension Emit {
    /// コアアイ(絵の中の (56,49))と、肩のキャノン 左 (25,46) / 右 (86,46)。新しい絵(2026-11-11)の位置
    static func mechEye(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx, cy - 14) }
    static func mechCannon(_ left: Bool, _ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (left ? cx - 62 : cx + 60, cy - 20) }

    /// ミサイルを作る。delay 秒は待機(見えず、当たらない)。そのあと decelEnd 秒まで減速、steerEnd 秒まで自機のほうへ向きを変える
    static func missileBullet(x: Double, y: Double, angle: Double, speed: Double, delay: Double, decelEnd: Double, steerEnd: Double,
                              turn: Double, accel: Double, maxSpeed: Double, look: UInt8, color: Int) -> Bullet {
        var b = Bullet(x: x, y: y, vx: cos(angle) * speed, vy: sin(angle) * speed, color: color)
        b.look = look
        b.script = Bullet.missileScript
        b.fuse = delay; b.u0 = decelEnd; b.u2 = steerEnd; b.u3 = accel; b.turn = turn; b.maxSpeed = maxSpeed
        return b
    }

    static func emitMech(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                         rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let eye = mechEye(cx, cy)
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        switch m.t {
        case .mechLockOn:
            // 照準「コアアイ・ロックオン」: 照準が自機を追い、止まって固定されると、コアアイから極太ビーム。同時に、肩から旋回に限りのある追尾ミサイル
            if room() {
                let a = atan2(py - eye.y, px - eye.x) + off
                var beam = Bullet.beam(x: eye.x, y: eye.y, angle: a, color: m.k, fireTime: 40.0 / 60)
                beam.radius = awakened ? 17 : 13
                beam.u0 = 46.0 / 60   // 0.77秒まで追い、残りの 0.23秒(14フレーム)は固定
                out.append(beam)
            }
            for i in 0..<(awakened ? 4 : 2) where room() {
                let c = mechCannon(i % 2 == 0, cx, cy)
                let a = -Double.pi / 2 + (i % 2 == 1 ? 0.7 : -0.7) * (1 + Double(i / 2) * 0.4)
                out.append(missileBullet(x: c.x, y: c.y, angle: a, speed: 156, delay: 1.0, decelEnd: 0, steerEnd: 1.5, turn: 2.4, accel: 0, maxSpeed: 0, look: look(.missile), color: m.k))
            }
        case .mechMissiles:
            // 弾幕「マイクロミサイル」: 肩から小型ミサイルを上向きにばらまく。減速して向きを変え、自機へ向かって加速する(覚醒は多く、間隔が短い)
            let count = awakened ? n * 5 / 3 : n
            let gap = awakened ? 3.0 : 5.0
            for i in 0..<count {
                let c = mechCannon(i % 2 == 0, cx, cy)
                let a = -Double.pi / 2 + (i % 2 == 1 ? 1.0 : -1.0) * (0.3 + rng.next() * 0.9)
                guard room() else { continue }
                out.append(missileBullet(x: c.x, y: c.y, angle: a, speed: sp, delay: Double(i) * gap / 60, decelEnd: 25.0 / 60, steerEnd: 85.0 / 60,
                                         turn: 3.6, accel: 288, maxSpeed: 204, look: look(.missile), color: m.k))
            }
        case .mechGatling:
            // 掃射「ガトリング・スイープ」: 両肩のキャノンが速い砲弾を連射しながら首を振る。90フレーム撃って、約20フレーム休む(覚醒は1つのキャノンから2列)
            let cyc = k % 37
            guard cyc < 30 else { return }
            let f = Double(cyc) / 30
            for left in [true, false] {
                let c = mechCannon(left, cx, cy)
                let a = left ? Double.pi / 6 + f * twoPi / 3 : Double.pi * 5 / 6 - f * twoPi / 3
                for d in (awakened ? [-0.1, 0.1] : [0.0]) where room() {
                    var b = Bullet(x: c.x, y: c.y, vx: cos(a + d + off) * sp, vy: sin(a + d + off) * sp, color: m.k)
                    b.look = look(.shell)
                    out.append(b)
                }
            }
        case .mechGrid:
            // 放射「ヘキサ・レーザー」: コアアイから放射状のレーザー(予告のあと、ゆっくり回る。1回ごとに逆向き)。合間に光子弾の自機狙い。5回に1回レーザー
            if k % 5 == 0 {
                let lasers = awakened ? n + 2 : n
                let a0 = rng.next() * twoPi
                let dir = (k / 5) % 2 == 0 ? -1.0 : 1.0
                for i in 0..<lasers where room() {
                    var beam = Bullet.beam(x: eye.x, y: eye.y, angle: a0 + Double(i) * twoPi / Double(lasers) + off, color: m.k,
                                           sweep: (awakened ? 0.01 : 0.006) * 60 * dir, fireTime: 70.0 / 60)
                    beam.radius = 5
                    out.append(beam)
                }
            }
            if room() {
                let a = atan2(py - eye.y, px - eye.x)
                var b = Bullet(x: eye.x, y: eye.y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                b.look = look(.hex)
                out.append(b)
            }
        default:
            // 制圧「オーバーロード」: コアアイから光子弾の輪。ゆっくり出て加速する。輪には自機の近くに抜け道が1つある(5輪撃って休む。覚醒は7輪)
            let rings = awakened ? 7 : 5
            let v = k % (rings + 3)
            guard v < rings else { return }
            let count = awakened ? n * 4 / 3 : n
            let gapA = atan2(py - eye.y, px - eye.x) + (v % 2 == 1 ? 0.5 : -0.5)
            for i in 0..<count where room() {
                let a = Double(i) * twoPi / Double(count) + Double(v) * 0.13 + off
                var d = (a - gapA).truncatingRemainder(dividingBy: twoPi)
                if d > Double.pi { d -= twoPi }
                if d < -Double.pi { d += twoPi }
                if abs(d) < twoPi / Double(count) * 1.6 { continue }
                var b = Bullet(x: eye.x, y: eye.y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                b.look = look(.hex)
                b.accel = 1.5; b.maxSpeed = 210
                out.append(b)
            }
        }
    }
}
