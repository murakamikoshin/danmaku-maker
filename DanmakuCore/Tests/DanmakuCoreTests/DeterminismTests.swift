import XCTest
@testable import DanmakuCore

final class DeterminismTests: XCTestCase {
    private let stage = Stage(name: "t", mode: .survive, durationSec: 20, emitters: [
        em(.spiral, i: 0.12, c: 3, v: 1.8, r: 11),
        em(.rain, y: 0, i: 0.18, c: 2, v: 2.2),
        em(.aim, i: 0.8, c: 5, v: 3, r: 40, k: 2),
        em(.sweep, y: 0.1, s: 3, i: 0.2, c: 3, v: 3, r: 70, k: 1),
    ]).sanitized()

    /// 同じステージ＋同じ入力なら、何回回しても弾の数・被弾ステップ・結果が一致する
    func testRepeatedRunsAreIdentical() {
        let moves = scriptedMoves(count: 2400)
        let first = Simulation.run(stage: stage, moves: moves)
        for _ in 0..<3 { XCTAssertEqual(Simulation.run(stage: stage, moves: moves), first) }
    }

    func testStepByStepBulletCountsMatch() {
        let moves = scriptedMoves(count: 1500)
        var a = Simulation(stage: stage), b = Simulation(stage: stage)
        for n in 0..<1500 where a.outcome == .playing {
            a.step(moves[n]); b.step(moves[n])
            XCTAssertEqual(a.bullets.count, b.bullets.count)
            XCTAssertEqual(a.bullets, b.bullets)
        }
        XCTAssertEqual(a.outcome, b.outcome)
        XCTAssertEqual(a.tick, b.tick)
    }

    func testDifferentInputGivesDifferentResult() {
        let a = Simulation.run(stage: stage, moves: scriptedMoves(count: 600))
        let b = Simulation.run(stage: stage, moves: [])
        XCTAssertNotEqual(a, b)
    }

    func testSeedDependsOnContentNotOrderOfJSON() {
        let s1 = stage
        var s2 = stage
        s2.emitters[0].c += 1
        XCTAssertNotEqual(s1.seed, s2.seed)
        let decoded = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s1))
        XCTAssertEqual(decoded.seed, s1.seed)
    }

    func testMulberry32MatchesPrototype() {
        // 試作の mulberry(12345) の最初の値（node で計算）
        var rng = Mulberry32(seed: 12345)
        let expected = [0.9797282677609473, 0.3067522644996643, 0.484205421525985]
        for e in expected { XCTAssertEqual(rng.next(), e, accuracy: 1e-15) }
    }

    func testSurviveClears() {
        let calm = Stage(name: "calm", mode: .survive, durationSec: 10, emitters: [em(.ring, x: 0.1, y: 0.0, e: 2, i: 2, c: 1, v: 1)]).sanitized()
        let r = Simulation.run(stage: calm, moves: [])
        XCTAssertEqual(r.outcome, .cleared)
    }
}

final class InvincibleTests: XCTestCase {
    func testInvincibleIgnoresHitsButDefaultDoesNot() {
        let stage = Stage(name: "i", mode: .survive, durationSec: 10,
                          emitters: [em(.aim, x: 0.5, y: 0.8, i: 0.3, c: 5, v: 3, r: 10)]).sanitized()
        var normal = Simulation(stage: stage), god = Simulation(stage: stage)
        god.invincible = true
        for _ in 0..<(144 + 1200) { normal.step(.zero); god.step(.zero) }
        XCTAssertEqual(normal.outcome, .hit)
        XCTAssertEqual(god.outcome, .cleared)
    }
}
