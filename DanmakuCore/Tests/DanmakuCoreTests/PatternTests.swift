import XCTest
@testable import DanmakuCore

/// 試作の emit の計算式から期待値を作って比べる
final class PatternTests: XCTestCase {
    private let deg = Double.pi / 180

    private func fire(_ m: Emitter, shot: Int = 0, cx: Double = 180, cy: Double = 100,
                      px: Double = 180, py: Double = 459) -> [Bullet] {
        var rng = Mulberry32(seed: 1), out: [Bullet] = []
        Emit.emit(m, shot: shot, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out)
        return out
    }

    func testRing() {
        let m = em(.ring, c: 12, v: 2.5, r: 6)
        let bs = fire(m, shot: 3)
        XCTAssertEqual(bs.count, 12)
        for (j, b) in bs.enumerated() {
            let a = Double(j) * 2 * .pi / 12 + 3 * 6 * deg
            XCTAssertEqual(b.vx, cos(a) * 150, accuracy: 1e-9)
            XCTAssertEqual(b.vy, sin(a) * 150, accuracy: 1e-9)
            XCTAssertEqual(b.x, 180); XCTAssertEqual(b.y, 100)
        }
    }

    func testSpiralUsesSameFormulaAsRing() {
        XCTAssertEqual(fire(em(.spiral, c: 3, r: 11), shot: 7), fire(em(.ring, c: 3, r: 11), shot: 7))
    }

    func testAimIsCenteredOnPlayer() {
        let m = em(.aim, c: 5, v: 3, r: 40)
        let bs = fire(m, cx: 100, cy: 80, px: 250, py: 400)
        let base = atan2(400.0 - 80, 250.0 - 100)
        for (j, b) in bs.enumerated() {
            let a = base + (Double(j) / 4 - 0.5) * 40 * deg
            XCTAssertEqual(b.vx, cos(a) * 180, accuracy: 1e-9)
            XCTAssertEqual(b.vy, sin(a) * 180, accuracy: 1e-9)
        }
    }

    func testAimSingleBulletPointsAtPlayer() {
        let b = fire(em(.aim, c: 1, v: 2, r: 60), cx: 100, cy: 80, px: 100, py: 400)[0]
        XCTAssertEqual(b.vx, 0, accuracy: 1e-9)
        XCTAssertEqual(b.vy, 120, accuracy: 1e-9)
    }

    func testRainComesFromTopWithSeededRandom() {
        let m = em(.rain, c: 2, v: 2.2)
        var rng = Mulberry32(seed: 1)
        var expected: [(Double, Double)] = []
        for _ in 0..<2 {
            let x = rng.next() * 360
            let a = Double.pi / 2 + (rng.next() - 0.5) * 0.3
            expected.append((x, a))
        }
        let bs = fire(m)
        XCTAssertEqual(bs.count, 2)
        for (b, e) in zip(bs, expected) {
            XCTAssertEqual(b.x, e.0); XCTAssertEqual(b.y, -8)
            XCTAssertEqual(b.vx, cos(e.1) * 132, accuracy: 1e-9)
            XCTAssertEqual(b.vy, sin(e.1) * 132, accuracy: 1e-9)
        }
    }

    func testSweepSwingsWithShotIndex() {
        let m = em(.sweep, c: 5, v: 2.5, r: 60)
        for shot in [0, 4, 10] {
            let bs = fire(m, shot: shot)
            let base = Double.pi / 2 + sin(Double(shot) * 0.25) * 60 * deg
            for (j, b) in bs.enumerated() {
                let a = base + (Double(j) / 4 - 0.5) * 0.5
                XCTAssertEqual(b.vx, cos(a) * 150, accuracy: 1e-9)
                XCTAssertEqual(b.vy, sin(a) * 150, accuracy: 1e-9)
            }
        }
    }

    func testCapAt1600() {
        var sim = Simulation(stage: Stage(name: "cap", mode: .survive, durationSec: 30,
            emitters: (0..<8).map { em(.ring, x: 0.1 * Double($0 + 1), y: 0, i: 0.05, c: 36, v: 1) }).sanitized())
        var peak = 0
        for _ in 0..<(144 + 360) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(peak, 1600)
    }
}
