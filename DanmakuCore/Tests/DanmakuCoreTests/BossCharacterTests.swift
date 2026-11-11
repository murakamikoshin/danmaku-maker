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
        XCTAssertNil(boss(look: BossCharacter.maxLook + 1).bossLook, "知らない番号は標準に戻す")
        XCTAssertEqual(boss(look: 3).bossLook, 3, "図形のボスは、これまでどおり")
    }

    /// 1.2.0 から、キャラクターのボスも動きと大きさ(半径 20〜60px)を選べる。図形のボスの 0〜2 は、キャラクターでは使わない
    func testCharacterKeepsMoveAndCharacterSize() {
        let s = boss(look: 5, size: 2, move: 2)
        XCTAssertNil(s.bossSize, "図形のボスの大きさ(0〜2)は、キャラクターでは使わない")
        XCTAssertEqual(s.bossMove, 2)
        XCTAssertEqual(boss(look: 5, size: 52, move: 0).bossSize, 52)
        XCTAssertNil(boss(look: 5, size: 40, move: 0).bossSize, "標準(40)は保存しない")
        XCTAssertNil(boss(look: 5, size: 61, move: 0).bossSize, "範囲外は標準に戻す")
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
        XCTAssertEqual(w.awaken, 2); XCTAssertEqual(w.bossMove, 1)
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
        XCTAssertEqual(boss(look: 5, move: 0).seed, boss(look: nil, move: 0).seed)
    }

    /// 動き・位置・大きさを選んだキャラクターのボス: 位置は図形のボスと同じ動き(キャラクターの高さ)、当たり判定と技の出る場所は大きさの倍率
    func testCharacterMoveAndScale() {
        var big = boss(look: 9, size: 60, move: 4); big.bossX = 0.4
        let sim = Simulation(stage: big.sanitized())
        XCTAssertEqual(sim.bossHitRadius, 60, accuracy: 1e-9)
        XCTAssertEqual(sim.bossScale, 1.5, accuracy: 1e-9)
        let still = Simulation(stage: boss(look: 9, move: 0).sanitized())
        XCTAssertEqual(still.bossScale, 1)
        XCTAssertEqual(still.bossPosition.x, BossCharacter.witch.position(waveT: 0).x, accuracy: 1e-9, "何も選ばなければ、これまで通りの定位置")
        // 円の動き(4)を、キャラクターの高さで。位置の指定(左へ 0.1)も効く
        let q = Simulation.bossPoint(move: 4, t: 0)
        XCTAssertEqual(sim.bossPosition.x, q.x - 0.1 * DanmakuConfig.width, accuracy: 1e-6)
        XCTAssertEqual(sim.bossPosition.y, q.y + BossCharacter.moveYOffset, accuracy: 1e-6)
        // 技の出る場所(魔女の提灯)は、中心から 1.5 倍の位置になる
        Emit.anchorScale = 1.5
        let lantern = Emit.witchLantern(100, 200)
        Emit.anchorScale = 1
        XCTAssertEqual(lantern.x, 100 + 42 * 1.5, accuracy: 1e-9)
        XCTAssertEqual(lantern.y, 200 - 54 * 1.5, accuracy: 1e-9)
        XCTAssertEqual(Emit.witchLantern(100, 200).x, 142, "撃ち終わったら、倍率は 1 に戻る")
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
