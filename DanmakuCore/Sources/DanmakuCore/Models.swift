import Foundation

/// 論理画面・固定ステップなどの定数
public enum DanmakuConfig {
    public static let formatVersion = 1
    public static let width = 360.0
    public static let height = 540.0
    /// 固定ステップ（秒）。描画フレームとは無関係に、必ずこの刻みで進める
    public static let step = 1.0 / 120.0
    public static let readySeconds = 1.2
    public static let maxBullets = 1600
    public static let maxEmitters = 8
    /// 追尾弾が曲がり続ける時間(秒)
    public static let homingSeconds = 2.5
    /// 停止弾: 進む秒数 / 止まっている秒数 / 飛び出すときの速さの倍率
    public static let stopGoMove = 0.55
    public static let stopGoHold = 0.6
    public static let stopGoBoost = 1.3
    /// 分裂弾: はじけるまでの秒数 / 散る弾の数 / 散る弾の速さの倍率
    public static let splitAfter = 0.7
    public static let splitCount = 6
    public static let splitSpeed = 0.7
    /// 時差弾: 止まっている秒数
    public static let timedHold = 1.1
    /// 判定距離の2乗（5.5 未満で被弾）
    public static let hitRadiusSquared = 30.25
}

public enum Pattern: String, Codable, CaseIterable, Sendable {
    // 並びを変えない(乱数シードに順番を使っているので、新しいものは必ず後ろに足す)
    case ring, spiral, aim, rain, sweep
    /// 左の端から、右へ向かって飛んでくる(高さはばらばら)
    case sideL
    /// 右の端から、左へ向かって飛んでくる(高さはばらばら)
    case sideR
    /// 四隅から、自機に向けて扇状に飛んでくる
    case corner
    /// 追尾弾: 自機に向かって曲がりながら飛んでくる(曲がるのは最初の数秒だけ)。課金で作れる(遊ぶのは誰でもできる)
    case homing
    // ここから下も、課金で作れる(遊ぶのは誰でもできる)。並びは変えない
    /// 花: 5枚の花びらの形に広がる輪(花びらの先ほど速い)
    case flower
    /// 星: 5つの角をもつ星の形に広がる輪
    case star
    /// ハート: ハートの形に広がる輪
    case heart
    /// 光線: 自機に向けて、速さの違う弾が一直線に伸びる
    case beam
    /// 十字: 上下左右の4方向に、弾が列になって伸びる
    case cross
    /// 加速弾: ゆっくり出て、どんどん速くなる(自機狙いの扇)
    case accel
    /// 反射弾: 左右の壁で2回はね返る(自機狙いの扇)
    case bounce
    /// 停止弾: 前に進んでぴたっと止まり、少しして自機に向かって飛び出す
    case stopgo
    /// 分裂弾: 少し進むと、小さな弾にはじけて散る
    case split
    /// 時差弾: 輪になったまま止まっていて、合図でいっせいに動き出す
    case timed

    var index: Int32 { Int32(Pattern.allCases.firstIndex(of: self)!) }

    /// 買わないと、ステージ作りで選べないパターン(遊ぶのは誰でもできる)
    public var isPaid: Bool { Pattern.paid.contains(self) }
    public static let paid: [Pattern] = [.homing, .flower, .star, .heart, .beam, .cross, .accel, .bounce, .stopgo, .split, .timed]
}

public enum Mode: String, Codable, Sendable {
    case survive, boss
    /// ダメージ勝負: ボスの HP は無限。制限時間まで生き残り、与えたダメージの合計を競う
    case damage
    /// 連戦: いくつかの場面(ウェーブ)を、順番に進む(中ボス → 雑魚だけ → 大ボス、など)
    case sequence
}

/// ボスを倒したときの演出の種類(演出だけで、計算には関わらない)
public enum DefeatEffect: Int, CaseIterable, Codable, Sendable {
    /// 演出なし
    case none = 0
    /// 爆発: 火花と衝撃波
    case explosion = 1
    /// 花火: カラフルな弾が放射状に広がる
    case fireworks = 2
    /// ハート: ピンクのハートが舞い上がる
    case hearts = 3
    /// 星くず: 金色の星がきらめく
    case stardust = 4

