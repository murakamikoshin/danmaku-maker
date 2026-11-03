import XCTest
@testable import DanmakuCore

/// 専用の絵・動き・当たり判定を持つボス(堕天使)と、覚醒の設定
final class BossCharacterTests: XCTestCase {
    private func boss(look: Int?, size: Int? = nil, move: Int = 2, awaken: Int? = nil, hp: Int = 150, emitters: [Emitter] = []) -> Stage {
        Stage(name: "b", mode: .boss, durationSec: 60, bossHp: hp, bossMove: move, emitters: emitters,
              bossSize: size, bossLook: look, awaken: awaken).sanitized()
    }

    func testCharacterLookIsKeptInBossModesOnly() {
        XCTAssertEqual(boss(look: 5).bossLook, 5)
        XCTAssertEqual(Stage(name: "d", mode: .damage, durationSec: 60, emitters: [], bossLook: 5).sanitized().bossLook, 5)
        XCTAssertNil(Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], bossLook: 5).sanitized().bossLook)
        XCTAssertNil(boss(look: 6).bossLook, "知らない番号は標準に戻す")
        XCTAssertEqual(boss(look: 3).bossLook, 3, "図形のボスは、これまでどおり")
    }

    func testCharacterIgnoresSizeAndMove() {
        let s = boss(look: 5, size: 2, move: 2)
        XCTAssertNil(s.bossSize)
        XCTAssertEqual(s.bossMove, 0)
        let shape = boss(look: 3, size: 2, move: 2)
        XCTAssertEqual(shape.bossSize, 2)
        XCTAssertEqual(shape.bossMove, 2)
    }

    func testAwakenOnlyForBossModesAndValidPhases() {
        XCTAssertEqual(boss(look: 5, awaken: 3).awaken, 3)
        XCTAssertEqual(boss(look: 0, awaken: 2).awaken, 2, "覚醒は図形のボスにも付けられる")
        XCTAssertNil(boss(look: 5, awaken: 1).awaken)
        XCTAssertNil(boss(look: 5, awaken: 4).awaken)
        XCTAssertNil(Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], awaken: 3).sanitized().awaken)
        let w = Wave(kind: .boss, durationSec: 60, bossHp: 200, bossMove: 1, emitters: [], bossLook: 5, awaken: 2).sanitized()
        XCTAssertEqual(w.awaken, 2); XCTAssertEqual(w.bossMove, 0)
        XCTAssertNil(Wave(kind: .survive, durationSec: 20, emitters: [], awaken: 2).sanitized().awaken)
    }

    func testAwakenCodingOmitsDefaults() throws {
        let plain = try JSONEncoder().encode(boss(look: nil))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("awaken"))
        let s = boss(look: 5, awaken: 3)
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    func testSeedDoesNotDependOnLook() {
        XCTAssertEqual(boss(look: 5).seed, boss(look: nil, move: 0).seed)
    }

    func testFallenAngelPositionAndRadius() {
        let sim = Simulation(stage: boss(look: 5))
        XCTAssertEqual(sim.bossCharacter, .fallenAngel)
        let p0 = sim.bossPosition
        XCTAssertEqual(p0.x, 180, accuracy: 1e-9)
        XCTAssertEqual(p0.y, 128, accuracy: 1e-9)
        for t in stride(from: 0.0, through: 20, by: 0.37) {
            let p = BossCharacter.fallenAngel.position(waveT: t)
            XCTAssertEqual(p.x, 180, accuracy: 30.0001)
            XCTAssertEqual(p.y, 128, accuracy: 5.0001)
        }
        XCTAssertEqual(BossCharacter.fallenAngel.hitRadius, 40)
        XCTAssertNil(Simulation(stage: boss(look: 2)).bossCharacter)
    }

    func testFallenAngelCanBeDefeatedAndUsesItsOwnHitRadius() {
        var sim = Simulation(stage: boss(look: 5, hp: 100))
        for _ in 0..<(144 + 60 * 120) where sim.outcome == .playing { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared)
    }

    func testAwakenedFlagFollowsPhase() {
        var sim = Simulation(stage: boss(look: 5, awaken: 3, hp: 300))
        XCTAssertFalse(sim.isAwakened)
        var seen: [(Int, Bool)] = []
        for _ in 0..<(144 + 60 * 120) where sim.outcome == .playing {
            sim.step(.zero)
            if seen.last?.0 != sim.phase { seen.append((sim.phase, sim.isAwakened)) }
        }
        XCTAssertEqual(seen.map(\.0), [1, 2, 3])
        XCTAssertEqual(seen.map(\.1), [false, false, true])
        var none = Simulation(stage: boss(look: 5, hp: 300))
        for _ in 0..<(144 + 60 * 120) where none.outcome == .playing { none.step(.zero); XCTAssertFalse(none.isAwakened) }
    }
}
