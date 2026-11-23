import Foundation

// 弾幕パック3(1.4.2)の11パターン。弾の出し方と、専用の弾の動き(印 = script 40〜44)。
// サーバーの firebase/functions/src/pack3.ts に、同じ計算がある(式を変えたら、両方を直して照合データを作り直す)。

extension Bullet {
    /// 急加速弾: 出てから u0 秒たったら、速さを u1 倍にする(一度だけ。そのあとは、ふつうの弾)
    public static let dashScript = 40
    /// 瞬間移動弾: homeLeft 秒ごとに、進む向きへ u1 px 飛ぶ(残り u2 回)。u0 が飛ぶ間隔(秒)
    public static let blinkScript = 41
    /// つむじ風: 中心 (u0, u1) が速さ (vx, vy) で進み、そのまわりの半径 u3 を、角度 u2 から turn(ラジアン/秒)で回る
    public static let whirlScript = 42
    /// バウンドボール: 重力(gravity)で落ち、画面の下で u0 回まではね返る
    public static let floorBounceScript = 43
    /// 吸い込み弾: ふつうに進むだけ。画面の外の大きな輪から出るので、画面の外でもしばらく消さない
    public static let implodeScript = 44

    /// バウンドボールがはね返る高さ(画面の下の端から少し上)と、はね返ったあとの速さの割合
    static let floorY = DanmakuConfig.height - 6
    static let floorKeep = 0.75
    /// 吸い込み弾が出る輪の半径(px)
    public static let implodeRadius = 150.0

    /// パック3の弾の1ステップ。パック3の弾でなければ nil
    mutating func advancePack3Script(dt: Double) -> BulletMotion? {
        switch script {
        case Bullet.dashScript:
            age += dt
            if u0 > 0 && age >= u0 { vx *= u1; vy *= u1; u0 = 0 }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.blinkScript:
            age += dt
            homeLeft -= dt
            if homeLeft <= 0 && u2 > 0 {
                let sp = (vx * vx + vy * vy).squareRoot()
                if sp > 0 { x += vx / sp * u1; y += vy / sp * u1 }
                u2 -= 1
                homeLeft += u0
            }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.whirlScript:
            age += dt
            let ang = u2 + turn * age
            x = u0 + vx * age + cos(ang) * u3
            y = u1 + vy * age + sin(ang) * u3
            return .alive
        case Bullet.floorBounceScript:
            age += dt
            vy += gravity * dt
            x += vx * dt; y += vy * dt
            if u0 > 0 && vy > 0 && y > Bullet.floorY {
                y = 2 * Bullet.floorY - y
                vy = -vy * Bullet.floorKeep
                u0 -= 1
            }
            return .alive
        case Bullet.implodeScript:
            age += dt
            x += vx * dt; y += vy * dt
            return .alive
        default:
            return nil
        }
    }

    /// 瞬間移動弾が、いま消えて見えるか(飛ぶ直前の短い間。見た目だけ)
    public var blinkHidden: Bool { script == Bullet.blinkScript && u2 > 0 && homeLeft < 0.08 }
}

