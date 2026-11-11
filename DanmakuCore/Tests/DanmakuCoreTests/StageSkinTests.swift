import XCTest
@testable import DanmakuCore

/// ステージの自機(作者が選ぶドット絵の自機)。見た目だけで、計算(種)には関わらない
final class StageSkinTests: XCTestCase {
    private func stage(_ skin: String?) -> Stage {
        var s = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)])
        s.shipSkin = skin
        return s.sanitized()
    }

    func testSanitizeAndRoundTrip() {
        XCTAssertEqual(stage("ace_gold").shipSkin, "ace_gold")
        XCTAssertEqual(stage("x_summer_2026").shipSkin, "x_summer_2026")
        XCTAssertNil(stage("Ace Gold").shipSkin)
        XCTAssertNil(stage("").shipSkin)
        XCTAssertNil(stage(String(repeating: "a", count: 41)).shipSkin)
        let back = try? JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(stage("ace_gold")))
        XCTAssertEqual(back?.shipSkin, "ace_gold")
        let plain = String(decoding: try! JSONEncoder().encode(stage(nil)), as: UTF8.self)
        XCTAssertFalse(plain.contains("shipSkin"), "使わないときは保存しない")
    }

    func testSkinDoesNotChangeTheGame() {
        XCTAssertEqual(stage("ace_gold").seed, stage(nil).seed, "見た目だけなので、弾幕の種は同じ")
    }
}
