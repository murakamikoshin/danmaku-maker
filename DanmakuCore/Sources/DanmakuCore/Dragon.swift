import Foundation

// 竜王(BossCharacter.dragon)の技。試射場(art/bosses/patterns/engine.js の R.dragon*)の移植。
// 試射場は 60fps のジェネレーターだが、Simulation は値型(コピーして先読みに使う)なので、クロージャを持たない状態機械で書く。
// 竜王の部分は偶数ステップ(60Hz)だけ進める(フレーム数・px/フレームを、試射場の値のまま使える)。
// サーバー(firebase/functions/src/dragon.ts)にも同じ計算がある。乱数を引く順番・計算の順番を変えるときは、両方を直す。

/// 竜王の技の種類(Pattern の dragon* と同じ並び)
public enum DragonMove: Int, CaseIterable, Sendable {
    /// 劫火の咆哮: 口から極太の炎の柱。ゆっくり自機を追い、通った跡に火柱
    case breath
    /// 強襲: 本体が飛んできて、左右の爪でひっかく(覚醒2から叩きつけ)
    case raid
    /// 暴風圏: 羽ばたきの風で自機が流される。風の刃
    case gale
    /// 星喰い: 吸い込み(自機の弾も食べる)→ 超巨大な火球 → 食べた弾を撃ち返す
    case inhale
    /// 灼熱の滑空: 横向きの姿で、自機の高さを突っ切る
    case glide
    /// 竜の威圧: 咆哮の輪(当たるとバインド)と大火球
    case roar
    /// 奈落の顎: 地割れのひびに沿って火柱
    case quake
    /// 竜尾一閃: 尻尾の薙ぎ払い
    case tail
    /// 紅蓮の大旋回: 本体が8の字に飛び回り、竜巻を残す(竜巻は引き寄せ・バインド)
    case rampage
    /// メギドの火: 光る輪の中以外は即死
    case end

    public var pattern: Pattern { Pattern.dragon[rawValue] }
}

/// 範囲攻撃
public struct DragonZone: Equatable, Sendable {
    public enum Shape: Int, Sendable { case rect, circle, safe, ring, beam }
    /// 絵の種類(当たり判定には関係しない)
    public enum Style: Int, Sendable { case plain, claw, boom, pillar, shadow, tail, ring, beam, megido }
    public struct Safe: Equatable, Sendable {
        public var x: Double, y: Double, r: Double, vx: Double
    }
    public var id = 0
    public var shape: Shape
    public var style: Style = .plain
    public var x = 0.0, y = 0.0, r = 0.0, w = 0.0, h = 0.0
    /// 予告のフレーム数・当たるフレーム数・経過フレーム(t が warn を超えて warn + dur までの間だけ当たる)
    public var warn = 0, dur = 0, t = 0
    /// 当たると動けなくなるフレーム数・即死か
    public var bind = 0
    public var kill = false
    /// 尻尾の向き(+1 = 左から右)。0 なら尻尾ではない。滑空の向き(絵だけ)
    public var sweep = 0
    public var fly = 0
    /// 輪: 広がる速さ(px/フレーム)・太さ・抜け道の向きと半分の幅(ラジアン)。最初の 3 フレームは口に付いていく
    public var vr = 0.0, th = 0.0, gapA = 0.0, gapW = 0.0
    /// 炎の柱: 向き・追う速さ(ラジアン/フレーム)・長さ。根元はいつも口
    public var a = 0.0, track = 0.0, len = 900.0
    /// 安全な輪(この外は全部焼ける)
    public var safe: [Safe] = []

    public var active: Bool { t > warn }
    /// 予告の進み(0〜1)
    public var warnProgress: Double { warn > 0 ? min(1, Double(t) / Double(warn)) : 1 }
}

/// 予告の印(絵だけ。当たり判定には関係しない)
public struct DragonMark: Equatable, Sendable {
    public enum Kind: Int, Sendable { case target, crack, wind }
    public var kind: Kind
    public var x = 0.0, y = 0.0, r = 0.0
    public var dir = 0
    public var pts: [Point] = []
    public var t = 0, life = 0
}

/// 竜王の状態(Simulation の中にある)
public struct DragonState: Equatable, Sendable {
    /// 構え → 技 → 硬直 → 休み → 待機
    public enum Stage: Int, Sendable { case idle, windup, attack, recover, rest }
    public static let windupFrames = 30, recoverFrames = 15, restFrames = 50
    /// 竜王の攻撃に当たったあと、竜王の攻撃が当たらない間(フレーム)
    public static let invFrames = 40
    /// 尻尾の長さ(px)
    public static let tailLength = 380.0

    public private(set) var stage = Stage.idle
    /// いま(または最後に)使った技と、その姿(0 通常・1 蒼炎・2 紫電・3 白金)
    public internal(set) var move: DragonMove?
    public internal(set) var lv = 0
    /// 竜王の時計(60Hz のフレーム)
    public internal(set) var frame = 0
    /// いまの段階(stage)が始まったフレーム
    public private(set) var stageStart = 0
    /// 本体のずれ(作者の決めた位置・動きに足す)
    public internal(set) var boff = Point(x: 0, y: 0)
    /// 横向きに飛ぶ姿(+1 右へ・-1 左へ・0 正面)
    public internal(set) var pose = 0
    /// 自機を流す風(px/フレーム)
    public internal(set) var wind = Point(x: 0, y: 0)
    /// 引き寄せ: 0 なし・1 口へ・2 いちばん近い竜巻へ。強さ(px/フレーム)
    public internal(set) var pull = 0
    public internal(set) var pullForce = 0.0
    /// 自機の弾を吸い込んで食べる間か・食べた数
    public internal(set) var absorbing = false
    public internal(set) var eaten = 0
    /// 動けない残りフレーム
    public internal(set) var bind = 0
    /// 当たらない残りフレーム
    public internal(set) var inv = 0
    public internal(set) var zones: [DragonZone] = []
    public internal(set) var marks: [DragonMark] = []