extension Emit {
    /// パック3の弾の出し方(Emit.emitCore から呼ぶ)
    static func emitPack3(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                          rng: inout Mulberry32, into out: inout [Bullet]) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let deg = Double.pi / 180
        let off = Double(m.a) * deg
        let W = DanmakuConfig.width
        func push(_ b: Bullet) { if out.count < DanmakuConfig.maxBullets { out.append(b) } }
        /// 自機狙いの扇で、j 番目の向き
        func fan(_ base: Double, _ j: Int) -> Double { base + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0) }
        switch m.t {
        case .radialLaser:
            // 全方位レーザー: n 本の光線を、等しい角度で全方向へ。撃っている間、みな同じ向きに 40 度回る。r は 1 回ごとの回転
            let sweep = 40 * deg, fire = 1.4
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                push(Bullet.beam(x: cx, y: cy, angle: a - sweep / 2, color: m.k, sweep: sweep / fire, fireTime: fire))
            }
        case .lightning:
            // 落雷: 画面の上の、ばらばらの横の位置から、真下へ光線
            for _ in 0..<n {
                let x = 12 + rng.next() * (W - 24)
                push(Bullet.beam(x: x, y: -10, angle: Double.pi / 2, color: m.k, fireTime: 0.35))
            }
        case .carpetBomb:
            // 爆撃ライン: 自機のほうへ向かう線の上に、爆発が順に連なる(遠いものほど遅れて爆発)
            let a = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let d = 36 + Double(j) * 34
                push(Bullet.blast(x: cx + cos(a) * d, y: cy + sin(a) * d, radius: 22, warn: 0.6 + Double(j) * 0.12, color: m.k))
            }
        case .dashShot:
            // 急加速弾: 自機狙いの扇。ゆっくり出て、0.9 秒で急に 4 倍の速さになる
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = fan(b, j)
                var q = Bullet(x: cx, y: cy, vx: cos(a) * sp * 0.35, vy: sin(a) * sp * 0.35, color: m.k, script: Bullet.dashScript)
                q.u0 = 0.9; q.u1 = 4
                push(q)
            }
        case .implode:
            // 吸い込み弾: 発射口のまわりの大きな輪から、中心へ向かって集まり、そのまま抜けて広がる。r は 1 回ごとの回転
            let R = Bullet.implodeRadius
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                push(Bullet(x: cx + cos(a) * R, y: cy + sin(a) * R, vx: -cos(a) * sp, vy: -sin(a) * sp, color: m.k, script: Bullet.implodeScript))
            }
        case .pincer:
            // 挟み撃ち: 画面の左右の端から、自機の高さへ、まっすぐ横に。片側 n 発を縦に並べる
            for j in 0..<n {
                let y = py + (Double(j) - Double(n - 1) / 2) * 18
                push(Bullet(x: -8, y: y, vx: sp, vy: 0, color: m.k))
                push(Bullet(x: W + 8, y: y, vx: -sp, vy: 0, color: m.k))
            }
        case .whirlwind:
            // つむじ風: n 発の弾が輪になって回りながら、輪ごと自機のほうへ流れてくる
            let a = atan2(py - cy, px - cx) + off
            let cvx = cos(a) * sp * 0.6, cvy = sin(a) * sp * 0.6
            let R = 16.0
            for j in 0..<n {
                let a0 = Double(j) * 2 * Double.pi / Double(n) + Double(k) * 0.5
                var q = Bullet(x: cx + cos(a0) * R, y: cy + sin(a0) * R, vx: cvx, vy: cvy, color: m.k, turn: 5, script: Bullet.whirlScript)
                q.u0 = cx; q.u1 = cy; q.u2 = a0; q.u3 = R
                push(q)
            }
        case .bounceBall:
            // バウンドボール: 上へ投げ上げ、放物線で落ちて、画面の下で 1 回はねる。r は投げる扇の広さ
            for j in 0..<n {
                let a = fan(-Double.pi / 2 + off, j)
                var q = Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, script: Bullet.floorBounceScript)
                q.gravity = 220; q.u0 = 1
                push(q)
            }
        case .needle:
            // ニードル: 細長い針(3 つの粒を、進む向きに 6px ずつ並べる)を、自機狙いの扇に
            let b = atan2(py - cy, px - cx) + off
            let look = BulletLook.code(.needle)
            for j in 0..<n {
                let a = fan(b, j)
                for s in 0..<3 {
                    var q = Bullet(x: cx - cos(a) * 6 * Double(s), y: cy - sin(a) * 6 * Double(s), vx: cos(a) * sp, vy: sin(a) * sp, color: m.k)
                    q.look = look
                    push(q)
                }
            }
        case .trackLaser:
            // 追跡レーザー: ためている間(0.8 秒まで)、自機を追って向きを合わせ、止めてから撃つ。
            // 2 本目からは、発射口の左右 28px ずつ離れたところから出る
            for j in 0..<n {
                let dx = j == 0 ? 0 : Double((j + 1) / 2) * 28 * (j % 2 == 1 ? 1 : -1)
                let x = cx + dx
                var q = Bullet.beam(x: x, y: cy, angle: atan2(py - cy, px - x) + off, color: m.k, fireTime: 0.6)
                q.u0 = 0.8
                push(q)
            }
        case .blinkShot:
            // 瞬間移動弾: 自機狙いの扇。0.5 秒ごとに、進む向きへ 48px ふっと飛ぶ(3 回)
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = fan(b, j)
                var q = Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, homeLeft: 0.5, script: Bullet.blinkScript)
                q.u0 = 0.5; q.u1 = 48; q.u2 = 3
                push(q)
            }
        default:
            break
        }
    }
}

public extension Pattern {
    /// パック3のパターンを、エディタで選んだときの初期値(間隔・数・速さ・角度)
    var pack3Defaults: (i: Double, c: Int, v: Double, r: Double)? {
        switch self {
        case .radialLaser: return (3.2, 8, 2.0, 15)
        case .lightning: return (1.6, 3, 2.0, 0)
        case .carpetBomb: return (2.2, 7, 2.0, 0)
        case .dashShot: return (1.0, 7, 2.0, 40)
        case .implode: return (1.6, 16, 2.0, 8)
        case .pincer: return (1.4, 3, 2.0, 0)
        case .whirlwind: return (1.5, 6, 2.0, 0)
        case .bounceBall: return (1.0, 4, 2.2, 50)
        case .needle: return (0.8, 5, 2.6, 40)
        case .trackLaser: return (3.0, 1, 2.0, 0)
        case .blinkShot: return (1.0, 5, 2.0, 30)
        default: return nil
        }
    }
    /// 表(広告・パック2)か、パック3の初期値
    var tableDefaults: (i: Double, c: Int, v: Double, r: Double)? { recipeDefaults ?? pack3Defaults }
}
