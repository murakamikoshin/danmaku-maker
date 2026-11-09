import XCTest
@testable import DanmakuCore

/// 発射の左右反転(線対称)と、ボスの位置の指定
final class MirrorAndHomeTests: XCTestCase {
    private func emit(_ t: DanmakuCore.Pattern, mir: Int?, shot: Int = 3, r: Double = 10) -> [Bullet] {
        var rng = Mulberry32(seed: 7)
        var out: [Bullet] = []
        let m = Emitter(t: t, x: 0.3, y: 0.2, s: 0, e: 30, i: 1, c: 8, v: 2, r: r, k: 0, mir: mir)
        Emit.emit(m, shot: shot, cx: 0.3 * DanmakuConfig.width, cy: 0.2 * DanmakuConfig.height, px: 250, py: 480, rng: &rng, into: &out)
        return out
    }

    /// 向きに関係のない輪は、同じ場所から、横向きだけ反対に出る
    func testMirrorFlipsHorizontalVelocityOnly() {
        for t in [DanmakuCore.Pattern.ring, .flower, .star] {
            let a = emit(t, mir: nil), b = emit(t, mir: 1)
            XCTAssertEqual(a.count, b.count)
            for (p, q) in zip(a, b) {
                XCTAssertEqual(p.x, q.x, accuracy: 1e-9)
                XCTAssertEqual(p.y, q.y, accuracy: 1e-9)
                XCTAssertEqual(p.vx, -q.vx, accuracy: 1e-9)
                XCTAssertEqual(p.vy, q.vy, accuracy: 1e-9)
            }
        }
    }

    /// 自機を狙う弾は、反転しても本物の自機の方へ向かう(狙いの広がりだけが反転する)
    func testMirroredAimStillTargetsPlayer() {
        let out = emit(.aim, mir: 1, r: 0)
        let cx = 0.3 * DanmakuConfig.width, cy = 0.2 * DanmakuConfig.height
        let target = atan2(480 - cy, 250 - cx)
        for b in out { XCTAssertEqual(atan2(b.vy, b.vx), target, accuracy: 1e-9) }
    }

    /// カーブする弾は、曲がる向きも反対になる
    func testMirrorReversesCurveDirection() {
        let a = emit(.boomerang, mir: nil), b = emit(.boomerang, mir: 1)
        XCTAssertFalse(a.isEmpty)
        for (p, q) in zip(a, b) { XCTAssertEqual(p.turn, -q.turn, accuracy: 1e-9) }
    }

    func testMirrorIsSavedOnlyWhenOn() throws {
        var m = Emitter(t: .ring, mir: 1)
        XCTAssertTrue(String(data: try JSONEncoder().encode(m), encoding: .utf8)!.contains("\"mir\":1"))
        m.mir = nil
        XCTAssertFalse(String(data: try JSONEncoder().encode(m), encoding: .utf8)!.contains("mir"))
        let back = try JSONDecoder().decode(Emitter.self, from: Data(#"{"t":"ring","x":0.5,"y":0.2,"s":0,"e":30,"i":1,"c":8,"v":2,"r":0,"k":0,"mir":5}"#.utf8))
        XCTAssertNil(back.mir)   // 1 以外は反転なし
    }

    // MARK: ボスの位置

    private func bossStage(x: Double?, y: Double?, move: Int = 0) -> Stage {
        Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: move,
              emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 60, i: 1, c: 8, v: 2, r: 0, k: 0, ph: 0)],
              bossX: x, bossY: y).sanitized()
    }

    func testBossPositionShiftsCenter() {
        let std = Simulation(stage: bossStage(x: nil, y: nil))
        let moved = Simulation(stage: bossStage(x: 0.7, y: 0.3))
        XCTAssertEqual(moved.bossPosition.x - std.bossPosition.x, 0.2 * DanmakuConfig.width, accuracy: 1e-9)
        XCTAssertEqual(moved.bossPosition.y - std.bossPosition.y, 0.1 * DanmakuConfig.height, accuracy: 1e-9)
    }

    func testBossPositionIsSanitized() {
        XCTAssertNil(bossStage(x: 0.5, y: 0.2).bossX)             // 標準と同じなら保存しない
        XCTAssertNil(bossStage(x: 0.5, y: 0.2).bossY)
        XCTAssertEqual(bossStage(x: 0.99, y: 0.01).bossX, 0.8)    // 範囲に丸める
        XCTAssertEqual(bossStage(x: 0.99, y: 0.01).bossY, 0.1)
        XCTAssertEqual(bossStage(x: 0.33, y: nil).bossX, 0.35)    // 0.05 刻み
        let survive = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)], bossX: 0.7).sanitized()
        XCTAssertNil(survive.bossX)                                // ボスのないモードでは使わない
    }

    func testBossPositionStaysOnScreenWhileMoving() {
        var sim = Simulation(stage: bossStage(x: 0.8, y: 0.3, move: 5))
        for _ in 0..<2000 {
            sim.step(.zero)
            let p = sim.bossPosition
            XCTAssertTrue(p.x >= 24 && p.x <= DanmakuConfig.width - 24)
            XCTAssertTrue(p.y >= 24 && p.y <= DanmakuConfig.height * 0.5)
        }
    }

    func testBossPositionRoundTripsThroughCodable() throws {
        let st = bossStage(x: 0.65, y: 0.15)
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.bossX, 0.65); XCTAssertEqual(back.bossY, 0.15)
    }
}