    /// 指定がないときの演出
    public static let standard = DefeatEffect.explosion
}

/// 連戦の1つの場面の種類
public enum WaveKind: String, Codable, Sendable {
    /// ボスなし。決めた時間、生き残る
    case survive
    /// ボスを倒す(制限時間つき)
    case boss
}

/// 連戦の1つの場面。ライフ・HP は、場面をまたいで続く
public struct Wave: Codable, Equatable, Sendable {
    public var kind: WaveKind
    /// 生き残る時間、またはボスの制限時間(秒)
    public var durationSec: Int
    public var bossHp: Int?
    public var bossMove: Int?
    public var emitters: [Emitter]
    /// ボスの場面の開始前に、警告(赤い点滅とサイレン)を出す。演出だけで、計算には関わらない
    public var warning: Bool?
    /// ボスを倒したときの演出(DefeatEffect の番号)。nil は標準(爆発)
    public var defeat: Int?

    public init(kind: WaveKind, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil, emitters: [Emitter], warning: Bool? = nil, defeat: Int? = nil) {
        self.kind = kind; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove; self.emitters = emitters; self.warning = warning; self.defeat = defeat
    }

    /// 実際に使う撃破の演出
    public var defeatEffect: DefeatEffect { defeat.flatMap(DefeatEffect.init(rawValue:)) ?? .standard }

    public static let surviveDurations = [10, 20, 30, 45, 60, 90, 120]
    public static let bossDurations = [30, 60, 90, 120, 180]
    public static let maxWaves = 6
    /// 場面と場面の間(画面の弾を消して、次の準備をする)の長さ(秒)
    public static let intermissionSeconds = 1.5
    /// 場面の切り替えにかかる時間を、制限時間の計算に入れるときの長さ(整数の秒)
    public static let intermissionBudget = 2

    /// 標準(爆発)と同じ指定は保存しない。範囲外は標準に戻す
    static func sanitizedDefeat(_ d: Int?) -> Int? {
        guard let d, let e = DefeatEffect(rawValue: d), e != .standard else { return nil }
        return d
    }

    func sanitized() -> Wave {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v.isFinite ? v : 0)) }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }
        let isBoss = kind == .boss
        let allowed = isBoss ? Wave.bossDurations : Wave.surviveDurations
        let d = allowed.contains(durationSec) ? durationSec : (isBoss ? 60 : 20)
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let mv = isBoss ? Int(clamp(Double(bossMove ?? 0), 0, 2).rounded()) : nil
        let ems = emitters.prefix(DanmakuConfig.maxEmitters).map { m in
            Emitter(t: m.t,
                    x: r2(clamp(m.x, 0, 1)), y: r2(clamp(m.y, 0, 0.6)),
                    s: r2(clamp(m.s, 0, 180)), e: r2(clamp(m.e, 0, 180)),
                    i: r2(clamp(m.i, 0.05, 2)), c: Int(clamp(Double(m.c), 1, 36)),
                    v: r2(clamp(m.v, 1, 5)), r: clamp(m.r, -90, 90).rounded(),
                    k: Int(clamp(Double(m.k), 0, 4)), ph: isBoss ? Int(clamp(Double(m.ph), 0, 3)) : 0,
                    p: isBoss && m.p == 1 ? 1 : 0)
        }
        return Wave(kind: kind, durationSec: d, bossHp: hp, bossMove: mv, emitters: Array(ems), warning: (isBoss && warning == true) ? true : nil,
                    defeat: isBoss ? Wave.sanitizedDefeat(defeat) : nil)
    }
}

/// 自機の耐久の決め方
public enum LifeMode: String, Codable, CaseIterable, Sendable {
    /// ライフ制: 当たるとライフが1つ減り、少しの間無敵になる。0になったら失敗
    case lives
    /// HP 制: 弾に当たるたびに HP が1減り、当たった弾は消える(無敵時間なし)。0になったら失敗
    case hp
}

