import XCTest
@testable import DanmakuCore

/// 1.4.2: 弾幕パック3・段階なし/2段階・左右からの弾の高さ・弾の形「＝」
final class Pack3Tests: XCTestCase {
    private func speed(_ b: Bullet) -> Double { (b.vx * b.vx + b.vy * b.vy).squareRoot() }
    private func shoot(_ m: Emitter, k: Int = 0, px: Double = 180, py: Double = 460) -> [Bullet] {
        var rng = Mulberry32(seed: 3)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 100, px: px, py: py, rng: &rng, into: &out)
        return out
    }
    private func make(_ t: DanmakuCore.Pattern) -> Emitter {
        let d = t.pack3Defaults!
        return Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 1)
    }

    func testEveryPack3PatternFiresAndIsPaid() {
        XCTAssertEqual(DanmakuCore.Pattern.pack3.count, 11)
        for p in DanmakuCore.Pattern.pack3 {
            XCTAssertTrue(p.isPaid && p.isPack3 && !p.isPack2 && !p.isAd, "\(p)")
            XCTAssertNil(p.bossCharacter)
            XCTAssertFalse(shoot(make(p)).isEmpty, "\(p) が弾を出さない")
        }
    }

    func testOwnershipOfPack3() {
        XCTAssertFalse(Ownership().has(.radialLaser))
        XCTAssertTrue(Ownership(owned: [.patternPack3]).has(.blinkShot))
        XCTAssertTrue(Ownership(owned: [.pattern(.needle)]).has(.needle))
        XCTAssertFalse(Ownership(owned: [.pattern(.needle)]).has(.dashShot))
        // パック1・2では使えない(中身が別)。永久買い切りは使える
        XCTAssertFalse(Ownership(owned: [.patternPack, .patternPack2]).has(.lightning))
        XCTAssertTrue(Ownership(owned: [.lifetime]).has(.lightning))
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.patternpack3"), .patternPack3)
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.pattern.radialLaser"), .pattern(.radialLaser))
        XCTAssertEqual(Product.pattern(.radialLaser).yen, 300)
        XCTAssertEqual(Product.pattern(.needle).yen, 100)
        XCTAssertTrue(Product.all.contains(.patternPack3))
    }

    func testDashShotSpeedsUpFourTimesAfterPointNineSeconds() {
        var b = shoot(make(.dashShot))[0]
        let v0 = speed(b)
        for _ in 0..<Int(0.85 * 120) { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460) }
        XCTAssertEqual(speed(b), v0, accuracy: 1e-9)
        for _ in 0..<12 { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460) }
        XCTAssertEqual(speed(b), v0 * 4, accuracy: 1e-6)
    }

    func testBounceBallBouncesOnceOffTheFloor() {
        var b = shoot(make(.bounceBall))[0]
        var bounced = 0
        var lastVy = b.vy
        for _ in 0..<(120 * 8) {
            _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460)
            if lastVy > 0 && b.vy < 0 { bounced += 1 }
            lastVy = b.vy
        }
        XCTAssertEqual(bounced, 1)
        XCTAssertGreaterThan(b.y, DanmakuConfig.height)   // 2回目は、はねずに落ちていく
    }

    func testBlinkShotJumpsAhead() {
        var b = shoot(make(.blinkShot))[0]
        let sp = speed(b)
        let x0 = b.x, y0 = b.y
        for _ in 0..<61 { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460) }
        // 0.5 秒進んだぶん + 48px の瞬間移動
        let dx: Double = b.x - x0, dy: Double = b.y - y0
        let moved: Double = (dx * dx + dy * dy).squareRoot()
        let expected: Double = sp * 61 * DanmakuConfig.step + 48
        XCTAssertEqual(moved, expected, accuracy: 0.01)
    }

    func testWhirlwindMirrorsAroundTheCenter() {
        var m = make(.whirlwind)
        let plain = shoot(m, px: 100)
        m.mir = 1
        let mirrored = shoot(m, px: 260)
        XCTAssertEqual(plain.count, mirrored.count)
        for (a, b) in zip(plain, mirrored) {
            var p = a, q = b
            for _ in 0..<60 {
                _ = p.advance(dt: DanmakuConfig.step, width: 360, playerX: 100, playerY: 460)
                _ = q.advance(dt: DanmakuConfig.step, width: 360, playerX: 260, playerY: 460)
            }
            XCTAssertEqual(p.x, 360 - q.x, accuracy: 1e-6)
            XCTAssertEqual(p.y, q.y, accuracy: 1e-6)
        }
    }

    func testImplodeSpawnsOutsideAndIsNotCulledImmediately() {
        let st = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [make(.implode)]).sanitized()
        var sim = Simulation(stage: st)
        while sim.t < 0.05 { sim.step(Move.zero) }
        XCTAssertEqual(sim.bullets.count, make(.implode).c)
    }

    func testPositionlessAndRotation() {
        XCTAssertTrue(Emitter(t: .lightning).isPositionless)
        XCTAssertTrue(Emitter(t: .pincer).isPositionless)
        XCTAssertFalse(Emitter(t: .pincer).canRotate)
        XCTAssertTrue(Emitter(t: .radialLaser).canRotate)
        XCTAssertFalse(Simulation.hasMook(Emitter(t: .lightning), boss: false))
    }

    func testSideHeightRange() {
        var m = Emitter(t: .sideL, x: 0.5, y: 0.2, s: 0, e: 20, i: 1, c: 30, v: 2, r: 0, k: 0)
        XCTAssertLessThanOrEqual(shoot(m).map(\.y).max()!, DanmakuConfig.height * 0.78)
        m.yr = 2
        let lower = shoot(m).map(\.y)
        XCTAssertGreaterThanOrEqual(lower.min()!, DanmakuConfig.height * 0.5)
        XCTAssertGreaterThan(lower.max()!, DanmakuConfig.height * 0.78)
        // 左右から以外では保存しない。範囲外も捨てる
        XCTAssertNil(Emitter.sanitizedHeightRange(1, pattern: .ring))
        XCTAssertNil(Emitter.sanitizedHeightRange(3, pattern: .sideR))
        let st = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [m]).sanitized()
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.emitters[0].yr, 2)
    }

    func testEqualsShapeIsSavedAndVisualOnly() {
        var m = Emitter(t: .ring)
        m.sh = 3
        let st = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [m]).sanitized()
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.emitters[0].sh, 3)
        var b = Bullet(x: 0, y: 0, vx: 1, vy: 0, color: 0)
        b.look = 3
        XCTAssertTrue(b.drawsAsBar)
        XCTAssertEqual(b.hitDistanceSquared, DanmakuConfig.hitRadiusSquared)
        XCTAssertNil(Emitter.sanitizedShape(4))
    }

    func testBossWithOnePhaseNeverChangesPhase() {
        var st = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 100, bossMove: 0,
                       emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.5, c: 8, v: 2, r: 0, k: 0, ph: 2)])
        st.phases = 1
        st.awaken = 2
        let s = st.sanitized()
        XCTAssertEqual(s.phases, 1)
        XCTAssertEqual(s.emitters[0].ph, 0)   // 段階が1つなら、撃つ段階は「全部」
        XCTAssertNil(s.awaken)                // 覚醒する段階がない
        var sim = Simulation(stage: s)
        var phases = Set<Int>()
        while sim.outcome == .playing && sim.tick < 120 * 70 { sim.step(Move.zero); phases.insert(sim.phase) }
        XCTAssertEqual(phases, [1])
        XCTAssertEqual(sim.phaseCount, 1)
    }

    func testBossWithTwoPhasesSplitsHpInHalf() {
        var st = Stage(name: "b", mode: .damage, durationSec: 30, bossMove: 0, emitters: [Emitter(t: .ring, ph: 2)])
        st.phases = 2
        var sim = Simulation(stage: st.sanitized())
        var seen: [Int] = []
        while sim.outcome == .playing && sim.tick < 120 * 40 {
            sim.step(Move.zero)
            if seen.last != sim.phase { seen.append(sim.phase) }
        }
        XCTAssertEqual(seen, [1, 2])
    }
}
