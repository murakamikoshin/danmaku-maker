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

    /// 当てる回数を決められる(1〜50)。撃ち方に関係なく、1発で1回。標準(20)と範囲外は整える
    func testMookHits() {
        func st(_ n: Int?, breakable: Bool? = true) -> Stage {
            var s = Stage(name: "m", mode: .survive, durationSec: 20, emitters: [em(), em(x: 0.1)], mooks: 1, shot: .heavy)
            s.mooksBreakable = breakable; s.mookHits = n
            return s.sanitized()
        }
        XCTAssertEqual(st(1).mookHits, 1)
        XCTAssertEqual(st(50).mookHits, 50)
        XCTAssertEqual(st(99).mookHits, 50)
        XCTAssertEqual(st(0).mookHits, 1)
        XCTAssertNil(st(20).mookHits, "標準は保存しない")
        XCTAssertNil(st(5, breakable: nil).mookHits, "倒せないなら使わない")
        let back = try? JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st(3)))
        XCTAssertEqual(back?.mookHits, 3)

        var one = Simulation(stage: st(1)); one.invincible = true
        XCTAssertEqual(one.mookHP, [1, 1])
        var n = 0
        while !one.mookDestroyed(0) && n < 120 * 4 { one.step(.zero); n += 1 }
        XCTAssertTrue(one.mookDestroyed(0), "1回で倒れる(重い弾でも1発は1回)")
        XCTAssertEqual(one.mookHP[0], 0)

        var many = Simulation(stage: st(50)); many.invincible = true
        for _ in 0..<n { many.step(.zero) }
        XCTAssertFalse(many.mookDestroyed(0), "50回なら、同じ時間ではまだ倒れない")
        XCTAssertLessThan(many.mookHP[0], 50)
    }

    /// 雑魚を全部倒したら次へ / クリア。倒しきれずに時間切れなら失敗。耐える場面で、倒せる雑魚がいるときだけ使える
    func testMooksClear() {
        func st(hits: Int, sec: Int = 20, clear: Bool? = true, breakable: Bool? = true, ems: [Emitter]? = nil) -> Stage {
            var s = Stage(name: "c", mode: .survive, durationSec: sec, emitters: ems ?? [em()], mooks: 1)
            s.mooksBreakable = breakable; s.mookHits = hits; s.mooksClear = clear
            return s.sanitized()
        }
        XCTAssertEqual(st(hits: 1).mooksClear, true)
        XCTAssertNil(st(hits: 1, breakable: nil).mooksClear, "倒せないなら使えない")
        let edgeOnly = [Emitter(t: .rain, x: 0.5, y: 0, s: 0, e: 20, i: 0.5, c: 3, v: 2, r: 0, k: 0)]
        XCTAssertNil(st(hits: 1, ems: edgeOnly).mooksClear, "雑魚がいない(画面の端から撃つだけ)なら使えない")
        var bossSt = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, emitters: [em(p: 1)], mooks: 1)
        bossSt.mooksBreakable = true; bossSt.mooksClear = true
        XCTAssertNil(bossSt.sanitized().mooksClear, "ボス戦では使わない(ボスを倒すとクリア)")

        // 1回で倒れる雑魚(真上)を倒すと、時間より前にクリア
        var a = Simulation(stage: st(hits: 1)); a.invincible = true
        while a.outcome == .playing && a.tick < 120 * 30 { a.step(.zero) }
        XCTAssertEqual(a.outcome, .cleared)
        XCTAssertLessThan(a.t, 5, "時間切れよりずっと早く終わる")
        XCTAssertEqual(a.mookClears, 1)
        // 横の雑魚は真上にいないので倒せず、時間切れで失敗
        var b = Simulation(stage: st(hits: 1, sec: 10, ems: [em(), em(x: 0.1)])); b.invincible = true
        while b.outcome == .playing && b.tick < 120 * 30 { b.step(.zero) }
        XCTAssertEqual(b.outcome, .timeUp)
        // オフなら、これまでどおり時間まで耐えてクリア
        var c = Simulation(stage: st(hits: 1, sec: 10, clear: nil)); c.invincible = true
        while c.outcome == .playing && c.tick < 120 * 30 { c.step(.zero) }
        XCTAssertEqual(c.outcome, .cleared)
        XCTAssertGreaterThanOrEqual(c.t, 10)
    }

    /// 連戦: 雑魚を全部倒すと、次の場面(ボス)へ進む
    func testMooksClearAdvancesToBoss() {
        var s = Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: [
            Wave(kind: .survive, durationSec: 30, emitters: [em()], mooks: 1),
            Wave(kind: .boss, durationSec: 40, bossHp: 100, emitters: [em(p: 1)])])
        s.waves![0].mooksBreakable = true; s.waves![0].mookHits = 1; s.waves![0].mooksClear = true
        let clean = s.sanitized()
        XCTAssertEqual(clean.waves?[0].mooksClear, true)
        var sim = Simulation(stage: clean); sim.invincible = true
        while sim.waveIndex == 0 && sim.tick < 120 * 40 { sim.step(.zero) }
        XCTAssertEqual(sim.waveIndex, 1)
        XCTAssertLessThan(sim.t, 5, "30秒待たずにボスへ")
        let back = try? JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(clean))
        XCTAssertEqual(back?.waves?[0].mooksClear, true)
    }
}
