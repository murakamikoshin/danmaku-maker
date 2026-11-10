import Foundation

/// 九尾の巫女の5つの技の弾の出し方。サーバー(kitsune.ts)にも同じ計算がある。
/// 1回の発射(shot k)は、技の「1コマ」。時間のかかる技(灯る・撃つ)は、発射の間隔(i)ごとに1コマずつ進む。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を、px/秒(×60)に直したもの。(cx, cy) はボスの中心
extension Emit {
    /// 尻尾の付け根(絵の中の (56,60))と、尻尾の先 k=0〜8(角度 -90°+(k-4)×24°、半径46。絵は2倍)
    static func kitsuneRoot(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx, cy + 8) }
    static func kitsuneTip(_ k: Int, _ cx: Double, _ cy: Double) -> (x: Double, y: Double) {
        let a = (-90.0 + Double(k - 4) * 24.0) * Double.pi / 180
        return (cx + cos(a) * 92, cy + 8 + sin(a) * 92)
    }

    static func emitKitsune(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                            rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func add(_ x: Double, _ y: Double, _ a: Double, _ speed: Double, _ kind: BulletLook.Kind) -> Bullet {
            var b = Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: m.k)
            b.look = BulletLook.code(kind, awakened: awakened)
            return b
        }
        switch m.t {
        case .kitsuneLanterns:
            // 九つの灯: 9回の発射で順に灯り(撃たない)、次の9回で同じ順に自機へ飛ばす。覚醒すると2周し、2周目は逆の端から。1つの先から3way
            let cycle = awakened ? 36 : 18
            let j = k % cycle
            let within = j % 18
            guard within >= 9 else { return }
            let idx = within - 9
            let tipIndex = (j / 18) % 2 == 1 ? 8 - idx : idx
            let o = kitsuneTip(tipIndex, cx, cy)
            let aim = atan2(py - o.y, px - o.x) + off
            let speed = awakened ? sp * 3.8 / 3.2 : sp
            for d in (awakened ? [-0.18, 0.0, 0.18] : [0.0]) where room() {
                out.append(add(o.x, o.y, aim + d, speed, .fox))
            }
        case .kitsuneBarrier:
            // 直角結界: 付け根から御札の輪。0.6秒で直角に曲がり(向きは1枚ごとに左右交互)、格子になる。覚醒は枚数1.5倍で、1.2秒でもう一度逆に曲がる
            let root = kitsuneRoot(cx, cy)
            let count = awakened ? (n * 3 + 1) / 2 : n
            for i in 0..<count where room() {
                let s = i % 2 == 1 ? 1.0 : -1.0
                let a = Double(k) * 0.26 + Double(i) * twoPi / Double(count) + off
                var b = add(root.x, root.y, a, sp, .ofuda)
                b.script = Bullet.foldScript
                b.u0 = 36.0 / 60; b.u1 = s * Double.pi / 2; b.u2 = awakened ? 72.0 / 60 : 0; b.u3 = 1.2
                out.append(b)
            }
        case .kitsuneSunshower:
            // 天気雨: 空から狐火が左右に揺れながら降る(覚醒は2倍・速い)。10回(0.5秒)に1回、自機狙いの御札3way
            let root = kitsuneRoot(cx, cy)
            // 間隔 0.05秒(3フレーム)の目盛りで、4フレームに1粒(覚醒は2フレームに1粒)になるよう間引く
            // 150フレーム(50回)降らせて、60フレーム休む
            let cyc = k % 70
            let drops = cyc >= 50 ? 0 : (awakened ? (cyc % 2 == 0 ? 2 : 1) : (cyc % 4 == 3 ? 0 : 1))
            for _ in 0..<drops {
                let x = rng.next() * DanmakuConfig.width
                let ph = rng.next() * 9
                guard room() else { continue }
                var b = add(x, -8, Double.pi / 2, awakened ? sp * 2.8 / 2.2 : sp, .fox)
                b.script = Bullet.swayScript
                b.u0 = ph * 20 * 0.04; b.u1 = 0.04; b.u2 = 0.8 * 60
                out.append(b)
            }
            if cyc < 50 && cyc % 10 == 0 {
                let aim = atan2(py - root.y, px - root.x) + off
                for d in [-0.2, 0.0, 0.2] where room() { out.append(add(root.x, root.y, aim + d, sp * 2.6 / 2.2, .ofuda)) }
            }
        case .kitsuneTorii:
            // 千本鳥居: 御札の横一列の壁が下りてくる。通り道は1か所で、8列ごとに真ん中に戻り、列ごとに30〜60pxずれる。r が通り道の広さ(0 なら60、覚醒は0.8倍)
            let row = k % 8, cycle = k / 8
            var r = Mulberry32(seed: salt ^ 0x0007_0F11 ^ (UInt32(truncatingIfNeeded: cycle) &* 0x9E37_79B1))
            var gx = 180.0
            for _ in 0...row {
                let dir = r.next() < 0.5 ? -1.0 : 1.0
                gx = min(310, max(50, gx + dir * (30 + r.next() * 30)))
            }
            let gap = (m.r == 0 ? 60.0 : abs(m.r)) * (awakened ? 0.8 : 1)
            let root = kitsuneRoot(cx, cy)
            var x = 8.0
            while x < DanmakuConfig.width {
                defer { x += 16 }
                if abs(x - gx) < gap / 2 || !room() { continue }
                var b = add(x, root.y, Double.pi / 2, sp, .ofuda)
                if awakened { b.script = Bullet.swayScript; b.u0 = Double(row); b.u1 = 0.05; b.u2 = 0.6 * 60 }
                out.append(b)
            }
        default:
            // 玉藻の舞: 九本の尻尾の先から、下向きの扇に狐火。扇は尻尾ごとに揺れる。覚醒は1つの先から2本(揺れが逆向き)
            // 4回に1回は休んで、平均で4フレームに1回の扇にする(間隔の目盛りが0.05秒刻みのため)
            // 120フレーム(40回)撃って、48フレーム休む
            let cyc = k % 56
            if cyc >= 40 || cyc % 4 == 3 { return }
            let t = Double(cyc) * m.i * 60
            for tip in 0..<9 {
                let o = kitsuneTip(tip, cx, cy)
                let base = Double.pi / 2 + Double(tip - 4) * 0.28 + off
                let sway = sin(t * 0.05 + Double(tip)) * 0.5
                let speed = awakened ? sp * 2.6 / 2.2 : sp
                if room() { out.append(add(o.x, o.y, base + sway, speed, .fox)) }
                if awakened && room() { out.append(add(o.x, o.y, base - sway, speed, .fox)) }
            }
        }
    }
}
