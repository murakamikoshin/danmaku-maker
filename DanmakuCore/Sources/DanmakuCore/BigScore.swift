/// スワイプ弾幕の点数。上限のない 0 以上の整数（仕様書 `docs/SWIPE_MODE.md` 9 章）。
///
/// `Int64` は約 922 京で止まるが、連続クリアで 3 倍ずつ・コンボで 2 倍ずつ増えるので、無量大数（10^68）の先まで数える。
/// 中身は 10^9 ごとの区切り（下の桁から）。0 は空の配列。先頭（上の桁）に 0 の区切りは持たない。
public struct BigScore: Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    static let base: UInt64 = 1_000_000_000
    static let baseDigits = 9

    /// 10^9 ごとの区切り。下の桁が先
    private(set) var limbs: [UInt32]

    public static let zero = BigScore(limbs: [])

    private init(limbs: [UInt32]) {
        var l = limbs
        while let last = l.last, last == 0 { l.removeLast() }
        self.limbs = l
    }

    public init(_ value: UInt64 = 0) {
        var v = value
        var l: [UInt32] = []
        while v > 0 { l.append(UInt32(v % BigScore.base)); v /= BigScore.base }
        self.limbs = l
    }

    public init(_ value: Int) { self.init(UInt64(max(0, value))) }

    /// 10 進の数字だけの文字列から作る（自己ベストの保存・サーバーの文字列から戻す用）。数字以外が混ざると nil
    public init?(_ decimal: String) {
        guard !decimal.isEmpty, decimal.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        let digits = Array(decimal.utf8.drop(while: { $0 == 48 }))
        var l: [UInt32] = []
        var end = digits.count
        while end > 0 {
            let start = max(0, end - BigScore.baseDigits)
            var v: UInt32 = 0
            for d in digits[start..<end] { v = v * 10 + UInt32(d - 48) }
            l.append(v)
            end = start
        }
        self = BigScore(limbs: l)
    }

    public var isZero: Bool { limbs.isEmpty }

    // MARK: 計算

    public static func + (a: BigScore, b: BigScore) -> BigScore {
        var out: [UInt32] = []
        out.reserveCapacity(max(a.limbs.count, b.limbs.count) + 1)
        var carry: UInt64 = 0
        for i in 0..<max(a.limbs.count, b.limbs.count) {
            let s = UInt64(i < a.limbs.count ? a.limbs[i] : 0) + UInt64(i < b.limbs.count ? b.limbs[i] : 0) + carry
            out.append(UInt32(s % base)); carry = s / base
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return BigScore(limbs: out)
    }

    public static func += (a: inout BigScore, b: BigScore) { a = a + b }

    public static func * (a: BigScore, b: BigScore) -> BigScore {
        if a.isZero || b.isZero { return .zero }
        var out = [UInt64](repeating: 0, count: a.limbs.count + b.limbs.count + 1)
        for (i, x) in a.limbs.enumerated() {
            var carry: UInt64 = 0
            for (j, y) in b.limbs.enumerated() {
                let cur = out[i + j] + UInt64(x) * UInt64(y) + carry   // 最大 約 1e18 + 1e18 + 1e9 < 1.8e19(UInt64 に収まる)
                out[i + j] = cur % base; carry = cur / base
            }
            var k = i + b.limbs.count
            while carry > 0 { let cur = out[k] + carry; out[k] = cur % base; carry = cur / base; k += 1 }
        }
        return BigScore(limbs: out.map { UInt32($0) })
    }

    public static func * (a: BigScore, b: UInt32) -> BigScore { a * BigScore(UInt64(b)) }

    /// 小さい整数で割った商（切り捨て）。0 では割れない
    public func divided(by d: UInt32) -> BigScore { quotientAndRemainder(dividingBy: d).quotient }

    public func quotientAndRemainder(dividingBy d: UInt32) -> (quotient: BigScore, remainder: UInt32) {
        precondition(d > 0, "0 では割れない")
        var out = [UInt32](repeating: 0, count: limbs.count)
        var rem: UInt64 = 0
        for i in stride(from: limbs.count - 1, through: 0, by: -1) {
            let cur = rem * BigScore.base + UInt64(limbs[i])
            out[i] = UInt32(cur / UInt64(d)); rem = cur % UInt64(d)
        }
        return (BigScore(limbs: out), UInt32(rem))
    }

    /// base^exp（base は小さい整数）。連続数・コンボ数ごとの倍率に使う
    public static func power(_ base: UInt32, _ exp: Int) -> BigScore {
        var result = BigScore(1), b = BigScore(UInt64(base)), e = max(0, exp)
        while e > 0 {
            if e & 1 == 1 { result = result * b }
            e >>= 1
            if e > 0 { b = b * b }
        }
        return result
    }

    // MARK: 比べる

    public static func < (a: BigScore, b: BigScore) -> Bool {
        if a.limbs.count != b.limbs.count { return a.limbs.count < b.limbs.count }
        for i in stride(from: a.limbs.count - 1, through: 0, by: -1) where a.limbs[i] != b.limbs[i] { return a.limbs[i] < b.limbs[i] }
        return false
    }

    // MARK: 文字列

    /// 10 進の数字だけの文字列（桁の区切りなし）
    public var description: String {
        guard let top = limbs.last else { return "0" }
        var s = String(top)
        for i in stride(from: limbs.count - 2, through: 0, by: -1) {
            let part = String(limbs[i])
            s += String(repeating: "0", count: BigScore.baseDigits - part.count) + part
        }
        return s
    }

    /// 10 進の桁数（0 は 1 桁）
    public var digitCount: Int { description.count }

    /// ランキングで並べ替えるための文字列（桁数 3 桁 0 埋め + 数字。仕様書 15.3 章）。文字列として比べると、数の大きさの順になる
    public var rankingKey: String {
        let s = description
        let n = String(s.count)
        return String(repeating: "0", count: max(0, 3 - n.count)) + n + s
    }
}

extension BigScore: Codable {
    public init(from decoder: Decoder) throws {
        let s = try decoder.singleValueContainer().decode(String.self)
        guard let v = BigScore(s) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "10 進の数字ではない: \(s)"))
        }
        self = v
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
