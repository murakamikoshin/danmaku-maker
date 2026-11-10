import XCTest
@testable import DanmakuCore

/// ボスの大きさ: 0〜2 は小・中・大、10〜44 は半径(px)。スライダーで細かく決められる
final class BossRadiusSliderTests: XCTestCase {
    func testRadiusFromSize() {
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 0), 17)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 1), 24)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 2), 34)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 10), 10)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 29), 29)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 44), 44)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 5), 34, "範囲外は、これまでどおり 0〜2 に丸める")
        XCTAssertEqual(DanmakuConfig.bossRadius(size: 99), 34)
        XCTAssertEqual(DanmakuConfig.bossRadius(size: -3), 17, "負の数は、これまでどおり小")
    }

    func testSliderValuesCollapseToTheOldSizes() {
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 17), 0)
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 24), 1)
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 34), 2)
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 30), 30)
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 3), 10, "下限に丸める")
        XCTAssertEqual(DanmakuConfig.bossSize(forRadius: 60), 44, "上限に丸める")
    }

    private func stage(_ size: Int?) -> Stage {
        Stage(name: "s", mode: .boss, durationSec: 30, bossHp: 200, bossMove: 0,
              emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 30, i: 1, c: 3, v: 2, r: 20, k: 0)], bossSize: size)
    }

    func testSanitizeKeepsRadiusAndDropsStandard() {
        XCTAssertEqual(stage(30).sanitized().bossSize, 30)
        XCTAssertEqual(stage(24).sanitized().bossSize, nil, "半径24は中(標準)なので保存しない")
        XCTAssertEqual(stage(17).sanitized().bossSize, 0)
        XCTAssertEqual(stage(34).sanitized().bossSize, 2)
        XCTAssertEqual(stage(9).sanitized().bossSize, nil, "範囲外は標準に戻す")
        XCTAssertEqual(stage(45).sanitized().bossSize, nil)
        XCTAssertEqual(stage(1).sanitized().bossSize, nil)
        XCTAssertEqual(stage(2).sanitized().bossSize, 2)
    }

    func testSimulationUsesTheChosenRadius() {
        XCTAssertEqual(Simulation(stage: stage(30).sanitized()).bossHitRadius, 30)
        XCTAssertEqual(Simulation(stage: stage(nil).sanitized()).bossHitRadius, 24)
        XCTAssertEqual(Simulation(stage: stage(17).sanitized()).bossHitRadius, 17)
        XCTAssertEqual(Simulation(stage: stage(44).sanitized()).bossHitRadius, 44)
        // キャラクターのボスは、大きさを使わない
        let ch = Stage(name: "c", mode: .boss, durationSec: 30, bossHp: 200, emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 1, c: 8, v: 2, r: 0, k: 0)], bossSize: 30, bossLook: 5).sanitized()
        XCTAssertNil(ch.bossSize)
        XCTAssertEqual(Simulation(stage: ch).bossHitRadius, 40)
    }
}
