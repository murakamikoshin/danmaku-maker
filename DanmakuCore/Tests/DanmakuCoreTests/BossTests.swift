import XCTest
@testable import DanmakuCore

final class BossTests: XCTestCase {
    /// 画面の端に逃げれば、ボスの弾も自機ショットも当たらない
    private func hideLeft(_ steps: Int) -> [Move] {
        [Move](repeating: Move(dx: -127, dy: 0), count: 20) + [Move](repeating: .zero, count: steps)
    }

    func testPhaseChangesClearBulletsAndPauseFiring() {
        // 弾(1発・右向き)を常に出し続ける。自機はボスの真下で撃つだけ
        let stage = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 150, bossMove: 0,
                          emitters: [em(.ring, i: 0.1, c: 1, v: 1, r: 0)]).sanitized()
        var sim = Simulation(stage: stage)
        var phases: [(tick: Int, phase: Int, bullets: Int, banner: Double)] = []
        var last = 1
        for _ in 0..<(144 + 60 * 120) where sim.outcome == .playing {
            sim.step(.zero)
            if sim.phase != last { phases.append((sim.tick, sim.phase, sim.bullets.count, sim.banner)); last = sim.phase }
        }
        XCTAssertEqual(phases.map(\.phase), [2, 3])
        for p in phases {
            XCTAssertEqual(p.bullets, 0, "切り替わりで全消去")
            XCTAssertEqual(p.banner, 1.2, accuracy: DanmakuConfig.step + 1e-9, "1.2秒（同じステップで1回ぶん減る）")
        }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertLessThanOrEqual(sim.hp, 0)
    }

    func testNoFiringDuringBanner() {
        let stage = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 150, bossMove: 0,
                          emitters: [em(.ring, i: 0.05, c: 1, v: 1, r: 0)]).sanitized()
        var sim = Simulation(stage: stage)
        var changeTick: Int?
        var last = 1
        for _ in 0..<(144 + 60 * 120) where sim.outcome == .playing {
            sim.step(.zero)
            if changeTick == nil, sim.phase != last { changeTick = sim.tick }
            if let c = changeTick, sim.tick < c + 100, sim.banner > 0 { XCTAssertEqual(sim.bullets.count, 0) }
        }
        XCTAssertNotNil(changeTick)
    }

    func testPhaseSpecificEmittersOnlyFireInTheirPhase() {
        let stage = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 600, bossMove: 0,
                          emitters: [em(.ring, i: 0.1, c: 1, v: 1, r: 0, k: 1, ph: 2)]).sanitized()
        var sim = Simulation(stage: stage)
        for _ in 0..<(144 + 60 * 120) where sim.outcome == .playing {
            sim.step(.zero)
            if sim.phase != 2 { XCTAssertEqual(sim.bullets.count, 0) }
        }
    }

    func testTimeUpIsFailure() {
        let stage = Stage(name: "b", mode: .boss, durationSec: 30, bossHp: 1000, bossMove: 0,
                          emitters: [em(.ring, i: 0.1, c: 1, v: 1, r: 0)]).sanitized()
        var sim = Simulation(stage: stage)
        let moves = hideLeft(0)
        for n in 0..<(144 + 31 * 120) where sim.outcome == .playing { sim.step(n < moves.count ? moves[n] : .zero) }
        XCTAssertEqual(sim.outcome, .timeUp)
        XCTAssertEqual(sim.hp, 1000)
    }

    func testBossMovementTable() {
        let stage = Stage(name: "b", mode: .boss, durationSec: 30, bossHp: 100, bossMove: 2, emitters: []).sanitized()
        var sim = Simulation(stage: stage)
        XCTAssertEqual(sim.bossPosition.x, 180, accuracy: 1e-9)
        for _ in 0..<(144 + 120) { sim.step(.zero) }
        XCTAssertEqual(sim.bossPosition.x, 360 * (0.5 + 0.32 * sin(sim.t * 1.3)), accuracy: 1e-9)
        XCTAssertEqual(sim.bossPosition.y, 540 * 0.18, accuracy: 1e-9)
    }
}
