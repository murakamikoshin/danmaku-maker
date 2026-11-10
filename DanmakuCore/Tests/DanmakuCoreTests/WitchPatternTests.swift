import XCTest
@testable import DanmakuCore

final class WitchPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 7, v: Double = 1.8, i: Double = 0.5) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: 0, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: 5)
        return out
    }
    private let dt = 1.0 / 120

    func testOwnership() {
        let em = [emitter(.witchAbyss), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 8).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 9).sanitized().emitters.map(\.t), [.witchAbyss, .ring])
        XCTAssertEqual(Pattern.witch.map(\.bossCharacter), Array(repeating: .witch, count: 5))
    }

    func testAbyssMakesDarknessAndWavyColumns() {
        let first = shot(emitter(.witchAbyss, c: 7), 0)
        XCTAssertEqual(first.filter { $0.script == Bullet.darkScript }.count, 1)
        XCTAssertTrue(first.filter { $0.script == Bullet.darkScript }.allSatisfy { $0.isDormant })
        XCTAssertEqual(first.filter { $0.script == Bullet.swayScript }.count, 7)
        XCTAssertEqual(shot(emitter(.witchAbyss, c: 7), 1).count, 7, "暗転の印は17回に1回")
        XCTAssertEqual(shot(emitter(.witchAbyss, c: 7), 0, awakened: true).filter { $0.script == Bullet.swayScript }.count, 9)
        XCTAssertEqual(shot(emitter(.witchAbyss, c: 7), 4, awakened: true).filter { BulletLook.kind(of: $0.look) == .bubble }.count, 1, "覚醒は泡も撃つ")
        // 暗転の印は 3.8 秒で消える
        var d = first.first { $0.script == Bullet.darkScript }!
        var steps = 0
        while steps < 1000 && d.advance(dt: dt, width: 360, playerX: 0, playerY: 0) == .alive { steps += 1 }
        XCTAssertEqual(Double(steps) * dt, 230.0 / 60, accuracy: 0.03)
        // 縦の列は、左右に波打つ
        var col = first.first { $0.script == Bullet.swayScript }!
        var xs: [Double] = []
        for _ in 0..<240 { _ = col.advance(dt: dt, width: 360, playerX: 0, playerY: 0); xs.append(col.x) }
        XCTAssertGreaterThan(xs.max()! - xs.min()!, 15)
    }

    func testBubblesGrowAndPopIntoPlanktonAtTheirPosition() {
        let out = shot(emitter(.witchBubbles, c: 4, v: 1.2), 0)
        let bubbles = out.filter { BulletLook.kind(of: $0.look) == .bubble }
        XCTAssertEqual(bubbles.count, 4)
        XCTAssertEqual(out.filter { $0.script == Bullet.holdScript }.count, 24, "弾けると6粒ずつ")
        XCTAssertEqual(shot(emitter(.witchBubbles, c: 4, v: 1.2), 0, awakened: true).filter { $0.script == Bullet.dragScript }.count, 8)
        var b = bubbles[0]
        let start = b.hitDistanceSquared
        var steps = 0
        while steps < 400 && b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) == .alive { steps += 1 }
        XCTAssertEqual(Double(steps) * dt, 1.5, accuracy: 0.03, "1.5秒で弾ける")
        XCTAssertGreaterThan(b.hitDistanceSquared, start * 2, "膨らんで、当たりも大きくなる")
        let frag = out.first { $0.script == Bullet.holdScript }!
        XCTAssertEqual(frag.x, b.x, accuracy: 1.0)
        XCTAssertEqual(frag.y, b.y, accuracy: 1.0)
    }

    func testTentaclesAndMaelstromBurstThenRest() {
        let t = emitter(.witchTentacles, c: 8, v: 2, i: 0.05)
        XCTAssertEqual(shot(t, 0).count, 8)
        XCTAssertEqual(shot(t, 30).count, 0, "30フレーム休む")
        XCTAssertEqual(shot(t, 40).count, 8)
        let mael = emitter(.witchMaelstrom, c: 5, v: 1.9, i: 0.05)
        XCTAssertEqual(shot(mael, 0).count, 5)
        XCTAssertEqual(shot(mael, 3).count, 0)
        XCTAssertEqual(shot(mael, 45).count, 0)
        XCTAssertEqual(shot(mael, 0, awakened: true).count, 7)
        // 渦: 曲がり続ける
        var b = shot(mael, 0)[0]
        let a0 = atan2(b.vy, b.vx)
        for _ in 0..<120 { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        var d = atan2(b.vy, b.vx) - a0
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        XCTAssertEqual(d, 0.72, accuracy: 0.02, "1秒で 0.72 ラジアン")
    }

    func testInkPopsAtMidScreenIntoRingAimedAtPlayer() {
        let out = shot(emitter(.witchInk, c: 3, v: 1, i: 0.85), 0, px: 180, py: 500)
        let ink = out.filter { BulletLook.kind(of: $0.look) == .ink }
        XCTAssertEqual(ink.count, 3)
        XCTAssertEqual(out.filter { $0.script == Bullet.holdScript && $0.u2 == 1 }.count, 24)
        XCTAssertEqual(shot(emitter(.witchInk, c: 3, v: 1, i: 0.85), 1).filter { BulletLook.kind(of: $0.look) == .ink }.count, 2)
        var b = ink[0]
        var steps = 0
        while steps < 1200 && b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) == .alive { steps += 1 }
        XCTAssertEqual(b.y, 300, accuracy: 2, "画面の半ば(y=300)で弾ける")
        // 粒の輪は、自機の方を向く(1つが必ず自機へ)
        var frags = out.filter { $0.script == Bullet.holdScript && $0.u2 == 1 && $0.x == ink[0].x }
        XCTAssertEqual(frags.count, 8)
        for i in frags.indices { for _ in 0..<(120 * 6) { _ = frags[i].advance(dt: dt, width: 360, playerX: 180, playerY: 500) } }
        let toPlayer = atan2(500 - 300.0, 180 - ink[0].x)
        XCTAssertTrue(frags.contains { abs(atan2($0.vy, $0.vx) - toPlayer) < 1e-9 })
    }

    func testFullStageRunsAndStaysCapped() {
        let ems = Pattern.witch.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.2, c: 8, v: 1.5, r: 0, k: 0) }
        let st = Stage(name: "w", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 9, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        var peak = 0
        for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets)
    }
}
