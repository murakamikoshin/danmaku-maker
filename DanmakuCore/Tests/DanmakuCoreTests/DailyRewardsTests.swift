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

    func testExtraClaimsUpToPerDayAfterTodays() {
        var s = DailyRewardState()
        // 今日の分をもらう前は、「もう1つ」はない
        XCTAssertFalse(s.canClaimExtra(today: 20000))
        XCTAssertNil(s.claimExtra(today: 20000))
        XCTAssertEqual(s.claim(today: 20000)?.index, 0)
        XCTAssertEqual(s.extraLeft(today: 20000), DailyRewards.perDay - 1)
        // 「もう1つ」は次の番号から順に、1日 perDay 個目まで
        XCTAssertEqual(s.claimExtra(today: 20000)?.index, 1)
        XCTAssertEqual(s.claimExtra(today: 20000)?.index, 2)
        XCTAssertEqual(s.extraLeft(today: 20000), 0)
        XCTAssertNil(s.claimExtra(today: 20000))
        XCTAssertFalse(s.canClaim(today: 20000))
        // 次の日は、今日の分からやり直し(前の日の「もう1つ」は持ち越さない)
        XCTAssertFalse(s.canClaimExtra(today: 20001))
        XCTAssertEqual(s.claim(today: 20001)?.index, 3)
        XCTAssertEqual(s.extraLeft(today: 20001), DailyRewards.perDay - 1)
        // 端末の日付を戻しても、「もう1つ」は増えない
        XCTAssertFalse(s.canClaimExtra(today: 20000))
    }

    func testExtraStopsAtLastReward() {
        var s = DailyRewardState(claimed: DailyRewards.total - 2, lastDay: 19999)
        XCTAssertEqual(s.claim(today: 20000)?.index, DailyRewards.total - 2)
        XCTAssertEqual(s.extraLeft(today: 20000), 1)
        XCTAssertEqual(s.claimExtra(today: 20000)?.index, DailyRewards.total - 1)
        XCTAssertFalse(s.canClaimExtra(today: 20000))
        XCTAssertNil(s.claimExtra(today: 20000))
    }

    func testOldSavedStateDecodesAsOneClaimThatDay() throws {
        // 1.2.1 までの保存データ(claimsOnLastDay がない)
        let old = Data(#"{"claimed":5,"lastDay":20000}"#.utf8)
        var s = try JSONDecoder().decode(DailyRewardState.self, from: old)
        XCTAssertEqual(s.claimed, 5)
        XCTAssertEqual(s.extraLeft(today: 20000), DailyRewards.perDay - 1)
        XCTAssertEqual(s.claimExtra(today: 20000)?.index, 5)
        // 保存し直しても、同じ状態に戻る
        let again = try JSONDecoder().decode(DailyRewardState.self, from: try JSONEncoder().encode(s))
        XCTAssertEqual(again, s)
        // まだ1つももらっていない記録
        let fresh = try JSONDecoder().decode(DailyRewardState.self, from: Data(#"{"claimed":0}"#.utf8))
        XCTAssertTrue(fresh.canClaim(today: 20000))
        XCTAssertFalse(fresh.canClaimExtra(today: 20000))
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

    // MARK: ステージに付ける演出(Stage.rewardFx)

    func testStageFxKeepsOnePerKindInKindOrder() {
        // 0=軌跡 1=火花 2=オーラ 3=爆発 4=称号(5個ごとに種類が回る)
        XCTAssertEqual(Reward.sanitizedFx([7, 5, 10]), [5, 7])           // 軌跡(5)・火花は無し・オーラ(7)、10は軌跡の2つ目で捨てる
        XCTAssertEqual(Reward.sanitizedFx([8, 1, 2]), [1, 2, 8])         // 火花(1)・オーラ(2)・爆発(8)
        XCTAssertNil(Reward.sanitizedFx([4, 9, 14]))                     // 称号だけなら付けない
        XCTAssertNil(Reward.sanitizedFx([365, -1, 9999]))               // 範囲外は捨てる
        XCTAssertNil(Reward.sanitizedFx([]))
        XCTAssertNil(Reward.sanitizedFx(nil))
    }

    func testStageFxSurvivesSanitizeAndCoding() throws {
        var st = Stage(name: "fx", mode: .survive, durationSec: 20, emitters: [em(.spiral)])
        st.rewardFx = [13, 6, 4]   // オーラ(13)・火花(6)・称号(4)
        let s = st.sanitized()
        XCTAssertEqual(s.rewardFx, [6, 13])
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.rewardFx, [6, 13])
        // 付けていないステージは、保存の形にも出ない
        let plain = try JSONEncoder().encode(Stage(name: "p", mode: .survive, durationSec: 20, emitters: [em(.spiral)]).sanitized())
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("rewardFx"))
        // 知らない形(数字以外)は、付けないものとして読む
        let bad = #"{"name":"x","mode":"survive","durationSec":20,"emitters":[],"rewardFx":"abc"}"#
        XCTAssertNil(try JSONDecoder().decode(Stage.self, from: Data(bad.utf8)).rewardFx)
    }
}
