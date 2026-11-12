import XCTest
@testable import DanmakuCore

/// ボスの体に触れるとダメージ(作者が選ぶ。1.3.0〜)
final class BodyHitTests: XCTestCase {
    /// ボスへ向かって動く(重なったら、そのままついていく)
    static func chase(_ sim: Simulation) -> Move {
        let b = sim.bossPosition, p = sim.player
        func dir(_ d: Double) -> Int8 { abs(d) < 2 ? 0 : (d > 0 ? 2 : -2) }
        return Move(dx: dir(b.x - p.x), dy: dir(b.y - p.y))
    }

    /// 弾はほとんど出さず、自機をボスへ寄せて、そのまま重ねる
    private func run(bodyHit: Bool, mode: Mode = .boss, life: LifeMode = .lives, count: Int = 3) -> Simulation {
        var st = Stage(name: "t", mode: mode, durationSec: 30, bossHp: 1000, bossMove: 0,
                       emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 15, c: 1, v: 1, r: 0, k: 0)],
                       lifeMode: life, lifeCount: count)
        st.bodyHit = bodyHit
        var sim = Simulation(stage: st.sanitized())
        for _ in 0..<(120 * 40) where sim.outcome == .playing { sim.step(BodyHitTests.chase(sim)) }
        return sim
    }

    func testTouchingTheBossCostsALifeOnlyWhenOn() {
        // ボスの位置から出る弾には、オンでもオフでも当たる。オフはそれだけで生き残り、オンは体当たりで失敗する
        let off = run(bodyHit: false)
        XCTAssertEqual(off.outcome, .timeUp, "オフなら、ボスに重なり続けても、体当たりでは減らない")
        XCTAssertGreaterThan(off.lifeLeft, 0)
        let on = run(bodyHit: true)
        XCTAssertEqual(on.outcome, .hit, "オンで重なり続けると、無敵が切れるたびに減って、最後は失敗")
        XCTAssertLessThan(on.tick, 120 * 10, "2秒ごとに減るので、10秒以内に尽きる")
    }

    func testShieldAfterTouchStopsInstantDrainInHpMode() {
        // HP 制でも、1回触れたら少しの間無敵(触れ続けて一気に減らない)
        var st = Stage(name: "t", mode: .boss, durationSec: 30, bossHp: 1000, bossMove: 0,
                       emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 15, c: 1, v: 1, r: 0, k: 0)], lifeMode: .hp, lifeCount: 10)
        st.bodyHit = true
        var sim = Simulation(stage: st.sanitized())
        var firstHitTick: Int?
        for _ in 0..<(120 * 20) where sim.outcome == .playing {
            sim.step(BodyHitTests.chase(sim))
            if firstHitTick == nil && sim.lifeLeft < 10 { firstHitTick = sim.tick }
            if let f = firstHitTick, sim.tick == f + 120 { break }
        }
        XCTAssertEqual(sim.lifeLeft, 9, "触れてから1秒は、それ以上減らない")
    }

    func testDamageRaceAndSanitize() {
        XCTAssertLessThan(run(bodyHit: true, mode: .damage, life: .hp, count: 20).lifeLeft, 20)
        var survive = Stage(name: "t", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)])
        survive.bodyHit = true
        XCTAssertNil(survive.sanitized().bodyHit, "生き残りには、ボスがいないので入れない")
        var seq = Stage(name: "t", mode: .sequence, durationSec: 0, emitters: [], waves: [Wave(kind: .survive, durationSec: 20, emitters: [Emitter(t: .ring)]), Wave(kind: .boss, durationSec: 30, bossHp: 100, emitters: [Emitter(t: .ring)])])
        seq.waves![0].bodyHit = true; seq.waves![1].bodyHit = true
        let s2 = seq.sanitized()
        XCTAssertNil(s2.waves![0].bodyHit); XCTAssertEqual(s2.waves![1].bodyHit, true)
        // 保存して読み直しても残る
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(run(bodyHit: true).stage))
        XCTAssertEqual(back.bodyHit, true)
    }
}
