import XCTest
@testable import DanmakuCore

/// スワイプ弾幕の並び（仕様書 3.3・10 章）
final class SwipeFeedTests: XCTestCase {
    /// 難しさが 0, 10, 20 … 1000（101 件）。作者は 7 人を順番に
    private let pool: [SwipeFeed.Entry] = (0...100).map { SwipeFeed.Entry(id: String(format: "S%04d", $0), d: $0 * 10, author: "u\($0 % 7)") }

    func testTheTargetGetsHarderWithTheStreak() {
        XCTAssertEqual([0, 5, 10, 15, 20, 100].map { SwipeFeed.targetRate(streak: $0) }, [850, 650, 450, 250, 80, 80], "仕様書 3.3 章の表。下限 8%")
        XCTAssertEqual(SwipeFeed.targetRate(streak: -3), 850)
    }

    func testPicksStayInsideTheRangeAroundTheTarget() {
        for (streak, target) in [(0, 850), (5, 650), (10, 450), (15, 250)] {
            for index in 0..<200 {
                let e = SwipeFeed.pick(pool: pool, seed: 7, index: index, streak: streak)!
                XCTAssertLessThanOrEqual(abs(e.d - target), 100, "連続 \(streak)・\(index) 本目")
            }
        }
    }

    func testItIsRandomButRepeatable() {
        let a = (0..<50).map { SwipeFeed.pick(pool: pool, seed: 42, index: $0, streak: 5)!.id }
        let b = (0..<50).map { SwipeFeed.pick(pool: pool, seed: 42, index: $0, streak: 5)!.id }
        XCTAssertEqual(a, b, "同じ種・同じ条件なら、何度でも同じ")
        let c = (0..<50).map { SwipeFeed.pick(pool: pool, seed: 43, index: $0, streak: 5)!.id }
        XCTAssertNotEqual(a, c, "種が違えば違う並び")
        XCTAssertGreaterThan(Set(a).count, 10, "ばらける")
        XCTAssertGreaterThan(Set((0..<50).map { SwipeFeed.pick(pool: pool, seed: 42, index: $0, streak: 5)!.d }).count, 10)
    }

    func testTheOrderOfThePoolDoesNotMatter() {
        let shuffled = pool.reversed().enumerated().sorted { ($0.offset * 37) % 101 < ($1.offset * 37) % 101 }.map(\.element)
        XCTAssertNotEqual(shuffled, pool)
        for index in 0..<30 {
            XCTAssertEqual(SwipeFeed.pick(pool: pool, seed: 9, index: index, streak: 3), SwipeFeed.pick(pool: shuffled, seed: 9, index: index, streak: 3))
        }
    }

    func testTheRangeWidensWhenThereAreTooFewClips() {
        // 目標 850 の ±100 に 5 件、±200 に 25 件
        var small: [SwipeFeed.Entry] = (0..<5).map { SwipeFeed.Entry(id: "N\($0)", d: 800 + $0 * 10, author: "a") }
        small += (0..<20).map { SwipeFeed.Entry(id: "W\($0)", d: 660 + $0 * 5, author: "a") }   // 660〜755（±200 の中。750 以上の 2 件だけ ±100 にも入る）
        var seen = Set<String>()
        for index in 0..<400 { seen.insert(SwipeFeed.pick(pool: small, seed: 1, index: index, streak: 0)!.id) }
        XCTAssertTrue(seen.contains(where: { $0.hasPrefix("W") }), "±200 に広げて、遠い方からも選ぶ")
        XCTAssertTrue(seen.contains(where: { $0.hasPrefix("N") }))
    }

