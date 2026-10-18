import Foundation

/// 論理画面・固定ステップなどの定数
public enum DanmakuCore {
    public static let formatVersion = 1
    public static let width = 360.0
    public static let height = 540.0
    /// 固定ステップ（秒）。描画フレームとは無関係に、必ずこの刻みで進める
    public static let step = 1.0 / 120.0
    public static let readySeconds = 1.2
    public static let maxBullets = 1600
    public static let maxEmitters = 8
    /// 判定距離の2乗（5.5 未満で被弾）
    public static let hitRadiusSquared = 30.25
}

public enum Pattern: String, Codable, CaseIterable, Sendable {
    case ring, spiral, aim, rain, sweep

    var index: Int32 { Int32(Pattern.allCases.firstIndex(of: self)!) }
}

public enum Mode: String, Codable, Sendable {
    case survive, boss
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

    public init(t: Pattern, x: Double = 0.5, y: Double = 0.2, s: Double = 0, e: Double = 30,
                i: Double = 1, c: Int = 16, v: Double = 2, r: Double = 0, k: Int = 0, ph: Int = 0) {
        self.t = t; self.x = x; self.y = y; self.s = s; self.e = e
        self.i = i; self.c = c; self.v = v; self.r = r; self.k = k; self.ph = ph
    }

    private enum CodingKeys: String, CodingKey { case t, x, y, s, e, i, c, v, r, k, ph }

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

    public init(name: String, mode: Mode, durationSec: Int, bossHp: Int? = nil, bossMove: Int? = nil,
                emitters: [Emitter], formatVersion: Int = DanmakuCore.formatVersion) {
        self.name = name; self.mode = mode; self.durationSec = durationSec
        self.bossHp = bossHp; self.bossMove = bossMove
        self.emitters = emitters; self.formatVersion = formatVersion
    }

    private enum CodingKeys: String, CodingKey {
        case name, mode, durationSec, bossHp, bossMove, emitters, formatVersion
    }

    public init(from decoder: Decoder) throws {
        let d = try decoder.container(keyedBy: CodingKeys.self)
        name = try d.decode(String.self, forKey: .name)
        mode = try d.decode(Mode.self, forKey: .mode)
        durationSec = try d.decode(Int.self, forKey: .durationSec)
        bossHp = try d.decodeIfPresent(Int.self, forKey: .bossHp)
        bossMove = try d.decodeIfPresent(Int.self, forKey: .bossMove)
        emitters = try d.decode([Emitter].self, forKey: .emitters)
        formatVersion = try d.decodeIfPresent(Int.self, forKey: .formatVersion) ?? DanmakuCore.formatVersion
    }

    public static let durations: [Mode: [Int]] = [
        .survive: [10, 20, 30, 45, 60, 90, 120],
        .boss: [30, 60, 90, 120, 180],
    ]

    /// 値の範囲を丸めた安全なステージを返す（試作の sanitize と同じ。HP は 50 刻み、小数は 2 桁、角度は整数に揃える）
    public func sanitized() -> Stage {
        func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
            let f = v.isFinite ? v : 0
            return min(hi, max(lo, f))
        }
        func r2(_ v: Double) -> Double { (v * 100).rounded() / 100 }

        let allowed = Stage.durations[mode]!
        let d = allowed.contains(durationSec) ? durationSec : allowed[1]
        let isBoss = mode == .boss
        let hp = isBoss ? Int((clamp(Double(bossHp ?? 400), 100, 1000) / 50).rounded()) * 50 : nil
        let mv = isBoss ? Int(clamp(Double(bossMove ?? 0), 0, 2).rounded()) : nil
        let trimmed = name.isEmpty ? "名無しステージ" : String(name.prefix(20))
        let ems = emitters.prefix(DanmakuCore.maxEmitters).map { m in
            Emitter(t: m.t,
                    x: r2(clamp(m.x, 0, 1)), y: r2(clamp(m.y, 0, 0.6)),
                    s: r2(clamp(m.s, 0, 180)), e: r2(clamp(m.e, 0, 180)),
                    i: r2(clamp(m.i, 0.05, 2)), c: Int(clamp(Double(m.c), 1, 36)),
                    v: r2(clamp(m.v, 1, 5)), r: clamp(m.r, -90, 90).rounded(),
                    k: Int(clamp(Double(m.k), 0, 4)), ph: Int(clamp(Double(m.ph), 0, 3)))
        }
        return Stage(name: trimmed, mode: mode, durationSec: d, bossHp: hp, bossMove: mv,
                     emitters: Array(ems), formatVersion: DanmakuCore.formatVersion)
    }
}
