import Foundation

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Bullet: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var color: Int
    /// 追尾弾の曲がる速さ(ラジアン/秒。0 なら追尾しない)と、追尾の残り時間(秒)
    public var turn: Double = 0
    public var homeLeft: Double = 0
}

/// 1ステップ分の自機移動量。単位は 0.25 論理px（リプレイに入れるため整数にしてある）
public struct Move: Equatable, Sendable {
    public static let unit = 0.25
    public var dx: Int8
    public var dy: Int8
    public init(dx: Int8 = 0, dy: Int8 = 0) { self.dx = dx; self.dy = dy }
    public static let zero = Move()
}

public enum Outcome: Equatable, Sendable {
    case playing, cleared, hit, timeUp
}

public enum Emit {
    /// 試作の `emit` と同じ。弾数は 1600 で頭打ち（乱数は上限でも消費する）
    public static func emit(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                     rng: inout Mulberry32, into out: inout [Bullet]) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let deg = Double.pi / 180
        func add(_ x: Double, _ y: Double, _ a: Double) {
            if out.count < DanmakuConfig.maxBullets {
                out.append(Bullet(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k))
            }
        }
        switch m.t {
        case .ring, .spiral:
            for j in 0..<n { add(cx, cy, Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg) }
        case .aim:
            let b = atan2(py - cy, px - cx)
            for j in 0..<n {
                add(cx, cy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0))
            }
        case .rain:
            for _ in 0..<n {
                let x = rng.next() * DanmakuConfig.width
                let a = Double.pi / 2 + (rng.next() - 0.5) * 0.3
                add(x, -8, a)
            }
        case .homing:
            // 最初は自機の方向へ。複数のときは少しずつ角度をずらして出す。曲がる速さは r で決める(大きいほど急に曲がる)
            let b = atan2(py - cy, px - cx)
            let turn = max(25.0, abs(m.r) * 2.0) * deg
            for j in 0..<n {
                let a = b + (Double(j) - Double(n - 1) / 2) * 0.35
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, turn: turn, homeLeft: DanmakuConfig.homingSeconds))
                }
            }
        case .sideL, .sideR:
            // 左右の端から横切る。高さはばらばら(自機の初期位置より少し上まで)。r はばらつきの角度(±)
            let toRight = m.t == .sideL
            let x0 = toRight ? -8.0 : DanmakuConfig.width + 8
            let spread = abs(m.r) * deg
            for _ in 0..<n {
                let y = rng.next() * DanmakuConfig.height * 0.78
                let a = (toRight ? 0.0 : Double.pi) + (rng.next() - 0.5) * 2 * spread
                add(x0, y, a)
            }
        case .corner:
            // 四隅(下の2つは、自機に近すぎないよう画面の6割の高さ)から自機に向けて、r 度の扇状に撃つ
            let w = DanmakuConfig.width, h = DanmakuConfig.height
            let corners: [(Double, Double)] = [(-8, -8), (w + 8, -8), (-8, h * 0.6), (w + 8, h * 0.6)]
            for (ox, oy) in corners {
                let b = atan2(py - oy, px - ox)
                for j in 0..<n {
                    add(ox, oy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0))
                }
            }
        case .sweep:
            let b = Double.pi / 2 + sin(Double(k) * 0.25) * m.r * deg
            for j in 0..<n {
                add(cx, cy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * 0.5 : 0))
            }
        }
    }
}

/// ステージのシミュレーション。計算だけを行い、描画には一切依存しない
public struct Simulation {
    public let stage: Stage
    public private(set) var tick = 0
    /// ゲーム内時間。READY 中は負。試作と同じく 1/120 を足していく
    public private(set) var t = -DanmakuConfig.readySeconds
    public private(set) var player = Point(x: DanmakuConfig.width / 2, y: DanmakuConfig.height * 0.85)
    public private(set) var bullets: [Bullet] = []
    public private(set) var shots: [PlayerShot] = []
    public let shotType: ShotType
    public private(set) var hp: Int
    /// ボスに与えたダメージの合計(ボス戦でも数える)
    public private(set) var damageDealt = 0
    public private(set) var phase = 1
    /// 「第N段階」表示の残り秒数
    public private(set) var banner = 0.0
    public private(set) var flash = 0.0
    public private(set) var outcome = Outcome.playing
    /// 被弾を無視する。UI テスト専用（アプリ側は DEBUG ビルドでしか立てない）
    public var invincible = false
    /// 復活直後の無敵が切れるステップ
    public private(set) var shieldUntilTick = 0
    /// 自機の耐久(ライフ制のときはライフの数、HP 制のときは HP)
    public let lifeMode: LifeMode
    public let lifeMax: Int
    public private(set) var lifeLeft: Int
    /// 被弾の直後に残りを数える表示用(秒)。画面のひらめきに使う
    public private(set) var hitFlash = 0.0

