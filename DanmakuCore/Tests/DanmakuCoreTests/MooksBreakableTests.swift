import XCTest
@testable import DanmakuCore

/// 雑魚を倒せる設定(1.2.0)。倒すと、その発射台はその場面では撃たなくなる。耐久のステージでも、この設定のときだけ自機が撃つ
final class MooksBreakableTests: XCTestCase {
    private func em(x: Double = 0.5, y: Double = 0.3, p: Int = 0) -> Emitter {
        Emitter(t: .ring, x: x, y: y, s: 0, e: 60, i: 0.3, c: 8, v: 2, r: 0, k: 0, ph: 0, p: p)
    }
    private func survive(breakable: Bool?, mooks: Int? = 1) -> Stage {
        var s = Stage(name: "m", mode: .survive, durationSec: 20, emitters: [em(), em(x: 0.1)], mooks: mooks)
        s.mooksBreakable = breakable
        return s.sanitized()
    }

    func testSanitizeKeepsOnlyWithMooks() {
        XCTAssertEqual(survive(breakable: true).mooksBreakable, true)
        XCTAssertNil(survive(breakable: false).mooksBreakable)
        XCTAssertNil(survive(breakable: true, mooks: nil).mooksBreakable, "雑魚を出さないなら、倒せる設定は使わない")
        let back = try? JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(survive(breakable: true)))
        XCTAssertEqual(back?.mooksBreakable, true)
        let plain = String(decoding: try! JSONEncoder().encode(survive(breakable: nil)), as: UTF8.self)
        XCTAssertFalse(plain.contains("mooksBreakable"), "使わないときは保存しない(古いステージの結果が変わらない)")
    }

    /// 自機の真上の雑魚は、撃ち続けると倒れて、その発射台は撃たなくなる。真上にいない雑魚は残る
    func testSurviveMookDiesAndStopsFiring() {
        var sim = Simulation(stage: survive(breakable: true))
        sim.invincible = true
        XCTAssertEqual(sim.mookHP, [DanmakuConfig.mookHp, DanmakuConfig.mookHp])
        for _ in 0..<(120 * 4) { sim.step(.zero) }
        XCTAssertTrue(sim.mookDestroyed(0), "真上の雑魚は倒れる")
        XCTAssertFalse(sim.mookDestroyed(1), "横の雑魚には当たらない")
        // 倒れた雑魚からは、もう弾が出ない: 倒せない同じステージより、画面の弾が少なくなる
        var plain = Simulation(stage: survive(breakable: nil))
        plain.invincible = true
        for _ in 0..<(120 * 4) { plain.step(.zero) }
        for _ in 0..<(120 * 4) { sim.step(.zero); plain.step(.zero) }
        XCTAssertLessThan(sim.bullets.count, plain.bullets.count)
    }

    func testOffByDefaultNothingChanges() {
        var a = Simulation(stage: survive(breakable: nil))
        var b = Simulation(stage: survive(breakable: false))
        for _ in 0..<(120 * 3) { a.step(.zero); b.step(.zero) }
        XCTAssertEqual(a.bullets.count, b.bullets.count)
        XCTAssertFalse(a.mookDestroyed(0))
        XCTAssertTrue(a.mookHP.allSatisfy { $0 == 0 })
    }

    /// ボス戦: 弾は雑魚に先に当たる(雑魚が盾になる)。ボスから撃つ発射台には雑魚が出ない
    func testBossModeMookShieldsBoss() {
        var shielded = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, emitters: [em(y: 0.4, p: 1)], mooks: 2)
        shielded.mooksBreakable = true
        var open = shielded; open.mooksBreakable = nil
        var s1 = Simulation(stage: shielded.sanitized()); s1.invincible = true
        var s2 = Simulation(stage: open.sanitized()); s2.invincible = true
        for _ in 0..<(120 * 2) { s1.step(.zero); s2.step(.zero) }
        XCTAssertLessThan(s1.damageDealt, s2.damageDealt, "雑魚に当たったぶん、ボスへのダメージが減る")
        XCTAssertFalse(Simulation.hasMook(em(), boss: true), "ボスから撃つ発射台には雑魚がいない")
        XCTAssertTrue(Simulation.hasMook(em(p: 1), boss: true))
    }
}
