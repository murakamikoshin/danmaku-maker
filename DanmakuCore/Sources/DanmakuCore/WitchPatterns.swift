import Foundation

/// 深海の魔女の5つの技の弾の出し方。サーバー(witch.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を、px/秒に直したもの。(cx, cy) はボスの中心
extension Emit {
    /// 触手の付け根(絵の中の (56,64))、提灯(70,8)、触手の先(付け根から角度 TENT[j]・半径30)
    static func witchRoot(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx, cy + 16) }
    static func witchLantern(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx + 28, cy - 96) }
    static let witchTentAngles: [Double] = [10, 34, 58, 80, 100, 122, 146, 170]
    static func witchTip(_ j: Int, _ cx: Double, _ cy: Double) -> (x: Double, y: Double) {
        let a = witchTentAngles[j] * Double.pi / 180
        return (cx + cos(a) * 60, cy + 16 + sin(a) * 60)
    }
    /// 暗転の長さ(秒): 技の間 150 フレーム + 80 フレーム
    static let witchDarkSeconds = 230.0 / 60

    static func emitWitch(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                          rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let W = DanmakuConfig.width
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        switch m.t {
        case .witchAbyss:
            // 深淵「提灯の誘い」: 画面が暗くなり、提灯と自機のまわりしか見えない。上から夜光虫が縦の列で、波打ちながら降る(覚醒は列が増え、提灯から自機狙いの泡も)
            let cast = 17
            let lantern = witchLantern(cx, cy)
            if k % cast == 0 && room() {
                var d = Bullet(x: lantern.x, y: lantern.y, vx: 0, vy: 0, color: m.k)
                d.script = Bullet.darkScript; d.fuse = witchDarkSeconds
                out.append(d)
            }
            let cols = awakened ? n + 2 : n
            for c in 0..<cols where room() {
                let x0 = (Double(c) + 0.5) * W / Double(cols)
                var b = Bullet(x: x0, y: -6, vx: 0, vy: awakened ? sp * 2.2 / 1.8 : sp, color: m.k)
                b.look = look(.plankton)
                b.script = Bullet.swayScript; b.u0 = Double(c); b.u1 = 0.06; b.u2 = 14 * 0.06 * 60; b.u3 = 2
                out.append(b)
            }
            if awakened && k % 4 == 0 && room() {
                let a = atan2(py - lantern.y, px - lantern.x) + off
                var b = Bullet(x: lantern.x, y: lantern.y, vx: cos(a) * 96, vy: sin(a) * 96, color: m.k)
                b.look = look(.bubble); b.radius = 2
                out.append(b)
            }
        case .witchBubbles:
            // 泡沫「膨らむ泡」: 触手の先から泡がゆっくり落ちて膨らみ(当たりも大きくなる)、1.5秒で弾けて夜光虫が散る
            let v = k % 4
            let count = awakened ? 8 : 4
            let pieces = awakened ? 10 : 6
            for j in 0..<count {
                let tp = witchTip(awakened ? j : (j * 2 + v) % 8, cx, cy)
                let a = Double.pi / 2 + (rng.next() - 0.5) * 1.2 + off
                let a0 = rng.next() * twoPi
                guard room() else { continue }
                var b = Bullet(x: tp.x, y: tp.y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                b.look = look(.bubble)
                b.script = Bullet.dragScript; b.fuse = 1.5
                b.radius = 0.01; b.grow = 0.09 * 60; b.growMax = 7
                out.append(b)
                // 弾けた場所(減速しながら進んだ先)に、夜光虫を待機させておく
                var px2 = tp.x, py2 = tp.y, vx = b.vx, vy = b.vy, age = 0.0
                let dt = 1.0 / 120
                while true {
                    age += dt
                    if age >= 1.5 { break }
                    vx *= Bullet.dragDecay; vy *= Bullet.dragDecay
                    px2 += vx * dt; py2 += vy * dt
                }
                for i in 0..<pieces where room() {
                    out.append(holdBullet(x: px2, y: py2, delay: 1.5, speed: 108, angle: a0 + Double(i) * twoPi / Double(pieces), look: look(.plankton), color: m.k))
                }
            }
        case .witchTentacles:
            // 触手「八腕の抱擁」: 八本の触手の先から、夜光虫が波打つ列になって伸びる。90フレーム撃って、30フレーム休む
            let cyc = k % 40
            guard cyc < 30 else { return }
            let t = Double(cyc) * m.i * 60
            let amp = awakened ? 18.0 : 12.0
            for j in 0..<8 where room() {
                let tp = witchTip(j, cx, cy)
                var b = Bullet(x: tp.x, y: tp.y, vx: 0, vy: 0, color: m.k)
                b.look = look(.plankton)
                b.script = Bullet.lateralScript
                b.u0 = witchTentAngles[j] * Double.pi / 180 + (awakened ? sin(t * 0.03) * 0.4 : 0) + off
                b.u1 = Double(j); b.u2 = amp * 6; b.u3 = sp
                out.append(b)
            }
        case .witchMaelstrom:
            // 渦潮「メイルシュトローム」: 付け根から渦の腕が回りながら伸び、弾は少しずつ曲がる。覚醒は1本おきに逆回り
            let cyc = k % 50
            guard cyc < 40 && cyc % 4 != 3 else { return }
            let root = witchRoot(cx, cy)
            let arms = awakened ? n + 2 : n
            let t = Double(cyc) * m.i * 60
            for a in 0..<arms where room() {
                let dir = awakened && a % 2 == 1 ? -1.0 : 1.0
                let ang = Double(a) * twoPi / Double(arms) + t * 0.02 * dir + off
                var b = Bullet(x: root.x, y: root.y, vx: cos(ang) * sp, vy: sin(ang) * sp, color: m.k)
                b.look = look(.plankton)
                b.script = Bullet.curveScript; b.u0 = 0.012 * 60 * dir
                out.append(b)
            }
        default:
            // 墨「黒潮の帳」: 大きな墨のしずくがゆっくり落ちて、画面の半ばで弾ける。粒の輪は自機の方を向く(覚醒は高く弾け、粒が増える)
            let v = k % 3
            let xs: [Double] = v % 2 == 1 ? [90, 270] : [45, 180, 315]
            let popY = awakened ? 260.0 : 300.0
            let pieces = awakened ? 12 : 8
            let life = (popY + 10) / sp
            for x in xs where room() {
                out.append(holdBullet(x: x, y: -10, delay: 0, speed: sp, angle: Double.pi / 2, look: look(.ink), color: m.k, lifetime: life))
                for i in 0..<pieces where room() {
                    out.append(holdBullet(x: x, y: popY, delay: life, speed: 120, angle: Double(i) * twoPi / Double(pieces), aim: true, look: look(.plankton), color: m.k))
                }
            }
        }
    }
}
