import XCTest
@testable import DanmakuCore

final class MechPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 6, v: Double = 2, i: Double = 1) -> Emitter {
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
        let em = [emitter(.mechGrid), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 9).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 10).sanitized().emitters.map(\.t), [.mechGrid, .ring])
        XCTAssertEqual(Pattern.mech.map(\.bossCharacter), Array(repeating: .mech, count: 5))
    }

    func testLockOnBeamTracksThenFixesAndIsThick() {
        let out = shot(emitter(.mechLockOn, c: 2, v: 2.6, i: 2), 0, px: 100, py: 500)
        let beam = out.first { $0.isBeam }!
        XCTAssertEqual(beam.radius, 13)
        XCTAssertEqual(out.filter { $0.script == Bullet.missileScript }.count, 2)
        XCTAssertEqual(shot(emitter(.mechLockOn, c: 2, v: 2.6, i: 2), 0, awakened: true).filter { $0.script == Bullet.missileScript }.count, 4)
        XCTAssertEqual(shot(emitter(.mechLockOn, c: 2, v: 2.6, i: 2), 0, awakened: true).first { $0.isBeam }!.radius, 17)
        // 追っている間は自機のほうへ向きが変わり、固定されたあとは変わらない
        var b = beam
        let target = { (p: (Double, Double)) in atan2(p.1 - b.y, p.0 - b.x) }
        var t = 0.0
        while t < 0.5 { _ = b.advance(dt: dt, width: 360, playerX: 300, playerY: 300); t += dt }
        XCTAssertEqual(atan2(b.vy, b.vx), target((300, 300)), accuracy: 0.05, "追う")
        let locked = atan2(b.vy, b.vx)
        while t < 0.9 { _ = b.advance(dt: dt, width: 360, playerX: 20, playerY: 200); t += dt }
        let lockedAngle = atan2(b.vy, b.vx)
        for _ in 0..<12 { _ = b.advance(dt: dt, width: 360, playerX: 20, playerY: 200) }
        XCTAssertEqual(atan2(b.vy, b.vx), lockedAngle, accuracy: 1e-12, "固定")
        XCTAssertNotEqual(locked, lockedAngle)
        // ビームの太さ: 中心から 12px は当たり、14px は当たらない(撃っている間)
        var fire = beam; fire.age = 1.1
        let nx = -fire.vy, ny = fire.vx
        XCTAssertTrue(fire.beamHits(fire.x + fire.vx * 100 + nx * 12, fire.y + fire.vy * 100 + ny * 12))
        XCTAssertFalse(fire.beamHits(fire.x + fire.vx * 100 + nx * 14, fire.y + fire.vy * 100 + ny * 14))
        // ミサイルは、ビームが出るまで(1秒)待機
        var mis = out.first { $0.script == Bullet.missileScript }!
        XCTAssertTrue(mis.isDormant)
        for _ in 0..<119 { _ = mis.advance(dt: dt, width: 360, playerX: 180, playerY: 500) }
        XCTAssertTrue(mis.isDormant)
        for _ in 0..<2 { _ = mis.advance(dt: dt, width: 360, playerX: 180, playerY: 500) }
        XCTAssertFalse(mis.isDormant)
    }

    func testMicroMissilesSlowTurnAndSpeedUp() {
        let out = shot(emitter(.mechMissiles, c: 12, v: 3, i: 2), 0)
        XCTAssertEqual(out.count, 12)
        XCTAssertEqual(shot(emitter(.mechMissiles, c: 12, v: 3, i: 2), 0, awakened: true).count, 20)
        // 発射は、順番に 5 フレームずつ
        XCTAssertEqual(out.map(\.fuse), (0..<12).map { Double($0) * 5 / 60 })
        var m = out[0]
        var maxSpeed = 0.0
        for _ in 0..<(120 * 3) { _ = m.advance(dt: dt, width: 360, playerX: 180, playerY: 500); maxSpeed = max(maxSpeed, hypot(m.vx, m.vy)) }
        XCTAssertEqual(maxSpeed, 204, accuracy: 0.5, "最高 3.4 × 60")
        XCTAssertGreaterThan(m.vy, 0, "自機のいる下へ向かう")
    }

    func testGatlingSweepsAndGridRotatesWithHexAimed() {
        let g = emitter(.mechGatling, c: 2, v: 3.4, i: 0.05)
        XCTAssertEqual(shot(g, 0).count, 2)
        XCTAssertEqual(shot(g, 0, awakened: true).count, 4)
        XCTAssertEqual(shot(g, 30).count, 0)
        let first = shot(g, 0), last = shot(g, 29)
        XCTAssertLessThan(atan2(first[0].vy, first[0].vx), atan2(last[0].vy, last[0].vx), "左の砲は首を振っていく")
        let grid = emitter(.mechGrid, c: 6, v: 2.4, i: 0.4)
        let a = shot(grid, 0), b = shot(grid, 5), c = shot(grid, 1)
        XCTAssertEqual(a.filter { $0.isBeam }.count, 6)
        XCTAssertEqual(a.filter { $0.isBeam }.first!.radius, 5)
        XCTAssertEqual(c.filter { $0.isBeam }.count, 0)
        XCTAssertEqual(c.count, 1, "光子弾の自機狙いだけ")
        XCTAssertEqual(a.first { $0.isBeam }!.turn, -b.first { $0.isBeam }!.turn, "1回ごとに逆向き")
        XCTAssertEqual(shot(grid, 0, awakened: true).filter { $0.isBeam }.count, 8)
    }

    func testOverloadRingsHaveOneGapNearPlayerAndAccelerate() {
        let m = emitter(.mechOverload, c: 24, v: 1.2, i: 0.3)
        for k in 0..<5 {
            let ring = shot(m, k)
            XCTAssertTrue(ring.count < 24 && ring.count >= 24 - 4, "抜け道は弾3つぶん(\(ring.count))")
        }
        XCTAssertEqual(shot(m, 5).count, 0, "5輪撃って休む")
        XCTAssertEqual(shot(m, 0, awakened: true).count < 32 && shot(m, 0, awakened: true).count >= 28, true)
        var b = shot(m, 0)[0]
        for _ in 0..<(120 * 2) { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertEqual(hypot(b.vx, b.vy), 210, accuracy: 0.5, "加速して 3.5 × 60 で頭打ち")
        let ems = Pattern.mech.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.4, c: 10, v: 2, r: 0, k: 0) }
        let st = Stage(name: "m", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 10, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        var peak = 0
        for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets)
    }
}
