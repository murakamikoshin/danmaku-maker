import XCTest
@testable import DanmakuCore

/// ボスの発射台の「撃つ段階」を2つ選べる(1.3.0〜。値は 12・13・23)
final class MultiPhaseTests: XCTestCase {
    func testCodesAndSets() {
        XCTAssertEqual(Emitter.phaseCodes.map { Emitter.phases(of: $0) }, [[], [1], [2], [3], [1, 2], [1, 3], [2, 3]])
        XCTAssertEqual(Emitter.phaseCode([]), 0)
        XCTAssertEqual(Emitter.phaseCode([2]), 2)
        XCTAssertEqual(Emitter.phaseCode([3, 1]), 13)
        XCTAssertEqual(Emitter.phaseCode([2, 3]), 23)
        XCTAssertEqual(Emitter.phaseCode([1, 2, 3]), 0)
        for code in Emitter.phaseCodes { XCTAssertEqual(Emitter.phaseCode(Emitter.phases(of: code)), code) }
    }

    func testFiresInPhase() {
        func on(_ ph: Int) -> [Int] { [1, 2, 3].filter { Emitter(t: .ring, ph: ph).fires(inPhase: $0) } }
        XCTAssertEqual(Emitter.phaseCodes.map(on), [[1, 2, 3], [1], [2], [3], [1, 2], [1, 3], [2, 3]])
    }

    func testSanitize() {
        XCTAssertEqual([0, 1, 2, 3, 12, 13, 23, 123, 4, 11, -1, 99].map(Emitter.sanitizedPhase), [0, 1, 2, 3, 12, 13, 23, 0, 3, 3, 0, 3])
        let boss = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, bossMove: 0, emitters: [Emitter(t: .ring, ph: 23)]).sanitized()
        XCTAssertEqual(boss.emitters[0].ph, 23)
        let seq = Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: [
            Wave(kind: .boss, durationSec: 60, bossHp: 300, bossMove: 0, emitters: [Emitter(t: .ring, ph: 13)]),
            Wave(kind: .survive, durationSec: 20, emitters: [Emitter(t: .ring, ph: 13)])]).sanitized()
        XCTAssertEqual(seq.waves?.map { $0.emitters[0].ph }, [13, 0])
        // 保存して読み直しても同じ
        let data = try! JSONEncoder().encode(boss)
        XCTAssertEqual(try! JSONDecoder().decode(Stage.self, from: data).emitters[0].ph, 23)
    }

    /// 第1段階では、ph=23 の発射台は撃たず、ph=12・13 は撃つ
    func testPhaseOne() {
        func bullets(_ ph: Int) -> Int {
            let st = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 1000, bossMove: 0, emitters: [Emitter(t: .ring, i: 0.3, c: 8, ph: ph)]).sanitized()
            var sim = Simulation(stage: st)
            sim.invincible = true
            var most = 0
            while sim.t < 4 && sim.outcome == .playing {
                sim.step(.zero)
                XCTAssertEqual(sim.phase, 1)
                most = max(most, sim.bullets.count)
            }
            return most
        }
        XCTAssertEqual(bullets(23), 0)
        XCTAssertGreaterThan(bullets(12), 0)
        XCTAssertGreaterThan(bullets(13), 0)
        XCTAssertEqual(bullets(2), 0)
    }
}