    // 技の進み(ジェネレーターの代わり)
    var pc = 0
    var resumeAt = 0
    var nextZoneID = 1
    /// ループの数え(rep・v・i・k など)と、技の中で覚えておく値
    var c0 = 0, c1 = 0, c2 = 0, c3 = 0
    var d0 = 0.0, d1 = 0.0, d2 = 0.0, d3 = 0.0, d4 = 0.0
    var cracks: [[Point]] = []
    /// 本体をなめらかに動かす(glideTo)。n フレームかけて (x0,y0) から (x1,y1) へ
    var glide: Glide?
    struct Glide: Equatable, Sendable { var x0: Double, y0: Double, x1: Double, y1: Double, n: Int, i: Int }

    public init() {}

    public var busy: Bool { stage != .idle }
    /// いまの段階の経過フレーム
    public var stageFrames: Int { frame - stageStart }

    mutating func setStage(_ s: Stage) { stage = s; stageStart = frame }

    /// 場面・段階が変わったとき: 技をやめて、元に戻す
    mutating func abort() {
        stage = .idle; stageStart = frame; pc = 0; glide = nil
        boff = Point(x: 0, y: 0); pose = 0; wind = Point(x: 0, y: 0); pull = 0; pullForce = 0
        absorbing = false; bind = 0; zones = []; marks = []; cracks = []
    }
}

extension Pattern {
    /// 竜王の技(並びは DragonMove と同じ)
    public static let dragon: [Pattern] = [.dragonBreath, .dragonRaid, .dragonGale, .dragonInhale, .dragonGlide,
                                           .dragonRoar, .dragonQuake, .dragonTail, .dragonRampage, .dragonEnd]
    public var dragonMove: DragonMove? { Pattern.dragon.firstIndex(of: self).flatMap { DragonMove(rawValue: $0) } }
    /// 竜王の、数・速さ・向き・左右反転を自由に決められる技(ふつうの技と同じく弾を出すだけ。本体は動かない)
    public static let dragonFree: [Pattern] = [.dragonWings, .dragonGeyser, .dragonClaw, .dragonTwister, .dragonJaws]
}

// MARK: - 弾

extension Bullet {
    /// 竜王のふつうの弾。まっすぐ(重力 gravity があれば落ちる)。fuse > 0 なら fuse 秒で消える。u3 == 1 なら当たっても消えない(大火球)
    public static let dragonPlainScript = 30
    /// 落ちてくる超巨大な火球。(u0, u1) から (u2, u3) へ、fuse 秒で落ちる(横は一定、縦はだんだん速く)。当たっても消えない
    public static let dragonSunScript = 31
    /// 炎の竜巻。(u0, u1) のまわりを揺れる(u2 が位相)。fuse 秒で消える。当たっても消えず、homeLeft フレーム動けなくする
    public static let dragonTornadoScript = 32
    /// 口へ吸い込まれる火の粉(向きは竜王が毎フレーム決める)
    public static let dragonEmberScript = 33
    /// 本体の当たり判定(見えない)。位置は竜王が毎ステップ合わせる。fuse 秒で消える。当たっても消えない
    public static let dragonBodyScript = 34
    /// メギドの火の予告中に降る火の玉(焼き尽くす瞬間に消える)
    public static let dragonDropScript = 35
    /// 曲がる弾(双翼・竜巻)。u1 秒の間、u0 (ラジアン/秒) で向きを変えながら進み、そのあとはまっすぐ
    public static let dragonCurveScript = 36
    /// 止まって待ってから動く弾(火柱・爪・牙)。fuse 秒はその場に止まる(見えて、当たる)。そのあと (vx, vy) で進む(重力 gravity があれば落ちる)
    public static let dragonWaitScript = 37

    public var isDragon: Bool { script >= Bullet.dragonPlainScript && script <= Bullet.dragonWaitScript }
    /// 当たっても消えない竜王の弾(本体・竜巻・大火球)
    public var dragonPersistent: Bool {
        script == Bullet.dragonBodyScript || script == Bullet.dragonTornadoScript || script == Bullet.dragonSunScript
            || (script == Bullet.dragonPlainScript && u3 == 1)
    }
    /// 描かない(本体の当たり判定)
    public var isHiddenBody: Bool { script == Bullet.dragonBodyScript }

    mutating func advanceDragonScript(dt: Double) -> BulletMotion? {
        switch script {
        case Bullet.dragonPlainScript, Bullet.dragonDropScript, Bullet.dragonEmberScript:
            age += dt
            if fuse > 0 && age >= fuse { return .gone }
            if gravity != 0 { vy += gravity * dt }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.dragonSunScript:
            age += dt
            if age >= fuse { return .gone }
            let s = age / fuse
            let nx = u0 + (u2 - u0) * s, ny = u1 + (u3 - u1) * s * s
            vx = (nx - x) / dt; vy = (ny - y) / dt
            x = nx; y = ny
            return .alive
        case Bullet.dragonTornadoScript:
            age += dt
            if age >= fuse { return .gone }
            let f = age * 60
            x = u0 + sin(f * 0.03 + u2) * 60
            y = u1 + sin(f * 0.05) * 16
            return .alive
        case Bullet.dragonBodyScript:
            age += dt
            return age >= fuse ? .gone : .alive
        case Bullet.dragonCurveScript:
            age += dt
            if age < u1 {
                let sp = (vx * vx + vy * vy).squareRoot()
                let na = atan2(vy, vx) + u0 * dt
                vx = cos(na) * sp; vy = sin(na) * sp
            }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.dragonWaitScript:
            age += dt
            if age < fuse { return .alive }
            if gravity != 0 { vy += gravity * dt }
            x += vx * dt; y += vy * dt
            return .alive
        default:
            return nil
        }
    }
}

// MARK: - 竜王を進める(Simulation から呼ぶ)

extension Simulation {
    /// 試射場の V(通常, 覚醒1, 覚醒2, 覚醒3)
    @inline(__always) static func dv<T>(_ lv: Int, _ a: T, _ b: T, _ c: T, _ d: T) -> T {
        switch lv { case 0: return a; case 1: return b; case 2: return c; default: return d }
    }

    static func angDiff(_ a: Double, _ b: Double) -> Double {
        var d = a - b
        while d > Double.pi { d -= 2 * Double.pi }
        while d < -Double.pi { d += 2 * Double.pi }
        return abs(d)
    }

