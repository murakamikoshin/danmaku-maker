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

enum Emit {
    /// 試作の `emit` と同じ。弾数は 1600 で頭打ち（乱数は上限でも消費する）
    static func emit(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
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
    public private(set) var shots: [Point] = []
    public private(set) var hp: Int
    public private(set) var phase = 1
    /// 「第N段階」表示の残り秒数
    public private(set) var banner = 0.0
    public private(set) var flash = 0.0
    public private(set) var outcome = Outcome.playing

    private var cooldown = 0.0
    private var rng: Mulberry32
    private var next: [Double]
    private var shotCount: [Int]

    static let bossMoves: [(a: Double, w: Double)] = [(0, 0), (0.25, 0.6), (0.32, 1.3)]

    public init(stage: Stage) {
        self.init(stage: stage, seed: stage.seed)
    }

    init(stage: Stage, seed: UInt32) {
        self.stage = stage
        hp = stage.bossHp ?? 0
        rng = Mulberry32(seed: seed)
        next = stage.emitters.map(\.s)
        shotCount = Array(repeating: 0, count: stage.emitters.count)
    }

    public var isBoss: Bool { stage.mode == .boss }

    public var bossPosition: Point {
        let mv = Simulation.bossMoves[stage.bossMove ?? 0]
        return Point(x: DanmakuConfig.width * (0.5 + mv.a * sin(max(0, t) * mv.w)),
                     y: DanmakuConfig.height * 0.18)
    }

    private func phaseOf() -> Int {
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
                cooldown = 0.09
                shots.append(Point(x: player.x - 5, y: player.y - 10))
                shots.append(Point(x: player.x + 5, y: player.y - 10))
            }
            var w = 0
            for var s in shots {
                s.y -= 600 * dt
                if s.y < -10 { continue }
                let dx = s.x - bp.x, dy = s.y - bp.y
                if dx * dx + dy * dy < 24 * 24 { hp -= 1; flash = 0.06; continue }
                shots[w] = s; w += 1
            }
            shots.removeSubrange(w...)
            if flash > 0 { flash -= dt }
            if hp <= 0 { outcome = .cleared; return }
        }

        if t >= 0 {
            for (idx, m) in stage.emitters.enumerated() {
                if isBoss {
                    if !(m.ph == 0 || m.ph == phase) || banner > 0 { next[idx] = t; continue }
                    while t >= next[idx] {
                        Emit.emit(m, shot: shotCount[idx], cx: m.t == .rain ? 0 : bp.x, cy: bp.y,
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
            b.x += b.vx * dt
            b.y += b.vy * dt
            if b.x < -20 || b.x > W + 20 || b.y < -20 || b.y > H + 20 { continue }
            let dx = b.x - player.x, dy = b.y - player.y
            if dx * dx + dy * dy < DanmakuConfig.hitRadiusSquared { outcome = .hit; return }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        if t >= Double(stage.durationSec) { outcome = isBoss ? .timeUp : .cleared }
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
        let limit = (stage.durationSec + 3) * 120 + 144
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
