/// 点数の表示（仕様書 `docs/SWIPE_MODE.md` 5.1 章）。表示だけで、計算には関わらない。
/// どれも 10 進の文字列の桁だけを見て作る（数を割らないので、桁がいくつでも同じ速さ）。
public enum ScoreFormat {
    public enum Language { case japanese, english }

    /// 全部の桁。日本語は `1兆6532億3141万3424`、英語は `1,653,231,413,424,424`
    public static func full(_ n: BigScore, _ lang: Language) -> String {
        switch lang {
        case .japanese: return japaneseFull(n.description)
        case .english: return commas(n.description)
        }
    }

    /// 短い書き方（かすりの「+点」・倍率・自己ベスト用）。日本語は `4.5億`、英語は `1.65Qa`
    public static func short(_ n: BigScore, _ lang: Language) -> String {
        switch lang {
        case .japanese: return japaneseShort(n.description)
        case .english: return englishShort(n.description)
        }
    }

    // MARK: 日本語

    /// 4 桁ごとの単位（万 = 10^4 から不可思議 = 10^64 まで）。10^68 は無量大数で、別に扱う
    private static let units: [(name: String, exp: Int)] = [
        ("万", 4), ("億", 8), ("兆", 12), ("京", 16), ("垓", 20), ("𥝱", 24), ("穣", 28), ("溝", 32), ("澗", 36),
        ("正", 40), ("載", 44), ("極", 48), ("恒河沙", 52), ("阿僧祇", 56), ("那由他", 60), ("不可思議", 64),
    ]
    private static let muryo = (name: "無量大数", exp: 68)

    private static func japaneseFull(_ s: String) -> String {
        if s.count <= 4 { return s }
        // 10^68 以上は、上の部分を同じ書き方で書いて「無量大数」を付ける（1万2345無量大数7、3万無量大数無量大数）
        var out = ""
        var lower = Substring(s)
        if s.count > muryo.exp {
            let cut = s.index(s.endIndex, offsetBy: -muryo.exp)
            out += japaneseFull(String(s[..<cut])) + muryo.name
            lower = s[cut...]
        }
        // 下 68 桁を 4 桁ずつ。0 の区切りは飛ばす
        let padded = String(repeating: "0", count: muryo.exp - lower.count) + lower
        let chars = Array(padded)
        for chunk in 0..<(muryo.exp / 4) {
            let q = Int(String(chars[(chunk * 4)..<(chunk * 4 + 4)]))!
            if q == 0 { continue }
            let exp = muryo.exp - 4 - chunk * 4   // 先頭の区切りは 10^64（不可思議）
            if exp == 0 { out += String(q) } else { out += String(q) + units.first(where: { $0.exp == exp })!.name }
        }
        return out
    }

    private static func japaneseShort(_ s: String) -> String {
        if s.count > muryo.exp {
            let upper = String(s.dropLast(muryo.exp))
            return upper.count <= 4 ? shortNumber(s, exp: muryo.exp, unit: muryo.name) : japaneseShort(upper) + muryo.name
        }
        for u in units.reversed() where s.count > u.exp { return shortNumber(s, exp: u.exp, unit: u.name) }
        return s
    }

    // MARK: 英語

    /// K=10^3 … Dc=10^33。それより上は指数表記（上限なし）
    private static let suffixes = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]

    private static func commas(_ s: String) -> String {
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && (s.count - i) % 3 == 0 { out.append(",") }
            out.append(ch)
        }
        return out
    }

    private static func englishShort(_ s: String) -> String {
        let len = s.count
        if len <= 3 { return s }
        let group = (len - 1) / 3
        if group < suffixes.count {
            return trimmed(hundredths: Int(s.prefix(len - 3 * group + 2))!) + suffixes[group]
        }
        return trimmed(hundredths: Int(s.prefix(3))!) + "e\(len - 1)"
    }

    // MARK: 共通

    /// `s`（10^exp 以上）を「一番上の単位で何個か」の形にする。小数の付け方は切り捨て
    private static func shortNumber(_ s: String, exp: Int, unit: String) -> String {
        trimmed(hundredths: Int(s.prefix(s.count - exp + 2))!) + unit
    }

    /// 100 倍した値（例 123 = 1.23）を書く。100 以上は整数、10 以上は小数 1 桁、10 未満は小数 2 桁。末尾の 0 は消す。切り捨て
    private static func trimmed(hundredths h: Int) -> String {
        if h >= 10_000 { return String(h / 100) }
        if h >= 1_000 {
            let tenths = h / 10
            return tenths % 10 == 0 ? String(tenths / 10) : "\(tenths / 10).\(tenths % 10)"
        }
        let whole = h / 100, frac = h % 100
        if frac == 0 { return String(whole) }
        return frac % 10 == 0 ? "\(whole).\(frac / 10)" : "\(whole).\(frac < 10 ? "0" : "")\(frac)"
    }
}
