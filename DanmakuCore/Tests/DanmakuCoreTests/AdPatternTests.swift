import XCTest
@testable import DanmakuCore

final class AdPatternTests: XCTestCase {
    func testThereAre30AdPatternsAndTheyAreNotPaid() {
        XCTAssertEqual(Pattern.ad.count, 30)
        XCTAssertEqual(Set(Pattern.ad).count, 30)
        for p in Pattern.ad {
            XCTAssertTrue(p.isAd)
            XCTAssertFalse(p.isPaid, "\(p)")
            XCTAssertNotNil(p.recipe, "\(p)")
            XCTAssertNotNil(p.recipeDefaults, "\(p)")
        }
        // 並びを変えない(乱数や記録に、並びの番号を使うので、いまある19個の後ろに追加する)
        XCTAssertEqual(Pattern.allCases.prefix(19).last, .timed)
        XCTAssertEqual(Array(Pattern.allCases.dropFirst(19).prefix(30)), Pattern.ad)
        XCTAssertEqual(Pattern.allCases.last, .custom, "弾幕作成モードのパターンは、いちばん後ろ")
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
        // 同じ設定で出したときの弾の並び(位置と速度)が、30個ともすべて違う
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
        XCTAssertEqual(s.claimed, 30)
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
}
