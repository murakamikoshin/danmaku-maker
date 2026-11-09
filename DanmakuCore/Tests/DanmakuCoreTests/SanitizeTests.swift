import XCTest
@testable import DanmakuCore

final class SanitizeTests: XCTestCase {
    func testClampsAndRounds() {
        let wild = Stage(name: String(repeating: "あ", count: 40), mode: .boss, durationSec: 77, bossHp: 9999, bossMove: 99,
            emitters: (0..<12).map { _ in em(.ring, x: 3, y: 2, s: -5, e: 999, i: 0, c: 99, v: 99, r: 500, k: 9, ph: 9) })
        let s = wild.sanitized()
        XCTAssertEqual(s.name.count, 20)
        XCTAssertEqual(s.durationSec, 60)
        XCTAssertEqual(s.bossHp, 1000)
        XCTAssertEqual(s.bossMove, Simulation.bossMoveCount - 1)   // 範囲を超えた動きは、いちばん最後の種類に丸める(いまは 0〜10)
        XCTAssertEqual(Stage(name: "m", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 6, emitters: []).sanitized().bossMove, 6)
        XCTAssertEqual(Stage(name: "m", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 3, emitters: []).sanitized().bossMove, 3)
        XCTAssertEqual(Stage(name: "m", mode: .boss, durationSec: 60, bossHp: 400, bossMove: -4, emitters: []).sanitized().bossMove, 0)
        XCTAssertEqual(s.emitters.count, 8)
        let m = s.emitters[0]
        XCTAssertEqual([m.x, m.y, m.s, m.e, m.i, m.v, m.r], [1, 0.6, 0, 180, 0.05, 5, 90])
        XCTAssertEqual([m.c, m.k, m.ph], [36, 4, 3])
    }

    func testBossHpRoundsTo50() {
        XCTAssertEqual(Stage(name: "a", mode: .boss, durationSec: 30, bossHp: 423, emitters: []).sanitized().bossHp, 400)
        XCTAssertEqual(Stage(name: "a", mode: .boss, durationSec: 30, bossHp: 10, emitters: []).sanitized().bossHp, 100)
    }

    func testSurviveDropsBossFields() {
        let s = Stage(name: "a", mode: .survive, durationSec: 20, bossHp: 500, bossMove: 1, emitters: []).sanitized()
        XCTAssertNil(s.bossHp); XCTAssertNil(s.bossMove)
    }

    func testEmptyNameAndNaN() {
        let s = Stage(name: "", mode: .survive, durationSec: 20, emitters: [em(.ring, x: .nan, v: .infinity)]).sanitized()
        XCTAssertEqual(s.name, "名無しステージ")
        XCTAssertEqual(s.emitters[0].x, 0)
        XCTAssertEqual(s.emitters[0].v, 1)
    }

    func testIdempotent() {
        let s = Stage(name: "x", mode: .survive, durationSec: 30, emitters: [em(.sweep, x: 0.333333, i: 0.123456)]).sanitized()
        XCTAssertEqual(s, s.sanitized())
    }

    func testJSONUsesSpecKeys() throws {
        let json = #"{"name":"j","mode":"survive","durationSec":20,"emitters":[{"t":"ring","x":0.5,"y":0.2,"s":0,"e":20,"i":1,"c":16,"v":2,"r":6,"k":0}],"formatVersion":1}"#
        let s = try JSONDecoder().decode(Stage.self, from: Data(json.utf8))
        XCTAssertEqual(s.emitters[0].ph, 0)
        XCTAssertEqual(s.emitters[0].t, .ring)
    }
}
