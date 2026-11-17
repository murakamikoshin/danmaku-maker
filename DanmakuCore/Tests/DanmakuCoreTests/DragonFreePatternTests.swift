import XCTest
@testable import DanmakuCore

/// 竜王の、数・速さ・向きを自由に決められる5つの技(1.4.0)
final class DragonFreePatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 6, v: Double = 2, i: Double = 1, a: Int = 0) -> Emitter {
        var e = Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: 0, k: 0)
        e.a = a
        return e
    }
    private func shot(_ m: Emitter, _ k: Int = 0, lv: Int = 0, px: Double = 180, py: Double = 460) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.dragonLv = lv
        defer { Emit.dragonLv = 0 }
        Emit.emit(m, shot: k, cx: 180, cy: 110, px: px, py: py, rng: &rng, into: &out, awakened: false, salt: 5)
        return out
    }

    func testOnlyTheDragonCanUseThemAndTheyAreNotDragonMoves() {
        XCTAssertEqual(Pattern.dragonFree.map(\.bossCharacter), Array(repeating: .dragon, count: 5))
        XCTAssertTrue(Pattern.dragonFree.allSatisfy { $0.dragonMove == nil })
        XCTAssertEqual(Pattern.moves(of: .dragon).count, 15)
        let em = [emitter(.dragonWings), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 12).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 13).sanitized().emitters.map(\.t), [.dragonWings, .ring])
    }

    func testEveryMoveUsesDragonBulletsAndTheCount() {
        for t in Pattern.dragonFree {
            let a = shot(emitter(t, c: 4)), b = shot(emitter(t, c: 8))
            XCTAssertFalse(a.isEmpty, "\(t)")
            XCTAssertGreaterThan(b.count, a.count, "\(t): 数を増やすと弾が増える")
            XCTAssertTrue(a.allSatisfy { $0.isDragon && !$0.dragonPersistent && $0.radius > 0 }, "\(t): 竜王の弾(当たったら消える)")
        }
    }

    func testWingsComeFromBothWingsAndCurveInward() {
        let out = shot(emitter(.dragonWings, c: 5))
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(out.filter { $0.x < 180 }.count, 5)
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.dragonCurveScript })
        // 左の翼の弾は、曲がって右(内側)へ向かう
        var b = out[0]
        let vx0 = b.vx
        for _ in 0..<108 { _ = b.advance(dt: 1.0 / 120, width: 360, playerX: 180, playerY: 460) }
        XCTAssertGreaterThan(b.vx, vx0)
    }

    func testGeyserWaitsAtTheBottomThenRisesAndFalls() {
        let out = shot(emitter(.dragonGeyser, c: 3, v: 3))
        XCTAssertEqual(out.count, 3 * 4)
        XCTAssertEqual(shot(emitter(.dragonGeyser, c: 3, v: 3), lv: 3).count, 3 * 7)
        XCTAssertTrue(out.allSatisfy { $0.y > DanmakuConfig.height && $0.script == Bullet.dragonWaitScript })
        var b = out[0]
        for _ in 0..<60 { _ = b.advance(dt: 1.0 / 120, width: 360, playerX: 180, playerY: 460) }
        XCTAssertEqual(b.y, DanmakuConfig.height + 6, "待っている間は動かない")
        for _ in 0..<120 { _ = b.advance(dt: 1.0 / 120, width: 360, playerX: 180, playerY: 460) }
        XCTAssertLessThan(b.y, DanmakuConfig.height - 100, "噴き上がる")
        XCTAssertGreaterThan(b.vy, -3 * 60 * 1.5, "重力で遅くなる")
    }

    func testClawLinesAlternateSidesAndPlatinumAddsALine() {
        let a = shot(emitter(.dragonClaw, c: 5), 0), b = shot(emitter(.dragonClaw, c: 5), 1)
        XCTAssertEqual(a.count, 15)
        XCTAssertEqual(shot(emitter(.dragonClaw, c: 5), lv: 3).count, 20)
        // 1 回目は自機の右上、2 回目は左上から
        XCTAssertGreaterThan(a.map(\.x).reduce(0, +) / 15, 180)
        XCTAssertLessThan(b.map(\.x).reduce(0, +) / 15, 180)
        XCTAssertTrue(a.allSatisfy { $0.y < 460 })
    }

    func testTwisterMovesAndAddsFlamesFromVioletLightning() {
        let m = emitter(.dragonTwister, c: 6, i: 0.35)
        let x0 = shot(m, 0).map(\.x).reduce(0, +) / 6, x3 = shot(m, 3).map(\.x).reduce(0, +) / 6
        XCTAssertNotEqual(x0, x3, accuracy: 1, "撃つ場所が動く")
        XCTAssertEqual(shot(m, 0, lv: 1).count, 6)
        XCTAssertEqual(shot(m, 0, lv: 2).count, 9)
    }

    func testJawsCloseOnThePlayer() {
        let out = shot(emitter(.dragonJaws, c: 7), px: 200, py: 300)
        XCTAssertEqual(out.count, 14)
        XCTAssertEqual(out.filter { $0.y < 300 }.count, 7)
        XCTAssertEqual(out.filter { $0.y > 300 }.count, 7)
        for b in out {
            let a = atan2(b.vy, b.vx), want = atan2(300 - b.y, 200 - b.x)
            XCTAssertEqual(cos(a - want), 1, accuracy: 1e-9)
        }
    }

    func testMirrorFlipsLeftAndRight() {
        var m = emitter(.dragonClaw, c: 5)
        let a = shot(m, 0, px: 120)
        m.mir = 1
        let b = shot(m, 0, px: 240)
        XCTAssertEqual(a.count, b.count)
        for (p, q) in zip(a, b) { XCTAssertEqual(p.x, 360 - q.x, accuracy: 1e-9); XCTAssertEqual(p.y, q.y, accuracy: 1e-9) }
    }

    /// ゲームの中で: 竜王の姿で強さが変わる(Emit.dragonLv は撃つ間だけ変わり、戻る)
    func testFormSetsStrengthInsideTheGame() {
        func count(_ form: Int) -> Int {
            var st = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 9999, emitters: [emitter(.dragonGeyser, c: 2, i: 5)], lifeMode: .lives, lifeCount: 9,
                           bossLook: BossCharacter.dragon.rawValue)
            st.forms = [form, form, form]
            var sim = Simulation(stage: st.sanitized())
            sim.invincible = true
            var most = 0
            for _ in 0..<Int((DanmakuConfig.readySeconds + 0.3) / DanmakuConfig.step) { sim.step(.zero); most = max(most, sim.bullets.filter { $0.script == Bullet.dragonWaitScript }.count) }
            return most
        }
        XCTAssertEqual(count(0), 8)
        XCTAssertEqual(count(3), 14)
        XCTAssertEqual(Emit.dragonLv, 0)
    }
}
