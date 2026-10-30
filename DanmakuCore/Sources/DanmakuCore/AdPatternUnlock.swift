import Foundation

/// 広告を見て、1日1つ解放できる30パターンの記録。端末の日付(1970年1月1日からの日数)で、1日1回に制限する。
/// 解放する順は Pattern.ad の並び。端末の日付を戻しても、解放した日より前には解放できない
public struct AdPatternState: Equatable, Codable, Sendable {
    /// これまでに解放した数(= 次に解放するパターンの番号)
    public private(set) var claimed: Int
    /// 最後に解放した日(日数)。まだなら nil
    public private(set) var lastDay: Int?

    public init(claimed: Int = 0, lastDay: Int? = nil) {
        self.claimed = max(0, min(claimed, Pattern.ad.count))
        self.lastDay = lastDay
    }

    public var isComplete: Bool { claimed >= Pattern.ad.count }

    /// 次に解放されるパターン(全部解放済みなら nil)
    public var next: Pattern? { isComplete ? nil : Pattern.ad[claimed] }

    /// 解放済みのパターン
    public var unlocked: Set<Pattern> { Set(Pattern.ad.prefix(claimed)) }

    public func canClaim(today: Int) -> Bool {
        guard !isComplete else { return false }
        guard let last = lastDay else { return true }
        return today > last
    }

    /// 解放する。解放できないときは nil
    public mutating func claim(today: Int) -> Pattern? {
        guard canClaim(today: today), let p = next else { return nil }
        claimed += 1
        lastDay = today
        return p
    }
}
