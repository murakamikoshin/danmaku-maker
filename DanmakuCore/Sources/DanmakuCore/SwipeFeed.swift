/// スワイプ弾幕で、次にどのクリップを流すか（仕様書 `docs/SWIPE_MODE.md` 3.3・10 章）。
/// ランダムだが、**序盤は易しく、連続が伸びるほど難しく**なる。乱数はサーバーが配る「種」から作るので、
/// サーバーも同じ並びを作り直せる（ランキングの検証）。アプリとサーバーで同じ結果になること。
public enum SwipeFeed {
    /// 候補の一覧の 1 件（サーバーが毎日 0 時に作る。仕様書 10 章）
    public struct Entry: Equatable, Hashable, Codable, Sendable {
        /// ステージの ID
        public let id: String
        /// 難しさ。クリア率を 1000 倍した整数（0〜1000。大きいほど易しい）。挑戦が 10 回以上たまっていれば実際のクリア率、なければ見積もり
        public let d: Int
        /// 作者の uid（ブロックした作者・自分のステージを除くため）
        public let author: String

        public init(id: String, d: Int, author: String) { self.id = id; self.d = d; self.author = author }
    }

    /// 連続 0 の目標のクリア率（千分率）と、1 本ごとに下げる量・下限
    public static let startRate = 850, stepRate = 40, floorRate = 80
    /// 目標の前後、この幅に入るものから選ぶ。少なければ広げる
    public static let narrowRange = 100, wideRange = 200
    /// 範囲に入るものがこれ未満なら、広げる（最後は、目標に近い順にこの数だけ）
    public static let minimumPool = 20

    /// 連続 `streak` のときの、目標のクリア率（千分率）：`max(80, 850 − 40 × 連続)`
    public static func targetRate(streak: Int) -> Int { max(floorRate, startRate - stepRate * max(0, streak)) }

    /// `index` 本目（0 から数える）に流すクリップを選ぶ。選べるものがなければ nil（公式ステージに切り替える）。
    /// - `seed`：サーバーが `useStamina` で渡す、そのプレイの乱数の種
    /// - `used`：このプレイでもう流したクリップ（同じプレイで 2 回出さない）
    /// - `excludedAuthors`：自分とブロックした作者の uid
    ///
    /// 手順：除くものを除く → 目標 ± 100 に入るものを集める（20 件未満なら ± 200、それでも足りなければ目標に近い順に 20 件）
    /// → 難しさ・ID の順に並べる → 種と `index` から作った乱数で 1 件選ぶ
    public static func pick(pool: [Entry], seed: UInt32, index: Int, streak: Int,
                            used: Set<String> = [], excludedAuthors: Set<String> = []) -> Entry? {
        let target = targetRate(streak: streak)
        let open = pool.filter { !used.contains($0.id) && !excludedAuthors.contains($0.author) }
        if open.isEmpty { return nil }

        func inRange(_ width: Int) -> [Entry] { open.filter { abs($0.d - target) <= width } }
        var chosen = inRange(narrowRange)
        if chosen.count < minimumPool { chosen = inRange(wideRange) }
        if chosen.count < minimumPool {
            // 目標に近い順（同じ近さなら、難しさ・ID の順）に 20 件
            chosen = Array(open.sorted {
                let (a, b) = (abs($0.d - target), abs($1.d - target))
                return a != b ? a < b : order($0, $1)
            }.prefix(minimumPool))
        }
        chosen.sort(by: order)

        var rng = Mulberry32(seed: seed &+ UInt32(truncatingIfNeeded: index) &* 0x9E37_79B9)
        return chosen[min(chosen.count - 1, Int(rng.next() * Double(chosen.count)))]
    }

    /// 難しさ（クリア率）の小さい順、同じなら ID の順
    private static func order(_ a: Entry, _ b: Entry) -> Bool { a.d != b.d ? a.d < b.d : a.id < b.id }
}
