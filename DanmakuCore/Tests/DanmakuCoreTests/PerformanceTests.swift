import XCTest
@testable import DanmakuCore

final class PerformanceTests: XCTestCase {
    /// 弾 1600 発が出続ける状態で 600 ステップ(5 秒)進める
    func testStepWith1600Bullets() {
        let stage = Stage(name: "p", mode: .survive, durationSec: 120, emitters: (0..<8).map {
            em(.ring, x: 0.1 * Double($0 + 1), y: 0, i: 0.05, c: 36, v: 0.0 + 1) }).sanitized()
        var warm = Simulation(stage: stage)
        for _ in 0..<(144 + 360) { warm.step(.zero) }
        XCTAssertGreaterThan(warm.bullets.count, 1500)
        measure {
            var sim = warm
            for _ in 0..<600 { sim.step(.zero) }
        }
    }
}
