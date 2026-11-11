import Foundation

/// 堕天使の5つの技の弾の出し方。サーバー(fallenangel.ts)にも同じ計算がある。
/// 発射位置は、ボスの絵の中の場所(左右のオーブ・光輪・胸)。(cx, cy) はボスの中心
extension Emit {
    static let angelOrbL = (dx: -44.0, dy: 10.0)
    static let angelOrbR = (dx: 42.0, dy: 10.0)
    static let angelHalo = (dx: -1.0, dy: -75.0)
    static let angelChest = (dx: 0.0, dy: -28.0)

    /// 失楽園の抜け道の向き。最初の輪はランダム、2つ目からは前の輪の抜け道から ±90° 以内。
    /// 輪は重なって来るので、抜け道を毎回ばらばらにすると、物理的に避けられない回が出る。ステージごとに決まる乱数で、k 番目を数え直す
    static func paradiseGap(shot k: Int, salt: UInt32) -> Double {
        var r = Mulberry32(seed: salt ^ 0x5BD1_E995)
        var g = r.next() * 2 * Double.pi
        if k > 0 { for _ in 0..<k { g += (r.next() - 0.5) * Double.pi } }
        let t = g.truncatingRemainder(dividingBy: 2 * Double.pi)
        return t < 0 ? t + 2 * Double.pi : t
    }

    static func emitFallenAngel(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                                rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let deg = Double.pi / 180
        let off = Double(m.a) * deg
        let twoPi = 2 * Double.pi
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func alt(_ i: Int) -> Int { i % 2 == 0 ? m.k : (m.k + 1) % 5 }
        switch m.t {
        case .angelTwin:
            // 両手のオーブから、逆回転の螺旋。c が腕の数(覚醒すると2本増える)、r が1回ごとの回転
            let arms = n + (awakened ? 2 : 0)
            let turned = Double(k) * m.r * deg
            for (side, orb) in [(-1.0, angelOrbL), (1.0, angelOrbR)] {
                let ox = cx + orb.dx * Emit.anchorScale, oy = cy + orb.dy * Emit.anchorScale
                for j in 0..<arms where room() {
                    let a = side * turned + off + Double(j) * twoPi / Double(arms)
                    out.append(Bullet(x: ox, y: oy, vx: cos(a) * sp, vy: sin(a) * sp, color: side < 0 ? m.k : (m.k + 2) % 5))
                }
            }
        case .angelFeather:
            // 翼から羽を扇状に。c が片側の枚数。覚醒すると、光輪から自機狙いの3way弾も撃つ
            for side in [-1.0, 1.0] {
                for i in 0..<n {
                    let a = side > 0 ? (-0.1 - Double(i) * 0.16) : (Double.pi + 0.1 + Double(i) * 0.16)
                    let ox = cx + side * (40 + rng.next() * 30) * Emit.anchorScale
                    let oy = cy - rng.next() * 40 * Emit.anchorScale
                    let speed = sp * (0.79 + rng.next() * 0.42)
                    let seed = rng.next() * 99
                    guard room() else { continue }
                    var b = Bullet(x: ox, y: oy, vx: cos(a + off) * speed, vy: sin(a + off) * speed, color: alt(i), script: Bullet.featherScript)
                    b.fuse = seed
                    b.maxSpeed = awakened ? 180 : 138
                    out.append(b)
                }
            }
            if awakened {
                let hx = cx + angelHalo.dx * Emit.anchorScale, hy = cy + angelHalo.dy * Emit.anchorScale
                let aim = atan2(py - hy, px - hx)
                for d in [-0.2, 0.0, 0.2] where room() {
                    out.append(Bullet(x: hx, y: hy, vx: cos(aim + d) * sp * 1.1, vy: sin(aim + d) * sp * 1.1, color: (m.k + 1) % 5))
                }
            }
        case .angelHalo:
            // 光輪から破片が輪になって広がり、回って、端から順に自機へ突進する。c が1つの輪の破片の数(覚醒すると輪が2つになる)
            let rings = awakened ? 2 : 1
            let count = awakened ? n + 4 : n
            let hx = cx + angelHalo.dx * Emit.anchorScale, hy = cy + angelHalo.dy * Emit.anchorScale
            for ring in 0..<rings {
                let dir = ring == 0 ? 1.0 : -1.0
                for i in 0..<count where room() {
                    var b = Bullet(x: hx, y: hy, vx: 0, vy: 0, color: ring == 0 ? m.k : (m.k + 1) % 5, script: Bullet.shardScript)
                    b.u0 = hx; b.u1 = hy
                    b.u2 = Double(i) * twoPi / Double(count) + Double(k) * 0.14 + off
                    b.turn = dir * 1.5
                    b.homeLeft = (64 + Double(i) * 2 + Double(ring) * 10) / 60
                    b.maxSpeed = 72 + Double(ring) * 30
                    b.u3 = awakened ? sp * 1.24 : sp
                    out.append(b)
                }
            }
        case .angelCross:
            // 胸を中心にした逆さ十字のレーザー。自機の方を向いて、ためてから、回りながら撃たれる。1回ごとに回る向きが入れ替わる
            let cxp = cx + angelChest.dx * Emit.anchorScale, cyp = cy + angelChest.dy * Emit.anchorScale
            let a0 = atan2(py - cyp, px - cxp) + off
            let va = (k % 2 == 1 ? -1.0 : 1.0) * (awakened ? 0.9 : 0.5)
            for (da, len) in [(0.0, 760.0), (Double.pi, 90.0), (Double.pi / 2, 170.0), (-Double.pi / 2, 170.0)] where room() {
                out.append(Bullet.beam(x: cxp, y: cyp, angle: a0 + da, color: m.k, sweep: va, fireTime: 1.0, length: len))
            }
        default:
            // 失楽園: 自機を中心にした半径240の輪が閉じてくる。抜け道は1か所。c は輪の弾の数の半分、r は抜け道の広さ(度)
            let count = awakened ? (n * 26) / 10 * 2 : n * 2
            let gap = paradiseGap(shot: k, salt: salt)
            let width = (m.r == 0 ? 29.0 : abs(m.r)) * deg * (awakened ? 0.76 : 1)
            let speed = awakened ? sp * 1.19 : sp
            let rot = awakened ? (k % 2 == 1 ? 0.21 : -0.21) : 0
            for i in 0..<count {
                let a = Double(i) * twoPi / Double(count)
                let d = abs((a - gap + 3 * Double.pi).truncatingRemainder(dividingBy: twoPi) - Double.pi)
                if d < width / 2 { continue }
                guard room() else { continue }
                var b = Bullet(x: px + cos(a) * Bullet.ringStartRadius, y: py + sin(a) * Bullet.ringStartRadius, vx: 0, vy: 0, color: alt(i), script: Bullet.ringScript)
                b.u0 = px; b.u1 = py; b.u2 = a; b.u3 = speed; b.turn = rot
                b.fuse = (Bullet.ringStartRadius - 4) / speed
                out.append(b)
            }
        }
    }
}
