import Foundation

/// ノエル(クリスマスの期間限定のボス。BossCharacter.santa)の5つの技の弾の出し方。サーバー(santa.ts)にも同じ計算がある。
/// 数値は art/bosses/patterns/engine.js(60fps の px/フレーム)を px/秒に直したもの。(cx, cy) はボスの中心。絵は 112×112
extension Emit {
    /// 浮いているプレゼント(絵の中の (80,36))、杖の先 (28,66)、帽子の鈴 (73,25)
    static func santaGift(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx + 48 * Emit.anchorScale, cy - 40 * Emit.anchorScale) }
    static func santaHook(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx - 56 * Emit.anchorScale, cy + 20 * Emit.anchorScale) }
    static func santaHat(_ cx: Double, _ cy: Double) -> (x: Double, y: Double) { (cx + 34 * Emit.anchorScale, cy - 62 * Emit.anchorScale) }

    static func emitSanta(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                          rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool, salt: UInt32) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let twoPi = 2 * Double.pi
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func look(_ kind: BulletLook.Kind) -> UInt8 { BulletLook.code(kind, awakened: awakened) }
        switch m.t {
        case .santaGift:
            // 贈り物「ひらけ、プレゼント」: 浮いているプレゼントから箱が飛び、自機のまわり(85px 以上はなれた所)で開いて、キャンディの輪になる。
            // 箱は 0.23 秒おきに 1 つずつ。3回撃ったら休む。覚醒は箱が 1 つ多く、キャンディも多く、ゆっくりした星が残る
            guard k % 4 < 3 else { return }
            let o = santaGift(cx, cy)
            let boxes = awakened ? n + 1 : n
            let pieces = awakened ? 12 : 8
            let life = 50.0 / 60
            for j in 0..<boxes {
                let a = rng.next() * twoPi, d = 85 + rng.next() * 65
                let a0 = rng.next() * twoPi
                let tx = min(W - 20, max(20, px + cos(a) * d)), ty = min(H - 30, max(200, py + sin(a) * d))
                let delay = Double(j) * 14 / 60
                let dist = ((tx - o.x) * (tx - o.x) + (ty - o.y) * (ty - o.y)).squareRoot()
                guard room() else { continue }
                out.append(holdBullet(x: o.x, y: o.y, delay: delay, speed: dist / life, angle: atan2(ty - o.y, tx - o.x), look: look(.gift), color: m.k, lifetime: life))
                for i in 0..<pieces where room() {
                    out.append(holdBullet(x: tx, y: ty, delay: delay + life, speed: sp, angle: a0 + Double(i) * twoPi / Double(pieces), look: look(.candy), color: m.k))
                }
                if awakened {
                    for i in 0..<4 where room() {
                        out.append(holdBullet(x: tx, y: ty, delay: delay + life, speed: sp * 0.54, angle: a0 + (Double(i) + 0.5) * twoPi / 4, look: look(.star), color: m.k))
                    }
                }
            }
        case .santaBell:
            // 鈴「ジングル・リング」: 帽子の鈴から、鈴の輪が左右にゆれながら広がる。輪ごとにゆれる向きが逆。3回撃ったら休む(覚醒は 5 回・数が多く・速い)
            let volleys = awakened ? 5 : 3
            guard k % (volleys + 1) < volleys else { return }
            let o = santaHat(cx, cy)
            let count = awakened ? (n * 5 + 2) / 4 : n
            let a0 = rng.next() * twoPi + off
            let dir = k % 2 == 1 ? 1.0 : -1.0
            let v = awakened ? sp * 1.19 : sp
            for i in 0..<count where room() {
                let a = a0 + Double(i) * twoPi / Double(count)
                var b = Bullet(x: o.x, y: o.y, vx: cos(a) * v, vy: sin(a) * v, color: m.k)
                b.look = look(.bell)
                b.script = Bullet.wobbleScript
                b.u0 = 0.72 * dir; b.u1 = 4.2; b.u2 = Double.pi / 2; b.u3 = 0; b.turn = 0
                out.append(b)
            }
        case .santaCane:
            // 杖「キャンディケイン」: 杖の先からキャンディの列が自機の横へ飛び、0.67 秒後、杖の先の形に半回転して戻ってくる。
            // 6 発つづけて撃って、5 発ぶん休む。左右交互(覚醒は左右同時・1列多い)
            let cycle = k / 11, step = k % 11
            guard step < 6 else { return }
            let o = santaHook(cx, cy)
            let a0 = atan2(py - o.y, px - o.x) + off
            let rows = awakened ? n + 1 : n
            let sides: [Double] = awakened ? [1, -1] : [cycle % 2 == 1 ? 1 : -1]
            for side in sides {
                for i in 0..<rows where room() {
                    let a = a0 + side * (0.25 + Double(i) * 0.3)
                    var b = Bullet(x: o.x, y: o.y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                    b.look = look(.candy)
                    b.script = Bullet.hookScript
                    b.u0 = -side * Double.pi / (56.0 / 60); b.u1 = 40.0 / 60; b.u2 = 56.0 / 60
                    out.append(b)
                }
            }
        case .santaTree:
            // 聖樹「ツリーの灯」: 上から、星の飾りがツリーの形(三角)に並んで降ってくる。先頭は自機の近く。いちばん下に幹の箱が 3 つ。
            // 星のあいだ(26px)を抜けるか、横へよける。覚醒は、少し遅れてもう 1 本、反対側に降る
            let rows = n
            let first = min(W - 90, max(90, px + (rng.next() - 0.5) * 60))
            var centers = [(first, 0.5)]
            if awakened { centers.append((min(W - 90, max(90, first + (first < W / 2 ? 120 : -120))), 1.1)) }
            for (center, wait) in centers {
                for r in 0..<rows {
                    for i in 0...r where room() {
                        out.append(holdBullet(x: center + (Double(i) - Double(r) / 2) * 26, y: -6, delay: wait + Double(r) * 0.25, speed: sp, angle: Double.pi / 2, look: look(.star), color: m.k))
                    }
                }
                let trunk = wait + Double(rows - 1) * 0.25 + 22 / sp
                for dx in [-13.0, 0, 13] where room() {
                    out.append(holdBullet(x: center + dx, y: -6, delay: trunk, speed: sp, angle: Double.pi / 2, look: look(.gift), color: m.k))
                }
            }
        default:
            // 煙突「真夜中の配達」: 上から箱がまっすぐ落ちてきて、下で開いてキャンディが上へ扇に飛ぶ。1 つは必ず自機の真上に落ちる。
            // 落ちる場所は、開く前からキャンディの光で分かる。4回撃ったら休む(覚醒は箱とキャンディが多い)
            guard k % 5 < 4 else { return }
            let boxes = awakened ? n + 2 : n
            let pieces = awakened ? 7 : 5
            let wait = 34.0 / 60
            let land = H - 40
            let life = (land + 6) / sp
            for j in 0..<boxes {
                let x = j == 0 ? min(W - 16, max(16, px)) : 16 + rng.next() * (W - 32)
                guard room() else { continue }
                out.append(holdBullet(x: x, y: -6, delay: wait, speed: sp, angle: Double.pi / 2, look: look(.gift), color: m.k, lifetime: life))
                for i in 0..<pieces where room() {
                    out.append(holdBullet(x: x, y: land, delay: wait + life, speed: sp * 0.425, angle: -Double.pi / 2 + (Double(i) - Double(pieces - 1) / 2) * 0.34,
                                          look: look(.candy), color: m.k, gravity: 0.012 * 3600))
                }
            }
        }
    }
}
