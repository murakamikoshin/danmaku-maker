import XCTest
@testable import DanmakuCore

final class HirePatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 8, v: Double = 2, i: Double = 1) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: 0, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: 5)
        return out
    }
    private let dt = 1.0 / 120

    func testOwnershipAndProduct() {
        let em = [emitter(.hireKaiyu), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 11).sanitized().emitters.map(\.t), [.ring, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 12).sanitized().emitters.map(\.t), [.hireKaiyu, .ring])
        XCTAssertEqual(Pattern.hire.map(\.bossCharacter), Array(repeating: .hire, count: 5))
        XCTAssertTrue(BossCharacter.hire.purchasable && BossCharacter.hire.ticketEligible && !BossCharacter.hire.inviteLimited)
        XCTAssertEqual(BossCharacter.maxLook, 12)
    }

    func testSukuiFansOutGoldfishThenRests() {
        let out = shot(emitter(.hireSukui), 0)
        XCTAssertEqual(out.count, 8)
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.wobbleScript && BulletLook.kind(of: $0.look) == .kingyo })
        XCTAssertEqual(shot(emitter(.hireSukui), 0, awakened: true).count, 12)
        XCTAssertEqual(shot(emitter(.hireSukui), 3).count, 0, "3回撃ったら休む")
        XCTAssertEqual(shot(emitter(.hireSukui), 3, awakened: true).count, 12, "覚醒は4回")
        XCTAssertEqual(shot(emitter(.hireSukui), 4, awakened: true).count, 0)
    }

    func testYoyoDropsBouncesAndPopsIntoBubbles() {
        let out = shot(emitter(.hireYoyo, c: 6, v: 2.2, i: 1.2), 0)
        let yoyos = out.filter { $0.script == Bullet.yoyoScript }
        XCTAssertEqual(yoyos.count, 6)
        XCTAssertEqual(out.count - yoyos.count, 6 * 8)
        XCTAssertEqual(shot(emitter(.hireYoyo, c: 6, v: 2.2, i: 1.2), 0, awakened: true).filter { $0.script == Bullet.holdScript }.count, 9 * 12)
        var y = yoyos[1]
        XCTAssertTrue(y.isDormant)
        var top = y.y, maxY = y.y
        var t = 0.0
        while t < 1.0 + 8.0 / 60 + 0.05 { _ = y.advance(dt: dt, width: 360, playerX: 180, playerY: 500); maxY = max(maxY, y.y); t += dt }
        XCTAssertGreaterThan(maxY, top + 60, "落ちる")
        top = maxY
        var gone = false
        for _ in 0..<400 { if y.advance(dt: dt, width: 360, playerX: 180, playerY: 500) == .gone { gone = true; break } }
        XCTAssertTrue(gone, "はじける")
    }

    func testHanabiShellsOpenIntoSparksThatFall() {
        let out = shot(emitter(.hireHanabi, c: 1, v: 4, i: 0.6), 0)
        XCTAssertEqual(out.count, 1 + 18)
        XCTAssertEqual(shot(emitter(.hireHanabi, c: 1, v: 4, i: 0.6), 0, awakened: true).count, 1 + 24)
        XCTAssertEqual(shot(emitter(.hireHanabi, c: 1, v: 4, i: 0.6), 4).count, 0, "4発で休む")
        var spark = out.last!
        for _ in 0..<(120 * 2) { _ = spark.advance(dt: dt, width: 360, playerX: 180, playerY: 500) }
        XCTAssertGreaterThan(spark.vy, 0, "重力で下へ向かう")
    }

    func testRippleStaysAwayFromPlayer() {
        for k in 0..<4 {
            let out = shot(emitter(.hireRipple, c: 14, v: 1.5, i: 0.5), k, px: 180, py: 480)
            XCTAssertEqual(out.count, 14)
            let cx = out.map(\.x).reduce(0, +) / 14, cy = out.map(\.y).reduce(0, +) / 14
            XCTAssertGreaterThan(((cx - 180) * (cx - 180) + (cy - 480) * (cy - 480)).squareRoot(), 15, "自機の真上には出ない(クランプ込み)")
            XCTAssertTrue(out.allSatisfy { $0.isDormant })
        }
        XCTAssertEqual(shot(emitter(.hireRipple, c: 14, v: 1.5, i: 0.5), 5).count, 0)
        XCTAssertEqual(shot(emitter(.hireRipple, c: 14, v: 1.5, i: 0.5), 0, awakened: true).count, 2 * 20)
    }

    func testKaiyuRingShrinksAroundPlayerThenScatters() {
        let out = shot(emitter(.hireKaiyu, c: 20, v: 1, i: 3.2), 0, px: 180, py: 400)
        XCTAssertGreaterThanOrEqual(out.count, 14)
        XCTAssertLessThanOrEqual(out.count, 17, "3匹ぶんのすき間")
        XCTAssertEqual(shot(emitter(.hireKaiyu, c: 20, v: 1, i: 3.2), 0, awakened: true).count > out.count, true)
        var b = out[0]
        let r0 = hypot(b.x - 180, b.y - 400)
        XCTAssertEqual(r0, 150, accuracy: 0.01)
        var t = 0.0
        while t < 100.0 / 60 - 0.02 { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0); t += dt }
        XCTAssertEqual(hypot(b.x - 180, b.y - 400), 60, accuracy: 2, "縮む")
        for _ in 0..<10 { _ = b.advance(dt: dt, width: 360, playerX: 0, playerY: 0) }
        XCTAssertEqual(b.script, 0)
        XCTAssertGreaterThan(hypot(b.vx, b.vy), 100, "外へ散る")
    }
}
