import XCTest
@testable import DanmakuCore

/// 弾の見た目の指定(くの字・丸)と、15秒までの発射間隔。見た目だけで、動き・当たり判定・点数は変えない
final class BulletLookTests: XCTestCase {
    private func stage(sh: Int?, interval: Double = 0.5, pattern: DanmakuCore.Pattern = .ring) -> Stage {
        Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: pattern, x: 0.5, y: 0.2, s: 0, e: 20, i: interval, c: 8, v: 2, sh: sh)])
    }

    func testSanitizeKeepsShapeAndLongInterval() {
        let m = stage(sh: 2, interval: 15).sanitized().emitters[0]
        XCTAssertEqual(m.sh, 2)
        XCTAssertEqual(m.i, 15)
        XCTAssertEqual(stage(sh: 1, interval: 99).sanitized().emitters[0].i, 15)
        XCTAssertNil(stage(sh: 7).sanitized().emitters[0].sh)
        XCTAssertNil(stage(sh: 0).sanitized().emitters[0].sh)
        XCTAssertNil(stage(sh: nil).sanitized().emitters[0].sh)
    }

    func testOldStagesWithoutShapeDecode() throws {
        let json = #"{"t":"ring","x":0.5,"y":0.2,"s":0,"e":20,"i":1,"c":8,"v":2,"r":0,"k":0}"#
        let e = try JSONDecoder().decode(Emitter.self, from: Data(json.utf8))
        XCTAssertNil(e.sh)
        let back = try JSONDecoder().decode(Emitter.self, from: JSONEncoder().encode(Emitter(t: .ring, sh: 1)))
        XCTAssertEqual(back.sh, 1)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(Emitter(t: .ring)), as: UTF8.self).contains("\"sh\""))
    }

    func testLooksAreSetOnlyForThatEmittersBullets() {
        var sim = Simulation(stage: stage(sh: 2, pattern: .swirl))
        while sim.t < 1 && sim.outcome == .playing { sim.step(.zero) }
        XCTAssertFalse(sim.bullets.isEmpty)
        XCTAssertTrue(sim.bullets.allSatisfy { $0.look == 2 })
        // 渦巻の弾は、標準ではくの字。丸にすると、くの字では描かない
        XCTAssertTrue(sim.bullets.allSatisfy { !$0.drawsAsBoomerang })
        var hook = Simulation(stage: stage(sh: 1, pattern: .ring))
        while hook.t < 1 && hook.outcome == .playing { hook.step(.zero) }
        XCTAssertTrue(hook.bullets.allSatisfy { $0.drawsAsBoomerang })
    }

    func testDefaultShapeKeepsPatternLook() {
        // 渦巻きは標準で丸
        var sim = Simulation(stage: stage(sh: nil, pattern: .swirl))
        while sim.t < 1 && sim.outcome == .playing { sim.step(.zero) }
        XCTAssertFalse(sim.bullets.isEmpty)
        XCTAssertTrue(sim.bullets.allSatisfy { !$0.drawsAsBoomerang })
        // ブーメランも標準は丸(くの字は選んだときだけ)
        var b = Simulation(stage: stage(sh: nil, pattern: .boomerang))
        while b.t < 1 && b.outcome == .playing { b.step(.zero) }
        XCTAssertFalse(b.bullets.isEmpty)
        XCTAssertTrue(b.bullets.allSatisfy { !$0.drawsAsBoomerang })
        // 渦巻きでも、くの字を選べる
        var h = Simulation(stage: stage(sh: 1, pattern: .swirl))
        while h.t < 1 && h.outcome == .playing { h.step(.zero) }
        XCTAssertTrue(h.bullets.allSatisfy { $0.drawsAsBoomerang })
    }

    /// 見た目の指定は、弾の数・位置・当たり判定に影響しない(丸にしても、同じ弾が同じ場所に出る)
    func testShapeDoesNotChangeTheSimulation() {
        func run(_ sh: Int?) -> [Double] {
            var sim = Simulation(stage: stage(sh: sh, interval: 0.3, pattern: .swirl))
            sim.invincible = true
            var out: [Double] = []
            while sim.t < 6 && sim.outcome == .playing { sim.step(Move(dx: 1, dy: 0)); out.append(Double(sim.bullets.count)); out.append(sim.bullets.last?.x ?? 0); out.append(sim.bullets.last?.y ?? 0) }
            return out
        }
        XCTAssertEqual(run(nil), run(2))
        XCTAssertEqual(run(nil), run(1))
    }

    func testVerySlowIntervalFiresOnTime() {
        var sim = Simulation(stage: stage(sh: nil, interval: 15))
        sim.invincible = true
        var shots = 0
        var last = 0
        while sim.t < 16 && sim.outcome == .playing {
            sim.step(.zero)
            if sim.bullets.count > last + 4 { shots += 1 }
            last = sim.bullets.count
        }
        XCTAssertGreaterThanOrEqual(shots, 1)
    }
}
