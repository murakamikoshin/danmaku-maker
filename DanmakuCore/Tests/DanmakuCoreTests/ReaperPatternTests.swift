import XCTest
@testable import DanmakuCore

final class ReaperPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 10, v: Double = 1, r: Double = 0, i: Double = 1) -> Emitter {
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
        let em = [emitter(.reaperScythe), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 7).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 8).sanitized().emitters.map(\.t), [.reaperScythe, .ring])
        XCTAssertEqual(Pattern.reaper.map(\.bossCharacter), Array(repeating: .reaper, count: 5))
    }

    func testScytheArcHoldsThenFalls() {
        let out = shot(emitter(.reaperScythe), 0)
        let blades = out.filter { $0.script == Bullet.holdScript }
        XCTAssertEqual(blades.count, 29)
        XCTAssertEqual(out.filter { $0.homeLeft == 2.5 }.count, 2, "追う魂が2つ")
        XCTAssertTrue(blades.allSatisfy { $0.isDormant })
        // 弧は、ボスの下側(中心から半径150)
        for b in blades { XCTAssertEqual(hypot(b.x - 180, b.y - 148), 150, accuracy: 1e-6) }
        // 覚醒: 2重の弧で、隙間が2か所(各列で4つぶん)
        let aw = shot(emitter(.reaperScythe), 0, awakened: true).filter { $0.script == Bullet.holdScript }
        XCTAssertEqual(aw.count, 29 + 41 - 16)
        var one = blades[0]
        var t = 0.0
        while t < 0.7 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(one.y, blades[0].y, "止まっている間は動かない")
        for _ in 0..<240 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertGreaterThan(one.y, blades[0].y + 100, "そのあと落ちる")
    }

    func testSoulsOrbitThenChaseThePlayer() {
        let out = shot(emitter(.reaperSouls, c: 10), 0)
        XCTAssertEqual(out.count, 10)
        XCTAssertEqual(shot(emitter(.reaperSouls, c: 10), 0, awakened: true).count, 16)
        var s = out[0]
        var t = 0.0
        while t < 0.6 { _ = s.advance(dt: dt, width: 360, playerX: 180, playerY: 500); t += dt }
        XCTAssertEqual(hypot(s.x - 200, s.y - 76), 10 + 72 * 0.6, accuracy: 3, "半径が広がりながら回る")
        for _ in 0..<20 { _ = s.advance(dt: dt, width: 360, playerX: 180, playerY: 500) }
        XCTAssertEqual(s.script, 0)
        XCTAssertEqual(hypot(s.vx, s.vy), 84, accuracy: 1e-6)
        XCTAssertGreaterThan(s.homeLeft, 0, "ゆるく追尾する")
    }

    func testChainsWarnThenAppearAlongTheLine() {
        let out = shot(emitter(.reaperChains, c: 3), 0)
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.holdScript && $0.look == BulletLook.code(.chain) })
        XCTAssertEqual(out.count, shot(emitter(.reaperChains, c: 3), 0).count)
        XCTAssertGreaterThan(shot(emitter(.reaperChains), 0, awakened: true).count, out.count)
        XCTAssertTrue(out.allSatisfy { $0.dormantGlow }, "伸びる前は薄い予告線")
        var b = out[0]
        for _ in 0..<(120 * 21 / 60) { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertFalse(b.isDormant)
        var steps = 0
        while steps < 400 && b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) == .alive { steps += 1 }
        XCTAssertEqual(Double(steps) * dt, 1.0, accuracy: 0.1, "鎖は1秒で消える")
    }

    func testDeadlineHasOneGapEachRowAndAimedSouls() {
        let m = emitter(.reaperDeadline, c: 14, v: 1, r: 56, i: 1.15)
        for k in 0..<4 {
            let out = shot(m, k)
            let blades = out.filter { $0.script == 0 && $0.vy > 0 }.map(\.x).sorted()
            var gaps = 0
            for (a, b) in zip(blades, blades.dropFirst()) where b - a > 14.5 { gaps += 1 }
            XCTAssertEqual(gaps, 1, "row \(k)")
            XCTAssertEqual(out.filter { $0.script == Bullet.holdScript }.count, 3, "合間に魂 3つ")
        }
        XCTAssertEqual(shot(emitter(.reaperDeadline, c: 14, v: 1, r: 56, i: 0.85), 0, awakened: true).filter { $0.script == Bullet.holdScript }.count, 2)
    }

    func testRiverLanesAlternateAndHaveBreaks() {
        let m = emitter(.reaperRiver, v: 2.4, i: 0.15)
        var total = 0
        for k in 0..<7 {
            let out = shot(m, k)
            total += out.count
            for b in out { XCTAssertEqual(b.vx > 0, b.x < 0, "流れは交互の向き") }
        }
        XCTAssertEqual(total, 5 * 5, "7回で、各レーン5個(2個ぶん途切れる)")
        XCTAssertEqual(shot(m, 3, awakened: true).first?.script, Bullet.swayScript)
        let ems = Pattern.reaper.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.4, c: 14, v: 1.5, r: 0, k: 0) }
        let st = Stage(name: "r", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 8, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        var peak = 0
        for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets)
    }
}
