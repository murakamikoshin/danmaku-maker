import XCTest
@testable import DanmakuCore

final class IceQueenPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 6, v: Double = 2, r: Double = 0, i: Double = 0.5) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: r, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: 5)
        return out
    }
    private let dt = 1.0 / 120

    func testOwnership() {
        let em = [emitter(.iceCage), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 6).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 7).sanitized().emitters.map(\.t), [.iceCage, .ring])
        XCTAssertEqual(Pattern.iceQueen.map(\.bossCharacter), Array(repeating: .iceQueen, count: 5))
        XCTAssertGreaterThanOrEqual(BossCharacter.maxLook, 7)
    }

    func testCageBranchesTwiceIntoFlakes() {
        let b = shot(emitter(.iceCage, v: 2), 0)
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(shot(emitter(.iceCage, v: 2), 0, awakened: true).count, 12)
        var one = b[0]
        var t = 0.0
        var motion = BulletMotion.alive
        while t < 0.6 && motion == .alive { motion = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(motion, .burst)
        XCTAssertEqual(t, 0.5, accuracy: 0.02, "0.5秒で分かれる")
        let kids = one.fragments()
        XCTAssertEqual(kids.count, 2)
        XCTAssertEqual(kids[0].look, BulletLook.code(.shard))
        XCTAssertEqual(kids[0].homeLeft, 1)
        // 進んでいた向きから ±0.5rad
        let base = atan2(one.vy, one.vx)
        XCTAssertEqual(atan2(kids[1].vy, kids[1].vx) - base, 0.5, accuracy: 1e-9)
        // 2回目の枝分かれで、結晶の弾(ふつうの弾)になる
        var k1 = kids[0]; t = 0
        motion = .alive
        while t < 0.6 && motion == .alive { motion = k1.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(motion, .burst)
        let last = k1.fragments()
        XCTAssertEqual(last[0].script, 0)
        XCTAssertEqual(last[0].look, BulletLook.code(.flake))
    }

    func testIciclesWaitThenAccelerate() {
        let b = shot(emitter(.iceIcicles, c: 6, v: 1), 0)
        XCTAssertEqual(b.count, 6)
        XCTAssertEqual(shot(emitter(.iceIcicles, c: 6, v: 1), 0, awakened: true).count, 9)
        var one = b[0]
        XCTAssertTrue(one.isDormant)
        var t = 0.0
        while t < 0.49 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(one.y, -6, "待機中は動かない")
        XCTAssertTrue(one.isDormant)
        for _ in 0..<6 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertFalse(one.isDormant)
        let v1 = one.vy
        for _ in 0..<120 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertGreaterThan(one.vy, v1 + 200, "だんだん速くなる(0.08 × 3600 px/秒²)")
    }

    func testFreezeStopsThenShattersIntoThree() {
        let c = emitter(.iceFreeze, c: 20, v: 2.5)
        let out = shot(c, 0)
        XCTAssertEqual(out.filter { $0.script == Bullet.freezeScript }.count, 20)
        XCTAssertEqual(out.filter { $0.script == Bullet.holdScript }.count, 60, "砕けたあとの氷片は、1つの結晶につき3つ(待機中)")
        XCTAssertEqual(shot(c, 0, awakened: true).filter { $0.script == Bullet.freezeScript }.count, 28)
        var crystal = out.first { $0.script == Bullet.freezeScript }!
        let frag = out.first { $0.script == Bullet.holdScript }!
        var t = 0.0
        while t < 0.7 { _ = crystal.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(crystal.vx, 0); XCTAssertEqual(crystal.vy, 0)
        XCTAssertEqual(crystal.look, BulletLook.code(.flake))
        // 氷片の待機位置は、結晶が止まる場所
        XCTAssertEqual(frag.x, crystal.x, accuracy: 1.5)
        XCTAssertEqual(frag.y, crystal.y, accuracy: 1.5)
        var steps = 0
        while steps < 300 && crystal.advance(dt: dt, width: 360, playerX: 0, playerY: 0) == .alive { steps += 1 }
        XCTAssertEqual(Double(steps) * dt + 0.7, 80.0 / 60, accuracy: 0.03, "1.33秒で消える")
    }

    func testBlizzardWindFlipsEveryTwoSecondsAndMirrorShot() {
        let m = emitter(.iceBlizzard, c: 8, v: 1.6, i: 0.05)
        XCTAssertEqual(shot(m, 1).count, 1)
        XCTAssertEqual(shot(m, 0, awakened: true).count, 2)
        XCTAssertEqual(shot(m, 1, awakened: true).count, 1)
        var b = shot(m, 1)[0]
        let w0 = b.u0
        var t = 0.0
        while t < 2.5 { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertLessThan(b.vx * w0, 0, "風向きが入れ替わる")
        XCTAssertEqual(shot(m, 40)[0].u0, -w0, "2秒後の発射は、逆向きの風")
    }

    func testMirrorFanBouncesAndStageRuns() {
        let fan = shot(emitter(.iceMirror, c: 5, v: 3), 0)
        XCTAssertEqual(fan.count, 5)
        XCTAssertEqual(fan.map(\.bounces), [2, 2, 2, 2, 2])
        let ems = Pattern.iceQueen.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.2, c: 20, v: 2, r: 0, k: 0) }
        let st = Stage(name: "i", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 7, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        var peak = 0
        for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets)
        XCTAssertEqual(sim.bossCharacter, .iceQueen)
    }
}
