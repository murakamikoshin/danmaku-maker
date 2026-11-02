import XCTest
@testable import DanmakuCore

typealias AngelPattern = DanmakuCore.Pattern

final class FallenAngelPatternTests: XCTestCase {
    private func emitter(_ t: AngelPattern, c: Int = 10, v: Double = 2, r: Double = 0, i: Double = 1) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: r, k: 0)
    }

    func testAngelPatternsOnlyKeptForFallenAngel() {
        let em = [emitter(.angelTwin), emitter(.ring)]
        let other = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 2).sanitized()
        XCTAssertEqual(other.emitters.map(\.t), [.ring, .ring])
        let angel = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 5).sanitized()
        XCTAssertEqual(angel.emitters.map(\.t), [.angelTwin, .ring])
        let survive = Stage(name: "x", mode: .survive, durationSec: 20, emitters: em).sanitized()
        XCTAssertEqual(survive.emitters.map(\.t), [.ring, .ring])
    }

    func testPatternOrderAppended() {
        // 並びは変えない: 新しい技は、いちばん後ろ
        let all = AngelPattern.allCases
        XCTAssertEqual(Array(all.suffix(5)), [.angelTwin, .angelFeather, .angelHalo, .angelCross, .angelParadise])
        XCTAssertEqual(all[all.count - 6], .swirl)
    }

    func testParadiseGapStaysWithin90DegreesOfPrevious() {
        for salt in [UInt32(1), 99, 123456789, 0xDEADBEEF] {
            var prev = Emit.paradiseGap(shot: 0, salt: salt)
            for k in 1..<60 {
                let g = Emit.paradiseGap(shot: k, salt: salt)
                var d = abs(g - prev)
                if d > Double.pi { d = 2 * Double.pi - d }
                XCTAssertLessThanOrEqual(d, Double.pi / 2 + 1e-9, "salt \(salt) k \(k)")
                prev = g
            }
        }
    }

    func testParadiseLeavesExactlyOneGap() {
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(emitter(.angelParadise, c: 23, v: 1.05, r: 29), shot: 3, cx: 180, cy: 128, px: 180, py: 460, rng: &rng, into: &out, salt: 42)
        XCTAssertGreaterThan(out.count, 30)
        XCTAssertLessThan(out.count, 46)
        // 弾の向き(自機から見た角度)を並べて、いちばん大きく空いている所が抜け道
        let angs = out.map { atan2($0.y - 460, $0.x - 180) }.sorted()
        var gaps: [Double] = []
        for j in 0..<angs.count { gaps.append((j + 1 < angs.count ? angs[j + 1] : angs[0] + 2 * Double.pi) - angs[j]) }
        gaps.sort()
        XCTAssertGreaterThan(gaps.last!, 0.5)    // 抜け道(約0.5rad + 弾の間隔)
        XCTAssertLessThan(gaps.last!, 0.75)
        XCTAssertLessThan(gaps[gaps.count - 2], 0.15)   // ほかは、弾の間隔(2π/46)だけ
        XCTAssertTrue(out.allSatisfy { $0.isRing })
    }

    func testRingClosesAndDisappears() {
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(emitter(.angelParadise, c: 10, v: 1.05), shot: 0, cx: 180, cy: 128, px: 180, py: 300, rng: &rng, into: &out, salt: 7)
        var b = out[0]
        let r0 = hypot(b.x - 180, b.y - 300)
        XCTAssertEqual(r0, 240, accuracy: 1e-6)
        var steps = 0
        while b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 300) == .alive { steps += 1; if steps > 1000 { break } }
        // 半径240を 63px/秒 で縮める → 約3.8秒で消える
        XCTAssertEqual(Double(steps) * DanmakuConfig.step, (240 - 4) / 63, accuracy: 0.05)
    }

    func testFeatherDecelerateThenFallWithSway() {
        var rng = Mulberry32(seed: 5)
        var out: [Bullet] = []
        Emit.emit(emitter(.angelFeather, c: 3, v: 3.8), shot: 0, cx: 180, cy: 128, px: 180, py: 460, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 6)
        var b = out[0]
        let v0 = hypot(b.vx, b.vy)
        for _ in 0..<62 { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 0, playerY: 0) }
        XCTAssertLessThan(hypot(b.vx, b.vy), v0 * 0.15)
        for _ in 0..<240 { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 0, playerY: 0) }
        XCTAssertGreaterThan(b.vy, 12)         // 落ち始めて、加速している
        XCTAssertLessThanOrEqual(b.vy, 138)    // 上限
        XCTAssertLessThanOrEqual(abs(b.vx), 54.0001)
    }

    func testHaloShardsDiveAtPlayerOneByOne() {
        var rng = Mulberry32(seed: 5)
        var out: [Bullet] = []
        Emit.emit(emitter(.angelHalo, c: 22, v: 4), shot: 0, cx: 180, cy: 128, px: 180, py: 460, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 22)
        var shards = out
        var fired: [Int] = []
        for step in 0..<400 {
            for i in 0..<shards.count {
                let was = shards[i].script
                _ = shards[i].advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460)
                if was == Bullet.shardScript && shards[i].script == 0 { fired.append(step) }
            }
        }
        XCTAssertEqual(fired.count, 22)
        XCTAssertEqual(fired, fired.sorted())
        // 最初の破片は 64/60 秒、最後は (64+42)/60 秒
        XCTAssertEqual(Double(fired.first!) * DanmakuConfig.step, 64.0 / 60, accuracy: 0.03)
        XCTAssertEqual(Double(fired.last!) * DanmakuConfig.step, 106.0 / 60, accuracy: 0.03)
        XCTAssertGreaterThan(shards[0].vy, 0)   // 下にいる自機に向かう
    }

    func testCrossBeamsHaveLengthAndRotate() {
        var rng = Mulberry32(seed: 5)
        var out: [Bullet] = []
        Emit.emit(emitter(.angelCross), shot: 0, cx: 180, cy: 128, px: 180, py: 460, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 4)
        XCTAssertTrue(out.allSatisfy { $0.isBeam })
        // 長い腕は自機の方を向く(下)。短い腕(長さ90)は逆の向き
        let long = out[0], short = out[1]
        XCTAssertGreaterThan(long.vy, 0.9)
        XCTAssertLessThan(short.vy, -0.9)
        var b = short; b.age = 1.2   // 撃っている間
        // 長さ90の腕: 胸(180,100)から上へ 90 の先は当たる、150 の先は当たらない
        XCTAssertTrue(b.beamHits(180, 100 - 60))
        XCTAssertFalse(b.beamHits(180, 100 - 150))
        // 十字の腕は長さ無制限ではない: 長い腕(760)は画面の外まで届く
        var l = long; l.age = 1.2
        XCTAssertTrue(l.beamHits(180, 500))
    }

    func testAwakenedTwinFiresMoreArms() {
        var rng = Mulberry32(seed: 1)
        var a: [Bullet] = [], b: [Bullet] = []
        Emit.emit(emitter(.angelTwin, c: 4), shot: 0, cx: 180, cy: 128, px: 0, py: 0, rng: &rng, into: &a)
        Emit.emit(emitter(.angelTwin, c: 4), shot: 0, cx: 180, cy: 128, px: 0, py: 0, rng: &rng, into: &b, awakened: true)
        XCTAssertEqual(a.count, 8)
        XCTAssertEqual(b.count, 12)
    }

    func testFullStageRunsWithAllAngelPatterns() {
        let ems = AngelPattern.fallenAngel.map { emitter($0, c: 6, v: 2, i: 0.6) }
        let st = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 5, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        sim.invincible = true
        var maxBullets = 0
        while sim.outcome == .playing && sim.tick < 120 * 40 {
            sim.step(.zero)
            maxBullets = max(maxBullets, sim.bullets.count)
        }
        XCTAssertGreaterThan(maxBullets, 50)
        XCTAssertLessThanOrEqual(maxBullets, DanmakuConfig.maxBullets)
    }
}