    func testItFallsBackToTheTwentyNearestClips() {
        // 全部が 900 で、目標が 80（連続 20）。範囲に 1 件もないので、目標に近い順（同じ近さなら ID 順）の 20 件
        let flat = (0..<30).map { SwipeFeed.Entry(id: String(format: "F%02d", $0), d: 900, author: "a") }
        var seen = Set<String>()
        for index in 0..<500 { seen.insert(SwipeFeed.pick(pool: flat, seed: 5, index: index, streak: 20)!.id) }
        XCTAssertEqual(seen, Set((0..<20).map { String(format: "F%02d", $0) }), "ID の小さい 20 件だけ")
        // 全体が 20 件に満たなければ、全部が候補
        let few = Array(flat.prefix(8))
        var seenFew = Set<String>()
        for index in 0..<500 { seenFew.insert(SwipeFeed.pick(pool: few, seed: 5, index: index, streak: 20)!.id) }
        XCTAssertEqual(seenFew.count, 8)
    }

    func testUsedClipsAndExcludedAuthorsNeverComeBack() {
        var used = Set<String>()
        let excluded: Set<String> = ["u0", "u3"]
        var picks: [SwipeFeed.Entry] = []
        while let e = SwipeFeed.pick(pool: pool, seed: 11, index: picks.count, streak: 0, used: used, excludedAuthors: excluded) {
            XCTAssertFalse(used.contains(e.id), "同じプレイで 2 回出さない")
            XCTAssertFalse(excluded.contains(e.author), "ブロックした作者・自分は出さない")
            used.insert(e.id)
            picks.append(e)
        }
        let allowed = pool.filter { !excluded.contains($0.author) }.count
        XCTAssertEqual(picks.count, allowed, "選べるものを全部使い切ったら nil")
        XCTAssertNil(SwipeFeed.pick(pool: [], seed: 1, index: 0, streak: 0))
        XCTAssertNil(SwipeFeed.pick(pool: pool, seed: 1, index: 0, streak: 0, excludedAuthors: Set(pool.map(\.author))))
    }

    func testARunGetsHarderAsTheStreakGrows() {
        // 連続を 1 本ごとに伸ばしていくと、流れてくる難しさの平均が下がっていく（クリア率が低くなる）
        let big = (0..<3000).map { SwipeFeed.Entry(id: String(format: "B%05d", $0), d: ($0 * 7) % 1001, author: "u\($0 % 50)") }
        func mean(streaks: ClosedRange<Int>) -> Double {
            var sum = 0, n = 0
            for run in 0..<40 {
                var used = Set<String>()
                for streak in streaks {
                    let e = SwipeFeed.pick(pool: big, seed: UInt32(run), index: streak, streak: streak, used: used)!
                    used.insert(e.id); sum += e.d; n += 1
                }
            }
            return Double(sum) / Double(n)
        }
        let early = mean(streaks: 0...3), middle = mean(streaks: 8...12), late = mean(streaks: 22...30)
        XCTAssertGreaterThan(early, 700)
        XCTAssertTrue((350...550).contains(middle), "連続 10 前後は目標 45%。実際 \(middle)")
        XCTAssertLessThan(late, 250, "下限 8% の近く")
        XCTAssertGreaterThan(early, middle)
        XCTAssertGreaterThan(middle, late)
    }

    func testEntriesRoundTripThroughJSON() throws {
        let e = SwipeFeed.Entry(id: "K7X2P", d: 437, author: "abc")
        let back = try JSONDecoder().decode(SwipeFeed.Entry.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(e, back)
    }

    func testTheSeedAndIndexMixingMatchesTheSpecFormula() {
        // サーバー（TypeScript）と合わせる式：Mulberry32(seed + index × 0x9E3779B9) の最初の 1 つ
        var rng = Mulberry32(seed: 100 &+ UInt32(3) &* 0x9E37_79B9)
        let r = rng.next()
        let chosen = SwipeFeed.pick(pool: pool, seed: 100, index: 3, streak: 0)!
        let inRange = pool.filter { abs($0.d - 850) <= 100 }
        XCTAssertEqual(chosen, inRange[Int(r * Double(inRange.count))])
    }
}
