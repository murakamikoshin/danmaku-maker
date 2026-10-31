import XCTest
@testable import DanmakuCore

final class AdPatternTests: XCTestCase {
    func testThereAre31AdPatternsAndTheyAreNotPaid() {
        XCTAssertEqual(Pattern.ad.count, 31)
        XCTAssertEqual(Set(Pattern.ad).count, 31)
        XCTAssertEqual(Pattern.ad[4], .chargeBeam, "チャージビームは5番目に解放する")
        for p in Pattern.ad {
            XCTAssertTrue(p.isAd)
            XCTAssertFalse(p.isPaid, "\(p)")
            XCTAssertNotNil(p.recipe, "\(p)")
            XCTAssertNotNil(p.recipeDefaults, "\(p)")
        }
        // 並びを変えない(乱数や記録に、並びの番号を使うので、新しいものは後ろに足す)
        XCTAssertEqual(Pattern.allCases.prefix(19).last, .timed)
        XCTAssertEqual(Set(Pattern.allCases.dropFirst(19).prefix(30)), Set(Pattern.ad).subtracting([.chargeBeam]))
        XCTAssertEqual(Pattern.allCases.dropFirst(49).first, .custom, "弾幕作成モードのパターンの番号は変えない")
        XCTAssertEqual(Pattern.allCases.last, .chargeBeam, "あとから足したパターンは、custom より後ろ")
        XCTAssertFalse(Pattern.custom.isAd)
        XCTAssertFalse(Pattern.custom.isPaid)
    }

