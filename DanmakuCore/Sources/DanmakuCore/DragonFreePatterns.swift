import Foundation

/// 竜王の、数・速さ・向き・左右反転を自由に決められる5つの技(1.4.0)。サーバー(dragonfree.ts)にも同じ計算がある。
/// ほかの技と同じく、弾を出すだけ(本体は動かない・範囲攻撃もない)。強さは段階ごとの姿(Emit.dragonLv: 0 通常〜3 白金)で上がる。
/// (cx, cy) は竜王の中心。弾は竜王の弾の絵で、竜王の演出(光・火花)つきで描く
extension Emit {
    /// 竜王の姿(0〜3)。ゲームの計算が竜王の技を撃つ間だけ変える(ほかは 0)。計算はスレッドごとに独立して動くので、スレッドごとに持つ
    public static var dragonLv: Int {
        get { (Thread.current.threadDictionary[dragonLvKey] as? Int) ?? 0 }
        set { if newValue == 0 { Thread.current.threadDictionary.removeObject(forKey: dragonLvKey) } else { Thread.current.threadDictionary[dragonLvKey] = newValue } }
    }
    private static let dragonLvKey = "danmaku.emit.dragonLv"

    static func emitDragonFree(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                               rng: inout Mulberry32, into out: inout [Bullet]) {
        let L = min(max(Emit.dragonLv, 0), 3)
        let sp = m.v * 60
        let n = max(1, m.c)
        let off = Double(m.a) * Double.pi / 180
        let s = Emit.anchorScale
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        let pi = Double.pi
        func room() -> Bool { out.count < DanmakuConfig.maxBullets }
        func add(_ kind: BulletLook.Kind, _ x: Double, _ y: Double, _ a: Double, _ speed: Double, r: Double, script: Int,
                 fuse: Double = 0, u0: Double = 0, u1: Double = 0, gravity: Double = 0) {
            guard room() else { return }
            var b = Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: m.k)
            b.look = BulletLook.code(kind, awakened: L > 0)
            b.script = script
            b.radius = r
            b.fuse = fuse; b.u0 = u0; b.u1 = u1
            b.gravity = gravity
            out.append(b)
        }
        switch m.t {
        case .dragonWings:
            // 双翼の羽ばたき: 左右の翼の先から、風の弾が外へ扇に広がり、内側へ曲がって画面の中ほどで交差する(翼を閉じる動き)。
            // 数 = 片方の翼の弾の数。向き = 翼の開き(+ で外へ開く)。姿が強いほど、速く・よく曲がる
            let speed = sp * (1 + 0.08 * Double(L))
            let turn = 1.4 + 0.25 * Double(L)
            for side in [-1.0, 1.0] {
                let ox = cx + side * 150 * s, oy = cy + 20 * s
                for j in 0..<n {
                    let t = n > 1 ? Double(j) / Double(n - 1) : 0.5
                    let a = pi / 2 - side * (0.25 + 0.95 * t + off)
                    add(.gust, ox, oy, a, speed, r: 4, script: Bullet.dragonCurveScript, u0: side * turn, u1: 0.9)
                }
            }
        case .dragonGeyser:
            // 噴き上がる火柱: 自機のまわりの、画面の下の端から炎の柱が噴き上がり、重力でまた落ちる。
            // 数 = 柱の本数。向き = 柱の傾き。柱の根もとで炎が少しためてから噴く。姿が強いほど、1本の炎が多い
            let cols = min(n, 12)
            let gap = min(64, (W - 40) / Double(cols))
            let center = min(W - 20 - gap * Double(cols - 1) / 2, max(20 + gap * Double(cols - 1) / 2, px))
            let per = 4 + L
            let a = -pi / 2 + off
            for i in 0..<cols {
                let x = min(W - 10, max(10, center + (Double(i) - Double(cols - 1) / 2) * gap + (rng.next() - 0.5) * 8))
                for j in 0..<per {
                    add(.flame, x, H + 6, a, sp * 1.5 * (1 - Double(j) * 0.06), r: 4, script: Bullet.dragonWaitScript,
                        fuse: 0.55 + Double(j) * 0.06, gravity: 120)
                }
            }
        case .dragonClaw:
            // 竜爪三連: 自機の斜め上に、爪あとの線が3本(白金は4本)現れ、少し止まってから、近い線から順に自機のほうへ滑ってくる。
            // 数 = 1本の線の弾の数。向き = 爪の角度。撃つたびに、左右が入れ替わる
            let lines = L >= 3 ? 4 : 3
            let theta = k % 2 == 0 ? pi / 4 + off : 3 * pi / 4 - off
            // 線に垂直で、上を向く側(右上 / 左上)。弾はその反対(自機のほう)へ滑る
            let nrm = k % 2 == 0 ? theta - pi / 2 : theta + pi / 2
            let (nx, ny) = (cos(nrm), sin(nrm))
            let (tx, ty) = (cos(theta), sin(theta))
            let speed = sp * (1 + 0.1 * Double(L))
            for i in 0..<lines {
                let d = 130 + Double(i) * 36
                let lx = px + nx * d, ly = py + ny * d
                for j in 0..<n {
                    let q = (Double(j) - Double(n - 1) / 2) * 16
                    add(.slash, lx + tx * q, ly + ty * q, nrm + pi, speed, r: 4, script: Bullet.dragonWaitScript, fuse: 0.5 + Double(i) * 0.14)
                }
            }
        case .dragonTwister:
            // 竜巻の行進: 画面を左右に往復する竜巻から、渦を巻く風の弾がまき散らされる(撃つ場所が動く)。
            // 数 = 1回にまく弾の数。向き = まく向きのずれ。紫電・白金は、逆に巻く炎の弾も混ざる
            let T = Double(k) * max(0.05, m.i)
            let tx = W / 2 + sin(T * 0.9) * (W / 2 - 40)
            let ty = cy + 150 * s + sin(T * 1.7) * 20
            let speed = sp * (1 + 0.08 * Double(L))
            let spin = 1.6 + 0.3 * Double(L)
            for j in 0..<n {
                let a = Double(j) * 2 * pi / Double(n) + T * 2.2 + off
                add(.gust, tx + cos(a) * 10, ty + sin(a) * 10, a, speed, r: 4, script: Bullet.dragonCurveScript, u0: spin, u1: 1.2)
            }
            if L >= 2 {
                let half = max(1, n / 2)
                for j in 0..<half {
                    let a = Double(j) * 2 * pi / Double(half) - T * 2.2 + off
                    add(.flame, tx, ty, a, speed * 0.85, r: 4, script: Bullet.dragonCurveScript, u0: -spin, u1: 1.2)
                }
            }
        default:
            // 顎の挟み撃ち: 自機の上と下に、牙の弧(上あご・下あご)が現れ、少し止まってから、閉じるように自機のいた場所へ迫る。
            // 数 = 片方のあごの牙の数。向き = あごの向き。姿が強いほど、あごの横のすき間が狭く、速い
            let margin = Simulation.dv(L, 0.45, 0.38, 0.3, 0.22)
            let ccx = min(W - 30, max(30, px)), ccy = min(py, H - 130)
            let R = 125.0
            let speed = sp * (1 + 0.1 * Double(L))
            for jaw in [pi, 0.0] {
                for j in 0..<n {
                    let t = n > 1 ? Double(j) / Double(n - 1) : 0.5
                    let phi = jaw + margin + (pi - 2 * margin) * t + off
                    add(.spine, ccx + cos(phi) * R, ccy + sin(phi) * R, phi + pi, speed, r: 3, script: Bullet.dragonWaitScript, fuse: 0.55)
                }
            }
        }
    }
}
