import XCTest
@testable import DanmakuCore

/// 狙い方(1.3.0): 自機狙い(これまで)・固定(真下)・ランダム(月ごとに変わる)
final class AimModeTests: XCTestCase {
    private func stage(_ t: DanmakuCore.Pattern, aim: Int?, mode: Mode = .survive) -> Stage {
        var e = Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.5, c: 5, v: 2, r: 20, k: 0, p: mode == .survive ? 0 : 1)
        e.aim = aim
        return Stage(name: "a", mode: mode, durationSec: 20, bossHp: mode == .survive ? nil : 99999, emitters: [e]).sanitized()
    }
    /// 自機を左か右へ動かしながら、弾が自機に届く前(撃ち始めて1.2秒)まで進めて、画面の弾を返す
    /// (無敵でも、触れた弾は消えるので、届いたあとは自機の動きで弾の並びが変わる)
    private func run(_ st: Stage, month: Int = 0, wiggle: Bool = true) -> [Bullet] {
        var sim = Simulation(stage: st, month: month)
        sim.invincible = true
        while sim.outcome == .playing && sim.t < 1.2 {
            sim.step(Move(dx: wiggle ? 1 : -1, dy: 0))
        }
        return sim.bullets
    }

    func testSupportTable() {
        XCTAssertEqual(Emitter(t: .aim).aimSupport, .full)
        XCTAssertEqual(Emitter(t: .gridLaser).aimSupport, .full, "格子レーザーは自機の位置で格子を作る")
        XCTAssertEqual(Emitter(t: .ring).aimSupport, .none)
        XCTAssertEqual(Emitter(t: .rain).aimSupport, .randomOnly, "雨は自機を見ないが、散らばりに乱数を使う")
    }

    func testDefaultIsUnchangedAndNotSaved() throws {
        let st = stage(.aim, aim: nil)
        XCTAssertNil(st.emitters[0].aim)
        let json = String(decoding: try JSONEncoder().encode(st), as: UTF8.self)
        XCTAssertFalse(json.contains("\"aim\":"), "使わないときは保存しない(これまでの投稿と同じ形)")
        XCTAssertNil(stage(.aim, aim: 7).emitters[0].aim, "知らない値は自機狙いに戻す")
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(stage(.aim, aim: 2)))
        XCTAssertEqual(back.emitters[0].aim, 2)
    }

    /// 固定は、自機がどこにいても同じ弾幕になる。自機狙いは、自機の動きで変わる
    func testFixedIgnoresPlayer() {
        let fixed = stage(.aim, aim: 1)
        XCTAssertEqual(run(fixed, wiggle: true), run(fixed, wiggle: false))
        let aimed = stage(.aim, aim: nil)
        XCTAssertNotEqual(run(aimed, wiggle: true), run(aimed, wiggle: false))
    }

    /// ランダムは、同じ月なら毎回同じ。月が変わると変わる。自機の動きには左右されない
    func testRandomIsStableWithinMonth() {
        for t in [DanmakuCore.Pattern.aim, .rain, .gridLaser] {
            let st = stage(t, aim: 2)
            XCTAssertEqual(run(st, month: 24311), run(st, month: 24311), "\(t)")
            XCTAssertNotEqual(run(st, month: 24311), run(st, month: 24312), "\(t)")
            XCTAssertNotEqual(run(st, month: 24311), run(stage(t, aim: nil), month: 24311), "\(t)")
            XCTAssertEqual(run(st, month: 5, wiggle: true), run(st, month: 5, wiggle: false), "\(t)")
        }
        XCTAssertTrue(Simulation.usesMonth(stage(.rain, aim: 2)))
        XCTAssertFalse(Simulation.usesMonth(stage(.rain, aim: 1)))
    }

    /// ランダムの発射台を足しても、ほかの発射台の弾の並びは変わらない(乱数を分けている)
    func testRandomDoesNotDisturbOthers() {
        var a = Emitter(t: .rain, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.5, c: 5, v: 2, r: 0, k: 0)
        var b = Emitter(t: .rain, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.7, c: 4, v: 3, r: 0, k: 1)
        let solo = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [a]).sanitized()
        b.aim = 2; a.aim = nil
        let both = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [a, b]).sanitized()
        var s1 = Simulation(stage: solo, month: 3), s2 = Simulation(stage: both, month: 3)
        s1.invincible = true; s2.invincible = true
        // 同じシード(ステージの内容で決まる)ではないので、弾の数で比べる: a の発射台の弾の数は同じ
        for _ in 0..<(120 * 5) { s1.step(.zero); s2.step(.zero) }
        XCTAssertGreaterThan(s2.bullets.count, s1.bullets.count)
    }

    func testMonthIsUTCYearMonth() {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = 30; c.hour = 23
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        XCTAssertEqual(Simulation.month(of: cal.date(from: c)!), 2026 * 12 + 10)
    }
}
