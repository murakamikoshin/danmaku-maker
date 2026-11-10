import XCTest
@testable import DanmakuCore

/// ドット絵の自機(招待のごほうび)の選択は、組み合わせ(Loadout)に保存される。古い保存データも読める
final class ShipSkinLoadoutTests: XCTestCase {
    func testShipSkinRoundTripsAndDefaultsToNil() throws {
        var l = Loadout()
        XCTAssertNil(l.shipSkin)
        l.shipSkin = "ace_steel"
        let back = try JSONDecoder().decode(Loadout.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.shipSkin, "ace_steel")
        XCTAssertEqual(back, l)
    }

    func testOldSavedLoadoutWithoutShipSkinStillLoads() throws {
        let old = #"{"bullets":"gold","background":"classic","ship":"classic","shot":"standard"}"#.data(using: .utf8)!
        let l = try JSONDecoder().decode(Loadout.self, from: old)
        XCTAssertEqual(l.bullets, .gold)
        XCTAssertNil(l.shipSkin)
    }

    func testEffectiveKeepsShipSkinBecauseOwnershipIsCheckedByTheApp() {
        var l = Loadout(); l.shipSkin = "wasp_gold"
        XCTAssertEqual(l.effective(Ownership()).shipSkin, "wasp_gold")
    }
}
