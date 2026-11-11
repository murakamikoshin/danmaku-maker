import Foundation

/// ぷにまる(ギャップボス)の5つの技の弾の出し方。サーバー(puni.ts)にも同じ計算がある。
/// 通常は「ぷに弾」を落とすだけのザコ。覚醒すると、同じ枠の技が別物(目玉・触手・牙・レーザー・瞬間移動)になる。
/// どの技も、発射の間隔は 0.05秒(3フレーム)の目盛りを前提にして、技の中の時間は「何回目の発射か」で数える
/// (通常と覚醒で、ほしい間隔がちがうため)。数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を px/秒に直したもの
extension Emit {
    /// 通常の本体 (66,88) と、覚醒の中心 (68,56)(絵は 136×112 の2倍)
    static func puniBody(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx - 4 * Emit.anchorScale, cy + 64 * Emit.anchorScale) }
    static func puniCore(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx, cy) }
    /// 覚醒の目玉22個の位置(絵の中のドット。engine.js の乱数で決めた値)
    static let puniEyes: [(Double, Double)] = [
        (53.769974, 48.769566), (32.2689, 48.927456), (56.758216, 40.63205), (91.927262, 37.444275), (101.303457, 68.256775), (71.595636, 66.088367),
        (78.477526, 55.65313), (60.787685, 60.679455), (93.244441, 64.921933), (96.380715, 45.321464), (67.414556, 48.286513), (51.060271, 44.701989),
        (77.802896, 79.920395), (96.827309, 65.691207), (73.806344, 61.539982), (61.744536, 34.713954), (89.011201, 38.269815), (83.427582, 37.257611),
        (86.019359, 59.033053), (84.209776, 72.284934), (55.115329, 64.464691), (72.433984, 43.501197)]
    static func puniEye(_ i: Int, _ cx: Double, _ cy: Double) -> (x: Double, y: Double) {
        (cx + (-136 + puniEyes[i].0 * 2) * Emit.anchorScale, cy + (-112 + puniEyes[i].1 * 2) * Emit.anchorScale)
    }

    static func emitPuni(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                         rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        func bullet(_ x: Double, _ y: Double, _ a: Double, _ speed: Double, _ kind: BulletLook.Kind) -> Bullet {
            var b = Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: m.k)
            b.look = look(kind)
            return b
        }
        let body = puniBody(cx, cy), core = puniCore(cx, cy)
        switch m.t {
        case .puniPoyon:
            if !awakened {
                // ぽよん: ぷに弾を真下にポトッと落とすだけ(1秒に1発 × 6)
                let cyc = k % 130
                guard cyc % 20 == 0 && cyc < 120 && room() else { return }
                out.append(bullet(body.x, body.y + 8, Double.pi / 2, sp, .jelly))
            } else {
                // 名状しがたき凝視: 22個の目が、順番に自機を狙い撃つ(2周)
                let cyc = k % 73
                guard cyc < 58 && cyc % 4 != 3 && room() else { return }
                let idx = (cyc - (cyc + 1) / 4) % 22
                let e = puniEye(idx, cx, cy)
                out.append(bullet(e.x, e.y, atan2(py - e.y, px - e.x) + off, sp * 3.0, .eye))
            }
        case .puniShower:
            if !awakened {
                // ぷにぷにシャワー: ぷに弾を3つ、ゆるい扇で落とす(4回)
                let cyc = k % 80
                guard cyc % 17 == 0 && cyc < 68 else { return }
                for d in [-0.3, 0.0, 0.3] where room() { out.append(bullet(body.x, body.y + 6, Double.pi / 2 + d, sp, .jelly)) }
            } else {
                // 螺旋の腕: 12本の触手の螺旋。粘液の弾が少しずつ曲がりながら回る(150フレーム)
                let cyc = k % 70
                guard cyc < 50 && cyc % 4 != 3 else { return }
                let t = Double(cyc) * 3
                for a in 0..<12 where room() {
                    var b = bullet(core.x, core.y, Double(a) * Double.pi / 6 + t * 0.03 + off, sp * 2.0 / 1.2, .goo)
                    b.script = Bullet.curveScript; b.u0 = 0.01 * 60
                    out.append(b)
                }
            }
        case .puniKorokoro:
            if !awakened {
                // ころころ: ぷに弾を2つ、ぽーんと投げ上げる(放物線で落ちてくる)
                let cyc = k % 71
                guard cyc % 17 == 0 && cyc < 51 else { return }
                for s in [-1.0, 1.0] where room() {
                    var b = bullet(body.x, body.y, -Double.pi / 2 + s * 0.6, sp, .jelly)
                    b.gravity = 0.05 * 3600
                    out.append(b)
                }
            } else {
                // 歯の環: 牙の輪が回りながら広がる。1輪ごとに逆回り(5輪)
                let cyc = k % 60
                guard cyc % 8 == 0 && cyc < 40 else { return }
                let v = cyc / 8
                for i in 0..<24 where room() {
                    var b = bullet(core.x, core.y, Double(i) * twoPi / 24 + Double(v) * 0.13 + off, sp * 1.6 / 2.0, .tooth)
                    b.script = Bullet.curveScript; b.u0 = (v % 2 == 1 ? 1.0 : -1.0) * 0.008 * 60
                    out.append(b)
                }
            }
        case .puniPurupuru:
            if !awakened {
                // ぷるぷる: ぷに弾8つの輪を、ゆっくり2回
                let cyc = k % 60
                guard cyc % 20 == 0 && cyc < 40 else { return }
                let v = cyc / 20
                for i in 0..<8 where room() { out.append(bullet(body.x, body.y, Double(i) * Double.pi / 4 + Double(v) * 0.4 + off, sp, .jelly)) }
            } else {
                // 二色の眼光: 水色と赤紫のレーザー4本が逆向きに回る。合間に粘液の自機狙い(20フレームごと)
                let cyc = k % 70
                guard cyc == 0 else { return }
                for i in 0..<4 where room() {
                    var beam = Bullet.beam(x: core.x, y: core.y, angle: Double(i) * Double.pi / 2 + Double.pi / 4 + off, color: (m.k + (i % 2) * 2) % 5,
                                           sweep: (i % 2 == 1 ? 1.0 : -1.0) * 0.008 * 60, fireTime: 150.0 / 60)
                    beam.radius = 4.5
                    out.append(beam)
                }
                for j in 0..<10 where room() {
                    out.append(holdBullet(x: core.x, y: core.y, delay: Double(j) * 20 / 60, speed: sp * 2.2, angle: 0, aim: true, look: look(.goo), color: m.k))
                }
            }
        default:
            if !awakened {
                // おすそわけ: 大きなぷに弾を落とし、画面の半ばで3つに分かれる(2回)
                let cyc = k % 80
                guard cyc % 33 == 0 && cyc < 66 && room() else { return }
                let y0 = body.y + 6
                let life = max(0, (320 - y0) / (sp * 0.9))
                var big = holdBullet(x: body.x, y: y0, delay: 0, speed: sp * 0.9, angle: Double.pi / 2, look: look(.jelly), color: m.k, lifetime: life)
                big.radius = 4
                out.append(big)
                for d in [-0.5, 0.0, 0.5] where room() {
                    out.append(holdBullet(x: body.x, y: max(y0, 320), delay: life, speed: sp * 1.4, angle: Double.pi / 2 + d, look: look(.jelly), color: m.k))
                }
            } else {
                // 位相のずれ: 目玉の輪をばらまき、75フレームごとに一部の弾が自機のまわりへ瞬間移動する。移動先には30フレーム前に予告の印が出る
                let cyc = k % 114
                guard cyc % 13 == 0 && cyc < 104 else { return }
                let r = cyc / 13
                let startFrame = Double(r) * 39
                let schedule = (0...20).map { 37 + 75 * Double($0) }
                let warpAt = schedule.first { $0 > startFrame + 15 } ?? 37
                for i in 0..<16 where room() {
                    var b = bullet(core.x, core.y, Double(i) * twoPi / 16 + startFrame * 0.01 + off, sp * 1.5, .eye)
                    if rng.next() < 0.2 {
                        let a = rng.next() * twoPi
                        let d = 50 + rng.next() * 30
                        b.script = Bullet.warpScript
                        b.fuse = (warpAt - startFrame) / 60; b.u0 = a; b.u1 = d
                    }
                    out.append(b)
                }
            }
        }
    }
}
