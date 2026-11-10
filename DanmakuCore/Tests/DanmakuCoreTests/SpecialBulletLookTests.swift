import XCTest
@testable import DanmakuCore

/// ボス専用の弾の見た目(look 16 以上)。見た目の番号と、種類ごとの当たる半径
final class SpecialBulletLookTests: XCTestCase {
    func testCodesRoundTrip() {
        for k in BulletLook.Kind.allCases {
            for aw in [false, true] {
                let c = BulletLook.code(k, awakened: aw)
                XCTAssertEqual(BulletLook.kind(of: c), k)
                XCTAssertEqual(BulletLook.isAwakened(c), aw)
            }
        }
        XCTAssertNil(BulletLook.kind(of: 0)); XCTAssertNil(BulletLook.kind(of: 1)); XCTAssertNil(BulletLook.kind(of: 2))
        XCTAssertNil(BulletLook.kind(of: 16 + 2 * 22))
        XCTAssertEqual(BulletLook.Kind.allCases.count, BulletLook.bodyRadius.count)
    }

    func testHitDistanceFollowsKind() {
        func b(_ look: UInt8) -> Bullet { var x = Bullet(x: 0, y: 0, vx: 0, vy: 0, color: 0); x.look = look; return x }
        // 標準の弾・くの字・丸は、いままでどおり 5.5px
        for l: UInt8 in [0, 1, 2] { XCTAssertEqual(b(l).hitDistanceSquared, DanmakuConfig.hitRadiusSquared) }
        // 狐火(半径 3)は標準と同じ 5.5px、夜光虫(2.5)は 5px、砲弾(2)は 4.5px、墨(6)は 8.5px
        XCTAssertEqual(b(BulletLook.code(.fox)).hitDistanceSquared, 5.5 * 5.5, accuracy: 1e-9)
        XCTAssertEqual(b(BulletLook.code(.plankton)).hitDistanceSquared, 25, accuracy: 1e-9)
        XCTAssertEqual(b(BulletLook.code(.shell, awakened: true)).hitDistanceSquared, 4.5 * 4.5, accuracy: 1e-9)
        XCTAssertEqual(b(BulletLook.code(.ink)).hitDistanceSquared, 8.5 * 8.5, accuracy: 1e-9)
        // かする距離は、当たる距離 + 12.5px
        XCTAssertEqual(b(BulletLook.code(.ink)).grazeDistanceSquared, 21 * 21, accuracy: 1e-9)
        XCTAssertEqual(b(BulletLook.code(.fox)).grazeDistanceSquared, 18 * 18, accuracy: 1e-9)
        // 広さを持つ弾(膨らむ泡)は、従来どおり radius を優先する
        var bubble = b(BulletLook.code(.bubble)); bubble.radius = 8
        XCTAssertEqual(bubble.hitDistanceSquared, 13.5 * 13.5, accuracy: 1e-9)
    }
}
