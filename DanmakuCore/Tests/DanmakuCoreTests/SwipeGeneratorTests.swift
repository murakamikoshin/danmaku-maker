import XCTest
@testable import DanmakuCore

/// ランダム生成ステージ（スワイプ弾幕）
final class SwipeGeneratorTests: XCTestCase {
    func testSameSeedGivesSameStageAndDifferentSeedsDiffer() {
        XCTAssertEqual(SwipeGenerator.stage(seed: 42, hard: 300), SwipeGenerator.stage(seed: 42, hard: 300))
        XCTAssertNotEqual(SwipeGenerator.stage(seed: 42, hard: 300), SwipeGenerator.stage(seed: 43, hard: 300))
        XCTAssertNotEqual(SwipeGenerator.stage(seed: 42, hard: 100), SwipeGenerator.stage(seed: 42, hard: 900))
    }

    func testStagesAreValidSurviveStages() {
        for seed in 0..<60 as Range<UInt32> {
            for hard in [0, 349, 350, 699, 700, 999] {
                let s = SwipeGenerator.stage(seed: seed &* 2654435761, hard: hard)
                XCTAssertEqual(s.mode, .survive)
                XCTAssertEqual(s.durationSec, 12)
                XCTAssertEqual(s.emitters.count, 2 + hard / 350)
                for e in s.emitters {
                    XCTAssertTrue(SwipeGenerator.patterns.contains(e.t))
                    XCTAssertTrue((0.2...0.8).contains(e.x) && (0.08...0.33).contains(e.y))
                    XCTAssertGreaterThanOrEqual(e.i, 0.15)
                    XCTAssertEqual(e.e, 12)
                    XCTAssertGreaterThan(e.c, 0)
                }
                // 変な値が混ざっていないか（作ったステージは、そのまま整えても変わらない）
                XCTAssertEqual(s.sanitized().emitters, s.emitters, "seed \(seed) hard \(hard)")
            }
        }
    }

    func testHarderStagesHaveMoreBullets() {
        func avg(_ hard: Int) -> Double {
            var total = 0
            for seed in 0..<12 as Range<UInt32> {
                let c = SwipeClipPicker.sample(stage: SwipeGenerator.stage(seed: seed &* 7919, hard: hard)).counts
                total += c.dropFirst(4).prefix(20).reduce(0, +)
            }
            return Double(total) / 12 / 20
        }
        let easy = avg(0), mid = avg(500), hard = avg(999)
        XCTAssertLessThan(easy, mid)
        XCTAssertLessThan(mid, hard)
    }

    func testIdsRoundTrip() {
        let id = SwipeGenerator.id(seed: 0xAB12, hard: 7)
        XCTAssertEqual(id, "G0000ab12007")
        XCTAssertEqual(SwipeGenerator.parse(id: id)?.seed, 0xAB12)
        XCTAssertEqual(SwipeGenerator.parse(id: id)?.hard, 7)
        XCTAssertNil(SwipeGenerator.parse(id: "R000"))
        XCTAssertNil(SwipeGenerator.parse(id: "Gzzzzzzzz000"))
        XCTAssertEqual(SwipeGenerator.parse(id: SwipeGenerator.id(seed: UInt32.max, hard: 999))?.seed, UInt32.max)
    }

    func testTheClipFitsInsideTheStage() {
        // 1.5 秒から 10 秒遊ぶので、ステージの終わり（12 秒）より前に収まる
        XCTAssertLessThan(SwipeGenerator.clipAt + 10, Double(SwipeGenerator.duration))
        let sim = SwipeClip.prepare(stage: SwipeGenerator.stage(seed: 1, hard: 500), at: SwipeGenerator.clipAt)
        XCTAssertEqual(sim.outcome, .playing)
    }
}