    func testEveryAdPatternFiresBulletsAndIsDeterministic() {
        for p in Pattern.ad {
            let d = p.recipeDefaults!
            let m = Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 1)
            func fire() -> [Bullet] {
                var rng = Mulberry32(seed: 7)
                var out: [Bullet] = []
                for k in 0..<5 { Emit.emit(m, shot: k, cx: 180, cy: 100, px: 180, py: 460, rng: &rng, into: &out) }
                return out
            }
            let a = fire()
            XCTAssertGreaterThanOrEqual(a.count, 5, "\(p)")
            XCTAssertLessThanOrEqual(a.count, DanmakuConfig.maxBullets)
            XCTAssertEqual(a, fire(), "\(p) は同じ入力で同じ弾になる")
            XCTAssertTrue(a.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.vx.isFinite && $0.vy.isFinite }, "\(p)")
        }
    }

    func testAdPatternsLookDifferentFromEachOther() {
        // 同じ設定で出したときの弾の並び(位置と速度)が、31個ともすべて違う
        var seen = Set<[Double]>()
        for p in Pattern.ad {
            let d = p.recipeDefaults!
            let m = Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 0)
            var rng = Mulberry32(seed: 3)
            var out: [Bullet] = []
            for k in 0..<3 { Emit.emit(m, shot: k, cx: 180, cy: 100, px: 120, py: 460, rng: &rng, into: &out) }
            let key = out.flatMap { [($0.x * 100).rounded(), ($0.vx * 100).rounded(), ($0.vy * 100).rounded(), Double($0.script), $0.turn, $0.accel] }
            XCTAssertTrue(seen.insert(key).inserted, "\(p) は他のパターンと同じ弾の並びになっている")
        }
    }

    func testOwnershipOfAdPatterns() {
        var own = Ownership()
        XCTAssertFalse(own.has(.twinRing))
        own.adPatterns = [.twinRing]
        XCTAssertTrue(own.has(.twinRing))
        XCTAssertFalse(own.has(.tripleRing))
        // 買うパターンのパックでは、広告のパターンは手に入らない。永久買い切りパックなら全部
        XCTAssertFalse(Ownership(productIDs: [Product.patternPack.id]).has(.tripleRing))
        XCTAssertTrue(Ownership(productIDs: [Product.lifetime.id]).has(.tripleRing))
    }

    func testDailyUnlockInOrderOnePerDay() {
        var s = AdPatternState()
        XCTAssertTrue(s.canClaim(today: 20000))
        XCTAssertEqual(s.next, Pattern.ad[0])
        XCTAssertEqual(s.claim(today: 20000), Pattern.ad[0])
        XCTAssertFalse(s.canClaim(today: 20000))
        XCTAssertNil(s.claim(today: 20000))
        XCTAssertNil(s.claim(today: 19990), "端末の日付を戻しても解放できない")
        XCTAssertEqual(s.claim(today: 20003), Pattern.ad[1], "休んだ日があっても、順番は飛ばない")
        XCTAssertEqual(s.unlocked, Set(Pattern.ad.prefix(2)))
        for d in 0..<40 { _ = s.claim(today: 20010 + d) }
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.next)
        XCTAssertFalse(s.canClaim(today: 30000))
        XCTAssertEqual(s.claimed, 31)
    }

    func testLifetimePackUnlocksEverything() {
        let l = Ownership(productIDs: [Product.lifetime.id])
        XCTAssertTrue(l.hasLifetime)
        for t in Theme.paid { for part in ThemePart.allCases { XCTAssertTrue(l.has(part, of: t)) } }
        for s in ShotType.allCases { XCTAssertTrue(l.has(s)) }
        for p in Pattern.allCases { XCTAssertTrue(l.has(p), "\(p)") }
        XCTAssertTrue(l.hasCustomImages)
        XCTAssertTrue(l.hasPatternMaker)
        XCTAssertFalse(l.canBuy(.lifetime))
        for p in Product.all where p != .lifetime { XCTAssertFalse(l.canBuy(p), "\(p)") }
        XCTAssertFalse(Ownership().hasLifetime)
        XCTAssertTrue(Ownership().canBuy(.lifetime))
        XCTAssertEqual(Product(id: Product.lifetime.id), .lifetime)
        XCTAssertEqual(Product(id: Product.patternMaker.id), .patternMaker)
    }

    // MARK: チャージビーム

    private func beamStage(lifeMode: LifeMode = .lives, lives: Int = 1) -> Stage {
        // 真上から真下に撃つビーム(自機は画面下の中央にいるので、自機狙いでも真下を向く)
        let m = Emitter(t: .chargeBeam, x: 0.5, y: 0.1, s: 0, e: 20, i: 10, c: 1, v: 2, r: 0, k: 0)
        var st = Stage(name: "beam", mode: .survive, durationSec: 5, emitters: [m])
        st.lifeMode = lifeMode
        st.lifeCount = lives
        return st
    }

    func testChargeBeamDoesNotHitWhileCharging() {
        var sim = Simulation(stage: beamStage())
        // READY の間と、ためている間(1秒)は、光線の上にいても当たらない
        let untilFire = Int(((DanmakuConfig.readySeconds + DanmakuConfig.beamCharge) / DanmakuConfig.step).rounded()) - 2
        for _ in 0..<untilFire { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.bullets.filter(\.isBeam).count, 1)
        XCTAssertFalse(sim.bullets[0].beamFiring)
        // 撃ち始めたら当たる
        for _ in 0..<10 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .hit)
    }

    func testChargeBeamCanBeDodgedSideways() {
        var sim = Simulation(stage: beamStage())
        // ためている間に、横へよける(光線の太さより外へ)
        for _ in 0..<Int(((DanmakuConfig.readySeconds + 0.5) / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        for _ in 0..<40 { sim.step(Move(dx: 4, dy: 0)) }   // 40 * 4 * 0.25 = 40px 右へ
        for _ in 0..<Int((1.5 / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        // 撃ち終わったビームは消える
        XCTAssertTrue(sim.bullets.filter(\.isBeam).isEmpty)
    }

    func testChargeBeamHitsOnlyOncePerBeam() {
        var sim = Simulation(stage: beamStage(lifeMode: .hp, lives: 5))
        for _ in 0..<Int(((DanmakuConfig.readySeconds + DanmakuConfig.beamCharge + DanmakuConfig.beamFire) / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.lifeLeft, 4, "光線の中にい続けても、1本のビームで減るのは1つだけ")
    }

    func testBeamHitGeometry() {
        var b = Bullet.beam(x: 100, y: 100, angle: Double.pi / 2, color: 0)   // 真下へ
        XCTAssertFalse(b.beamHits(100, 300), "ためている間は当たらない")
        b.age = DanmakuConfig.beamCharge
        XCTAssertTrue(b.beamHits(100, 300))
        XCTAssertTrue(b.beamHits(108, 400), "中心から8px以内は当たる")
        XCTAssertFalse(b.beamHits(110, 400), "中心から10px離れれば当たらない")
        XCTAssertFalse(b.beamHits(100, 80), "出る場所より後ろには伸びない")
        b.bounces = 0
        XCTAssertFalse(b.beamHits(100, 300), "一度当たったビームは、もう当たらない")
    }
}
