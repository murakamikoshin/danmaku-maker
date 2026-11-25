import XCTest
@testable import DanmakuCore

/// ノエル(期間限定のボス)の技5つ
final class SantaPatternTests: XCTestCase {
    private func emitter(_ t: DanmakuCore.Pattern, c: Int = 8, v: Double = 2, i: Double = 1) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 60, i: i, c: c, v: v, r: 0, k: 0)
    }
    private func shot(_ m: Emitter, _ k: Int, awakened: Bool = false, px: Double = 180, py: Double = 500) -> [Bullet] {
        var rng = Mulberry32(seed: 9)
        var out: [Bullet] = []
        Emit.emit(m, shot: k, cx: 180, cy: 128, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: 5)
        return out
    }
    private func kinds(_ bs: [Bullet]) -> [BulletLook.Kind: Int] {
        var d: [BulletLook.Kind: Int] = [:]
        for b in bs { if let k = BulletLook.kind(of: b.look) { d[k, default: 0] += 1 } }
        return d
    }
    private let dt = 1.0 / 120

    func testPatternsAreLastInTheList() {
        // 技の並び順の番号は、ステージのシードの計算に入っている。途中に足すと、後ろの技を使う既存のステージの弾の出方が変わる(1.5.0 の作業中に実際に起きた)。
        // ノエルの技は、いちばん後ろの5つ。その直前は、弾幕パック3の最後(blinkShot)
        let all = DanmakuCore.Pattern.allCases
        XCTAssertEqual(Array(all.suffix(5)), [.santaGift, .santaBell, .santaCane, .santaTree, .santaDelivery])
        XCTAssertEqual(all[all.count - 6], .blinkShot)
        XCTAssertEqual(DanmakuCore.Pattern.santa, [.santaGift, .santaBell, .santaCane, .santaTree, .santaDelivery])
        XCTAssertEqual(DanmakuCore.Pattern.moves(of: .santa).count, 5)
    }

    func testOnlyNoelCanUseThem() {
        let em = [emitter(.santaGift), emitter(.ring)]
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 14).sanitized().emitters.map(\.t), [.santaGift, .ring])
        XCTAssertEqual(Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: 12).sanitized().emitters.map(\.t), [.ring, .ring], "ほかのボスでは使えない(ふつうの輪に置き換わる)")
        XCTAssertEqual(Stage(name: "x", mode: .survive, durationSec: 60, emitters: em).sanitized().emitters.map(\.t), [.ring, .ring], "ボスのいないステージでは使えない")
    }

    func testBulletLooks() {
        // 弾の種類の番号は、後ろに足した(サーバーの KIND と同じ: gift 32, candy 33, bell 34, star 35)
        XCTAssertEqual(BulletLook.Kind.gift.rawValue, 32)
        XCTAssertEqual(BulletLook.Kind.star.rawValue, 35)
        XCTAssertEqual(BulletLook.Kind.needle.rawValue, 31, "既存の番号は変えない")
        XCTAssertEqual(BulletLook.hitDistance(BulletLook.code(.gift)), 6.5)
        XCTAssertEqual(BulletLook.hitDistance(BulletLook.code(.candy, awakened: true)), 5.0)
    }

    func testGift() {
        let out = shot(emitter(.santaGift, c: 3, v: 1.3), 0)
        XCTAssertEqual(kinds(out), [.gift: 3, .candy: 24])
        // 箱は 0.23 秒おきに出て、0.83 秒で届いて消える。キャンディは、箱が届く時刻まで待つ
        let boxes = out.filter { BulletLook.kind(of: $0.look) == .gift }
        XCTAssertEqual(boxes.map(\.fuse), [0, 14.0 / 60, 28.0 / 60])
        XCTAssertTrue(boxes.allSatisfy { abs($0.u3 - 50.0 / 60) < 1e-9 })
        let candies = out.filter { BulletLook.kind(of: $0.look) == .candy }
        XCTAssertEqual(candies[0].fuse, 50.0 / 60, accuracy: 1e-9)
        // 開く場所は、自機から 85px 以上はなれている(画面の端で切りつめた分は除く)
        for c in candies where c.x > 21 && c.x < 339 && c.y > 201 && c.y < 509 {
            XCTAssertGreaterThanOrEqual(((c.x - 180) * (c.x - 180) + (c.y - 500) * (c.y - 500)).squareRoot(), 84.9)
        }
        // 箱は、届く時刻に、キャンディの待つ場所の近くにいる
        var b = boxes[0]
        while b.age < b.fuse + b.u3 - dt { _ = b.advanceBossScript(dt: dt, playerX: 180, playerY: 500) }
        XCTAssertEqual(b.x, candies[0].x, accuracy: 3); XCTAssertEqual(b.y, candies[0].y, accuracy: 3)
        XCTAssertEqual(kinds(shot(emitter(.santaGift, c: 3, v: 1.3), 0, awakened: true)), [.gift: 4, .candy: 48, .star: 16])
        XCTAssertEqual(shot(emitter(.santaGift, c: 3), 3).count, 0, "3回撃ったら休む")
    }

    func testBell() {
        let out = shot(emitter(.santaBell, c: 16, v: 1.6), 0)
        XCTAssertEqual(kinds(out), [.bell: 16])
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.wobbleScript && $0.u3 == 0 && $0.turn == 0 }, "ゆれるだけで、自機は追わない")
        XCTAssertEqual(out[0].u0, -shot(emitter(.santaBell, c: 16, v: 1.6), 1)[0].u0, "輪ごとにゆれる向きが逆")
        XCTAssertEqual(shot(emitter(.santaBell, c: 16), 3).count, 0, "3回撃ったら休む")
        XCTAssertEqual(shot(emitter(.santaBell, c: 16), 0, awakened: true).count, 20)
        XCTAssertEqual(shot(emitter(.santaBell, c: 16), 4, awakened: true).count, 20, "覚醒は5回")
        XCTAssertEqual(shot(emitter(.santaBell, c: 16), 5, awakened: true).count, 0)
    }

    func testCaneTurnsHalfwayAndComesBack() {
        let out = shot(emitter(.santaCane, c: 4, v: 2.4), 0)
        XCTAssertEqual(kinds(out), [.candy: 4])
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.hookScript })
        var b = out[0]
        let a0 = atan2(b.vy, b.vx)
        for _ in 0..<Int(0.6 / dt) { _ = b.advanceBossScript(dt: dt, playerX: 180, playerY: 500) }
        XCTAssertEqual(atan2(b.vy, b.vx), a0, accuracy: 1e-9, "0.67 秒まではまっすぐ")
        for _ in 0..<Int(1.2 / dt) { _ = b.advanceBossScript(dt: dt, playerX: 180, playerY: 500) }
        var d = atan2(b.vy, b.vx) - a0
        while d > Double.pi { d -= 2 * Double.pi }
        while d < -Double.pi { d += 2 * Double.pi }
        XCTAssertEqual(abs(d), Double.pi, accuracy: 0.06, "半回転して、あとはまっすぐ")
        XCTAssertEqual((b.vx * b.vx + b.vy * b.vy).squareRoot(), 144, accuracy: 1e-6, "速さは変わらない")
        XCTAssertEqual(shot(emitter(.santaCane, c: 4), 6).count, 0, "6発撃ったら、5発ぶん休む")
        XCTAssertEqual(shot(emitter(.santaCane, c: 4), 11).count, 4)
        XCTAssertEqual(shot(emitter(.santaCane, c: 4), 0, awakened: true).count, 10, "覚醒は左右同時・1列多い")
        // 左右反転: 曲がる向きが逆になる
        var m = b; m.mirrorX()
        XCTAssertEqual(m.u0, -b.u0)
    }

    func testTreeIsATriangle() {
        let out = shot(emitter(.santaTree, c: 7, v: 1.5), 0, px: 180)
        XCTAssertEqual(kinds(out), [.star: 28, .gift: 3])
        let stars = out.filter { BulletLook.kind(of: $0.look) == .star }
        XCTAssertTrue(stars.allSatisfy { $0.y == -6 && $0.script == Bullet.holdScript })
        // 段ごとに 1 つずつ増え、0.25 秒おきに降る。星のあいだは 26px
        let rows = Dictionary(grouping: stars, by: { ($0.fuse * 1000).rounded() }).sorted { $0.key < $1.key }.map(\.value)
        XCTAssertEqual(rows.map(\.count), [1, 2, 3, 4, 5, 6, 7])
        let last = rows[6].map(\.x).sorted()
        XCTAssertEqual(last[1] - last[0], 26, accuracy: 1e-9)
        XCTAssertEqual(rows[0][0].x, 180, accuracy: 30.1, "先頭は自機の近く")
        XCTAssertEqual(kinds(shot(emitter(.santaTree, c: 7, v: 1.5), 0, awakened: true)), [.star: 56, .gift: 6], "覚醒はもう1本")
    }

    func testDeliveryDropsOneOnThePlayer() {
        let out = shot(emitter(.santaDelivery, c: 4, v: 4), 0, px: 123)
        XCTAssertEqual(kinds(out), [.gift: 4, .candy: 20])
        let boxes = out.filter { BulletLook.kind(of: $0.look) == .gift }
        XCTAssertEqual(boxes[0].x, 123, "1つは必ず自機の真上")
        // 箱は 0.57 秒の予告のあと落ち始め、下(H-40)で消える。キャンディは、そこで待っていて、上へ扇に飛ぶ
        XCTAssertEqual(boxes[0].fuse, 34.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(boxes[0].u3, (DanmakuConfig.height - 40 + 6) / 240, accuracy: 1e-9)
        let candies = out.filter { BulletLook.kind(of: $0.look) == .candy }
        XCTAssertTrue(candies.allSatisfy { $0.y == DanmakuConfig.height - 40 && $0.gravity > 0 && sin($0.u1) < 0 }, "上向きに出て、少しずつ落ちる")
        XCTAssertEqual(candies[0].fuse, boxes[0].fuse + boxes[0].u3, accuracy: 1e-9)
        XCTAssertTrue(candies[0].dormantGlow, "落ちる場所が、開く前から光って分かる")
        XCTAssertEqual(kinds(shot(emitter(.santaDelivery, c: 4, v: 4), 0, awakened: true)), [.gift: 6, .candy: 42])
        XCTAssertEqual(shot(emitter(.santaDelivery, c: 4, v: 4), 4).count, 0, "4回撃ったら休む")
    }
}
