import XCTest
@testable import DanmakuCore

final class DanmakuCoreTests: XCTestCase {
    func testConstants() {
        XCTAssertEqual(DanmakuCore.width, 360)
        XCTAssertEqual(DanmakuCore.height, 540)
        XCTAssertEqual(DanmakuCore.step, 1.0 / 120.0)
    }
}
