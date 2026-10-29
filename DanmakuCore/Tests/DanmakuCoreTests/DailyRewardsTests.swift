import XCTest
@testable import DanmakuCore

final class DailyRewardsTests: XCTestCase {
    func testThereAre365DistinctRewards() {
        let all = DailyRewards.all
        XCTAssertEqual(all.count, 365)
        // 種類・色・かたちの組み合わせが、すべて違う
        struct Key: Hashable { let kind: RewardKind; let color: Int; let style: RewardStyle }
        XCTAssertEqual(Set(all.map { Key(kind: $0.kind, color: $0.colorIndex, style: $0.style) }).count, 365)
        // 種類は5つに均等(73個ずつ)
        for kind in RewardKind.allCases { XCTAssertEqual(all.filter { $0.kind == kind }.count, 73) }
        XCTAssertNil(Reward(index: 365))
        XCTAssertNil(Reward(index: -1))
    }

    func testNeighboursLookDifferent() {
        // 続けてもらう報酬どうしは、種類も色も違う(ショップの「次の報酬」が似た見た目にならない)
        let all = DailyRewards.all
        for (a, b) in zip(all, all.dropFirst()) {
            XCTAssertNotEqual(a.kind, b.kind)
            let d = abs(a.colorIndex - b.colorIndex)
            XCTAssertGreaterThanOrEqual(min(d, DailyRewards.colorCount - d), 5, "\(a.index)→\(b.index)")
        }
        // 先の8個は、見た目(色・かたち)がすべて違う
        let first = all.prefix(8)
        XCTAssertEqual(Set(first.map { "\($0.colorIndex)-\($0.style.rawValue)" }).count, 8)
    }

    func testOneClaimPerDayInOrder() {
        var s = DailyRewardState()
        XCTAssertTrue(s.canClaim(today: 20000))
        XCTAssertEqual(s.claim(today: 20000)?.index, 0)
        XCTAssertFalse(s.canClaim(today: 20000))
        XCTAssertNil(s.claim(today: 20000))
        // 休んだ日があっても、番号は飛ばない
        XCTAssertEqual(s.claim(today: 20005)?.index, 1)
        XCTAssertEqual(s.claimed, 2)
    }

    func testClockRollbackCannotClaimAgain() {
        var s = DailyRewardState()
        _ = s.claim(today: 20010)
        XCTAssertFalse(s.canClaim(today: 20009))
        XCTAssertFalse(s.canClaim(today: 20010))
        XCTAssertTrue(s.canClaim(today: 20011))
    }

    func testStopsAfterAllClaimed() {
        var s = DailyRewardState()
        for d in 0..<365 { XCTAssertNotNil(s.claim(today: 20000 + d)) }
        XCTAssertEqual(s.claimed, 365)
        XCTAssertFalse(s.canClaim(today: 30000))
        XCTAssertNil(s.claim(today: 30000))
        XCTAssertEqual(s.owned().count, 365)
    }

    func testOwnedFilterAndLoadout() {
        var s = DailyRewardState()
        for d in 0..<12 { _ = s.claim(today: 20000 + d) }
        XCTAssertEqual(s.owned(.trail).count, 3)  // 0, 5, 10
        var l = RewardLoadout()
        let r = Reward(index: 5)!
        l.select(r, kind: .trail)
        XCTAssertEqual(l.reward(for: .trail, state: s), r)
        // 持っていない報酬を選んでいても、使われない
        l.select(Reward(index: 100)!, kind: .trail)
        XCTAssertNil(l.reward(for: .trail, state: s))
        // 種類が違う報酬は選べない
        l.select(Reward(index: 1)!, kind: .trail)
        XCTAssertNil(l.reward(for: .trail, state: s))
    }

    func testDayOfDateChangesAtLocalMidnight() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let a = cal.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 23, minute: 59))!
        let b = cal.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 0, minute: 1))!
        XCTAssertEqual(DailyRewardState.day(of: b, calendar: cal) - DailyRewardState.day(of: a, calendar: cal), 1)
    }
}
