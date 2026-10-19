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

    var index: Int32 { Int32(Pattern.allCases.firstIndex(of: self)!) }
}

public enum Mode: String, Codable, Sendable {
    case survive, boss
    /// ダメージ勝負: ボスの HP は無限。制限時間まで生き残り、与えたダメージの合計を競う
    case damage
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

    public init(name: String, mode: Mode, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil,
                emitters: [Emitter], formatVersion: Int = DanmakuConfig.formatVersion,
                lifeMode: LifeMode? = nil, lifeCount: Int? = nil) {
        self.name = name; self.mode = mode; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove
        self.emitters = emitters; self.formatVersion = formatVersion
        self.lifeMode = lifeMode; self.lifeCount = lifeCount
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, durationSec, bossHp, bossMove, emitters, formatVersion, lifeMode, lifeCount
    }

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
    }

    public static let durations: [Mode: [Int]] = [
        .survive: [10, 20, 30, 45, 60, 90, 120],
        .boss: [0, 30, 60, 90, 120, 180],   // 0 は「時間無制限」(最長 unlimitedCapSec で打ち切る)
        .damage: [30, 60, 90, 120, 180],
    ]

    /// 値の範囲を丸めた安全なステージを返す（試作の sanitize と同じ。HP は 50 刻み、小数は 2 桁、角度は整数に揃える）
    public func sanitized() -> Stage {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            let f = v.isFinite ? v : 0
            return min(hi, max(lo, f))
        }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

        let allowed = Stage.durations[mode]!
        // 選択肢にない値は、標準の長さに丸める(生き残りは20秒、ボス戦とダメージ勝負は60秒)
        let d = allowed.contains(durationSec) ? durationSec : (mode == .survive ? 20 : 60)
        let isBoss = mode == .boss
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let mv = mode != .survive ? Int(clamp(Double(bossMove ?? 0), 0, 2).rounded()) : nil
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
                     lifeMode: isDefaultLife ? nil : lm, lifeCount: isDefaultLife ? nil : lc)
    }
}