/// 発射台。キー名は SPEC 7章（試作のステージ形式）と同じ
public struct Emitter: Codable, Equatable, Sendable {
    public var t: Pattern
    public var x: Double
    public var y: Double
    public var s: Double
    public var e: Double
    public var i: Double
    public var c: Int
    public var v: Double
    public var r: Double
    public var k: Int
    public var ph: Int
    /// 出す場所(ボス戦・ダメージ勝負だけ): 0 = ボスの位置(これまでと同じ)、1 = x, y で決めた場所
    public var p: Int

    public init(t: Pattern, x: Double = 0.5, y: Double = 0.2, s: Double = 0, e: Double = 30,
                i: Double = 1, c: Int = 16, v: Double = 2, r: Double = 0, k: Int = 0, ph: Int = 0, p: Int = 0) {
        self.t = t; self.x = x; self.y = y; self.s = s; self.e = e
        self.i = i; self.c = c; self.v = v; self.r = r; self.k = k; self.ph = ph; self.p = p
    }

    /// ボス戦で、好きな場所から出すか
    public var firesFromPoint: Bool { p == 1 }

    private enum CodingKeys: String, CodingKey { case t, x, y, s, e, i, c, v, r, k, ph, p }

    /// 出す場所が標準(ボス)のときは、データに入れない(これまでの投稿と同じ形のまま)
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(t, forKey: .t); try c.encode(x, forKey: .x); try c.encode(y, forKey: .y)
        try c.encode(s, forKey: .s); try c.encode(e, forKey: .e); try c.encode(i, forKey: .i)
        try c.encode(self.c, forKey: .c); try c.encode(v, forKey: .v); try c.encode(r, forKey: .r)
        try c.encode(k, forKey: .k); try c.encode(ph, forKey: .ph)
        if p != 0 { try c.encode(p, forKey: .p) }
    }

    public init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        t = try d.decode(Pattern.self, forKey: .t)
        x = try d.decode(Double.self, forKey: .x)
        y = try d.decode(Double.self, forKey: .y)
        s = try d.decode(Double.self, forKey: .s)
        e = try d.decode(Double.self, forKey: .e)
        i = try d.decode(Double.self, forKey: .i)
        c = try d.decode(Int.self, forKey: .c)
        v = try d.decode(Double.self, forKey: .v)
        r = try d.decode(Double.self, forKey: .r)
        k = try d.decode(Int.self, forKey: .k)
        ph = try d.decodeIfPresent(Int.self, forKey: .ph) ?? 0
        p = try d.decodeIfPresent(Int.self, forKey: .p) ?? 0
    }
}

/// シミュレーション用の、1つの場面
struct WaveSpec {
    var boss: Bool
    var damage: Bool
    var limit: Double
    var hp: Int
    var move: Int
    var emitters: [Emitter]
    var warning = false
    var defeat = DefeatEffect.standard
}

public struct Stage: Codable, Equatable, Sendable {
    public var name: String
    public var mode: Mode
    public var durationSec: Int
    public var bossHp: Int?
    public var bossMove: Int?
    public var emitters: [Emitter]
    public var formatVersion: Int
    /// 自機の耐久。nil は「ライフ制・ライフ1」(これまでのステージと同じ。1回当たったら失敗)
    public var lifeMode: LifeMode?
    public var lifeCount: Int?
    /// 遊ぶときに流れる BGM の番号(0〜4)。nil は、モードごとの標準の曲(生き残り=0、ボス戦・ダメージ勝負=1)
    public var bgm: Int?

    /// 連戦(mode == .sequence)の場面。ほかのモードでは nil
    public var waves: [Wave]?
    /// ボス戦・ダメージ勝負の開始前に、警告(赤い点滅とサイレン)を出す。演出だけで、計算には関わらない
    public var bossWarning: Bool?
    /// ボス戦(ダメージ勝負以外)で、ボスを倒したときの演出(DefeatEffect の番号)。nil は標準(爆発)
    public var bossDefeat: Int?
    public var bossDefeatEffect: DefeatEffect { bossDefeat.flatMap(DefeatEffect.init(rawValue:)) ?? .standard }