    /// 竜王の体の上の点(絵の 240×200 を 2 倍で描いたときの、中心からのずれ)。大きさの設定に合わせて広げる
    func dragonPoint(_ dx: Double, _ dy: Double) -> Point {
        let b = bossPosition, s = bossScale
        return Point(x: b.x + dx * s, y: b.y + dy * s)
    }
    public var dragonMouth: Point { dragonPoint(22, -28) }
    func dragonHand(_ right: Bool) -> Point { right ? dragonPoint(76, 16) : dragonPoint(-80, 16) }
    func dragonWing(_ right: Bool) -> Point { right ? dragonPoint(172, 24) : dragonPoint(-172, 24) }
    func aimFrom(_ o: Point) -> Double { atan2(player.y - o.y, player.x - o.x) }

    /// 竜王の弾を出す。速さは px/フレーム(試射場の値)
    mutating func dragonFire(_ kind: BulletLook.Kind, _ x: Double, _ y: Double, _ a: Double, _ s: Double, r: Double,
                             life: Int = 0, script: Int = Bullet.dragonPlainScript, gravity: Double = 0, persistent: Bool = false) {
        guard bullets.count < DanmakuConfig.maxBullets else { return }
        var b = Bullet(x: x, y: y, vx: cos(a) * s * 60, vy: sin(a) * s * 60, color: 0)
        b.look = BulletLook.code(kind, awakened: dragon.lv > 0)
        b.script = script
        b.radius = r
        b.fuse = life > 0 ? Double(life) / 60 : 0
        b.gravity = gravity * 3600
        if persistent { b.u3 = 1 }
        bullets.append(b)
    }

    mutating func dragonZone(_ z: DragonZone) {
        var z = z
        z.id = dragon.nextZoneID
        dragon.nextZoneID += 1
        dragon.zones.append(z)
    }

    /// 本体の当たり判定を frames フレームの間、体に重ねる
    mutating func dragonBodyHit(frames: Int, r: Double) {
        guard bullets.count < DanmakuConfig.maxBullets else { return }
        let b0 = bossPosition
        var b = Bullet(x: b0.x, y: b0.y + 10 * bossScale, vx: 0, vy: 0, color: 0)
        b.script = Bullet.dragonBodyScript
        b.radius = r * bossScale
        b.fuse = Double(frames) / 60
        bullets.append(b)
    }

    /// glideTo: 本体の中心を、n フレームかけて (x, y)(画面の座標)へ動かす
    mutating func dragonGlide(toX x: Double, y: Double, frames n: Int) {
        let base = Simulation.bossPosition(character: spec.character, move: spec.move, homeDX: spec.homeDX, homeDY: spec.homeDY, t: waveT)
        dragon.glide = DragonState.Glide(x0: dragon.boff.x, y0: dragon.boff.y, x1: x - base.x, y1: y - base.y, n: n, i: 0)
    }
    /// glideTo で、ずれを (dx, dy) へ戻す
    mutating func dragonGlide(toOffsetX dx: Double, y dy: Double, frames n: Int) {
        dragon.glide = DragonState.Glide(x0: dragon.boff.x, y0: dragon.boff.y, x1: dx, y1: dy, n: n, i: 0)
    }

    /// 竜王の技を始めてよいか
    var dragonReady: Bool { spec.character == .dragon && !dragon.busy }

    /// いまの段階の姿(0〜3)。作者が段階ごとに選ぶ。選んでいなければ、覚醒していれば蒼炎
    public var dragonForm: Int {
        if let f = spec.forms, phase - 1 < f.count, phase >= 1 { return min(max(f[phase - 1], 0), 3) }
        return isAwakened ? 1 : 0
    }

    mutating func dragonStart(_ move: DragonMove) {
        dragon.move = move
        dragon.lv = dragonForm
        dragon.pc = 0
        dragon.setStage(.windup)
    }

    /// 60Hz の 1 フレーム(偶数ステップで呼ぶ)
    mutating func dragonFrame() {
        dragon.frame += 1
        let f = dragon.frame
        if dragon.inv > 0 { dragon.inv -= 1 }
        if dragon.bind > 0 { dragon.bind -= 1 }
        // 構え・技・硬直・休み
        switch dragon.stage {
        case .idle: break
        case .windup:
            if dragon.stageFrames >= DragonState.windupFrames { dragon.setStage(.attack); dragon.pc = 0; dragon.resumeAt = f }
        case .attack:
            if let g = dragon.glide {
                // 本体の移動の途中(1 フレームずつ進む)
                var g = g
                g.i += 1
                let t = Double(g.i) / Double(g.n), e = t * t * (3 - 2 * t)
                dragon.boff = Point(x: g.x0 + (g.x1 - g.x0) * e, y: g.y0 + (g.y1 - g.y0) * e)
                dragon.glide = g.i >= g.n ? nil : g
                if dragon.glide != nil { break }
                dragon.resumeAt = f + 1
                break
            }
            if f >= dragon.resumeAt, let m = dragon.move {
                if !runDragonMove(m) {
                    dragon.boff = Point(x: 0, y: 0); dragon.wind = Point(x: 0, y: 0); dragon.pull = 0; dragon.pullForce = 0
                    dragon.pose = 0; dragon.absorbing = false
                    dragon.setStage(.recover)
                }
            }
        case .recover:
            if dragon.stageFrames >= DragonState.recoverFrames { dragon.setStage(.rest) }
        case .rest:
            if dragon.stageFrames >= DragonState.restFrames { dragon.setStage(.idle) }
        }
        // 火の粉は口へ吸い込まれる
        if bullets.contains(where: { $0.script == Bullet.dragonEmberScript }) {
            let m = dragonMouth
            var w = 0
            for i in 0..<bullets.count {
                var b = bullets[i]
                if b.script == Bullet.dragonEmberScript {
                    let dx = m.x - b.x, dy = m.y - b.y
                    if dx * dx + dy * dy < 14 * 14 { continue }
                    let a = atan2(dy, dx), sp = min(5, 1.2 + b.age * 60 * 0.05) * 60
                    b.vx = cos(a) * sp; b.vy = sin(a) * sp
                }
                bullets[w] = b; w += 1
            }
            bullets.removeSubrange(w...)
        }
        // 範囲攻撃を進める
        let mouth = dragonMouth
        for i in dragon.zones.indices {
            var z = dragon.zones[i]
            z.t += 1
            switch z.shape {
            case .ring:
                if z.t < 4 { z.x = mouth.x; z.y = mouth.y }
                z.r += z.vr
            case .safe:
                for j in z.safe.indices {
                    z.safe[j].x += z.safe[j].vx
                    if z.safe[j].x < 50 || z.safe[j].x > DanmakuConfig.width - 50 { z.safe[j].vx = -z.safe[j].vx }
                }
            case .beam:
                z.x = mouth.x; z.y = mouth.y
                if z.track > 0 {
                    var d = atan2(player.y - mouth.y, player.x - mouth.x) - z.a
                    while d > Double.pi { d -= 2 * Double.pi }
                    while d < -Double.pi { d += 2 * Double.pi }
                    z.a += min(z.track, max(-z.track, d))
                }
            default: break
            }
            dragon.zones[i] = z
        }
        dragon.zones.removeAll { $0.t >= $0.warn + $0.dur || ($0.shape == .ring && $0.r > 760) }
        for i in dragon.marks.indices { dragon.marks[i].t += 1 }
        dragon.marks.removeAll { $0.t >= $0.life }
        // 引き寄せ先の竜巻がなくなったら、引き寄せをやめる
        if dragon.pull == 2 && !bullets.contains(where: { $0.script == Bullet.dragonTornadoScript }) { dragon.pull = 0 }
    }

