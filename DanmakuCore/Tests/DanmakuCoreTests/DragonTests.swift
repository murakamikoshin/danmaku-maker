import XCTest
@testable import DanmakuCore

final class DragonTests: XCTestCase {
    private func stage(_ moves: [DanmakuCore.Pattern], forms: [Int]? = nil, lives: Int = 3, i: Double = 1, mode: DanmakuCore.Mode = .boss) -> Stage {
        var s = Stage(name: "dragon", mode: mode, durationSec: 120, bossHp: 99_999,
                      emitters: moves.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 120, i: i, c: 1, v: 1, r: 0, k: 0) },
                      lifeMode: .lives, lifeCount: lives, bossLook: BossCharacter.dragon.rawValue)
        s.forms = forms
        return s.sanitized()
    }

    /// 技が始まって、終わるまで(休みのあと待機に戻るまで)進める。最大 steps ステップ
    private func runMove(_ p: DanmakuCore.Pattern, lv: Int, invincible: Bool = true, steps: Int = 120 * 40,
                         each: (inout Simulation) -> Void = { _ in }) -> (sim: Simulation, sawZone: Bool, maxBullets: Int, finished: Bool) {
        var sim = Simulation(stage: stage([p], forms: [lv, lv, lv]))
        sim.invincible = invincible
        var sawZone = false, maxB = 0, started = false, finished = false
        for _ in 0..<steps {
            sim.step(.zero)
            each(&sim)
            if sim.outcome != .playing { break }
            if sim.dragon.stage == .attack { started = true }
            sawZone = sawZone || !sim.dragon.zones.isEmpty
            maxB = max(maxB, sim.bullets.count)
            if started && sim.dragon.stage == .rest { finished = true; break }
        }
        return (sim, sawZone, maxB, finished)
    }

    func testTicketCostMatchesServer() {
        // サーバーの TICKET_COST(dragon: 3)と同じ。ほかのボスは 1 枚
        XCTAssertEqual(BossCharacter.dragon.ticketCost, 3)
        for b in BossCharacter.allCases where b != .dragon { XCTAssertEqual(b.ticketCost, 1) }
    }

    /// カットインを出さない設定(1.4.0): 竜王だけに付く。見た目だけで、計算には関わらない
    func testCutInSwitchIsDragonOnlyAndDecorOnly() {
        let em = [Emitter(t: Pattern.dragon[0], x: 0.5, y: 0.2, s: 0, e: 60, i: 3, c: 1, v: 1, r: 0, k: 0)]
        var d = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: BossCharacter.dragon.rawValue)
        d.noCutIn = true
        let s = d.sanitized()
        XCTAssertEqual(s.noCutIn, true)
        XCTAssertTrue(s.hidesDragonCutIn(forWave: 0))
        var plain = d; plain.noCutIn = nil
        XCTAssertFalse(plain.sanitized().hidesDragonCutIn(forWave: 0))
        XCTAssertEqual(Simulation.run(stage: s, moves: []), Simulation.run(stage: plain.sanitized(), moves: []))
        XCTAssertEqual(s.seed, plain.sanitized().seed)
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.noCutIn, true)
        var other = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: [Emitter(t: .ring)], bossLook: BossCharacter.hire.rawValue)
        other.noCutIn = true
        XCTAssertNil(other.sanitized().noCutIn, "竜王だけ")
    }

    func testOnlyTheDragonCanUseDragonMovesAndFormsAreSanitized() {
        let em = Pattern.dragon.map { Emitter(t: $0, x: 0.5, y: 0.2, s: 0, e: 60, i: 3, c: 1, v: 1, r: 0, k: 0) }
        var other = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: BossCharacter.hire.rawValue)
        other.forms = [1, 2, 3]
        let o = other.sanitized()
        XCTAssertFalse(o.emitters.contains { $0.t.dragonMove != nil }, "竜王でないボスには置けない")
        XCTAssertNil(o.forms, "姿は竜王だけ")
        var d = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 300, emitters: em, bossLook: BossCharacter.dragon.rawValue)
        d.forms = [0, 9, -2, 1, 1]
        d.awaken = 2
        let s = d.sanitized()
        XCTAssertEqual(s.emitters.map(\.t), Pattern.dragon.prefix(DanmakuConfig.maxEmitters).map { $0 })
        XCTAssertEqual(s.forms, [0, 3, 0], "段階の数(3)にそろえ、0〜3 に収める")
        XCTAssertNil(s.awaken, "竜王は覚醒の代わりに姿を選ぶ")
        d.forms = [0, 0, 0]
        XCTAssertNil(d.sanitized().forms, "全部通常なら保存しない")
        XCTAssertEqual(Pattern.dragon.map(\.bossCharacter), Array(repeating: .dragon, count: 10))
        XCTAssertEqual(BossCharacter.maxLook, 14)   // 14 はサンタ娘(1.5.0)
        XCTAssertEqual(BossCharacter.dragon.productKey, "dragon")
        // 保存して読み直しても、姿は残る
        let data = try! JSONEncoder().encode(s)
        XCTAssertEqual(try! JSONDecoder().decode(Stage.self, from: data).forms, [0, 3, 0])
    }

    func testEveryMoveRunsToTheEndInEveryForm() {
        for p in Pattern.dragon {
            for lv in 0...3 {
                let r = runMove(p, lv: lv)
                XCTAssertTrue(r.finished, "\(p) lv\(lv) が終わらない")
                XCTAssertTrue(r.sawZone || r.maxBullets > 0, "\(p) lv\(lv) で何も起きない")
                XCTAssertEqual(r.sim.dragon.lv, lv)
                XCTAssertEqual(r.sim.dragon.boff, Point(x: 0, y: 0), "\(p): 技が終わったら、本体は元の位置")
                XCTAssertEqual(r.sim.dragon.wind, Point(x: 0, y: 0))
                XCTAssertEqual(r.sim.dragon.pull, 0)
                XCTAssertFalse(r.sim.dragon.absorbing)
            }
        }
    }

    func testMovesThatShouldUseZonesDoSo() {
        for p: DanmakuCore.Pattern in [.dragonBreath, .dragonRaid, .dragonInhale, .dragonGlide, .dragonRoar, .dragonQuake, .dragonTail, .dragonEnd] {
            XCTAssertTrue(runMove(p, lv: 0).sawZone, "\(p) は範囲攻撃を使う")
        }
    }

    func testStrongerFormsLastLongerOrHitHarder() {
        // 覚醒が進むほど、技の数が増える(例: 強襲の回数、地割れの回数)
        for p: DanmakuCore.Pattern in [.dragonRaid, .dragonQuake, .dragonRoar] {
            let weak: Int = runMove(p, lv: 0).sim.dragon.frame
            let strong: Int = runMove(p, lv: 3).sim.dragon.frame
            XCTAssertLessThan(weak, strong, "\(p)")
        }
    }

    func testSameInputGivesSameResult() {
        let s = stage(Pattern.dragon, forms: [0, 2, 3], i: 0.5)
        var moves: [Move] = []
        for k in 0..<(120 * 50) {
            let dx: Int = (k / 37) % 5 - 2, dy: Int = (k / 53) % 5 - 2
            moves.append(Move(dx: Int8(dx), dy: Int8(dy)))
        }
        let a = Simulation.run(stage: s, moves: moves)
        let b = Simulation.run(stage: s, moves: moves)
        XCTAssertEqual(a, b)
    }

    func testBindIgnoresInput() {
        var sim = Simulation(stage: stage([.dragonRoar]))
        for _ in 0..<(120 * 3) { sim.step(.zero) }
        let x0 = sim.player.x
        sim.dragon.bind = 30
        sim.step(Move(dx: 8, dy: 0))
        XCTAssertEqual(sim.player.x, x0, "動けない")
        sim.dragon.bind = 0
        sim.step(Move(dx: 8, dy: 0))
        XCTAssertGreaterThan(sim.player.x, x0)
    }

    func testMegidoKillsOutsideTheSafeRingEvenWithLivesLeft() {
        let r = runMove(.dragonEnd, lv: 0, invincible: false)
        XCTAssertEqual(r.sim.outcome, .hit, "止まったままだと、輪の外で焼かれる")
        XCTAssertEqual(r.sim.lifeLeft, 0, "即死(ライフが残っていても)")
    }

    func testMegidoSafeRingIsReachable() {
        // 輪は「予告のあいだに走れば届く」所に出る。輪へまっすぐ走れば助かる
        var sim = Simulation(stage: stage([.dragonEnd], lives: 1))
        var survivedBurn = false
        for _ in 0..<(120 * 30) {
            var mv = Move.zero
            if let z = sim.dragon.zones.first(where: { $0.shape == .safe }), let c = z.safe.first {
                let ex = Simulation.safeEnd(c, warn: max(0, z.warn - z.t - 1))
                let dx = ex - sim.player.x, dy = c.y - sim.player.y
                let mx: Double = max(-8, min(8, dx * 2)), my: Double = max(-8, min(8, dy * 2))
                mv = Move(dx: Int8(mx), dy: Int8(my))
                if z.t > z.warn { survivedBurn = true }
            }
            sim.step(mv)
            if sim.outcome != .playing { break }
            if sim.dragon.stage == .rest { break }
        }
        XCTAssertEqual(sim.outcome, .playing, "輪へ走れば助かる")
        XCTAssertTrue(survivedBurn)
    }

    func testInhaleEatsPlayerShotsAndShootsThemBack() {
        var ate = 0, shotBack = false
        _ = runMove(.dragonInhale, lv: 0) { sim in
            ate = max(ate, sim.dragon.eaten)
            if sim.bullets.contains(where: { BulletLook.kind(of: $0.look) == .pshot }) { shotBack = true }
        }
        XCTAssertGreaterThan(ate, 5, "吸い込みの間、自機の弾は食べられる")
        XCTAssertTrue(shotBack, "食べた弾を撃ち返す")
    }

    func testRaidMovesTheBodyTowardThePlayerAndBack() {
        var farthest = 0.0
        let r = runMove(.dragonRaid, lv: 0) { sim in farthest = max(farthest, sim.dragon.boff.y) }
        XCTAssertGreaterThan(farthest, 100, "本体が自機のほうへ飛んでくる")
        XCTAssertEqual(r.sim.dragon.boff, Point(x: 0, y: 0))
    }

    func testGaleWindPushesThePlayer() {
        var moved = false
        _ = runMove(.dragonGale, lv: 1) { sim in if abs(sim.player.x - 180) > 20 { moved = true } }
        XCTAssertTrue(moved, "風で流される")
    }

    func testPhaseChangeStopsTheMove() {
        var sim = Simulation(stage: stage([.dragonRampage], forms: [0, 1, 2]))
        sim.invincible = true
        for _ in 0..<(120 * 4) { sim.step(.zero) }
        XCTAssertNotEqual(sim.dragon.boff, Point(x: 0, y: 0))
        sim.dragon.abort()
        XCTAssertEqual(sim.dragon.boff, Point(x: 0, y: 0))
        XCTAssertTrue(sim.dragon.zones.isEmpty)
        XCTAssertFalse(sim.dragon.busy)
    }

    func testDragonPersistentBulletsAreNotConsumed() {
        var b = Bullet(x: 0, y: 0, vx: 0, vy: 0, color: 0)
        b.script = Bullet.dragonTornadoScript
        XCTAssertTrue(b.dragonPersistent)
        b.script = Bullet.dragonPlainScript
        XCTAssertFalse(b.dragonPersistent)
        b.u3 = 1
        XCTAssertTrue(b.dragonPersistent)
    }

    /// 段階を増やして姿が足りないときは、直前の段階の姿を引き継ぐ(急に通常へ戻らない)
    func testFormsPadWithLastForm() {
        XCTAssertEqual(Wave.sanitizedForms([1, 3], phases: 4, look: BossCharacter.dragon.rawValue), [1, 3, 3, 3])
        XCTAssertEqual(Wave.sanitizedForms([2, 9, -1], phases: 2, look: BossCharacter.dragon.rawValue), [2, 3])
        XCTAssertNil(Wave.sanitizedForms([0], phases: 3, look: BossCharacter.dragon.rawValue))
        XCTAssertNil(Wave.sanitizedForms([1, 2], phases: 3, look: BossCharacter.kitsune.rawValue))
    }
}
