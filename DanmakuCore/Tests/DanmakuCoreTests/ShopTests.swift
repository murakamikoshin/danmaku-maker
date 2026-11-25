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
        XCTAssertEqual(Product.all.count, 62)   // 弾幕パック2で12個、ボス(堕天使・九尾の巫女・雪の女王・死神・深海の魔女・機神)で6個増えた(金魚姫で48個、竜王で49個、弾幕パック3の12個で61個)
    }

    func testLifetimeGrantsPurchasableBossesButNotInviteOnly() {
        let own = Ownership(owned: [.lifetime])
        for b in BossCharacter.allCases where b.purchasable { XCTAssertTrue(own.has(b), "永久買い切りで \(b) が使える") }
        XCTAssertFalse(own.has(.puni), "招待限定のぷにまるは、永久買い切りでは使えない")
        var invited = own
        invited.freeBosses = [.puni]
        XCTAssertTrue(invited.has(.puni), "招待の特典でもらえば使える")
    }

    // MARK: 期間限定のボス(「商品として存在する」と「いま売り場に出す」は別)

    func testSeasonalBossIsInLifetimeRegardlessOfSeason() {
        let santa = BossCharacter.santa
        XCTAssertEqual(santa.season, .xmas)
        XCTAssertTrue(santa.purchasable, "商品として存在する(永久買い切りパックに含む)。期間外でも true")
        // 所持の判定は、販売中かどうかを受け取らない。永久買い切りパックの人は、期間に関係なく使える(期間のあとに買った人も)
        XCTAssertTrue(Ownership(owned: [.lifetime]).has(santa))
        XCTAssertFalse(Ownership(owned: [.lifetime]).canBuy(.boss(santa)), "永久買い切りパックの人に、買うボタンは出さない")
    }

    func testSeasonalBossOwnedByPurchaseForever() {
        // 期間中に買った人: 期間が終わっても使える。商品 ID は期間外でも読める(購入の復元)
        let id = Product.idPrefix + "boss.santa"
        XCTAssertEqual(Product(id: id), .boss(.santa))
        XCTAssertTrue(Product.all.contains(.boss(.santa)), "期間外でも、商品の一覧(復元・価格の取得)に残す")
        let restored = Ownership(productIDs: [id])
        XCTAssertTrue(restored.has(.santa))
        XCTAssertFalse(restored.has(.kitsune))
        XCTAssertEqual(Product.boss(.santa).yen, 400)
    }

    func testSeasonalBossNotOwnedWithoutPurchase() {
        XCTAssertFalse(Ownership().has(.santa))
        XCTAssertFalse(Ownership(owned: [.boss(.kitsune), .patternPack, .set(.sakura)]).has(.santa))
        // 無料チケットではもらえない(サーバーの PAID_ONLY_BOSSES と同じ)
        XCTAssertFalse(BossCharacter.santa.ticketEligible)
        XCTAssertFalse(BossCharacter.santa.inviteLimited)
    }

    func testShelfFollowsSeasonButOwnershipDoesNot() {
        let santa = BossCharacter.santa
        XCTAssertFalse(santa.onShelf([]), "期間外は売り場に出さない")
        XCTAssertTrue(santa.onShelf([.xmas]), "期間中は売り場に出す")
        // いつも売っているボスは、期間に関係なく売り場に出る。招待限定は出ない
        for b in BossCharacter.allCases where b.season == nil && !b.inviteLimited {
            XCTAssertTrue(b.onShelf([])); XCTAssertTrue(b.onShelf([.xmas]))
        }
        XCTAssertFalse(BossCharacter.puni.onShelf([.xmas]))
        // 期間限定のボスは、どれも商品として存在する(= 永久買い切りパックに含む)
        for b in BossCharacter.allCases where b.season != nil {
            XCTAssertTrue(b.purchasable)
            XCTAssertTrue(Ownership(owned: [.lifetime]).has(b))
            XCTAssertTrue(Ownership(owned: [.boss(b)]).has(b))
        }
        XCTAssertEqual(SaleSeason.xmas.configKey, "xmas_boss_on_sale")
    }

    func testSeasonalBossStageSurvivesSanitizeAndNeedsNewApp() {
        XCTAssertEqual(BossCharacter.maxLook, 14)
        XCTAssertEqual(DanmakuConfig.contentLevel, 8)
        let st = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: [], bossLook: 14).sanitized()
        XCTAssertEqual(st.bossLook, 14)
    }

    func testProductIDRoundTrip() {
        XCTAssertEqual(Product.all.count, 62)   // 弾幕パック3(1.4.2)で12個、期間限定のサンタ娘(1.5.0)で1個増えた
        XCTAssertEqual(Set(Product.all.map(\.id)).count, 62)
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
