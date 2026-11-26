import XCTest
@testable import DanmakuCore

/// 1.4.3 の要望: エディタで、ボスを途中の段階から試す(skipToPhase)
final class PhaseTestFromTests: XCTestCase {
    private func stage(_ mode: Mode, phases: Int?, hp: Int = 600) -> Stage {
        var s = Stage(name: "b", mode: mode, durationSec: 60, bossHp: mode == .boss ? hp : nil, bossMove: 0,
                      emitters: [Emitter(t: .ring, i: 0.3, c: 8)])
        s.phases = phases
        return s.sanitized()
    }

    private func phaseAfterStart(_ st: Stage, from n: Int) -> Simulation {
        var sim = Simulation(stage: st)
        sim.skipToPhase(n)
        sim.invincible = true
        for _ in 0..<10 { sim.step(.zero) }
        return sim
    }

    func testBossStartsAtTheChosenPhaseForEveryCount() {
        for count in [2, 3, 4, 5] {
            for n in 1...count {
                let sim = phaseAfterStart(stage(.boss, phases: count), from: n)
                XCTAssertEqual(sim.phase, n, "\(count)段階のボスを第\(n)段階から")
                XCTAssertEqual(sim.outcome, .playing)
            }
        }
    }

    func testDamageRaceStartsAtTheChosenPhase() {
        for count in [2, 3, 5] {
            for n in 1...count {
                XCTAssertEqual(phaseAfterStart(stage(.damage, phases: count), from: n).phase, n, "ダメージ勝負 \(count)段階・第\(n)段階から")
            }
        }
    }

    func testOutOfRangeAndSurviveDoNothing() {
        XCTAssertEqual(phaseAfterStart(stage(.boss, phases: 3), from: 9).phase, 1)
        XCTAssertEqual(phaseAfterStart(stage(.boss, phases: 3), from: 0).phase, 1)
        XCTAssertEqual(phaseAfterStart(stage(.boss, phases: 1), from: 2).phase, 1, "段階なしのボス")
        let s = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)]).sanitized()
        XCTAssertEqual(phaseAfterStart(s, from: 2).phase, 1)
    }

    func testTheLastPhaseStillNeedsTheRestOfTheHp() {
        // 第3段階から: HP は 1/3 残っていて、まだ倒れていない
        let sim = phaseAfterStart(stage(.boss, phases: 3, hp: 600), from: 3)
        XCTAssertEqual(sim.hp, 200)
    }

    func testDarkColorSurvivesSanitize() {
        var e = Emitter(t: .ring); e.k = Emitter.darkColor
        let s = Stage(name: "d", mode: .survive, durationSec: 20, emitters: [e]).sanitized()
        XCTAssertEqual(s.emitters[0].k, 5)
    }
}
