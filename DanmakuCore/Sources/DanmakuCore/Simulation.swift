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
    /// 加速弾: 1秒あたりに速さが増える割合(0 なら加速しない)と、速さの上限(px/秒)
    public var accel: Double = 0
    public var maxSpeed: Double = 0
    /// 反射弾: 左右の壁で、あと何回はね返るか
    public var bounces: Int = 0
    /// 時間で動きが変わる弾: 1=停止弾 2=分裂弾 3=時差弾(0 なら、ふつうの弾)と、出てからの経過秒
    public var script: Int = 0
    public var age: Double = 0
    /// 弾幕作成モードで描いた軌道に沿って進む弾(nil なら、ふつうの弾)
    public var follow: PathFollow?

    /// チャージビームの印(script)。ビームは動かず、x, y が出る場所、vx, vy が向き(長さ1)、
    /// bounces が「まだ当たれるか」(1本のビームで当たるのは1回だけ)、age が出てからの経過秒
    public static let beamScript = 4

    public static func beam(x: Double, y: Double, angle a: Double, color: Int) -> Bullet {
        Bullet(x: x, y: y, vx: cos(a), vy: sin(a), color: color, bounces: 1, script: beamScript)
    }

    public var isBeam: Bool { script == Bullet.beamScript }
    /// ビームが撃たれている(当たる)ところか。ためている間は当たらない
    public var beamFiring: Bool { isBeam && age >= DanmakuConfig.beamCharge }
    /// ためている間の進み具合(0〜1)
    public var beamChargeProgress: Double { isBeam ? min(1, age / DanmakuConfig.beamCharge) : 0 }

    /// ビームが (px, py) に当たるか。光線は出る場所から向きのほうへ、画面の外まで伸びる
    public func beamHits(_ px: Double, _ py: Double) -> Bool {
        guard beamFiring, bounces > 0 else { return false }
        let rx = px - x, ry = py - y
        let along = rx * vx + ry * vy
        let d2 = along < 0 ? rx * rx + ry * ry : rx * rx + ry * ry - along * along
        return d2 < DanmakuConfig.beamHitRadiusSquared
    }

    /// 分裂弾がはじけたときに散る小さな弾(進んでいた向きから、均等な角度で)
    public func fragments() -> [Bullet] {
        let speed = (vx * vx + vy * vy).squareRoot() * DanmakuConfig.splitSpeed
        let base = atan2(vy, vx)
        return (0..<DanmakuConfig.splitCount).map { j in
            let a = base + Double(j) * 2 * Double.pi / Double(DanmakuConfig.splitCount)
            return Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: color)
        }
    }
}

/// 弾の1ステップの結果。burst は、分裂弾がはじけて消えたこと(散った小さな弾は fragments() で作る)、
/// gone は、撃ち終わったチャージビームが消えたこと
public enum BulletMotion: Sendable { case alive, burst, gone }