    /// 発射位置の予告(点線のひし形)を出さない。nil は、出す(これまでと同じ)。作者が決める
    public var hideMarkers: Bool?
    public var showsMarkers: Bool { hideMarkers != true }

    /// ステージの見た目(作者が決める。遊ぶ全員に、そう見える)。nil は標準
    public var themeBullets: Theme?
    public var themeBackground: Theme?
    public var themeShip: Theme?

    public var lookBullets: Theme { themeBullets ?? .classic }
    public var lookBackground: Theme { themeBackground ?? .classic }
    public var lookShip: Theme { themeShip ?? .classic }

    /// 選べる BGM の数
    public static let bgmCount = 5

    /// 実際に流す BGM の番号
    public var effectiveBGM: Int {
        if let b = bgm, (0..<Stage.bgmCount).contains(b) { return b }
        return mode == .survive ? 0 : 1
    }

    public init(name: String, mode: Mode, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil,
                emitters: [Emitter], formatVersion: Int = DanmakuConfig.formatVersion,
                lifeMode: LifeMode? = nil, lifeCount: Int? = nil, bgm: Int? = nil,
                themeBullets: Theme? = nil, themeBackground: Theme? = nil, themeShip: Theme? = nil,
                hideMarkers: Bool? = nil, waves: [Wave]? = nil, bossWarning: Bool? = nil, bossDefeat: Int? = nil) {
        self.name = name; self.mode = mode; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove
        self.emitters = emitters; self.formatVersion = formatVersion
        self.lifeMode = lifeMode; self.lifeCount = lifeCount; self.bgm = bgm
        self.themeBullets = themeBullets; self.themeBackground = themeBackground; self.themeShip = themeShip
        self.hideMarkers = hideMarkers
        self.waves = waves
        self.bossWarning = bossWarning
        self.bossDefeat = bossDefeat
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, durationSec, bossHp, bossMove, emitters, formatVersion, lifeMode, lifeCount, bgm
        case themeBullets, themeBackground, themeShip, hideMarkers, waves, bossWarning, bossDefeat
    }

    /// シミュレーションが使う場面の一覧。連戦以外は、これまでのステージ全体を「場面1つ」として扱う
    var waveSpecs: [WaveSpec] {
        if mode == .sequence, let ws = waves, !ws.isEmpty {
            return ws.map { w in
                WaveSpec(boss: w.kind == .boss, damage: false, limit: Double(w.durationSec), hp: w.bossHp ?? 0, move: w.bossMove ?? 0, emitters: w.emitters, warning: w.warning == true, defeat: w.defeatEffect)
            }
        }
        return [WaveSpec(boss: mode != .survive, damage: mode == .damage, limit: Double(timeLimitSec), hp: bossHp ?? 0, move: bossMove ?? 0, emitters: emitters, warning: bossWarning == true, defeat: bossDefeatEffect)]
    }

    /// 連戦のとき、最後まで通しての所要時間の上限(秒)。場面の合計と、切り替えの時間
    public static func sequenceTotalSeconds(_ waves: [Wave]) -> Int {
        waves.reduce(0) { $0 + $1.durationSec } + Wave.intermissionBudget * max(0, waves.count - 1)
    }

    /// ランキングに載るモードか(連戦もボス戦と同じ、クリアまでの時間で競う)
    public var ranksByTime: Bool { mode == .boss || mode == .sequence }
    public var hasRanking: Bool { mode != .survive }

    /// 時間無制限(durationSec が 0)のボス戦を、記録の大きさのために打ち切る長さ(秒)
    public static let unlimitedCapSec = 600
    /// 時間無制限か(ボス戦だけ)
    public var isUnlimitedTime: Bool { durationSec == 0 && mode == .boss }
    /// 実際に使う制限時間(秒)。無制限のときは打ち切りの長さ
    public var timeLimitSec: Int { isUnlimitedTime ? Stage.unlimitedCapSec : durationSec }

