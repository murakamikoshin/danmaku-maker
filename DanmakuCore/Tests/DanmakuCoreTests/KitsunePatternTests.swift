import XCTest
@testable import DanmakuCore

final class KitsunePatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 12, v: Double = 2, r: Double = 0, i: Double = 0.5) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: r, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, salt: UInt32 = 5, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        return out
    }

    func testPatternsOnlyKeptForKitsune() {
        let em = [emitter(.kitsuneTorii), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 5).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 6).sanitized().emitters.map(\.t), [.kitsuneTorii, .ring])
        // 堕天使の技は九尾では使えない
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: [emitter(.angelTwin)], bossLook: 6).sanitized().emitters.map(\.t), [.ring])
        XCTAssertEqual(Pattern.kitsune.map(\.bossCharacter), Array(repeating: .kitsune, count: 5))
        XCTAssertEqual(BossCharacter.of(look: 6), .kitsune)
        XCTAssertGreaterThanOrEqual(BossCharacter.maxLook, 6)
    }

    func testLanternsLightThenFireInOrder() {
        let m = emitter(.kitsuneLanterns, c: 9, v: 3.2)
        for k in 0..<9 { XCTAssertTrue(shot(m, k).isEmpty, "灯る間は撃たない k=\(k)") }
        let first = shot(m, 9)
        XCTAssertEqual(first.count, 1)
        let tip0 = Emit.kitsuneTip(0, 180, 128), tip8 = Emit.kitsuneTip(8, 180, 128)
        XCTAssertEqual(first[0].x, tip0.x, accuracy: 1e-9)
        XCTAssertEqual(shot(m, 17)[0].x, tip8.x, accuracy: 1e-9)
        XCTAssertEqual(first[0].look, BulletLook.code(.fox))
        // 速さは 3.2 × 60
        XCTAssertEqual((first[0].vx * first[0].vx + first[0].vy * first[0].vy).squareRoot(), 192, accuracy: 1e-6)
        // 覚醒: 3way・2周目は逆の端から
        XCTAssertEqual(shot(m, 9, awakened: true).count, 3)
        XCTAssertEqual(shot(m, 27, awakened: true)[0].x, tip8.x, accuracy: 1e-9)
        XCTAssertEqual(shot(m, 9, awakened: true)[0].look, BulletLook.code(.fox, awakened: true))
    }

    func testBarrierFoldsAtRightAngleAndAwakenedFoldsBack() {
        var b = shot(emitter(.kitsuneBarrier, c: 12, v: 2), 0)
        XCTAssertEqual(b.count, 12)
        XCTAssertEqual(shot(emitter(.kitsuneBarrier, c: 12, v: 2), 0, awakened: true).count, 18)
        var one = b[0]
        let a0 = atan2(one.vy, one.vx)
        let dt = 1.0 / 120
        var t = 0.0
        while t < 0.59 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(atan2(one.vy, one.vx), a0, accuracy: 1e-9, "0.6秒までは曲がらない")
        for _ in 0..<3 { _ = one.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        var d = atan2(one.vy, one.vx) - a0
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        XCTAssertEqual(abs(d), .pi / 2, accuracy: 1e-9)
        XCTAssertEqual((one.vx * one.vx + one.vy * one.vy).squareRoot(), 144, accuracy: 1e-6, "曲がると 1.2 倍")
        // 隣の札は逆向きに曲がる
        var two = b[1]
        t = 0; while t < 0.62 { _ = two.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        var d2 = atan2(two.vy, two.vx) - atan2(b[1].vy, b[1].vx)
        while d2 > .pi { d2 -= 2 * .pi }; while d2 < -.pi { d2 += 2 * .pi }
        XCTAssertEqual(d2, -d, accuracy: 1e-9)
        b.removeAll()
    }

    func testToriiHasExactlyOneGapPerRowAndDriftsWithinLimits() {
        let m = emitter(.kitsuneTorii, c: 22, v: 1.4, r: 60)
        var prevGap: Double?
        for k in 0..<8 {
            let row = shot(m, k).map(\.x).sorted()
            XCTAssertFalse(row.isEmpty)
            // 札の間隔は 16px。抜けているのは 1 か所(60px の通り道 = 札 3〜4 枚ぶん)
            var gaps: [(Double, Double)] = []
            for (a, b) in zip(row, row.dropFirst()) where b - a > 16.5 { gaps.append((a, b)) }
            XCTAssertEqual(gaps.count, 1, "row \(k)")
            let center = (gaps[0].0 + gaps[0].1) / 2
            XCTAssertGreaterThan(center, 40); XCTAssertLessThan(center, 320)
            if let p = prevGap { XCTAssertLessThanOrEqual(abs(center - p), 70, "通り道のずれは 60px 前後まで") }
            prevGap = center
        }
        // 覚醒は通り道が狭い
        let wide = shot(m, 0).count, narrow = shot(m, 0, awakened: true).count
        XCTAssertGreaterThanOrEqual(narrow, wide)
    }

    func testSunshowerAndDanceCounts() {
        let rain = emitter(.kitsuneSunshower, v: 2.2, i: 0.05)
        XCTAssertEqual(shot(rain, 1).count, 1)
        XCTAssertEqual(shot(rain, 3).count, 0, "4回に1回は休む(平均で4フレームに1粒)")
        XCTAssertEqual((0..<12).map { k in shot(rain, k + 1).filter { $0.look == BulletLook.code(.fox) }.count }.reduce(0, +), 9, "12回で9粒")
        XCTAssertEqual(shot(rain, 1, awakened: true).count, 1)
        XCTAssertEqual(shot(rain, 2, awakened: true).count, 2, "覚醒は2フレームに1粒")
        XCTAssertEqual(shot(rain, 0).count, 4, "10回に1回、御札3way")
        XCTAssertEqual(shot(rain, 50).count, 0, "60フレーム休む")
        XCTAssertEqual(shot(rain, 70).count, 4, "また降り始める")
        let dance = emitter(.kitsuneDance, v: 2.2, i: 0.05)
        XCTAssertEqual(shot(dance, 1).count, 9)
        XCTAssertEqual(shot(dance, 3).count, 0)
        XCTAssertEqual(shot(dance, 41).count, 0, "休む間")
        XCTAssertEqual(shot(dance, 57).count, 9, "また撃ち始める")
        XCTAssertEqual(shot(dance, 1, awakened: true).count, 18)
    }

    func testFullStageRunsAndBulletsStayCapped() {
        let ems = Pattern.kitsune.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.07, c: 22, v: 2.2, r: 60, k: 0) }
        let st = Stage(name: "k", mode: .boss, durationSec: 60, bossHp: 300, emitters: ems, lifeMode: .hp, lifeCount: 20, bossLook: 6, awaken: 2).sanitized()
        var sim = Simulation(stage: st)
        var peak = 0
        for _ in 0..<(120 * 30) { sim.step(.zero); peak = max(peak, sim.bullets.count) }
        XCTAssertLessThanOrEqual(peak, DanmakuConfig.maxBullets)
        XCTAssertEqual(sim.bossCharacter, .kitsune)
    }
}
