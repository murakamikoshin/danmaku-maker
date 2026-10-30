import XCTest
@testable import DanmakuCore

final class CustomPathTests: XCTestCase {
    func testSanitizedKeepsOnlyValidPaths() {
        XCTAssertEqual(PathData.sanitized([0, 0, 10.04, -5.05]), [0, 0, 10.0, -5.1])
        XCTAssertNil(PathData.sanitized([0, 0]), "1点だけ")
        XCTAssertNil(PathData.sanitized([0, 0, 1]), "奇数個")
        XCTAssertNil(PathData.sanitized(Array(repeating: 1, count: 122)), "61点")
        XCTAssertNotNil(PathData.sanitized(Array(repeating: 1, count: 120)), "60点")
        XCTAssertNil(PathData.sanitized([0, 0, .nan, 0]))
        XCTAssertNil(PathData.sanitized(nil))
        XCTAssertEqual(PathData.sanitized([0, 0, 9999, -9999]), [0, 0, 600, -600], "範囲外は範囲内に収める")
    }

    func testPositionFollowsTheLineAndKeepsGoingAtTheLastSpeed() {
        let p: [Double] = [0, 0, 10, 0, 10, 20]
        func close(_ a: (x: Double, y: Double), _ x: Double, _ y: Double, _ line: UInt = #line) {
            XCTAssertEqual(a.x, x, accuracy: 1e-9, line: line); XCTAssertEqual(a.y, y, accuracy: 1e-9, line: line)
        }
        close(PathData.position(p, at: 0), 0, 0)
        close(PathData.position(p, at: 0.05), 5, 0)
        close(PathData.position(p, at: 0.15), 10, 10)
        close(PathData.position(p, at: 0.3), 10, 20 + 200 * 0.1)
    }

    func testBulletsFollowThePathWithRotationAndSpeedScale() {
        let path: [Double] = [0, 0, 10, 0, 20, 0, 30, 0]   // 右へ 100px/秒
        let m = Emitter(t: .custom, x: 0.5, y: 0.2, s: 0, e: 10, i: 1, c: 4, v: 4, r: 0, k: 2, path: path)   // v=4 は 2倍速
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(m, shot: 0, cx: 100, cy: 100, px: 0, py: 0, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 4)
        XCTAssertTrue(out.allSatisfy { $0.follow != nil && $0.color == 2 && $0.x == 100 && $0.y == 100 })
        for i in 0..<out.count { _ = out[i].advance(dt: 0.1, width: 360, playerX: 0, playerY: 0) }
        // 0.1秒 × 2倍速 = 軌道の 0.2秒ぶん = 20px。4つは 90度ずつ回って、右・下・左・上へ進む
        let moved = out.map { ($0.x - 100, $0.y - 100) }
        XCTAssertEqual(moved[0].0, 20, accuracy: 1e-9); XCTAssertEqual(moved[0].1, 0, accuracy: 1e-9)
        XCTAssertEqual(moved[1].0, 0, accuracy: 1e-9); XCTAssertEqual(moved[1].1, 20, accuracy: 1e-9)
        XCTAssertEqual(moved[2].0, -20, accuracy: 1e-9)
        XCTAssertEqual(moved[3].1, -20, accuracy: 1e-9)
    }

    func testCustomWithoutAValidPathFiresNothing() {
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(Emitter(t: .custom, c: 5, path: nil), shot: 0, cx: 100, cy: 100, px: 0, py: 0, rng: &rng, into: &out)
        Emit.emit(Emitter(t: .custom, c: 5, path: [1, 2, 3]), shot: 0, cx: 100, cy: 100, px: 0, py: 0, rng: &rng, into: &out)
        XCTAssertTrue(out.isEmpty)
    }

    func testStageKeepsPathOnlyForCustomAndRoundTrips() throws {
        let path: [Double] = [0, 0, 10.04, 5, 20, 10]
        let st = Stage(name: "p", mode: .survive, durationSec: 20, emitters: [
            Emitter(t: .custom, s: 0, e: 20, i: 1, c: 6, v: 2, path: path),
            Emitter(t: .ring, s: 0, e: 20, path: path),             // custom 以外には付かない
            Emitter(t: .custom, s: 0, e: 20, path: [1, 2, 3]),      // 不正な軌道は外れる(何も撃たない)
        ]).sanitized()
        XCTAssertEqual(st.emitters[0].path, [0, 0, 10.0, 5, 20, 10])
        XCTAssertNil(st.emitters[1].path)
        XCTAssertNil(st.emitters[2].path)
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.emitters[0].path, st.emitters[0].path)
        XCTAssertEqual(back, st)
        // 軌道のないエミッターは、データに path を出さない
        let plain = try JSONEncoder().encode(Emitter(t: .ring))
        XCTAssertFalse(String(decoding: plain, as: UTF8.self).contains("path"))
    }

    func testSimulationRunsCustomPatternDeterministically() {
        let path = (0..<30).flatMap { i -> [Double] in [40 * sin(Double(i) * 0.4), Double(i) * 6] }
        let st = Stage(name: "p", mode: .survive, durationSec: 20, emitters: [Emitter(t: .custom, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.5, c: 8, v: 2, path: path)]).sanitized()
        func run() -> UInt32 {
            var sim = Simulation(stage: st)
            for _ in 0..<600 { sim.step(.zero) }
            XCTAssertGreaterThan(sim.bullets.count, 0)
            return sim.result.bulletHash
        }
        XCTAssertEqual(run(), run())
    }
}