    /// 選べるライフの数と HP の範囲
    public static let livesRange = 1...5
    public static let hpRange = 3...20

    /// 実際に使う耐久の方式と数(未指定ならライフ1)
    public var effectiveLifeMode: LifeMode { lifeMode ?? .lives }
    public var effectiveLifeCount: Int {
        let range = effectiveLifeMode == .lives ? Stage.livesRange : Stage.hpRange
        return min(range.upperBound, max(range.lowerBound, lifeCount ?? 1))
    }

    public init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        name = try d.decode(String.self, forKey: .name)
        mode = try d.decode(Mode.self, forKey: .mode)
        durationSec = try d.decode(Int.self, forKey: .durationSec)
        bossHp = try d.decodeIfPresent(Int.self, forKey: .bossHp)
        bossMove = try d.decodeIfPresent(Int.self, forKey: .bossMove)
        emitters = try d.decode([Emitter].self, forKey: .emitters)
        formatVersion = try d.decodeIfPresent(Int.self, forKey: .formatVersion) ?? DanmakuConfig.formatVersion
        lifeMode = try d.decodeIfPresent(LifeMode.self, forKey: .lifeMode)
        lifeCount = try d.decodeIfPresent(Int.self, forKey: .lifeCount)
        bgm = try d.decodeIfPresent(Int.self, forKey: .bgm)
        // 知らないテーマ名(新しい版で増えたもの)は、標準として読む
        themeBullets = (try? d.decodeIfPresent(Theme.self, forKey: .themeBullets)) ?? nil
        themeBackground = (try? d.decodeIfPresent(Theme.self, forKey: .themeBackground)) ?? nil
        themeShip = (try? d.decodeIfPresent(Theme.self, forKey: .themeShip)) ?? nil
        hideMarkers = try d.decodeIfPresent(Bool.self, forKey: .hideMarkers)
        waves = try d.decodeIfPresent([Wave].self, forKey: .waves)
        bossWarning = try d.decodeIfPresent(Bool.self, forKey: .bossWarning)
        bossDefeat = try d.decodeIfPresent(Int.self, forKey: .bossDefeat)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(mode, forKey: .mode)
        try c.encode(durationSec, forKey: .durationSec)
        try c.encodeIfPresent(bossHp, forKey: .bossHp)
        try c.encodeIfPresent(bossMove, forKey: .bossMove)
        try c.encode(emitters, forKey: .emitters)
        try c.encode(formatVersion, forKey: .formatVersion)
        try c.encodeIfPresent(lifeMode, forKey: .lifeMode)
        try c.encodeIfPresent(lifeCount, forKey: .lifeCount)
        try c.encodeIfPresent(bgm, forKey: .bgm)
        try c.encodeIfPresent(themeBullets, forKey: .themeBullets)
        try c.encodeIfPresent(themeBackground, forKey: .themeBackground)
        try c.encodeIfPresent(themeShip, forKey: .themeShip)
        try c.encodeIfPresent(hideMarkers, forKey: .hideMarkers)
        try c.encodeIfPresent(waves, forKey: .waves)
        try c.encodeIfPresent(bossWarning, forKey: .bossWarning)
        try c.encodeIfPresent(bossDefeat, forKey: .bossDefeat)
    }

    public static let durations: [Mode: [Int]] = [
        .survive: [10, 20, 30, 45, 60, 90, 120],
        .boss: [0, 30, 60, 90, 120, 180],   // 0 は「時間無制限」(最長 unlimitedCapSec で打ち切る)
        .damage: [30, 60, 90, 120, 180],
        .sequence: [],   // 連戦の長さは、場面の合計(sanitized が計算する)
    ]

    /// 値の範囲を丸めた安全なステージを返す（試作の sanitize と同じ。HP は 50 刻み、小数は 2 桁、角度は整数に揃える）
    public func sanitized() -> Stage {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            let f = v.isFinite ? v : 0
            return min(hi, max(lo, f))
        }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

        if mode == .sequence {
            let ws = (waves ?? []).prefix(Wave.maxWaves).map { $0.sanitized() }
            let trimmed = name.isEmpty ? "名無しステージ" : String(name.prefix(20))
            let lm = effectiveLifeMode, lc = effectiveLifeCount
            let isDefaultLife = lm == .lives && lc == 1
            return Stage(name: trimmed, mode: .sequence, durationSec: Stage.sequenceTotalSeconds(Array(ws)), bossHp: nil, bossMove: nil,
                         emitters: [], formatVersion: DanmakuConfig.formatVersion,
                         lifeMode: isDefaultLife ? nil : lm, lifeCount: isDefaultLife ? nil : lc,
                         bgm: (bgm.map { (0..<Stage.bgmCount).contains($0) } ?? false) && bgm != 1 ? bgm : nil,
                         themeBullets: lookBullets == .classic ? nil : lookBullets,
                         themeBackground: lookBackground == .classic ? nil : lookBackground,
                         themeShip: lookShip == .classic ? nil : lookShip,
                         hideMarkers: hideMarkers == true ? true : nil, waves: Array(ws), bossWarning: nil, bossDefeat: nil)
        }
        let allowed = Stage.durations[mode]!
        // 選択肢にない値は、標準の長さに丸める(生き残りは20秒、ボス戦とダメージ勝負は60秒)
        let d = allowed.contains(durationSec) ? durationSec : (mode == .survive ? 20 : 60)
        let isBoss = mode == .boss
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let mv = (mode == .boss || mode == .damage) ? Int(clamp(Double(bossMove ?? 0), 0, 2).rounded()) : nil
        let trimmed = name.isEmpty ? "名無しステージ" : String(name.prefix(20))
        let ems = emitters.prefix(DanmakuConfig.maxEmitters).map { m in
            Emitter(t: m.t,
                    x: r2(clamp(m.x, 0, 1)), y: r2(clamp(m.y, 0, 0.6)),
                    s: r2(clamp(m.s, 0, 180)), e: r2(clamp(m.e, 0, 180)),
                    i: r2(clamp(m.i, 0.05, 2)), c: Int(clamp(Double(m.c), 1, 36)),
                    v: r2(clamp(m.v, 1, 5)), r: clamp(m.r, -90, 90).rounded(),
                    k: Int(clamp(Double(m.k), 0, 4)), ph: Int(clamp(Double(m.ph), 0, 3)),
                    p: mode == .survive ? 0 : (m.p == 1 ? 1 : 0))
        }
        // 耐久: 標準(ライフ1)は未指定に揃える。サーバーの検証と同じ丸め方
        let lm = effectiveLifeMode, lc = effectiveLifeCount
        let isDefaultLife = lm == .lives && lc == 1
        return Stage(name: trimmed, mode: mode, durationSec: d, bossHp: hp, bossMove: mv,
                     emitters: Array(ems), formatVersion: DanmakuConfig.formatVersion,
                     lifeMode: isDefaultLife ? nil : lm, lifeCount: isDefaultLife ? nil : lc,
                     // 標準の曲と同じ指定は保存しない(範囲外も標準に戻す)
                     bgm: (bgm.map { (0..<Stage.bgmCount).contains($0) } ?? false) && bgm != (mode == .survive ? 0 : 1) ? bgm : nil,
                     // 標準と同じ指定は保存しない
                     themeBullets: lookBullets == .classic ? nil : lookBullets,
                     themeBackground: lookBackground == .classic ? nil : lookBackground,
                     themeShip: lookShip == .classic ? nil : lookShip,
                     // 予告を出さないときだけ保存する(出す=標準は保存しない)。出さない設定は、生き残りのステージだけ(ボス戦には予告がない)
                     hideMarkers: (hideMarkers == true && mode == .survive) ? true : nil,
                     bossWarning: (bossWarning == true && (mode == .boss || mode == .damage)) ? true : nil,
                     bossDefeat: mode == .boss ? Wave.sanitizedDefeat(bossDefeat) : nil)
    }
}