    private var cooldown = 0.0
    private var rng: Mulberry32
    private var next: [Double]
    private var shotCount: [Int]

    /// ライフ制で1つ失ったあとの無敵の長さ(秒)
    static let lifeShieldSeconds = 2.0

    static let bossMoves: [(a: Double, w: Double)] = [(0, 0), (0.25, 0.6), (0.32, 1.3)]

    public init(stage: Stage, shotType: ShotType = .standard) {
        self.init(stage: stage, seed: stage.seed, shotType: shotType)
    }

    init(stage: Stage, seed: UInt32, shotType: ShotType = .standard) {
        self.stage = stage
        self.shotType = shotType
        lifeMode = stage.effectiveLifeMode
        lifeMax = stage.effectiveLifeCount
        lifeLeft = stage.effectiveLifeCount
        hp = stage.bossHp ?? 0
        rng = Mulberry32(seed: seed)
        next = stage.emitters.map(\.s)
        shotCount = Array(repeating: 0, count: stage.emitters.count)
    }

    /// ボスが出る(ボス戦とダメージ勝負)
    public var isBoss: Bool { stage.mode != .survive }
    /// ダメージ勝負(ボスの HP は無限。与えたダメージの合計を数える)
    public var isDamageRace: Bool { stage.mode == .damage }

    /// 復活直後で、被弾しない状態か
    public var isShielded: Bool { tick < shieldUntilTick }

    /// 被弾した場所からそのまま復活する。画面の弾を全消去し、短い間だけ無敵にする
    public mutating func revive(shieldSeconds: Double = 2) {
        guard outcome == .hit else { return }
        outcome = .playing
        // 復活のとき、ライフは1、HP は半分(最低1)まで戻す
        lifeLeft = lifeMode == .lives ? 1 : max(1, lifeMax / 2)
        bullets.removeAll(keepingCapacity: true)
        shieldUntilTick = tick + Int((shieldSeconds / DanmakuConfig.step).rounded())
    }

    public var bossPosition: Point {
        let mv = Simulation.bossMoves[stage.bossMove ?? 0]
        return Point(x: DanmakuConfig.width * (0.5 + mv.a * sin(max(0, t) * mv.w)),
                     y: DanmakuConfig.height * 0.18)
    }

