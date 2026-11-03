import XCTest
@testable import DanmakuCore

/// スワイプ弾幕で使う 10 秒の区間の選び方（仕様書 4 章）
final class SwipeClipPickerTests: XCTestCase {
    private func ats(_ c: [SwipeClipPicker.Candidate]) -> [Double] { c.map(\.at) }

    // MARK: 数の並びから選ぶ部分

    func testEstimatedClearRate() {
        XCTAssertEqual(SwipeClipPicker.estimatedClearRate(averageBullets: 0), 0.95, "上限 0.95")
        XCTAssertEqual(SwipeClipPicker.estimatedClearRate(averageBullets: 15), 0.95)
        XCTAssertEqual(SwipeClipPicker.estimatedClearRate(averageBullets: 100), 0.7, accuracy: 1e-12)
        XCTAssertEqual(SwipeClipPicker.estimatedClearRate(averageBullets: 250), 0.1, accuracy: 1e-12)
        XCTAssertEqual(SwipeClipPicker.estimatedClearRate(averageBullets: 900), 0.05, "下限 0.05")
    }

    func testThePeakIsChosenFirstAndTheOthersAreSpacedOut() {
        // 40 秒（80 サンプル）。20〜30 秒だけ盛り上がる
        var counts = [Int](repeating: 30, count: 80)
        for i in 40..<60 { counts[i] = 400 }
        let c = SwipeClipPicker.candidates(counts: counts, gaps: [Bool](repeating: false, count: 80))
        XCTAssertEqual(ats(c), [20, 15, 25, 2, 7], "山をすっぽり含む区間が先頭。次の候補は 5 秒以上離す。同じ合計なら早い順。開始 2 秒以内は避ける")
        XCTAssertEqual(c.map(\.total), [8000, 4300, 4300, 600, 600])
        XCTAssertEqual(c[0].average, 400)
        XCTAssertEqual(c.count, SwipeClipPicker.maxCandidates)
        for (i, a) in c.enumerated() { for b in c[(i + 1)...] { XCTAssertGreaterThanOrEqual(abs(a.at - b.at), 5) } }
    }

    func testAreasThatAreTooQuietMakeNoClip() {
        XCTAssertEqual(SwipeClipPicker.candidates(counts: [Int](repeating: 14, count: 60), gaps: [Bool](repeating: false, count: 60)), [], "平均 14 発では足りない")
        let exactly = SwipeClipPicker.candidates(counts: [Int](repeating: 15, count: 60), gaps: [Bool](repeating: false, count: 60))
        XCTAssertFalse(exactly.isEmpty, "平均ちょうど 15 発ならよい")
        XCTAssertEqual(exactly[0].total, 300)
    }

    func testShortStagesStartFromTheTopOnlyWhenNothingElseFits() {
        func at(_ n: Int) -> [Double] {
            ats(SwipeClipPicker.candidates(counts: [Int](repeating: 100, count: n), gaps: [Bool](repeating: false, count: n)))
        }
        XCTAssertEqual(at(19), [], "10 秒に足りない")
        XCTAssertEqual(at(20), [0], "ちょうど 10 秒のステージは先頭から")
        XCTAssertEqual(at(23), [0], "2 秒より後に始められる区間がなければ、先頭から（同じ合計なら早い順、間隔 5 秒の制限で 1 つだけ）")
        XCTAssertEqual(at(24), [2], "2 秒より後に始められる区間があれば、そちらだけ")
    }

    func testWindowsAcrossASceneChangeAreSkipped() {
        var gaps = [Bool](repeating: false, count: 80)
        for i in 40...42 { gaps[i] = true }
        let c = SwipeClipPicker.candidates(counts: [Int](repeating: 100, count: 80), gaps: gaps)
        XCTAssertEqual(ats(c), [2, 7, 21.5, 26.5])
        for x in c {
            let j = Int(x.at * 2)
            XCTAssertFalse((j..<(j + 20)).contains(where: { gaps[$0] }), "切り替えの間をまたがない")
        }
    }

