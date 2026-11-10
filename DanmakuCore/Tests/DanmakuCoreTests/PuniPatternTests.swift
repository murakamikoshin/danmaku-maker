import XCTest
@testable import DanmakuCore

final class PuniPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 1, v: Double = 1) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.05, c: c, v: v, r: 0, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: 5)
        return out
    }
    private let dt = 1.0 / 120

    func testOwnershipAndInviteLimited() {
        let em = [emitter(.puniPoyon), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 10).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 11).sanitized().emitters.map(\.t), [.puniPoyon, .ring])
        XCTAssertEqual(Pattern.puni.map(\.bossCharacter), Array(repeating: .puni, count: 5))
        // 招待限定: 買えず、チケットでも手に入らない。商品にならない
        XCTAssertTrue(BossCharacter.puni.inviteLimited)
        XCTAssertFalse(BossCharacter.puni.purchasable)
        XCTAssertFalse(BossCharacter.puni.ticketEligible)
        XCTAssertFalse(Product.all.contains { $0.id.hasSuffix("boss.puni") })
        XCTAssertNil(Product(id: Product.idPrefix + "boss.puni").flatMap { Product.all.contains($0) ? $0 : nil })
        // 他のボスは、これまでどおり
        for b in BossCharacter.allCases where b != .puni { XCTAssertTrue(b.purchasable && b.ticketEligible && !b.inviteLimited) }
    }

    func testNormalFormJustDropsPuniBullets() {
        let poyon = emitter(.puniPoyon, v: 1)
        XCTAssertEqual(shot(poyon, 0).count, 1)
        XCTAssertEqual(shot(poyon, 1).count, 0)
        XCTAssertEqual(shot(poyon, 20).count, 1, "1秒に1発")
        XCTAssertEqual(shot(poyon, 120).count, 0, "6発で休む")
        XCTAssertEqual(shot(poyon, 0)[0].look, BulletLook.code(.jelly))
        XCTAssertEqual(shot(poyon, 0)[0].vx, 0, accuracy: 1e-9)
        XCTAssertEqual(shot(emitter(.puniShower, v: 1.2), 0).count, 3)
        XCTAssertEqual(shot(emitter(.puniKorokoro, v: 2), 0).count, 2)
        XCTAssertEqual(shot(emitter(.puniKorokoro, v: 2), 0)[0].gravity, 180)
        XCTAssertEqual(shot(emitter(.puniPurupuru, v: 1), 0).count, 8)
        let big = shot(emitter(.puniOsusowake, v: 1), 0)
        XCTAssertEqual(big.filter { $0.radius == 4 }.count, 1, "大きなぷに弾")
        XCTAssertEqual(big.filter { $0.script == Bullet.holdScript && $0.radius == 0 }.count, 3, "半ばで3つに分かれる")
    }

    func testAwakenedFormIsADifferentSetOfMoves() {
        // 凝視: 22個の目が順番に狙い撃つ。2周
        let gaze = emitter(.puniPoyon)
        var xs = Set<Double>()
        var shots = 0
        for k in 0..<73 {
            let out = shot(gaze, k, awakened: true)
            if !out.isEmpty { shots += 1; xs.insert((out[0].x * 1000).rounded()) }
            XCTAssertTrue(out.allSatisfy { BulletLook.kind(of: $0.look) == .eye })
        }
        XCTAssertEqual(shots, 44)
        XCTAssertEqual(xs.count, 22, "22個の目")
        XCTAssertEqual(shot(emitter(.puniShower, v: 1.2), 0, awakened: true).count, 12)
        XCTAssertTrue(shot(emitter(.puniShower, v: 1.2), 0, awakened: true).allSatisfy { $0.script == Bullet.curveScript && BulletLook.kind(of: $0.look) == .goo })
        XCTAssertEqual(shot(emitter(.puniKorokoro, v: 2), 0, awakened: true).count, 24)
        XCTAssertTrue(shot(emitter(.puniKorokoro, v: 2), 8, awakened: true).allSatisfy { BulletLook.kind(of: $0.look) == .tooth })
        XCTAssertEqual(shot(emitter(.puniKorokoro, v: 2), 0, awakened: true)[0].u0, -shot(emitter(.puniKorokoro, v: 2), 8, awakened: true)[0].u0, "1輪ごとに逆回り")
        let lasers = shot(emitter(.puniPurupuru, v: 1), 0, awakened: true)
        XCTAssertEqual(lasers.filter { $0.isBeam }.count, 4)
        XCTAssertEqual(Set(lasers.filter { $0.isBeam }.map(\.color)).count, 2, "二色")
        XCTAssertEqual(lasers.filter { $0.script == Bullet.holdScript }.count, 10)
    }

    func testPhaseShiftWarpsWithWarningAndNeverLandsTooClose() {
        let ring = shot(emitter(.puniOsusowake), 0, awakened: true)
        XCTAssertEqual(ring.count, 16)
        let warpers = ring.filter { $0.script == Bullet.warpScript }
        // 乱数で、一部の弾だけが瞬間移動する
        var total = 0
        for k in stride(from: 0, to: 104, by: 13) { total += shot(emitter(.puniOsusowake), k, awakened: true).filter { $0.script == Bullet.warpScript }.count }
        XCTAssertGreaterThan(total, 5); XCTAssertLessThan(total, 60)
        _ = warpers
        guard var b = (0..<8).lazy.flatMap({ self.shot(self.emitter(.puniOsusowake), $0 * 13, awakened: true) }).first(where: { $0.script == Bullet.warpScript }) else { return XCTFail("瞬間移動する弾がない") }
        let player = (x: 120.0, y: 400.0)
        var marked = false, jumped = false
        var t = 0.0
        while t < b.fuse + 0.1 {
            let before = (b.x, b.y)
            _ = b.advance(dt: dt, width: 360, playerX: player.x, playerY: player.y)
            if b.homeLeft == 1 && !marked {
                marked = true
                XCTAssertEqual(b.fuse - b.age, 0.5, accuracy: 0.02, "30フレーム前に行き先が決まる")
                let d = hypot(b.u2 - player.x, b.u3 - player.y)
                XCTAssertGreaterThanOrEqual(d, 40, "自機から40px以内には出ない")
            }
            if hypot(b.x - before.0, b.y - before.1) > 20 { jumped = true }
            t += dt
        }
        XCTAssertTrue(marked && jumped)
    }

    func testWholeStageRunsInBothFormsAndStaysCapped() {
        for aw in [nil, 2] as [Int?] {
            let ems = Pattern.puni.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.05, c: 1, v: 1.5, r: 0, k: 0) }
            let st = Stage(name: "p", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 11, awaken: aw).sanitized()
            var sim = Simulation(stage: st)
            var peak = 0
            for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
            XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets, "aw=\(aw ?? 0)")
        }
    }
}
