import XCTest
@testable import DanmakuCore

final class ShopTests: XCTestCase {
    private func boss(hp: Int = 600) -> Stage {
        Stage(name: "t", mode: .boss, durationSec: 60, bossHp: hp, bossMove: 0, emitters: [])
    }

    /// 動かさずに撃ち続けて、ボスを倒すまでにかかるステップ数
    private func stepsToKill(_ type: ShotType) -> Int {
        var sim = Simulation(stage: boss(), shotType: type)
        while sim.outcome == .playing && sim.tick < 120 * 80 { sim.step(.zero) }
        return sim.outcome == .cleared ? sim.tick : -1
    }

    func testAllShotTypesHaveSameDamagePerSecond() {
        let base = ShotType.standard.damagePerSecond
        for t in ShotType.allCases { XCTAssertEqual(t.damagePerSecond, base, accuracy: 0.01, "\(t)") }
    }

    func testStandardShotMatchesLegacyBehaviour() {
        var a = Simulation(stage: boss())
        var b = Simulation(stage: boss(), shotType: .standard)
        for _ in 0..<2000 { a.step(.zero); b.step(.zero) }
        XCTAssertEqual(a.hp, b.hp)
        XCTAssertEqual(a.result, b.result)
    }

    func testEveryShotTypeCanKillBossStandingStill() {
        for t in ShotType.allCases {
            let n = stepsToKill(t)
            XCTAssertGreaterThan(n, 0, "\(t) cannot clear")
        }
    }

    func testClearTimesAreComparable() {
        let std = Double(stepsToKill(.standard))
        for t in ShotType.allCases {
            let ratio = Double(stepsToKill(t)) / std
            XCTAssertEqual(ratio, 1, accuracy: 0.15, "\(t) differs too much from standard: \(ratio)")
        }
    }

    func testSpreadShotsFanOut() {
        var sim = Simulation(stage: boss(), shotType: .spread)
        for _ in 0..<(120 * 4) where sim.tick < 120 * 3 + 20 { sim.step(.zero) }
        let xs = sim.shots.map(\.x)
        XCTAssertGreaterThan((xs.max() ?? 0) - (xs.min() ?? 0), 8)
    }

    func testRewardThemesUnlockByPostCountAndCannotBeBought() {
        XCTAssertEqual(Theme.reward.map(\.unlockPosts), [1, 3, 10])
        XCTAssertFalse(Theme.paid.contains(.gold))
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.gold.set"))
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.rainbow.bullets"))
        var o = Ownership()
        for t in Theme.reward { for p in ThemePart.allCases { XCTAssertFalse(o.has(p, of: t)) } }
        o.posts = 1
        XCTAssertTrue(o.hasUnlocked(.gold)); XCTAssertFalse(o.hasUnlocked(.neon))
        for p in ThemePart.allCases { XCTAssertTrue(o.has(p, of: .gold)) }
        o.posts = 3
        XCTAssertTrue(o.hasUnlocked(.neon)); XCTAssertFalse(o.hasUnlocked(.rainbow))
        o.posts = 10
        XCTAssertTrue(o.hasUnlocked(.rainbow))
        XCTAssertFalse(Ownership(owned: Set(Product.all)).hasUnlocked(.gold), "買っても、投稿数で解放されるものは解放されない")
        XCTAssertEqual(Product.all.count, 45)   // 弾幕パック2で12個、ボス(堕天使・九尾の巫女・雪の女王・死神)で4個増えた
    }

    func testProductIDRoundTrip() {
        XCTAssertEqual(Product.all.count, 45)
        XCTAssertEqual(Set(Product.all.map(\.id)).count, 45)
        for p in Product.all { XCTAssertEqual(Product(id: p.id), p) }
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.removeads"))
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.classic.set"))
        XCTAssertNil(Product(id: "com.koshin.danmakumaker.shot.standard"))
        XCTAssertNil(Product(id: "other.sakura.set"))
    }

    func testSetGrantsAllPartsOfThatThemeOnly() {
        let own = Ownership(productIDs: [Product.set(.sakura).id])
        for p in ThemePart.allCases {
            XCTAssertTrue(own.has(p, of: .sakura))
            XCTAssertFalse(own.has(p, of: .ocean))
        }
        XCTAssertFalse(own.canBuy(.set(.sakura)))
        XCTAssertFalse(own.canBuy(.part(.sakura, .ship)))
        XCTAssertTrue(own.canBuy(.set(.ocean)))
    }

    func testPartsOnlyGrantThatPart() {
        let own = Ownership(productIDs: [Product.part(.ocean, .bullets).id, "garbage"])
        XCTAssertTrue(own.has(.bullets, of: .ocean))
        XCTAssertFalse(own.has(.background, of: .ocean))
        XCTAssertTrue(own.canBuy(.set(.ocean)))
        XCTAssertTrue(own.has(.background, of: .classic))
    }

    func testSetIsCheaperThanBuyingAllParts() {
        XCTAssertLessThan(Product.set(.aurora).yen, 3 * Product.part(.aurora, .ship).yen)
    }

    func testLoadoutFallsBackWhenNotOwned() {
        var l = Loadout()
        l.bullets = .sakura; l.ship = .ocean; l.shot = .heavy
        let own = Ownership(productIDs: [Product.part(.sakura, .bullets).id])
        let e = l.effective(own)
        XCTAssertEqual(e.bullets, .sakura)
        XCTAssertEqual(e.ship, .classic)
        XCTAssertEqual(e.shot, .standard)
    }

    func testCustomImagesProduct() {
        XCTAssertEqual(Product.customImages.id, "com.koshin.danmakumaker.customimages")
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.customimages"), .customImages)
        XCTAssertEqual(Product.customImages.yen, 500)
        XCTAssertFalse(Ownership().hasCustomImages)
        XCTAssertTrue(Ownership().canBuy(.customImages))
        let own = Ownership(productIDs: [Product.customImages.id])
        XCTAssertTrue(own.hasCustomImages)
        XCTAssertFalse(own.canBuy(.customImages))
    }

    func testCustomImageFlagsOnlyWorkWhenOwned() {
        var l = Loadout()
        l.customBoss = true; l.customBullet = true; l.customShip = true
        let none = l.effective(Ownership())
        XCTAssertFalse(none.customBoss || none.customBullet || none.customShip)
        let owned = l.effective(Ownership(productIDs: [Product.customImages.id]))
        XCTAssertTrue(owned.customBoss && owned.customBullet && owned.customShip)
    }

    func testOldSavedLoadoutStillDecodes() throws {
        let old = #"{"bullets":"sakura","background":"classic","ship":"classic","shot":"spread"}"#.data(using: .utf8)!
        let l = try JSONDecoder().decode(Loadout.self, from: old)
        XCTAssertEqual(l.bullets, .sakura)
        XCTAssertEqual(l.shot, .spread)
        XCTAssertFalse(l.customBoss)
    }

    func testLoadoutCodable() throws {
        var l = Loadout(); l.background = .aurora; l.shot = .spread
        let back = try JSONDecoder().decode(Loadout.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
    }
}