    func testTheSlidingSumMatchesTheDirectSum() {
        var counts: [Int] = []
        var s: UInt32 = 12345
        for _ in 0..<200 { s = s &* 1_664_525 &+ 1_013_904_223; counts.append(Int(s >> 24) + 20) }
        let c = SwipeClipPicker.candidates(counts: counts, gaps: [Bool](repeating: false, count: 200))
        for x in c {
            let j = Int(x.at * 2)
            XCTAssertEqual(x.total, counts[j..<(j + 20)].reduce(0, +), "ずらして足した合計が、直接足した合計と同じ")
        }
        // 先頭が、全部の区間のうち一番大きい
        let best = (4...180).map { counts[$0..<($0 + 20)].reduce(0, +) }.max()!
        XCTAssertEqual(c[0].total, best)
    }

    // MARK: 本物のシミュレーションで

    private let strong = Emitter(t: .ring, x: 0.5, y: 0.1, s: 0, e: 30, i: 0.1, c: 30, v: 3, r: 0, k: 0)

    func testSamplingCountsHalfSecondsFromTheStartOfTheStage() {
        let stage = Stage(name: "40", mode: .survive, durationSec: 40, emitters: [strong])
        let (counts, gaps) = SwipeClipPicker.sample(stage: stage)
        XCTAssertTrue((79...81).contains(counts.count), "40 秒 ÷ 0.5 秒 = 80（時間の足し算の端数で 1 つ前後する）。実際 \(counts.count)")
        XCTAssertEqual(counts.count, gaps.count)
        XCTAssertEqual(counts[0], 0, "開始の瞬間は弾がない")
        XCTAssertFalse(gaps.contains(true))
        XCTAssertGreaterThan(counts[20], 100)
    }

    func testAStageWithAPeakGetsItsClipAroundThePeak() {
        let burst = Emitter(t: .ring, x: 0.5, y: 0.1, s: 20, e: 30, i: 0.2, c: 20, v: 2, r: 0, k: 0)
        let stage = Stage(name: "山", mode: .survive, durationSec: 40, emitters: [burst])
        let c = SwipeClipPicker.candidates(stage: stage)
        XCTAssertFalse(c.isEmpty)
        XCTAssertTrue((20...24).contains(c[0].at), "20〜30 秒の山の真ん中あたり。実際 \(c[0].at)")
        XCTAssertGreaterThan(c[0].average, 100)
        XCTAssertLessThan(c[0].estimatedClearRate, 0.7)
        XCTAssertEqual(c, SwipeClipPicker.candidates(stage: stage), "何度やっても同じ")
    }

    func testAQuietStageMakesNoClip() {
        let stage = Stage(name: "静か", mode: .survive, durationSec: 30, emitters: [em(.ring, i: 2, c: 2, v: 1)])
        XCTAssertEqual(SwipeClipPicker.candidates(stage: stage), [])
    }

    func testATenSecondStageUsesTheWholeStage() {
        let stage = Stage(name: "10", mode: .survive, durationSec: 10, emitters: [strong])
        let c = SwipeClipPicker.candidates(stage: stage)
        XCTAssertEqual(ats(c), [0])
    }

    func testBossStagesAreSampledWithoutEverDefeatingTheBoss() {
        let stage = Stage(name: "ボス", mode: .boss, durationSec: 40, bossHp: 100, bossMove: 0, emitters: [em(.ring, y: 0.2, i: 0.15, c: 24, v: 2.5, r: 4)])
        let (counts, _) = SwipeClipPicker.sample(stage: stage)
        XCTAssertTrue((79...81).contains(counts.count), "ボスは倒れないので、40 秒の最後まで続く。実際 \(counts.count)")
    }

    func testSceneChangesInASequenceAreAvoided() {
        let wave = Wave(kind: .survive, durationSec: 20, emitters: [strong])
        let stage = Stage(name: "連戦", mode: .sequence, durationSec: 0, emitters: [], waves: [wave, wave]).sanitized()
        let (counts, gaps) = SwipeClipPicker.sample(stage: stage)
        XCTAssertTrue(gaps.contains(true), "場面の切り替えの間が見つかる")
        XCTAssertGreaterThan(counts.count, 80, "20 秒 + 切り替え 1.5 秒 + 20 秒")
        let c = SwipeClipPicker.candidates(stage: stage)
        XCTAssertFalse(c.isEmpty)
        for x in c {
            // 切り替えは 20〜21.5 秒。10 秒の区間 [at, at + 10) が重ならないこと
            XCTAssertFalse(x.at + 10 > 20 && x.at < 21.5, "区間 \(x.at) 秒が切り替えをまたいでいる")
        }
    }
}