    /// 自機を流す・引き寄せる(毎ステップ。px/フレームの半分ずつ)
    mutating func dragonPushPlayer() {
        guard spec.character == .dragon else { return }
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        var p = player
        p.x += dragon.wind.x * 0.5; p.y += dragon.wind.y * 0.5
        if dragon.pull != 0, let o = dragonPullTarget() {
            let dx = o.x - p.x, dy = o.y - p.y, l = (dx * dx + dy * dy).squareRoot()
            if l > 30 { p.x += dx / l * dragon.pullForce * 0.5; p.y += dy / l * dragon.pullForce * 0.5 }
        }
        player = Point(x: min(max(p.x, 6), W - 6), y: min(max(p.y, 6), H - 6))
    }

    public func dragonPullTarget() -> Point? {
        if dragon.pull == 1 { return dragonMouth }
        var best: Point?, bd = Double.infinity
        for b in bullets where b.script == Bullet.dragonTornadoScript {
            let dx = b.x - player.x, dy = b.y - player.y, d = dx * dx + dy * dy
            if d < bd { bd = d; best = Point(x: b.x, y: b.y) }
        }
        return best
    }

    /// 自機の弾を口へ吸い込む(星喰い)。食べた弾は消えて、ボスに届かない。食べたら true
    mutating func dragonAbsorb(_ s: inout PlayerShot) -> Bool {
        let m = dragonMouth
        let a = atan2(m.y - s.y, m.x - s.x)
        let k = Bullet.absorbLerp
        s.vx += (cos(a) * 360 - s.vx) * k
        s.vy += (sin(a) * 360 - s.vy) * k
        let dx = m.x - s.x, dy = m.y - s.y
        if dx * dx + dy * dy < 16 * 16 { dragon.eaten += 1; return true }
        return false
    }

    /// 範囲攻撃が自機に当たっているか(当たる間だけ)
    func dragonZoneHits(_ z: DragonZone) -> Bool {
        guard z.active else { return false }
        let px = player.x, py = player.y
        switch z.shape {
        case .rect:
            var h = px > z.x && px < z.x + z.w && py > z.y && py < z.y + z.h
            if h && z.sweep != 0 {
                let tip = Simulation.tailTip(z), d = Double(z.sweep)
                h = d * (tip + d * 40 - px) > 0 && d * (px - (tip - d * DragonState.tailLength)) > 0
            }
            return h
        case .circle:
            let dx = px - z.x, dy = py - z.y
            return dx * dx + dy * dy < z.r * z.r
        case .safe:
            return !z.safe.contains { c in let dx = px - c.x, dy = py - c.y; return dx * dx + dy * dy < c.r * c.r }
        case .ring:
            let dx = px - z.x, dy = py - z.y, q = (dx * dx + dy * dy).squareRoot()
            return abs(q - z.r) < z.th / 2 && Simulation.angDiff(atan2(dy, dx), z.gapA) > z.gapW
        case .beam:
            let ux = cos(z.a), uy = sin(z.a), ox = px - z.x, oy = py - z.y, pr = ox * ux + oy * uy
            return pr > 0 && pr < z.len && abs(ox * uy - oy * ux) < z.w / 2
        }
    }

    /// 尻尾の先の x(当たり判定と絵で使う)。先は画面の外(-60)から入り、付け根まで抜けきるまで dur フレームで進む
    public static func tailTip(_ z: DragonZone) -> Double {
        let u = Double(z.t - z.warn) / Double(max(1, z.dur))
        let x = -60 + u * (DanmakuConfig.width + DragonState.tailLength + 80)
        return z.sweep > 0 ? x : DanmakuConfig.width - x
    }

    /// 竜王の攻撃(範囲・本体・竜巻・大火球)に当たったとき。終わったら true
    mutating func dragonHit(bind: Int, kill: Bool) -> Bool {
        if invincible || tick < shieldUntilTick || dragon.inv > 0 { return false }
        dragon.inv = DragonState.invFrames
        if bind > 0 { dragon.bind = max(dragon.bind, bind) }
        lifeLeft = kill ? 0 : lifeLeft - 1
        if lifeLeft <= 0 { outcome = .hit; return true }
        if lifeMode == .lives {
            shieldUntilTick = tick + Int((Simulation.lifeShieldSeconds / DanmakuConfig.step).rounded())
            hitFlash = 0.5
        } else {
            hitFlash = 0.15
        }
        return false
    }

    // MARK: 技(ジェネレーターを手で状態機械にしたもの。yield n は「n フレーム後に続き」)