final class BossProductTests: XCTestCase {
    func testBossProductIDRoundTripAndPrice() {
        let p = Product.boss(.fallenAngel)
        XCTAssertEqual(p.id, "com.koshin.danmakumaker.boss.fallen_angel")
        XCTAssertEqual(Product(id: p.id), p)
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.boss.unknown"))
        XCTAssertTrue(Product.all.contains(p))
        XCTAssertEqual(Set(Product.all.map(\.id)).count, Product.all.count)
    }

    func testOwnershipAndLifetime() {
        XCTAssertFalse(Ownership().has(.fallenAngel))
        XCTAssertTrue(Ownership().canBuy(.boss(.fallenAngel)))
        let own = Ownership(owned: [.boss(.fallenAngel)])
        XCTAssertTrue(own.has(.fallenAngel))
        XCTAssertFalse(own.canBuy(.boss(.fallenAngel)))
        let life = Ownership(owned: [.lifetime])
        XCTAssertTrue(life.has(.fallenAngel))
        XCTAssertFalse(life.canBuy(.boss(.fallenAngel)))
        XCTAssertEqual(Ownership(productIDs: ["com.koshin.danmakumaker.boss.fallen_angel"]).has(.fallenAngel), true)
    }

    func testUsedBosses() {
        let em = [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 60, i: 1, c: 8, v: 2, r: 0, k: 0)]
        XCTAssertEqual(Stage(name: "a", mode: .boss, durationSec: 60, bossHp: 200, emitters: em, bossLook: 5).sanitized().usedBosses, [.fallenAngel])
        XCTAssertEqual(Stage(name: "a", mode: .boss, durationSec: 60, bossHp: 200, emitters: em, bossLook: 2).sanitized().usedBosses, [])
        XCTAssertEqual(Stage(name: "a", mode: .survive, durationSec: 20, emitters: em).sanitized().usedBosses, [])
        let seq = Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: [
            Wave(kind: .boss, durationSec: 30, bossHp: 100, bossMove: 1, emitters: em),
            Wave(kind: .boss, durationSec: 30, bossHp: 100, bossMove: 0, emitters: em, bossLook: 5)]).sanitized()
        XCTAssertEqual(seq.usedBosses, [.fallenAngel])
    }
}