extension Bullet {
    /// 1ステップ分の弾の動き(時間で変わる動き・追尾・加速・移動・壁での反射)。ゲーム本体、ショップの見本、
    /// エディタのプレビューが、同じ計算を使う。画面の外に出たか、自機に当たったかは、呼ぶ側で調べる
    public mutating func advance(dt: Double, width W: Double, playerX: Double, playerY: Double) -> BulletMotion {
        if let f = follow {
            // 描いた軌道の上を、時間に沿って進む(速さや向きの変化は、軌道そのもので決まる)
            age += dt
            let p = PathData.position(f.ref.points, at: age * f.scale)
            x = f.ox + f.cosR * p.x - f.sinR * p.y
            y = f.oy + f.sinR * p.x + f.cosR * p.y
            return .alive
        }
        if isBeam {
            // チャージビームは動かない。ためて、撃って、消える
            age += dt
            return age >= DanmakuConfig.beamCharge + DanmakuConfig.beamFire ? .gone : .alive
        }
        var frozen = false
        if script != 0 {
            age += dt
            switch script {
            case 1:
                if age >= DanmakuConfig.stopGoMove + DanmakuConfig.stopGoHold {
                    // 止まっていた弾が、自機に向かって、少し速く飛び出す
                    let speed = (vx * vx + vy * vy).squareRoot() * DanmakuConfig.stopGoBoost
                    let a = atan2(playerY - y, playerX - x)
                    vx = cos(a) * speed; vy = sin(a) * speed
                    script = 0
                } else if age >= DanmakuConfig.stopGoMove { frozen = true }
            case 2:
                if age >= DanmakuConfig.splitAfter { return .burst }
            default:
                if age >= DanmakuConfig.timedHold { script = 0 } else { frozen = true }
            }
        }
        if homeLeft > 0 {
            // 追尾: 速さはそのまま、向きだけを、1ステップあたり turn*dt まで自機のほうへ回す
            let want = atan2(playerY - y, playerX - x)
            let cur = atan2(vy, vx)
            var diff = want - cur
            while diff > Double.pi { diff -= 2 * Double.pi }
            while diff < -Double.pi { diff += 2 * Double.pi }
            let maxTurn = turn * dt
            let na = cur + min(maxTurn, max(-maxTurn, diff))
            let speed = (vx * vx + vy * vy).squareRoot()
            vx = cos(na) * speed
            vy = sin(na) * speed
            homeLeft -= dt
        }
        if accel != 0 {
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed < maxSpeed {
                // 上限を超えないように、増やす割合を頭打ちにする
                let g = min(1 + accel * dt, maxSpeed / speed)
                vx *= g; vy *= g
            }
        }
        if !frozen { x += vx * dt; y += vy * dt }
        if bounces > 0 {
            if x < 0 { x = -x; vx = -vx; bounces -= 1 }
            else if x > W { x = 2 * W - x; vx = -vx; bounces -= 1 }
        }
        return .alive
    }
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
        let off = Double(m.a) * deg   // パターン全体を回す角度
        func add(_ x: Double, _ y: Double, _ a: Double) {
            if out.count < DanmakuConfig.maxBullets {
                out.append(Bullet(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k))
            }
        }
        switch m.t {
        case .ring, .spiral:
            for j in 0..<n { add(cx, cy, Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off) }
        case .aim:
            let b = atan2(py - cy, px - cx) + off
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
            let b = atan2(py - cy, px - cx) + off
            let turn = max(25.0, abs(m.r) * 2.0) * deg
            for j in 0..<n {
                let a = b + (Double(j) - Double(n - 1) / 2) * 0.35
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, turn: turn, homeLeft: DanmakuConfig.homingSeconds))
                }
            }
        case .flower, .star, .heart:
            // 輪の形の弾幕: 角度ごとに速さを変えて、花・星・ハートの輪郭をつくる(r は、1回ごとの回転)
            let rot = Double(k) * m.r * deg
            for j in 0..<n {
                let th = Double(j) * 2 * Double.pi / Double(n) + rot + off
                let rel = th - rot - off     // 形は、回転とは別に決める(回転させると、形ごと回る)
                let f: Double
                switch m.t {
                case .flower: f = 0.4 + 0.6 * abs(cos(2.5 * rel))
                case .star:
                    let u = (rel * 5 / (2 * Double.pi)).truncatingRemainder(dividingBy: 1)
                    let ph = u < 0 ? u + 1 : u
                    f = 0.45 + 0.55 * abs(ph - 0.5) * 2
                default:
                    let q = -rel
                    let sq = abs(cos(q)).squareRoot()
                    let rr = (2 - 2 * sin(q) + sin(q) * sq / (sin(q) + 1.4)) / 4
                    f = 0.15 + 0.85 * max(0, min(1, rr))
                }
                let a = th
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k))
                }
            }
        case .beam:
            // 自機に向けて、速さをずらした弾を一直線に出す(c 個)。r は、狙いのずれ(度)
            let b = atan2(py - cy, px - cx) + off + m.r * deg * 0.2
            for j in 0..<n {
                let f = 1 + Double(j) * 0.18
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(b) * sp * f, vy: sin(b) * sp * f, color: m.k))
                }
            }
        case .cross:
            // 上下左右の4方向。1方向あたり c/4 個(最低1個)が、速さをずらして列になる。r は、1回ごとの回転
            let per = max(1, n / 4)
            let rot = Double(k) * m.r * deg
            for arm in 0..<4 {
                let a = Double(arm) * Double.pi / 2 + rot + off
                for j in 0..<per {
                    let f = 1 + Double(j) * 0.25
                    if out.count < DanmakuConfig.maxBullets {
                        out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k))
                    }
                }
            }
        case .accel:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * 0.3, vy: sin(a) * sp * 0.3, color: m.k, accel: 0.9, maxSpeed: sp * 2))
                }
            }
        case .bounce:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, bounces: 2))
                }
            }
        case .stopgo, .split:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, script: m.t == .stopgo ? 1 : 2))
                }
            }
        case .timed:
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, script: 3))
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
        case .custom:
            // 弾幕作成モードで描いた軌道を、n 個、均等に回して出す。r は 1回ごとの回転、v は進む速さの倍率(2 で描いたとおり)
            guard let pts = PathData.sanitized(m.path) else { break }
            let ref = PathRef(pts)
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: 0, vy: 0, color: m.k,
                                      follow: PathFollow(ref: ref, ox: cx, oy: cy, cosR: cos(a), sinR: sin(a), scale: m.v / 2)))
                }
            }
        default:
            // 広告で解放するパターン: 弾の出し方の表に従う
            if let r = m.t.recipe { emitRecipe(r, m, shot: k, cx: cx, cy: cy, px: px, py: py, off: off, sp: sp, n: n, rng: &rng, into: &out) }
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
    /// ボスを倒した回数と、直近の撃破の場所・演出(画面の演出に使う。計算には関わらない)
    public private(set) var defeats = 0
    public private(set) var lastDefeatPosition = Point(x: 0, y: 0)
    public private(set) var lastDefeatEffect = DefeatEffect.standard

    private var cooldown = 0.0
    private var rng: Mulberry32
    private var next: [Double]
    private var shotCount: [Int]
    /// 場面の一覧と、いまの場面。連戦以外は、ステージ全体が「場面1つ」
    private let specs: [WaveSpec]
    public private(set) var waveIndex = 0
    /// いまの場面が始まった時刻(t)。最初の場面は 0(ステージの開始)。連戦の途中では、切り替えの時間のあとになる
    private var waveStart = 0.0

    /// ライフ制で1つ失ったあとの無敵の長さ(秒)
    static let lifeShieldSeconds = 2.0

    static let bossMoves: [(a: Double, w: Double)] = [(0, 0), (0.25, 0.6), (0.32, 1.3)]

    /// shotType を省くと、ステージで決まっている撃ち方を使う(ふつうは、これ)
    public init(stage: Stage, shotType: ShotType? = nil) {
        self.init(stage: stage, seed: stage.seed, shotType: shotType ?? stage.shotType)
    }

    init(stage: Stage, seed: UInt32, shotType: ShotType = .standard) {
        self.stage = stage
        self.shotType = shotType
        lifeMode = stage.effectiveLifeMode
        lifeMax = stage.effectiveLifeCount
        lifeLeft = stage.effectiveLifeCount
        let specs = stage.waveSpecs
        self.specs = specs
        hp = specs[0].hp
        rng = Mulberry32(seed: seed)
        next = specs[0].emitters.map(\.s)
        shotCount = Array(repeating: 0, count: specs[0].emitters.count)
    }

    private var spec: WaveSpec { specs[waveIndex] }
    /// 画面に出す、ボスの大きさ(0=小 1=中 2=大)と見た目、雑魚の大きさ(nil は出さない)と見た目。いまの場面のもの
    public var bossSizeIndex: Int { spec.size }
    public var bossLookIndex: Int { spec.look }
    public var mookSizeIndex: Int? { spec.mooks }
    public var mookLookIndex: Int { spec.mookLook }
    /// 場面の数
    public var waveCount: Int { specs.count }
    /// いまの場面の中の経過時間(秒)。切り替えの間と、READY の間は負
    public var waveT: Double { t - waveStart }
    /// 場面の切り替えの間か(2場面目以降の、開始前)
    public var isIntermission: Bool { waveIndex > 0 && waveT < 0 }
    /// いまの場面の開始前に、警告の演出を出すか
    public var warningNow: Bool { spec.warning }
    /// いまの場面の制限時間(秒)
    public var waveLimit: Double { spec.limit }
    /// いまの場面の、ボスの最大 HP
    public var waveBossHp: Int { spec.hp }
    public var currentEmitters: [Emitter] { spec.emitters }

    /// 次の場面へ。画面の弾と自機の弾を消し、切り替えの間(自機は動ける)のあと、新しい場面が始まる
    private mutating func advanceWave() {
        waveIndex += 1
        waveStart = t + Wave.intermissionSeconds
        bullets.removeAll(keepingCapacity: true)
        shots.removeAll(keepingCapacity: true)
        next = spec.emitters.map(\.s)
        shotCount = Array(repeating: 0, count: spec.emitters.count)
        hp = spec.hp
        phase = 1
        banner = 0
        flash = 0
        cooldown = 0
        shieldUntilTick = max(shieldUntilTick, tick + Int((Wave.intermissionSeconds / DanmakuConfig.step).rounded()))
    }

    /// いまの場面に、ボスが出る(ボス戦・ダメージ勝負・連戦のボスの場面)
    public var isBoss: Bool { spec.boss }
    /// ダメージ勝負(ボスの HP は無限。与えたダメージの合計を数える)
    public var isDamageRace: Bool { spec.damage }

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
        let mv = Simulation.bossMoves[min(max(spec.move, 0), 2)]
        return Point(x: DanmakuConfig.width * (0.5 + mv.a * sin(max(0, waveT) * mv.w)),
                     y: DanmakuConfig.height * 0.18)
    }

    private func phaseOf() -> Int {
        if isDamageRace {
            // ダメージ勝負は、HP ではなく時間の3分の1ずつで段階が進む
            let f = max(0, waveT) / spec.limit
            return f < 1.0 / 3 ? 1 : f < 2.0 / 3 ? 2 : 3
        }
        let r = Double(hp) / Double(max(1, spec.hp))
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
            if waveT >= 0 && cooldown <= 0 {
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
                let br = DanmakuConfig.bossRadii[min(max(spec.size, 0), 2)]
                if dx * dx + dy * dy < br * br {
                    damageDealt += s.damage
                    if !isDamageRace { hp -= s.damage }
                    flash = 0.06; continue
                }
                shots[w] = s; w += 1
            }
            shots.removeSubrange(w...)
            if flash > 0 { flash -= dt }
            if !isDamageRace && hp <= 0 {
                defeats += 1
                lastDefeatPosition = bp
                lastDefeatEffect = spec.defeat
                if waveIndex + 1 < specs.count { advanceWave() } else { outcome = .cleared }
                return
            }
        }

        if waveT >= 0 {
            for (idx, m) in spec.emitters.enumerated() {
                if isBoss {
                    if !(m.ph == 0 || m.ph == phase) || banner > 0 { next[idx] = waveT; continue }
                    while waveT >= next[idx] {
                        // ボス戦でも、好きな場所から出せる(p == 1)。雨は、これまでどおり位置を使わない
                        let fx = m.firesFromPoint ? m.x * W : bp.x
                        let fy = m.firesFromPoint ? m.y * H : bp.y
                        Emit.emit(m, shot: shotCount[idx], cx: m.t == .rain ? 0 : fx, cy: fy,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets)
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                } else {
                    let end = min(m.e, spec.limit)
                    while waveT >= next[idx] && next[idx] < end {
                        Emit.emit(m, shot: shotCount[idx], cx: m.x * W, cy: m.y * H,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets)
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                }
            }
        }

        var w = 0
        var born: [Bullet] = []
        for i in 0..<bullets.count {
            var b = bullets[i]
            let motion = b.advance(dt: dt, width: W, playerX: player.x, playerY: player.y)
            if motion == .burst {
                let room = max(0, DanmakuConfig.maxBullets - (w + born.count + (bullets.count - i - 1)))
                born.append(contentsOf: b.fragments().prefix(room))
                continue
            }
            if motion == .gone { continue }
            if b.isBeam {
                // チャージビーム: 撃っている間だけ、光線に触れると当たる。当たっても光線は消えない(同じビームでは1回だけ)
                if b.beamHits(player.x, player.y) && !(invincible || tick < shieldUntilTick) {
                    b.bounces = 0
                    lifeLeft -= 1
                    if lifeLeft <= 0 { outcome = .hit; return }
                    if lifeMode == .lives {
                        shieldUntilTick = tick + Int((Simulation.lifeShieldSeconds / dt).rounded())
                        hitFlash = 0.5
                    } else {
                        hitFlash = 0.15
                    }
                }
                bullets[w] = b; w += 1
                continue
            }
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
        bullets.append(contentsOf: born)
        if waveT >= spec.limit {
            if waveIndex + 1 < specs.count {
                // 連戦の途中: ボスの場面は、時間切れで失敗。生き残る場面は、クリアして次へ
                if spec.boss && !spec.damage { outcome = .timeUp } else { advanceWave() }
            } else {
                outcome = (isBoss && !isDamageRace) ? .timeUp : .cleared
            }
        }
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
        /// 弾の位置を、小数第3位に丸めて作ったハッシュ(sin/cos の最後の桁の違いに左右されない。サーバーとの一致の確認用)
        public var bulletHashCoarse: UInt32
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
        var c = FNV1a()
        for b in bullets { for q in [b.x, b.y] { c.add(Int32((q * 1000).rounded())) } }
        return Result(outcome: outcome, steps: tick, bulletCount: bullets.count, hp: hp, bulletHash: h.value, bulletHashCoarse: c.value)
    }
}