    private func phaseOf() -> Int {
        if isDamageRace {
            // ダメージ勝負は、HP ではなく時間の3分の1ずつで段階が進む
            let f = max(0, t) / Double(stage.durationSec)
            return f < 1.0 / 3 ? 1 : f < 2.0 / 3 ? 2 : 3
        }
        let r = Double(hp) / Double(stage.bossHp ?? 1)
        return r > 2.0 / 3 ? 1 : r > 1.0 / 3 ? 2 : 3
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// 1ステップ（1/120 秒）進める。終了後は何もしない
    public mutating func step(_ move: Move) {
        guard outcome == .playing else { return }
        let dt = DanmakuConfig.step
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        tick += 1
        t += dt
        if hitFlash > 0 { hitFlash = max(0, hitFlash - dt) }
        player.x = Simulation.clamp(player.x + Double(move.dx) * Move.unit, 6, W - 6)
        player.y = Simulation.clamp(player.y + Double(move.dy) * Move.unit, 6, H - 6)

        let bp = isBoss ? bossPosition : Point(x: 0, y: 0)
        if isBoss {
            let ph = phaseOf()
            if ph != phase {
                phase = ph
                if ph > 1 { bullets.removeAll(keepingCapacity: true); banner = 1.2 }
            }
            if banner > 0 { banner -= dt }
            cooldown -= dt
            if t >= 0 && cooldown <= 0 {
                cooldown = shotType.interval
                for spec in shotType.volley {
                    shots.append(PlayerShot(x: player.x + spec.dx, y: player.y - 10, vx: spec.vx, damage: spec.damage))
                }
            }
            var w = 0
            for var s in shots {
                s.x += s.vx * dt
                s.y -= 600 * dt
                if s.y < -10 || s.x < -10 || s.x > W + 10 { continue }
                let dx = s.x - bp.x, dy = s.y - bp.y
                if dx * dx + dy * dy < 24 * 24 {
                    damageDealt += s.damage
                    if !isDamageRace { hp -= s.damage }
                    flash = 0.06; continue
                }
                shots[w] = s; w += 1
            }
            shots.removeSubrange(w...)
            if flash > 0 { flash -= dt }
            if !isDamageRace && hp <= 0 { outcome = .cleared; return }
        }

        if t >= 0 {
            for (idx, m) in stage.emitters.enumerated() {
                if isBoss {
                    if !(m.ph == 0 || m.ph == phase) || banner > 0 { next[idx] = t; continue }
                    while t >= next[idx] {
                        // ボス戦でも、好きな場所から出せる(p == 1)。雨は、これまでどおり位置を使わない
                        let fx = m.firesFromPoint ? m.x * W : bp.x
                        let fy = m.firesFromPoint ? m.y * H : bp.y
                        Emit.emit(m, shot: shotCount[idx], cx: m.t == .rain ? 0 : fx, cy: fy,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets)
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                } else {
                    let end = min(m.e, Double(stage.durationSec))
                    while t >= next[idx] && next[idx] < end {
                        Emit.emit(m, shot: shotCount[idx], cx: m.x * W, cy: m.y * H,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets)
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                }
            }
        }

        var w = 0
        for i in 0..<bullets.count {
            var b = bullets[i]
            if b.homeLeft > 0 {
                // 追尾: 速さはそのまま、向きだけを、1ステップあたり turn*dt まで自機のほうへ回す
                let want = atan2(player.y - b.y, player.x - b.x)
                let cur = atan2(b.vy, b.vx)
                var diff = want - cur
                while diff > Double.pi { diff -= 2 * Double.pi }
                while diff < -Double.pi { diff += 2 * Double.pi }
                let maxTurn = b.turn * dt
                let na = cur + min(maxTurn, max(-maxTurn, diff))
                let speed = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                b.vx = cos(na) * speed
                b.vy = sin(na) * speed
                b.homeLeft -= dt
            }
            b.x += b.vx * dt
            b.y += b.vy * dt
            if b.x < -20 || b.x > W + 20 || b.y < -20 || b.y > H + 20 { continue }
            let dx = b.x - player.x, dy = b.y - player.y
            if dx * dx + dy * dy < DanmakuConfig.hitRadiusSquared {
                if invincible || tick < shieldUntilTick { continue }
                lifeLeft -= 1
                if lifeLeft <= 0 { outcome = .hit; return }   // ライフ1・HP が尽きたとき: 以前と同じく、その場で終了
                if lifeMode == .lives {
                    shieldUntilTick = tick + Int((Simulation.lifeShieldSeconds / dt).rounded())
                    hitFlash = 0.5
                } else {
                    hitFlash = 0.15
                }
                continue   // 当たった弾は消える
            }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        if t >= Double(stage.timeLimitSec) { outcome = (isBoss && !isDamageRace) ? .timeUp : .cleared }
    }
}

extension Simulation {
    public struct Result: Equatable, Sendable {
        public var outcome: Outcome
        /// 終了時のステップ数
        public var steps: Int
        public var bulletCount: Int
        public var hp: Int
        /// 終了時の弾の位置から作ったハッシュ（完全一致の確認用）
        public var bulletHash: UInt32
    }

    /// 入力列を再生して結果を返す。入力が尽きたら動かさずに続ける
    public static func run(stage: Stage, moves: [Move]) -> Result {
        var sim = Simulation(stage: stage)
        let limit = (stage.timeLimitSec + 3) * 120 + 144
        while sim.outcome == .playing && sim.tick < limit {
            sim.step(sim.tick < moves.count ? moves[sim.tick] : .zero)
        }
        return sim.result
    }

    public var result: Result {
        var h = FNV1a()
        for b in bullets {
            for q in [b.x, b.y] {
                let bits = q.bitPattern
                for shift in stride(from: 0, to: 64, by: 8) { h.add(UInt8((bits >> UInt64(shift)) & 0xFF)) }
            }
        }
        return Result(outcome: outcome, steps: tick, bulletCount: bullets.count, hp: hp, bulletHash: h.value)
    }
}