    /// 1 フレーム分進める。技が終わったら false
    mutating func runDragonMove(_ m: DragonMove) -> Bool {
        while true {
            let r: Int?
            switch m {
            case .breath: r = moveBreath()
            case .raid: r = moveRaid()
            case .gale: r = moveGale()
            case .inhale: r = moveInhale()
            case .glide: r = moveGlide()
            case .roar: r = moveRoar()
            case .quake: r = moveQuake()
            case .tail: r = moveTail()
            case .rampage: r = moveRampage()
            case .end: r = moveEnd()
            }
            // nil = 終わり。0 = 待たずに続ける。n > 0 = n フレーム後に続ける。-1 = 本体の移動(glide)が終わったら続ける
            guard let n = r else { return false }
            if n == 0 { continue }
            if n < 0 { return true }
            dragon.resumeAt = dragon.frame + n
            return true
        }
    }

    private var W: Double { DanmakuConfig.width }
    private var H: Double { DanmakuConfig.height }
    private static func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { max(a, min(b, v)) }
    private var lv: Int { dragon.lv }

    private mutating func moveBreath() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 1, 1, 1, 2) { dragon.pc = 9; return 20 }
            let o = dragonMouth
            let dur = Simulation.dv(L, 150, 160, 160, 150), warn = dragon.c0 > 0 ? 30 : 44
            var z = DragonZone(shape: .beam, style: .beam)
            z.x = o.x; z.y = o.y
            z.a = aimFrom(o) + (player.x < W / 2 ? 0.45 : -0.45)
            z.w = Simulation.dv(L, 78, 96, 106, 124)
            z.warn = warn; z.dur = dur
            z.track = Simulation.dv(L, 0.0041, 0.0046, 0.0050, 0.0057)
            dragonZone(z)
            dragon.c1 = dragon.zones[dragon.zones.count - 1].id
            dragon.c2 = 0; dragon.c3 = warn + dur
            dragon.pc = 2; return 0
        case 2:
            let t = dragon.c2
            if t >= dragon.c3 { dragon.pc = 3; return 24 }
            let warn = dragon.c0 > 0 ? 30 : 44
            if t > warn + 6 && t % Simulation.dv(L, 13, 11, 9, 8) == 0, let z = dragon.zones.first(where: { $0.id == dragon.c1 }) {
                let m = dragonMouth
                let d = 150 + rng.next() * 380
                let x = m.x + cos(z.a) * d + (rng.next() - 0.5) * 30, y = m.y + sin(z.a) * d
                if y < H - 10 && x > 10 && x < W - 10 {
                    dragonFire(.flame, x, y, -Double.pi / 2, 0.15, r: Simulation.dv(L, 8, 8, 9, 10), life: Simulation.dv(L, 110, 120, 130, 140))
                }
            }
            dragon.c2 = t + 1
            return 1
        case 3:
            dragon.c0 += 1; dragon.pc = 1; return 0
        default:
            return nil
        }
    }

    private mutating func moveRaid() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 2, 3, 3, 4) { dragon.pc = 99; return 30 }
            let tx = Simulation.clamp(player.x, 70, W - 70), ty = Simulation.clamp(player.y - 95, 150, H - 180)
            let ap = Simulation.dv(L, 26, 19, 15, 14), w1 = 10 + ap + 6
            dragon.d0 = tx; dragon.d1 = ty; dragon.c1 = ap
            dragon.marks.append(DragonMark(kind: .target, x: tx, y: ty + 95, life: w1 - 6))
            let cx = Simulation.dv(L, 30.0, 24, 20, 18), cy = ty + Simulation.dv(L, 64.0, 76, 80, 82), cr = Simulation.dv(L, 66.0, 81, 86, 88)
            dragonZone(DragonZone(shape: .circle, style: .claw, x: tx + cx, y: cy, r: cr, warn: w1, dur: 8))
            dragonZone(DragonZone(shape: .circle, style: .claw, x: tx - cx, y: cy, r: cr, warn: w1 + 20, dur: 8))
            if L >= 2 { dragonZone(DragonZone(shape: .circle, style: .boom, x: tx, y: ty + 85, r: Simulation.dv(L, 0.0, 0, 100, 116), warn: w1 + 44, dur: 14)) }
            dragon.pc = 2; return 10
        case 2:
            let ap = dragon.c1
            dragonBodyHit(frames: ap + (L >= 2 ? 90 : 66), r: 44)
            dragonGlide(toX: dragon.d0, y: dragon.d1, frames: ap)
            dragon.c2 = 1      // side: 1(右の爪)→ 0
            dragon.pc = 3; return -1
        case 3:
            dragon.pc = 4; return 6
        case 4:
            let side = dragon.c2 == 1
            let h = dragonHand(side), dir = side ? -1.0 : 1.0, n = Simulation.dv(L, 3, 5, 6, 7)
            for k in 0..<n {
                let a = Double.pi / 2 + dir * (0.25 + Double(k) * 1.3 / Double(n))
                dragonFire(.slash, h.x, h.y, a, 4.4 + Double(k) * 0.3, r: 10)
            }
            dragon.pc = 5; return 14
        case 5:
            if dragon.c2 == 1 { dragon.c2 = 0; dragon.pc = 3; return 0 }
            dragon.pc = 6
            return L >= 2 ? 28 : 0
        case 6:
            dragonGlide(toOffsetX: 0, y: 0, frames: Simulation.dv(L, 30, 26, 24, 20))
            dragon.pc = 7; return -1
        case 7:
            dragon.pc = 8; return Simulation.dv(L, 10, 8, 6, 4)
        case 8:
            dragon.c0 += 1; dragon.pc = 1; return 0
        default:
            return nil
        }
    }

    private mutating func moveGale() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c3 = rng.next() < 0.5 ? 1 : -1    // dir
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 4, 6, 7, 8) { dragon.pc = 99; return 40 }
            dragon.c3 = L >= 1 ? (rng.next() < 0.5 ? 1 : -1) : -dragon.c3
            let w = Simulation.dv(L, 26, 24, 22, 20)
            dragon.marks.append(DragonMark(kind: .wind, dir: dragon.c3, life: w))
            dragon.pc = 2; return w
        case 2:
            let dir = Double(dragon.c3)
            dragon.wind = Point(x: dir * Simulation.dv(L, 1.5, 2.2, 2.7, 3.0), y: Simulation.dv(L, 0.5, 0.6, 0.8, 1.0))
            dragon.c1 = 0; dragon.pc = 3; return 0
        case 3:
            if dragon.c1 >= Simulation.dv(L, 3, 8, 10, 12) { dragon.pc = 4; return 0 }
            let dir = dragon.c3
            let y = 240 + rng.next() * (H - 270)
            let s = Simulation.dv(L, 3.4, 4.3, 4.9, 5.3) + rng.next()
            dragonFire(.gust, dir > 0 ? -20 : W + 20, y, dir > 0 ? 0 : Double.pi, s, r: Simulation.dv(L, 11, 12, 13, 14))
            dragon.c1 += 1
            return Simulation.dv(L, 12, 8, 7, 6)
        case 4:
            for side in [false, true] {
                let o = dragonWing(side)
                for d in L >= 2 ? [-0.3, 0, 0.3] : [0.0] {
                    dragonFire(.gust, o.x, o.y, aimFrom(o) + d, Simulation.dv(L, 3.2, 3.6, 3.8, 4.0), r: 9)
                }
            }
            dragon.pc = 5; return 14
        case 5:
            dragon.wind = Point(x: 0, y: 0)
            dragon.c0 += 1; dragon.pc = 1; return 0
        default:
            return nil
        }
    }

    private mutating func moveInhale() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.pull = 1; dragon.pullForce = Simulation.dv(L, 0.7, 1.0, 1.3, 1.6)
            dragon.absorbing = true; dragon.eaten = 0
            dragon.c1 = 0; dragon.pc = 1; return 0
        case 1:
            let t = dragon.c1
            if t >= 130 {
                dragon.pull = 0; dragon.pullForce = 0; dragon.absorbing = false
                dragon.c0 = 0; dragon.pc = 2; return 0
            }
            if t % 10 == 0 {
                let side = rng.next(), x = side < 0.5 ? -6 : W + 6, y = 240 + rng.next() * 200
                dragonFire(.ember, x, y, 0, 0, r: 3, script: Bullet.dragonEmberScript)
            }
            dragon.c1 = t + 1
            return 1
        case 2:
            if dragon.c0 >= Simulation.dv(L, 1, 2, 3, 3) { dragon.c1 = 0; dragon.pc = 3; return 0 }
            let m = dragonMouth, tx = player.x, ty = player.y
            let rr = Simulation.dv(L, 140.0, 154, 160, 168)
            let fl = Int((rr / 3.3).rounded()) + Simulation.dv(L, 26, 20, 16, 13)
            dragonZone(DragonZone(shape: .circle, style: .boom, x: tx, y: ty, r: rr, warn: fl, dur: 26))
            if bullets.count < DanmakuConfig.maxBullets {
                var b = Bullet(x: m.x, y: m.y, vx: 0, vy: 0, color: 0)
                b.look = BulletLook.code(.sun, awakened: L > 0)
                b.script = Bullet.dragonSunScript
                b.radius = 26
                b.fuse = Double(fl) / 60
                b.u0 = m.x; b.u1 = m.y; b.u2 = tx; b.u3 = ty
                bullets.append(b)
            }
            dragon.c0 += 1
            return fl + Simulation.dv(L, 40, 20, 18, 12)
        case 3:
            let back = min(dragon.eaten, Simulation.dv(L, 24, 36, 48, 60))
            if dragon.c1 >= back { dragon.pc = 99; return 40 }
            let m = dragonMouth, i = Double(dragon.c1)
            for d in L >= 3 ? [-0.25, 0, 0.25] : [0.0] {
                dragonFire(.pshot, m.x, m.y, aimFrom(m) + d + sin(i * 0.9) * 0.5, Simulation.dv(L, 3.6, 4.2, 4.8, 5.4), r: 3)
            }
            dragon.c1 += 1
            return Simulation.dv(L, 4, 3, 2, 2)
        default:
            return nil
        }
    }

    private mutating func moveGlide() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragonGlide(toOffsetX: 0, y: -340, frames: 26)
            dragon.c0 = 0; dragon.pc = 1; return -1
        case 1:
            if dragon.c0 >= Simulation.dv(L, 3, 4, 5, 6) {
                dragonGlide(toOffsetX: 0, y: 0, frames: 30)
                dragon.pc = 5; return -1
            }
            let dir = dragon.c0 % 2 == 1 ? -1 : 1
            let hh = Simulation.dv(L, 100.0, 124, 136, 148), y0 = player.y - hh / 2
            let warn = Simulation.dv(L, 48, 35, 35, 34), n = Simulation.dv(L, 36, 34, 30, 28)
            dragonZone(DragonZone(shape: .rect, style: .shadow, x: 0, y: y0, w: W, h: hh, warn: warn, dur: n, fly: dir))
            dragon.c3 = dir; dragon.d0 = y0; dragon.d1 = hh; dragon.c2 = n; dragon.c1 = 0
            dragon.pc = 2; return warn
        case 2:
            dragon.pose = dragon.c3
            dragon.pc = 3; return 0
        case 3:
            let i = dragon.c1, n = dragon.c2, dir = Double(dragon.c3)
            if i >= n {
                dragon.pose = 0
                dragon.boff = Point(x: 0, y: -340)
                dragon.pc = 4; return Simulation.dv(L, 18, 10, 8, 6)
            }
            let span = (W + 520) / Double(n)
            let x = dir > 0 ? -260 + Double(i) * span : W + 260 - Double(i) * span
            let base = Simulation.bossPosition(character: spec.character, move: spec.move, homeDX: spec.homeDX, homeDY: spec.homeDY, t: waveT)
            dragon.boff = Point(x: x + dir * 20 - base.x, y: dragon.d0 + dragon.d1 / 2 - 24 - base.y)
            if i % Simulation.dv(L, 4, 3, 2, 2) == 0 && x > 10 && x < W - 10 {
                let a = Double.pi / 2 + (rng.next() - 0.5) * 0.3
                let s = Simulation.dv(L, 1.6, 1.9, 2.2, 2.5) + rng.next()
                dragonFire(.flame, x, dragon.d0 + dragon.d1 / 2 + 16, a, s, r: 8, life: 90)
            }
            dragon.c1 = i + 1
            return 1
        case 4:
            dragon.c0 += 1; dragon.pc = 1; return 0
        case 5:
            dragon.pc = 99; return 20
        default:
            return nil
        }
    }

    private mutating func moveRoar() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 3, 5, 6, 7) { dragon.pc = 99; return 70 }
            let m = dragonMouth
            let base = aimFrom(m)
            let sgn = rng.next() < 0.5 ? 1.0 : -1.0
            let gapA = base + sgn * (0.3 + rng.next() * 0.25)
            var z = DragonZone(shape: .ring, style: .ring, x: m.x, y: m.y, r: 10, warn: 0, dur: 200)
            z.vr = Simulation.dv(L, 2.6, 2.9, 3.0, 3.4); z.th = Simulation.dv(L, 16.0, 16, 18, 20)
            z.gapA = gapA; z.gapW = Simulation.dv(L, 0.55, 0.50, 0.49, 0.42)
            z.bind = Simulation.dv(L, 80, 85, 95, 110)
            dragonZone(z)
            dragon.pc = 2; return Simulation.dv(L, 34, 32, 30, 28)
        case 2:
            let v = dragon.c0
            if v % 2 == 1 || L >= 2 {
                let o = dragonMouth
                for d in L >= 3 && v % 2 == 1 ? [-0.22, 0.22] : [0.0] {
                    dragonFire(.sun, o.x, o.y, aimFrom(o) + d, 3.0 + Double(L) * 0.15, r: 16, persistent: true)
                }
            }
            dragon.c0 += 1; dragon.pc = 1
            return Simulation.dv(L, 26, 24, 22, 20)
        default:
            return nil
        }
    }

    private mutating func moveQuake() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 2, 3, 4, 5) { dragon.pc = 99; return 40 }
            let warn = Simulation.dv(L, 46, 38, 34, 30), r = Simulation.dv(L, 22.0, 26, 30, 34)
            dragon.cracks = []
            let x0 = Simulation.clamp(player.x + (rng.next() - 0.5) * 80, 40, W - 40)
            var starts = [x0]
            if L >= 2 { starts.append(x0 + (x0 < W / 2 ? 1 : -1) * (110 + rng.next() * 40)) }
            for sx in starts {
                var pts: [Point] = []
                var x = Simulation.clamp(sx, 30, W - 30)
                var y = 150.0
                while y <= H + 20 {
                    pts.append(Point(x: x, y: y))
                    let sgn = rng.next() < 0.5 ? -1.0 : 1.0
                    x = Simulation.clamp(x + sgn * (30 + rng.next() * 40), 30, W - 30)
                    y += 50
                }
                dragon.marks.append(DragonMark(kind: .crack, r: r, pts: pts, life: warn))
                dragon.cracks.append(pts)
            }
            dragon.pc = 2; return warn
        case 2:
            let r = Simulation.dv(L, 22.0, 26, 30, 34)
            for pts in dragon.cracks {
                for i in 0..<(pts.count - 1) {
                    for k in 0..<2 {
                        let a = pts[i], b = pts[i + 1], f = Double(k) / 2
                        dragonZone(DragonZone(shape: .circle, style: .pillar, x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f, r: r,
                                              warn: i * 2, dur: Simulation.dv(L, 46, 50, 54, 58)))
                    }
                }
                for _ in 0..<Simulation.dv(L, 4, 7, 7, 9) {
                    let q = pts[1 + Int(rng.next() * Double(pts.count - 2))]
                    let a = -Double.pi / 2 + (rng.next() - 0.5) * 1.4
                    let s = Simulation.dv(L, 3.0, 3.4, 3.8, 4.2) + rng.next() * 2
                    dragonFire(.rock, q.x, q.y, a, s, r: 8, gravity: 0.07)
                }
            }
            dragon.c0 += 1; dragon.pc = 1
            return Simulation.dv(L, 64, 50, 44, 38)
        default:
            return nil
        }
    }

    private mutating func moveTail() -> Int? {
        let L = dragon.lv
        // 薙ぎ払い 1 回: pc 10〜11(c2 = 向き、c3 = このあと続けるか)
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 3, 4, 4, 5) { dragon.pc = 99; return 50 }
            dragon.c2 = dragon.c0 % 2 == 1 ? -1 : 1
            dragon.c3 = 0
            dragon.pc = 10; return 0
        case 10:
            let hh = Simulation.dv(L, 80.0, 112, 120, 132), y0 = player.y - hh / 2, dur = Simulation.dv(L, 38, 34, 30, 27)
            let warn = dragon.c3 == 0 ? Simulation.dv(L, 34, 23, 26, 24) : Simulation.dv(L, 0, 0, 32, 30)
            dragonZone(DragonZone(shape: .rect, style: .tail, x: 0, y: y0, w: W, h: hh, warn: warn, dur: dur, sweep: dragon.c2))
            dragon.d0 = y0 + hh / 2
            dragon.pc = 11
            return warn + Int((Double(dur) * 0.4).rounded())
        case 11:
            let n = Simulation.dv(L, 7, 9, 12, 14)
            let sx0 = rng.next() * (W / Double(n))
            for k in 0..<n {
                let x = sx0 + Double(k) * W / Double(n)
                dragonFire(.spine, x, dragon.d0, k % 2 == 1 ? Double.pi / 2 : -Double.pi / 2, Simulation.dv(L, 2.3, 2.8, 3.2, 3.6), r: 6)
            }
            if dragon.c3 == 0 && L >= 2 { dragon.c3 = 1; dragon.c2 = -dragon.c2; dragon.pc = 10; return 0 }
            dragon.pc = 12
            return Simulation.dv(L, 50, 40, 30, 24)
        case 12:
            dragon.c0 += 1; dragon.pc = 1; return 0
        default:
            return nil
        }
    }

    private mutating func moveRampage() -> Int? {
        let L = dragon.lv
        let T = Simulation.dv(L, 210, 250, 280, 300)
        switch dragon.pc {
        case 0:
            dragonBodyHit(frames: T + 20, r: Simulation.dv(L, 40.0, 44, 48, 52))
            dragon.c1 = 0; dragon.d0 = 0
            dragon.pc = 1; return 0
        case 1:
            let t = dragon.c1
            if t >= T {
                dragon.boff = Point(x: 0, y: 0)
                dragon.pc = 2; return 120
            }
            let u = Double(t) / Double(T) * 2 * Double.pi * Simulation.dv(L, 1.5, 2, 2.6, 3.2)
            let e = min(1, Double(t) / 30, Double(T - t) / 30)
            let b = bossPosition   // このフレームの初めの位置(試射場と同じく、動かす前)
            dragon.d0 += (Simulation.clamp(player.x - 180, -90, 90) * Simulation.dv(L, 0, 0.4, 0.7, 0.9) - dragon.d0) * 0.03
            dragon.boff = Point(x: (sin(u * 2) * Simulation.dv(L, 110.0, 120, 130, 140) + dragon.d0) * e,
                                y: (0.5 - 0.5 * cos(u)) * Simulation.dv(L, 288.0, 306, 324, 346) * e)
            let at = Simulation.dv(L, [60, 130], [50, 110, 170], [40, 95, 150, 205], [30, 80, 130, 180, 230])
            if at.contains(t) && bullets.count < DanmakuConfig.maxBullets {
                var q = Bullet(x: b.x, y: b.y + 40, vx: 0, vy: 0, color: 0)
                q.look = BulletLook.code(.tornado, awakened: L > 0)
                q.script = Bullet.dragonTornadoScript
                q.radius = Simulation.dv(L, 22.0, 22, 24, 26)
                q.homeLeft = Double(Simulation.dv(L, 50, 50, 60, 70))
                q.fuse = 260.0 / 60
                q.u0 = Simulation.clamp(b.x, 60, W - 60); q.u1 = Simulation.clamp(b.y + 60, 280, H - 80); q.u2 = rng.next() * 9
                bullets.append(q)
            }
            if bullets.contains(where: { $0.script == Bullet.dragonTornadoScript }) {
                dragon.pull = 2; dragon.pullForce = Simulation.dv(L, 0.6, 0.9, 1.15, 1.4)
            } else {
                dragon.pull = 0
            }
            if t % Simulation.dv(L, 16, 12, 9, 7) == 0 {
                let a = Double.pi / 2 + (rng.next() - 0.5) * 0.8
                dragonFire(.flame, b.x, b.y + 30, a, Simulation.dv(L, 1.4, 1.8, 2.2, 2.6), r: 8)
            }
            dragon.c1 = t + 1
            return 1
        case 2:
            dragon.pull = 0
            return nil
        default:
            return nil
        }
    }

    private mutating func moveEnd() -> Int? {
        let L = dragon.lv
        switch dragon.pc {
        case 0:
            dragon.c0 = 0; dragon.pc = 1; return 0
        case 1:
            if dragon.c0 >= Simulation.dv(L, 2, 2, 3, 3) { dragon.pc = 99; return 40 }
            let n = Simulation.dv(L, 2, 1, 1, 1), sp = Simulation.dv(L, 0.0, 0.5, 0.8, 1.1)
            let warn = Simulation.dv(L, 115, 100, 92, 85), reach = 3.3 * Double(warn - 30), far = Simulation.dv(L, 60.0, 80, 100, 110)
            let cr = Simulation.dv(L, 46.0, 40, 36, 32)
            var safe: [DragonZone.Safe] = []
            for k in 0..<n {
                var c = DragonZone.Safe(x: 0, y: 0, r: cr, vx: 0)
                var tries = 0
                repeat {
                    c = DragonZone.Safe(x: 60 + rng.next() * (W - 120), y: 300 + rng.next() * (H - 360), r: cr, vx: 0)
                    c.vx = sp * (rng.next() < 0.5 ? 1 : -1)
                    let ex = Simulation.safeEnd(c, warn: warn)
                    let d = ((ex - player.x) * (ex - player.x) + (c.y - player.y) * (c.y - player.y)).squareRoot() - (c.r - 14)
                    let ok = k == 0 ? (d <= reach && d >= far)
                        : !safe.contains { o in ((o.x - c.x) * (o.x - c.x) + (o.y - c.y) * (o.y - c.y)).squareRoot() < 130 }
                    if ok { break }
                    tries += 1
                } while tries < 60
                if k == 0 && tries >= 60 {
                    c.x = Simulation.clamp(player.x, 60, W - 60); c.y = Simulation.clamp(player.y, 300, H - 60); c.vx = 0
                }
                safe.append(c)
            }
            var z = DragonZone(shape: .safe, style: .megido, warn: warn, dur: 22)
            z.kill = true
            z.safe = safe
            dragonZone(z)
            dragon.c1 = 0; dragon.c2 = warn
            dragon.pc = 2; return 0
        case 2:
            let t = dragon.c1, warn = dragon.c2
            if t >= warn + Simulation.dv(L, 60, 50, 40, 34) { dragon.c0 += 1; dragon.pc = 1; return 0 }
            if L >= 1 && t < warn - 20 && t > 4 && t % Simulation.dv(L, 1, 9, 6, 4) == 0 {
                let x = 20 + rng.next() * (W - 40), y = 150 + rng.next() * 60
                let a = Double.pi / 2 + (rng.next() - 0.5) * 0.2
                dragonFire(.flame, x, y, a, Simulation.dv(L, 0, 3.6, 4.2, 4.8), r: 9, life: 260, script: Bullet.dragonDropScript)
            }
            if t == warn { bullets.removeAll { $0.script == Bullet.dragonDropScript } }
            dragon.c1 = t + 1
            return 1
        default:
            return nil
        }
    }

    /// 予告が終わる瞬間の、安全な輪の x(範囲攻撃の進め方と同じ動き)
    static func safeEnd(_ c: DragonZone.Safe, warn: Int) -> Double {
        var x = c.x, vx = c.vx
        for _ in 0...warn {
            x += vx
            if x < 50 || x > DanmakuConfig.width - 50 { vx = -vx }
        }
        return x
    }
}

extension Bullet {
    /// 吸い込みで、自機の弾の速さを口の向きへ寄せる割合(1/60 秒あたり 0.08 を、1/120 秒の刻みに直したもの)
    static let absorbLerp = 1 - (0.92 as Double).squareRoot()
}
