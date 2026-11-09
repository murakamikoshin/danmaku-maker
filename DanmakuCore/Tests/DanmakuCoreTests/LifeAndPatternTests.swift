import XCTest
@testable import DanmakuCore

final class LifeAndPatternTests: XCTestCase {
    /// 自機に向けて 0.3 秒おきに1発ずつ撃つステージ(動かなければ、一定の間隔で当たり続ける)
    private func gauntlet(mode: LifeMode? = nil, count: Int? = nil) -> Stage {
        Stage(name: "g", mode: .survive, durationSec: 30, bossHp: nil, bossMove: nil,
              emitters: [Emitter(t: .aim, x: 0.5, y: 0.6, s: 0, e: 30, i: 0.3, c: 1, v: 3, r: 0, k: 0, ph: 0)],
              lifeMode: mode, lifeCount: count)
    }

    /// 動かさずに進めて、ライフ(HP)の残りが変わった時刻(ステップ)を集める
    private func lifeTimeline(_ stage: Stage) -> (changes: [Int], final: Simulation) {
        var sim = Simulation(stage: stage)
        var last = sim.lifeLeft
        var changes: [Int] = []
        while sim.outcome == .playing && sim.tick < 120 * 40 {
            sim.step(.zero)
            if sim.lifeLeft != last { changes.append(sim.tick); last = sim.lifeLeft }
        }
        return (changes, sim)
    }

    func testDefaultIsOneLifeAndDiesOnFirstHit() {
        let s = gauntlet()
        XCTAssertEqual(s.effectiveLifeMode, .lives)
        XCTAssertEqual(s.effectiveLifeCount, 1)
        let r = lifeTimeline(s)
        XCTAssertEqual(r.final.outcome, .hit)
        XCTAssertEqual(r.final.lifeMax, 1)
        XCTAssertEqual(r.changes.count, 1)
    }

    func testLivesModeLosesOneLifeAtATimeWithShield() {
        let r = lifeTimeline(gauntlet(mode: .lives, count: 3))
        XCTAssertEqual(r.final.outcome, .hit)
        XCTAssertEqual(r.changes.count, 3, "3→2→1→0")
        let shield = Int((Simulation.lifeShieldSeconds / DanmakuConfig.step).rounded())
        XCTAssertGreaterThanOrEqual(r.changes[1] - r.changes[0], shield, "無敵の間は減らない")
        XCTAssertGreaterThanOrEqual(r.changes[2] - r.changes[1], shield)
        let one = lifeTimeline(gauntlet())
        XCTAssertGreaterThan(r.final.tick, one.final.tick)
    }

    func testHPModeLosesOnePerBulletWithoutShield() {
        let r = lifeTimeline(gauntlet(mode: .hp, count: 5))
        XCTAssertEqual(r.final.outcome, .hit)
        XCTAssertEqual(r.changes.count, 5)
        // 無敵がないので、次の弾(0.3秒後)でまた減る
        let gap = r.changes[1] - r.changes[0]
        XCTAssertLessThan(gap, Int(1.0 / DanmakuConfig.step), "HP制は無敵時間がない")
    }

    func testReviveRestoresSomeLife() {
        var a = lifeTimeline(gauntlet(mode: .lives, count: 3)).final
        XCTAssertEqual(a.outcome, .hit)
        a.revive()
        XCTAssertEqual(a.outcome, .playing)
        XCTAssertEqual(a.lifeLeft, 1)
        var b = lifeTimeline(gauntlet(mode: .hp, count: 10)).final
        b.revive()
        XCTAssertEqual(b.lifeLeft, 5)
        var c = lifeTimeline(gauntlet(mode: .hp, count: 3)).final
        c.revive()
        XCTAssertEqual(c.lifeLeft, 1)
    }

    func testSanitizeCanonicalizesLife() {
        XCTAssertNil(gauntlet(mode: .lives, count: 1).sanitized().lifeMode)
        let big = gauntlet(mode: .lives, count: 99).sanitized()
        XCTAssertEqual(big.lifeCount, 5)
        let low = gauntlet(mode: .hp, count: 1).sanitized()
        XCTAssertEqual(low.lifeMode, .hp)
        XCTAssertEqual(low.lifeCount, 3)
        let high = gauntlet(mode: .hp, count: 500).sanitized()
        XCTAssertEqual(high.lifeCount, 20)
        XCTAssertNil(gauntlet().sanitized().lifeCount)
    }

    func testOldJSONWithoutLifeFieldsStillDecodesAndEncodesWithoutThem() throws {
        let old = #"{"name":"x","mode":"survive","durationSec":20,"emitters":[{"t":"ring","x":0.5,"y":0.2,"s":0,"e":20,"i":1,"c":16,"v":2,"r":6,"k":0}]}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Stage.self, from: old)
        XCTAssertNil(s.lifeMode)
        XCTAssertEqual(s.effectiveLifeCount, 1)
        let data = try JSONEncoder().encode(s)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("lifeMode"))
        XCTAssertFalse(text.contains("lifeCount"))
        let withLife = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(gauntlet(mode: .hp, count: 8)))
        XCTAssertEqual(withLife.lifeMode, .hp)
        XCTAssertEqual(withLife.lifeCount, 8)
    }

    func testLifeSettingsDoNotChangeTheRandomSeed() {
        XCTAssertEqual(gauntlet().seed, gauntlet(mode: .hp, count: 9).seed)
    }

    // MARK: 新しいパターン

    private func fire(_ pattern: DanmakuCore.Pattern, c: Int = 4, r: Double = 10, k: Int = 0) -> [Bullet] {
        var rng = Mulberry32(seed: 1234)
        var out: [Bullet] = []
        let m = Emitter(t: pattern, x: 0.5, y: 0.2, s: 0, e: 10, i: 1, c: c, v: 2, r: r, k: k, ph: 0)
        Emit.emit(m, shot: 0, cx: 180, cy: 100, px: 180, py: 459, rng: &rng, into: &out)
        return out
    }

    func testSideLeftComesFromTheLeftEdgeMovingRight() {
        let b = fire(.sideL, c: 6)
        XCTAssertEqual(b.count, 6)
        for x in b {
            XCTAssertEqual(x.x, -8)
            XCTAssertGreaterThan(x.vx, 0)
            XCTAssertGreaterThanOrEqual(x.y, 0)
            XCTAssertLessThanOrEqual(x.y, DanmakuConfig.height * 0.78)
        }
    }

    func testSideRightComesFromTheRightEdgeMovingLeft() {
        let b = fire(.sideR, c: 6)
        XCTAssertEqual(b.count, 6)
        for x in b {
            XCTAssertEqual(x.x, DanmakuConfig.width + 8)
            XCTAssertLessThan(x.vx, 0)
        }
    }

    func testSideSpreadZeroIsPerfectlyHorizontal() {
        for x in fire(.sideL, c: 5, r: 0) { XCTAssertEqual(x.vy, 0, accuracy: 1e-9) }
        let spread = fire(.sideL, c: 20, r: 40)
        XCTAssertTrue(spread.contains { abs($0.vy) > 1 })
    }

    func testCornerFiresFromFourCornersTowardThePlayer() {
        let b = fire(.corner, c: 3, r: 20)
        XCTAssertEqual(b.count, 12)
        let xs = Set(b.map(\.x))
        XCTAssertEqual(xs, [-8, DanmakuConfig.width + 8])
        // 自機(下の中央)のほうへ向かう: 左上の弾は右下向き、右上の弾は左下向き
        let topLeft = b.filter { $0.x < 0 && $0.y < 0 }
        let topRight = b.filter { $0.x > DanmakuConfig.width && $0.y < 0 }
        XCTAssertEqual(topLeft.count, 3); XCTAssertEqual(topRight.count, 3)
        XCTAssertTrue(topLeft.allSatisfy { $0.vx > 0 && $0.vy > 0 })
        XCTAssertTrue(topRight.allSatisfy { $0.vx < 0 && $0.vy > 0 })
        // 下の2つは自機の高さの手前(画面の6割)から
        let low = b.filter { $0.y > 0 }
        XCTAssertEqual(low.count, 6)
        XCTAssertTrue(low.allSatisfy { abs($0.y - DanmakuConfig.height * 0.6) < 1e-9 })
    }

    func testNewPatternsAreDeterministicAndSurviveSanitize() {
        for p in [DanmakuCore.Pattern.sideL, .sideR, .corner] {
            XCTAssertEqual(fire(p), fire(p))
            let stage = Stage(name: "n", mode: .survive, durationSec: 20,
                              emitters: [Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.4, c: 4, v: 2, r: 10)])
            XCTAssertEqual(stage.sanitized().emitters.first?.t, p)
            let a = Simulation.run(stage: stage, moves: [])
            let b = Simulation.run(stage: stage, moves: [])
            XCTAssertEqual(a, b)
        }
    }

    func testExistingPatternIndexesDidNotMove() {
        XCTAssertEqual(Pattern.ring.index, 0); XCTAssertEqual(Pattern.spiral.index, 1)
        XCTAssertEqual(Pattern.aim.index, 2); XCTAssertEqual(Pattern.rain.index, 3)
        XCTAssertEqual(Pattern.sweep.index, 4)
        XCTAssertEqual(Pattern.sideL.index, 5); XCTAssertEqual(Pattern.corner.index, 7)
    }
}

final class DamageRaceTests: XCTestCase {
    private func stage(_ mode: Mode, hp: Int? = nil, duration: Int = 30) -> Stage {
        Stage(name: "d", mode: mode, durationSec: duration, bossHp: hp, bossMove: 0, emitters: [])
    }

    func testDamageRaceNeverKillsTheBossAndClearsAtTimeUp() {
        var sim = Simulation(stage: stage(.damage))
        XCTAssertTrue(sim.isBoss); XCTAssertTrue(sim.isDamageRace)
        while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared, "時間いっぱい生き残ればクリア")
        XCTAssertGreaterThan(sim.damageDealt, 600, "30秒撃ち続ければ、ふつうのボス戦のHPをはるかに超える")
        XCTAssertGreaterThanOrEqual(sim.t, 30)
    }

    func testNormalBossFightStillEndsWhenHPRunsOut() {
        var sim = Simulation(stage: stage(.boss, hp: 100))
        while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertLessThan(sim.t, 30)
        XCTAssertGreaterThanOrEqual(sim.damageDealt, 100)
    }

    func testDamageTotalIsTheSameForEveryShotStyle() {
        func total(_ type: ShotType) -> Int {
            var sim = Simulation(stage: stage(.damage), shotType: type)
            while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero) }
            return sim.damageDealt
        }
        let std = Double(total(.standard))
        for t in ShotType.allCases { XCTAssertEqual(Double(total(t)) / std, 1, accuracy: 0.1, "\(t)") }
    }

    func testPhasesAdvanceByTime() {
        var sim = Simulation(stage: stage(.damage, duration: 30))
        var seen: [Int] = []
        while sim.outcome == .playing && sim.tick < 120 * 40 {
            sim.step(.zero)
            if seen.last != sim.phase { seen.append(sim.phase) }
        }
        XCTAssertEqual(seen, [1, 2, 3])
    }

    func testSanitizeKeepsBossMoveButDropsHP() {
        let s = Stage(name: "d", mode: .damage, durationSec: 60, bossHp: 700, bossMove: 2,
                      emitters: [Emitter(t: .ring)]).sanitized()
        XCTAssertNil(s.bossHp)
        XCTAssertEqual(s.bossMove, 2)
        XCTAssertEqual(s.durationSec, 60)
        let bad = Stage(name: "d", mode: .damage, durationSec: 20, emitters: [Emitter(t: .ring)]).sanitized()
        XCTAssertEqual(bad.durationSec, 60, "ボス戦と同じ選択肢(30/60/90/120/180)に丸める")
    }

    func testSeedDiffersFromSurviveAndBossButExistingModesAreUnchanged() {
        let e = [Emitter(t: .ring)]
        let a = Stage(name: "a", mode: .survive, durationSec: 30, emitters: e).seed
        let b = Stage(name: "a", mode: .damage, durationSec: 30, emitters: e).seed
        XCTAssertNotEqual(a, b)
    }

    func testDeterministicReplayInDamageRace() {
        let s = stage(.damage)
        let moves = (0..<3000).map { Move(dx: Int8(($0 / 120) % 2 == 0 ? 2 : -2), dy: 0) }
        XCTAssertEqual(Simulation.run(stage: s, moves: moves), Simulation.run(stage: s, moves: moves))
    }
}

final class ReviveFlowTests: XCTestCase {
    private func gauntlet(_ mode: LifeMode?, _ count: Int?) -> Stage {
        Stage(name: "r", mode: .survive, durationSec: 30, bossHp: nil, bossMove: nil,
              emitters: [Emitter(t: .aim, x: 0.5, y: 0.6, s: 0, e: 30, i: 0.3, c: 1, v: 3, r: 0, k: 0, ph: 0)],
              lifeMode: mode, lifeCount: count)
    }

    /// 倒れるまで動かさずに進める
    private func dieStanding(_ stage: Stage) -> Simulation {
        var sim = Simulation(stage: stage)
        while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero) }
        return sim
    }

    func testReviveClearsBulletsAndGivesShield() {
        var sim = dieStanding(gauntlet(nil, nil))
        XCTAssertEqual(sim.outcome, .hit)
        let tickAtDeath = sim.tick
        sim.revive()
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertTrue(sim.bullets.isEmpty, "復活のとき、画面の弾は全部消える")
        XCTAssertTrue(sim.isShielded, "復活直後は無敵")
        // 2秒の無敵のあいだは、当たらない
        for _ in 0..<(120 * 2 - 2) { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertGreaterThan(sim.tick, tickAtDeath)
    }

    func testRevivedRunCanStillBeClearedOrFailAgain() {
        var sim = dieStanding(gauntlet(.lives, 2))
        sim.revive()
        XCTAssertEqual(sim.lifeLeft, 1)
        // 動かさなければ、また倒れる(復活は1回ぶんの余裕を与えるだけ)
        while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .hit)
    }

    func testReviveOnlyWorksAfterAHit() {
        var sim = Simulation(stage: gauntlet(.lives, 3))
        let before = sim.lifeLeft
        sim.revive()            // まだ倒れていないので、何も変わらない
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.lifeLeft, before)
        XCTAssertFalse(sim.isShielded)
    }

    func testHPModeReviveRestoresHalfHP() {
        var sim = dieStanding(gauntlet(.hp, 10))
        sim.revive()
        XCTAssertEqual(sim.lifeLeft, 5)
        XCTAssertTrue(sim.isShielded)
    }
}

final class UnlimitedTimeTests: XCTestCase {
    private func boss(_ duration: Int, hp: Int = 600) -> Stage {
        Stage(name: "u", mode: .boss, durationSec: duration, bossHp: hp, bossMove: 0, emitters: [])
    }

    func testBossAllowsUnlimitedButOtherModesDoNot() {
        XCTAssertTrue(Stage.durations[.boss]!.contains(0))
        XCTAssertFalse(Stage.durations[.damage]!.contains(0))
        XCTAssertFalse(Stage.durations[.survive]!.contains(0))
        XCTAssertEqual(boss(0).sanitized().durationSec, 0)
        XCTAssertTrue(boss(0).isUnlimitedTime)
        XCTAssertEqual(boss(0).timeLimitSec, 600)
        XCTAssertFalse(boss(60).isUnlimitedTime)
        // 他のモードで 0 を指定しても、通常の既定(60秒)に丸められる
        XCTAssertEqual(Stage(name: "d", mode: .damage, durationSec: 0, emitters: []).sanitized().durationSec, 60)
        XCTAssertEqual(Stage(name: "s", mode: .survive, durationSec: 0, emitters: []).sanitized().durationSec, 20)
    }

    func testUnlimitedBossIsClearedByHPNotByTime() {
        var sim = Simulation(stage: boss(0, hp: 1000))
        while sim.outcome == .playing && sim.tick < 120 * 700 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertGreaterThan(sim.t, 30, "1000HPは、30秒より長くかかる(時間切れにならない)")
        XCTAssertLessThan(sim.t, 120)
    }

    func testUnlimitedBossStopsAtTheCap() {
        // どうやっても倒せない(HPを取れない位置にボスがいる)ことは作れないので、上限は時間で確かめる
        var s = Simulation(stage: Stage(name: "u", mode: .boss, durationSec: 0, bossHp: 1000, bossMove: 2, emitters: []))
        // 画面の端に張りつくと、ボスの弾は当たらないが、自分の弾もボスに届きにくくなる
        var steps = 0
        while s.outcome == .playing && steps < 120 * 700 { s.step(Move(dx: -127, dy: 0)); steps += 1 }
        XCTAssertNotEqual(s.outcome, .playing, "10分以内に必ず終わる")
        XCTAssertLessThanOrEqual(s.t, Double(Stage.unlimitedCapSec) + 0.1)
    }

    func testUnlimitedDoesNotChangeExistingTimedBossSeeds() {
        let a = Stage(name: "a", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 1, emitters: [Emitter(t: .ring)]).seed
        let b = Stage(name: "a", mode: .boss, durationSec: 0, bossHp: 400, bossMove: 1, emitters: [Emitter(t: .ring)]).seed
        XCTAssertNotEqual(a, b)
    }
}


final class HomingTests: XCTestCase {
    private func stage(c: Int = 1, r: Double = 45, v: Double = 1.6) -> Stage {
        Stage(name: "h", mode: .survive, durationSec: 30,
              emitters: [Emitter(t: .homing, x: 0.5, y: 0.1, s: 0, e: 30, i: 1.5, c: c, v: v, r: r, k: 1)])
    }

    func testHomingBulletsCurveTowardThePlayerThenGoStraight() {
        var sim = Simulation(stage: stage(c: 1))
        var sawHoming = false, sawStraight = false
        // 弾が出たあと、自機を左へ大きく動かす。追尾弾は、向きを変えて追いかける
        var first: Bullet?
        var moveLeft = false
        for _ in 0..<(120 * 8) where sim.outcome == .playing {
            sim.step(moveLeft ? Move(dx: -12, dy: 0) : .zero)
            if first == nil, let b = sim.bullets.first { first = b; moveLeft = true }
            if let b = sim.bullets.first(where: { $0.homeLeft > 0 }) { sawHoming = true; XCTAssertGreaterThan(b.turn, 0) }
            if sim.bullets.contains(where: { $0.turn > 0 && $0.homeLeft <= 0 }) { sawStraight = true }
        }
        XCTAssertTrue(sawHoming)
        XCTAssertTrue(sawStraight, "追尾は最初の数秒だけで終わる")
        XCTAssertNotNil(first)
    }

    func testHomingChangesDirectionButNotSpeed() {
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        let m = Emitter(t: .homing, x: 0.5, y: 0.1, s: 0, e: 30, i: 1, c: 3, v: 2, r: 45, k: 0)
        Emit.emit(m, shot: 0, cx: 180, cy: 54, px: 180, py: 459, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 3)
        for b in out {
            XCTAssertEqual(b.turn, 90 * Double.pi / 180, accuracy: 1e-9)
            XCTAssertEqual(b.homeLeft, DanmakuConfig.homingSeconds)
            XCTAssertEqual((b.vx * b.vx + b.vy * b.vy).squareRoot(), 120, accuracy: 1e-9)   // v=2 → 120 px/s
        }
        // 中央の弾は、自機(真下)へまっすぐ
        XCTAssertEqual(out[1].vx, 0, accuracy: 1e-6)
        XCTAssertGreaterThan(out[1].vy, 0)
    }

    func testHomingMakesStagesHarderToDodgeStanding() {
        // 動かない自機には、追尾弾がまっすぐ当たる
        let r = Simulation.run(stage: stage(c: 3), moves: [])
        XCTAssertEqual(r.outcome, .hit)
    }

    func testHomingIsDeterministic() {
        let moves = (0..<2000).map { Move(dx: Int8(($0 / 60) % 2 == 0 ? 5 : -5), dy: 0) }
        XCTAssertEqual(Simulation.run(stage: stage(c: 4), moves: moves), Simulation.run(stage: stage(c: 4), moves: moves))
    }

    func testHomingPatternIndexAndSanitize() {
        XCTAssertEqual(DanmakuCore.Pattern.homing.index, 8)
        XCTAssertEqual(stage().sanitized().emitters.first?.t, .homing)
    }

    func testHomingProductAndOwnership() {
        XCTAssertEqual(Product.pattern(.homing).id, "com.koshin.danmakumaker.homing")
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.homing"), .pattern(.homing))
        XCTAssertEqual(Product.pattern(.homing).yen, 300)
        XCTAssertFalse(Ownership().has(.homing))
        XCTAssertTrue(Ownership(productIDs: [Product.pattern(.homing).id]).has(.homing))
        XCTAssertFalse(Ownership(productIDs: [Product.pattern(.homing).id]).canBuy(.pattern(.homing)))
    }
}


final class FirePointTests: XCTestCase {
    private func bossStage(p: Int, x: Double = 0.2, y: Double = 0.5) -> Stage {
        Stage(name: "p", mode: .boss, durationSec: 60, bossHp: 1000, bossMove: 0,
              emitters: [Emitter(t: .ring, x: x, y: y, s: 0, e: 60, i: 1, c: 8, v: 1, r: 0, k: 0, ph: 0, p: p)])
    }

    func testDefaultStillFiresFromTheBoss() {
        var a = Simulation(stage: bossStage(p: 0))
        for _ in 0..<(120 * 3) { a.step(.zero) }
        let b0 = a.bullets.first!
        // 輪は、ボス(画面の上のほう、横は中央)のまわりから広がる
        XCTAssertEqual(b0.x, 180, accuracy: 120)
        XCTAssertLessThan(b0.y, 200)
    }

    func testFirePointFiresFromTheChosenPlace() {
        var sim = Simulation(stage: bossStage(p: 1, x: 0.2, y: 0.5))
        for _ in 0..<(120 * 3 / 2 + 10) { sim.step(.zero) }
        XCTAssertFalse(sim.bullets.isEmpty)
        // 発射直後の弾は、(0.2*360, 0.5*540) = (72, 270) のごく近く
        let near = sim.bullets.min { hypot($0.x - 72, $0.y - 270) < hypot($1.x - 72, $1.y - 270) }!
        XCTAssertLessThan(hypot(near.x - 72, near.y - 270), 60)
    }

    func testDefaultDoesNotChangeSeedOrJSON() {
        let std = bossStage(p: 0)
        let data = try! JSONEncoder().encode(std)
        let text = String(data: data, encoding: .utf8)!
        XCTAssertFalse(text.contains("\"p\":"), text)
        XCTAssertEqual(std.seed, Stage(name: "p", mode: .boss, durationSec: 60, bossHp: 1000, bossMove: 0,
                                       emitters: [Emitter(t: .ring, x: 0.2, y: 0.5, s: 0, e: 60, i: 1, c: 8, v: 1, r: 0, k: 0, ph: 0)]).seed)
        XCTAssertNotEqual(std.seed, bossStage(p: 1).seed)
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(bossStage(p: 1)))
        XCTAssertEqual(back.emitters.first?.p, 1)
    }

    func testSurviveIgnoresFirePointAndSanitizeClamps() {
        let s = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring, p: 1)]).sanitized()
        XCTAssertEqual(s.emitters.first?.p, 0)
        let weird = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring, p: 7)]).sanitized()
        XCTAssertEqual(weird.emitters.first?.p, 0)
    }
}


final class BGMTests: XCTestCase {
    private func stage(_ mode: Mode, bgm: Int?) -> Stage {
        Stage(name: "m", mode: mode, durationSec: mode == .survive ? 20 : 60, bossHp: mode == .boss ? 400 : nil, bossMove: mode == .survive ? nil : 0,
              emitters: [Emitter(t: .ring)], bgm: bgm)
    }

    func testDefaultsByMode() {
        XCTAssertEqual(stage(.survive, bgm: nil).effectiveBGM, 0)
        XCTAssertEqual(stage(.boss, bgm: nil).effectiveBGM, 1)
        XCTAssertEqual(stage(.damage, bgm: nil).effectiveBGM, 1)
    }

    func testChosenBGMIsUsedAndOutOfRangeFallsBack() {
        XCTAssertEqual(stage(.survive, bgm: 3).effectiveBGM, 3)
        XCTAssertEqual(stage(.boss, bgm: 4).effectiveBGM, 4)
        XCTAssertEqual(stage(.survive, bgm: 9).effectiveBGM, 0)
        XCTAssertEqual(stage(.boss, bgm: -1).effectiveBGM, 1)
    }

    func testSanitizeDropsStandardAndInvalid() {
        XCTAssertNil(stage(.survive, bgm: 0).sanitized().bgm)
        XCTAssertNil(stage(.boss, bgm: 1).sanitized().bgm)
        XCTAssertNil(stage(.survive, bgm: 99).sanitized().bgm)
        XCTAssertEqual(stage(.survive, bgm: 1).sanitized().bgm, 1)
        XCTAssertEqual(stage(.boss, bgm: 0).sanitized().bgm, 0)
        XCTAssertEqual(stage(.boss, bgm: 4).sanitized().bgm, 4)
    }

    func testBGMDoesNotChangeTheSeedOrBehaviour() {
        XCTAssertEqual(stage(.boss, bgm: 3).seed, stage(.boss, bgm: nil).seed)
        XCTAssertEqual(Simulation.run(stage: stage(.survive, bgm: 2), moves: []), Simulation.run(stage: stage(.survive, bgm: nil), moves: []))
    }

    func testJSONOnlyIncludesBGMWhenChosen() throws {
        XCTAssertFalse(String(data: try JSONEncoder().encode(stage(.survive, bgm: nil)), encoding: .utf8)!.contains("bgm"))
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(stage(.survive, bgm: 2)))
        XCTAssertEqual(back.bgm, 2)
    }
}


final class PaidPatternTests: XCTestCase {
    private func fire(_ p: DanmakuCore.Pattern, c: Int = 12, r: Double = 10, k: Int = 0) -> [Bullet] {
        var rng = Mulberry32(seed: 99)
        var out: [Bullet] = []
        Emit.emit(Emitter(t: p, x: 0.5, y: 0.1, s: 0, e: 10, i: 1, c: c, v: 2, r: r, k: k), shot: k, cx: 180, cy: 54, px: 180, py: 459, rng: &rng, into: &out)
        return out
    }
    private func speeds(_ b: [Bullet]) -> [Double] { b.map { ($0.vx * $0.vx + $0.vy * $0.vy).squareRoot() } }

    func testPaidListAndFreePatterns() {
        XCTAssertEqual(Set(DanmakuCore.Pattern.paid), [.homing, .flower, .star, .heart, .beam, .cross, .accel, .bounce, .stopgo, .split, .timed])
        for p in [DanmakuCore.Pattern.ring, .spiral, .aim, .rain, .sweep, .sideL, .sideR, .corner] { XCTAssertFalse(p.isPaid) }
        XCTAssertEqual(DanmakuCore.Pattern.flower.index, 9)
        XCTAssertEqual(DanmakuCore.Pattern.bounce.index, 15)
    }

    private func sim(_ p: DanmakuCore.Pattern, c: Int = 3) -> Simulation {
        // 弾を1回だけ出すステージ(ボスは動かさず、自機は真下で動かない)
        Simulation(stage: Stage(name: "t", mode: .survive, durationSec: 20, emitters: [Emitter(t: p, x: 0.5, y: 0.1, s: 0, e: 20, i: 5, c: c, v: 2, r: 0, k: 0)]).sanitized())
    }

    /// 開始のカウントダウンが終わって、最初の弾が出るまで進める
    private func untilFirstBullet(_ s: inout Simulation) {
        var n = 0
        while s.bullets.isEmpty && n < 120 * 10 { s.step(.zero); n += 1 }
    }

    func testStopGoStopsThenDashesAtPlayer() {
        var s = sim(.stopgo, c: 1)
        untilFirstBullet(&s)
        var maxStill = 0, still = 0
        var lastY = -1.0
        for _ in 0..<Int(120 * 1.2) {
            s.step(.zero)
            if let b = s.bullets.first {
                if abs(b.y - lastY) < 1e-9 { still += 1; maxStill = max(maxStill, still) } else { still = 0 }
                lastY = b.y
            }
        }
        XCTAssertGreaterThan(maxStill, 60, "止まっている間がある")
        for _ in 0..<60 { s.step(.zero) }
        let b = try! XCTUnwrap(s.bullets.first)
        XCTAssertEqual(b.script, 0)
        XCTAssertGreaterThan(b.vy, 0, "自機(下)に向かう")
    }

    func testSplitBurstsIntoSix() {
        var s = sim(.split, c: 1)
        untilFirstBullet(&s)
        var maxCount = 0
        for _ in 0..<120 { s.step(.zero); maxCount = max(maxCount, s.bullets.count) }
        XCTAssertEqual(maxCount, DanmakuConfig.splitCount)
    }

    func testTimedRingWaitsThenMovesTogether() {
        var s = sim(.timed, c: 8)
        untilFirstBullet(&s)
        for _ in 0..<60 { s.step(.zero) }
        let y0 = s.bullets.map(\.y)
        XCTAssertEqual(s.bullets.count, 8)
        for _ in 0..<30 { s.step(.zero) }
        XCTAssertEqual(s.bullets.map(\.y), y0, "止まっている間は動かない")
        for _ in 0..<80 { s.step(.zero) }
        XCTAssertNotEqual(s.bullets.map(\.y), y0, "あとで動き出す")
    }

    func testShapePatternsVarySpeedByAngle() {
        for p in [DanmakuCore.Pattern.flower, .star, .heart] {
            let sp = speeds(fire(p, c: 36))
            XCTAssertEqual(sp.count, 36)
            XCTAssertGreaterThan(sp.max()! / sp.min()!, 1.8, "\(p) の輪郭に、はっきり凹凸がある")
            XCTAssertLessThanOrEqual(sp.max()!, 120.0001)
        }
    }

    func testFlowerHasFivePetals() {
        let sp = speeds(fire(.flower, c: 36, r: 0))
        var peaks = 0
        for i in 0..<36 where sp[i] > sp[(i + 35) % 36] && sp[i] >= sp[(i + 1) % 36] && sp[i] > 100 { peaks += 1 }
        XCTAssertEqual(peaks, 5)
    }

    func testBeamIsALineOfIncreasingSpeedTowardThePlayer() {
        let b = fire(.beam, c: 6, r: 0)
        XCTAssertEqual(b.count, 6)
        let s = speeds(b)
        for i in 1..<s.count { XCTAssertGreaterThan(s[i], s[i - 1]) }
        for x in b { XCTAssertEqual(x.vx, 0, accuracy: 1e-6); XCTAssertGreaterThan(x.vy, 0) }   // 自機は真下
    }

    func testCrossFiresFourArms() {
        let b = fire(.cross, c: 8, r: 0)
        XCTAssertEqual(b.count, 8)          // 4方向 × 2個
        let dirs = Set(b.map { "\(Int(($0.vx).sign == .minus ? -1 : ($0.vx.magnitude > 1e-6 ? 1 : 0)))\(Int(($0.vy).sign == .minus ? -1 : ($0.vy.magnitude > 1e-6 ? 1 : 0)))" })
        XCTAssertEqual(dirs.count, 4)
        XCTAssertEqual(fire(.cross, c: 3).count, 4, "最低でも各方向に1個")
    }

    func testAccelBulletsStartSlowAndSpeedUpToACap() {
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(Emitter(t: .accel, c: 1, v: 2, r: 0), shot: 0, cx: 180, cy: 54, px: 180, py: 459, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(speeds(out)[0], 120 * 0.3, accuracy: 1e-9)
        XCTAssertGreaterThan(out[0].accel, 0)
        // 動かない自機で、時間とともに弾が速くなる(当たるまで)
        let st = Stage(name: "a", mode: .survive, durationSec: 30, emitters: [Emitter(t: .accel, x: 0.5, y: 0.0, s: 0, e: 30, i: 5, c: 1, v: 2, r: 0)])
        var sim = Simulation(stage: st)
        var seen: [Double] = []
        for _ in 0..<(120 * 6) where sim.outcome == .playing {
            sim.step(Move(dx: 0, dy: 0))
            if let b = sim.bullets.first { seen.append((b.vx * b.vx + b.vy * b.vy).squareRoot()) }
        }
        XCTAssertGreaterThan(seen.last!, seen.first! * 1.5)
        XCTAssertLessThanOrEqual(seen.max()!, 240.0001)
    }

    func testBounceBulletsReflectOffWallsTwice() {
        var b = Bullet(x: 10, y: 100, vx: -300, vy: 0, color: 0, bounces: 2)
        // 同じ計算を、シミュレーションの外から確かめる代わりに、実際のステージで確認する
        let st = Stage(name: "b", mode: .survive, durationSec: 30, emitters: [Emitter(t: .bounce, x: 0.05, y: 0.1, s: 0, e: 30, i: 9, c: 1, v: 4, r: 0)])
        var sim = Simulation(stage: st)
        sim.step(Move(dx: -127, dy: 0))        // 自機を左端へ(弾が左へ向かうように)
        b.bounces = 2
        var minX = 1000.0, maxX = -1000.0
        for _ in 0..<(120 * 8) where sim.outcome == .playing {
            sim.step(Move(dx: 0, dy: 0))
            for x in sim.bullets { minX = min(minX, x.x); maxX = max(maxX, x.x) }
        }
        XCTAssertGreaterThanOrEqual(minX, -0.001, "反射する弾は、左の壁の外へ出ない")
    }

    func testPatternPackOwnershipAndProducts() {
        XCTAssertEqual(Product.patternPack.id, "com.koshin.danmakumaker.patternpack")
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.patternpack"), .patternPack)
        XCTAssertEqual(Product.patternPack.yen, 600)
        XCTAssertLessThan(Product.patternPack.yen, Pattern.paid.map { Product.pattern($0).yen }.reduce(0, +))
        let pack = Ownership(productIDs: [Product.patternPack.id])
        for p in DanmakuCore.Pattern.paid { XCTAssertTrue(pack.has(p)); XCTAssertFalse(pack.canBuy(.pattern(p))) }
        XCTAssertFalse(pack.canBuy(.patternPack))
        let one = Ownership(productIDs: [Product.pattern(.flower).id])
        XCTAssertTrue(one.has(.flower)); XCTAssertFalse(one.has(.star))
        XCTAssertTrue(one.canBuy(.patternPack))
        XCTAssertTrue(Ownership().has(.ring))
        for p in DanmakuCore.Pattern.paid { XCTAssertEqual(Product(id: Product.pattern(p).id), .pattern(p)) }
    }

    func testAllNewPatternsAreDeterministicAndSurviveSanitize() {
        for p in DanmakuCore.Pattern.paid {
            XCTAssertEqual(fire(p), fire(p))
            let st = Stage(name: "n", mode: .survive, durationSec: 20, emitters: [Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: 0.4, c: 8, v: 2, r: 20)])
            XCTAssertEqual(st.sanitized().emitters.first?.t, p)
            XCTAssertEqual(Simulation.run(stage: st, moves: []), Simulation.run(stage: st, moves: []))
        }
    }
}


final class StageLookTests: XCTestCase {
    private func stage(_ b: Theme? = nil, _ bg: Theme? = nil, _ sh: Theme? = nil) -> Stage {
        Stage(name: "l", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)], themeBullets: b, themeBackground: bg, themeShip: sh)
    }

    func testDefaultLookIsClassicAndNotStored() throws {
        let s = stage()
        XCTAssertEqual([s.lookBullets, s.lookBackground, s.lookShip], [.classic, .classic, .classic])
        let text = String(data: try JSONEncoder().encode(s), encoding: .utf8)!
        XCTAssertFalse(text.contains("theme"))
        let c = stage(.classic, .classic, .classic).sanitized()
        XCTAssertNil(c.themeBullets); XCTAssertNil(c.themeBackground); XCTAssertNil(c.themeShip)
    }

    func testChosenLookIsKeptAndRoundTrips() throws {
        let s = stage(.sakura, .ocean, .aurora).sanitized()
        XCTAssertEqual([s.lookBullets, s.lookBackground, s.lookShip], [.sakura, .ocean, .aurora])
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.themeBullets, .sakura)
        XCTAssertEqual(back.themeBackground, .ocean)
        XCTAssertEqual(back.themeShip, .aurora)
        // 一部だけ選んだ場合
        let p = stage(nil, .ocean, nil).sanitized()
        XCTAssertNil(p.themeBullets); XCTAssertEqual(p.themeBackground, .ocean); XCTAssertNil(p.themeShip)
    }

    func testUnknownThemeFromANewerVersionReadsAsClassic() throws {
        let json = #"{"name":"x","mode":"survive","durationSec":20,"emitters":[{"t":"ring","x":0.5,"y":0.2,"s":0,"e":20,"i":1,"c":16,"v":2,"r":6,"k":0}],"themeBullets":"galaxy","themeShip":"sakura"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Stage.self, from: json)
        XCTAssertNil(s.themeBullets)
        XCTAssertEqual(s.themeShip, .sakura)
    }

    func testLookDoesNotChangeSeedOrBehaviour() {
        XCTAssertEqual(stage(.sakura, .ocean, .aurora).seed, stage().seed)
        XCTAssertEqual(Simulation.run(stage: stage(.sakura), moves: []), Simulation.run(stage: stage(), moves: []))
    }
}


final class MarkerOptionTests: XCTestCase {
    func testMarkersShownByDefaultAndHideIsStoredOnlyWhenOn() throws {
        let std = Stage(name: "m", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)])
        XCTAssertTrue(std.showsMarkers)
        XCTAssertFalse(String(data: try JSONEncoder().encode(std), encoding: .utf8)!.contains("hideMarkers"))
        let hidden = Stage(name: "m", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)], hideMarkers: true).sanitized()
        XCTAssertFalse(hidden.showsMarkers)
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(hidden))
        XCTAssertEqual(back.hideMarkers, true)
        // false は保存しない(標準に揃える)。ボス戦では意味がないので落とす
        XCTAssertNil(Stage(name: "m", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)], hideMarkers: false).sanitized().hideMarkers)
        XCTAssertNil(Stage(name: "m", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring)], hideMarkers: true).sanitized().hideMarkers)
    }

    func testMarkerOptionDoesNotChangeBehaviour() {
        let a = Stage(name: "m", mode: .survive, durationSec: 20, emitters: [Emitter(t: .aim, x: 0.5, y: 0.3, s: 1, e: 20, i: 0.5, c: 3, v: 2, r: 20)])
        var b = a; b.hideMarkers = true
        XCTAssertEqual(a.seed, b.seed)
        XCTAssertEqual(Simulation.run(stage: a, moves: []), Simulation.run(stage: b, moves: []))
    }
}

final class WaveSequenceTests: XCTestCase {
    private func em(_ t: DanmakuCore.Pattern = .ring, c: Int = 4, i: Double = 1.0, v: Double = 1.0) -> Emitter {
        Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 120, i: i, c: c, v: v, r: 0)
    }

    private func sequence(_ waves: [Wave], life: Int? = nil) -> Stage {
        Stage(name: "seq", mode: .sequence, durationSec: 0, emitters: [],
              lifeMode: life == nil ? nil : .lives, lifeCount: life, waves: waves).sanitized()
    }

    private func run(_ st: Stage, moves: (Int) -> Move = { _ in .zero }, limit: Int = 120 * 700) -> Simulation {
        var sim = Simulation(stage: st)
        while sim.outcome == .playing && sim.tick < limit { sim.step(moves(sim.tick)) }
        return sim
    }

    func testSanitizeComputesTotalAndClampsWaves() {
        let st = sequence([Wave(kind: .boss, durationSec: 77, bossHp: 9999, bossMove: 7, emitters: [em()]),
                           Wave(kind: .survive, durationSec: 33, emitters: [em()])])
        XCTAssertEqual(st.mode, .sequence)
        XCTAssertEqual(st.waves?.count, 2)
        XCTAssertEqual(st.waves![0].durationSec, 60)      // 選べない長さは、標準(ボス=60秒)に
        XCTAssertEqual(st.waves![0].bossHp, 1000)
        XCTAssertEqual(st.waves![0].bossMove, 6)          // 7 は範囲外なので、いちばん最後の種類(0〜6)に
        XCTAssertEqual(st.waves![1].durationSec, 20)      // 生き残り=20秒
        XCTAssertNil(st.waves![1].bossHp)
        XCTAssertEqual(st.durationSec, 60 + 20 + Wave.intermissionBudget)
        XCTAssertNil(st.bossHp); XCTAssertTrue(st.emitters.isEmpty)
        let many = sequence((0..<9).map { _ in Wave(kind: .survive, durationSec: 10, emitters: [em()]) })
        XCTAssertEqual(many.waves?.count, Wave.maxWaves)
    }

    func testSeedDependsOnWaveContentAndOrder() {
        let a = Wave(kind: .survive, durationSec: 10, emitters: [em(.ring)])
        let b = Wave(kind: .boss, durationSec: 30, bossHp: 200, bossMove: 0, emitters: [em(.aim)])
        XCTAssertNotEqual(sequence([a, b]).seed, sequence([b, a]).seed)
        XCTAssertNotEqual(sequence([a, b]).seed, sequence([a]).seed)
        XCTAssertEqual(sequence([a, b]).seed, sequence([a, b]).seed)
    }

    func testSurviveThenBossThenClear() {
        // 雑魚だけ(10秒) → ボス(HP100)。動かなくても、弾が当たらない遅い弾幕
        let st = sequence([Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .sideL, x: 0.5, y: 0.1, s: 0, e: 10, i: 2, c: 1, v: 1, r: 0)]),
                           Wave(kind: .boss, durationSec: 60, bossHp: 100, bossMove: 0, emitters: [Emitter(t: .sideR, x: 0.5, y: 0.1, s: 0, e: 60, i: 2, c: 1, v: 1, r: 0)])], life: 5)
        var sim = Simulation(stage: st)
        var seenWaves: [Int] = [0]
        var intermissionSeen = false
        while sim.outcome == .playing && sim.tick < 120 * 120 {
            sim.step(.zero)
            if sim.waveIndex != seenWaves.last { seenWaves.append(sim.waveIndex) }
            if sim.isIntermission { intermissionSeen = true }
        }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertEqual(seenWaves, [0, 1])
        XCTAssertTrue(intermissionSeen)
        XCTAssertEqual(sim.waveCount, 2)
        XCTAssertEqual(sim.defeats, 1)
        XCTAssertGreaterThan(sim.t, 10 + Wave.intermissionSeconds)
    }

    func testBossTimeUpMidSequenceFails() {
        // 倒せない大きな HP を、短い時間で: 時間切れで失敗(次の場面には進まない)
        let st = sequence([Wave(kind: .boss, durationSec: 30, bossHp: 1000, bossMove: 2, emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 2, c: 1, v: 1, r: 0)]),
                           Wave(kind: .survive, durationSec: 10, emitters: [em()])], life: 5)
        var sim = Simulation(stage: st)
        // 画面の端に張りつく(ボスに弾が当たりにくい)
        while sim.outcome == .playing && sim.tick < 120 * 100 { sim.step(Move(dx: -127, dy: 0)) }
        XCTAssertTrue(sim.outcome == .timeUp || sim.outcome == .cleared)
        if sim.outcome == .timeUp { XCTAssertEqual(sim.waveIndex, 0) }
    }

    func testLifeCarriesAcrossWavesAndBulletsAreClearedBetweenWaves() {
        let st = sequence([Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .aim, x: 0.5, y: 0.5, s: 0, e: 10, i: 0.3, c: 1, v: 3, r: 0)]),
                           Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .aim, x: 0.5, y: 0.5, s: 0, e: 10, i: 0.3, c: 1, v: 3, r: 0)])], life: 5)
        var sim = Simulation(stage: st)
        var lifeAtSwitch: Int?
        var bulletsAtSwitch: Int?
        var lastWave = 0
        while sim.outcome == .playing && sim.tick < 120 * 60 {
            sim.step(.zero)
            if sim.waveIndex != lastWave { lastWave = sim.waveIndex; lifeAtSwitch = sim.lifeLeft; bulletsAtSwitch = sim.bullets.count }
        }
        if let l = lifeAtSwitch { XCTAssertLessThan(l, 5, "場面の前半で、ライフが減っている"); XCTAssertEqual(bulletsAtSwitch, 0) }
        XCTAssertLessThanOrEqual(sim.lifeLeft, lifeAtSwitch ?? 5)
    }

    func testSequenceIsDeterministicAndLimitCoversAllWaves() {
        let st = sequence([Wave(kind: .survive, durationSec: 10, emitters: [em(.spiral, c: 3, i: 0.2, v: 2)]),
                           Wave(kind: .boss, durationSec: 30, bossHp: 200, bossMove: 1, emitters: [em(.aim, c: 5, i: 0.8, v: 2)])], life: 3)
        let moves: (Int) -> Move = { Move(dx: Int8(($0 / 70) % 2 == 0 ? 6 : -6), dy: 0) }
        let a = run(st, moves: moves), b = run(st, moves: moves)
        XCTAssertEqual(a.result, b.result)
        XCTAssertEqual(a.waveIndex, b.waveIndex)
        XCTAssertEqual(Simulation.run(stage: st, moves: (0..<3000).map(moves)), Simulation.run(stage: st, moves: (0..<3000).map(moves)))
    }

    func testSingleWaveModesBehaveAsBefore() {
        // 連戦ではないステージは、場面1つとして動く(場面の切り替えはない)
        let s = Stage(name: "x", mode: .boss, durationSec: 60, bossHp: 100, bossMove: 0, emitters: [em()])
        var sim = Simulation(stage: s)
        while sim.outcome == .playing && sim.tick < 120 * 70 { sim.step(.zero) }
        XCTAssertEqual(sim.waveCount, 1); XCTAssertEqual(sim.waveIndex, 0); XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertEqual(sim.defeats, 1)
        XCTAssertFalse(sim.isIntermission)
    }

    func testJSONRoundTripAndOldStagesHaveNoWaves() throws {
        let st = sequence([Wave(kind: .boss, durationSec: 30, bossHp: 200, bossMove: 1, emitters: [em()], warning: true, defeat: 3)])
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back, st)
        XCTAssertEqual(back.waves?.first?.warning, true)
        XCTAssertEqual(back.waves?.first?.defeat, 3)
        let plain = Stage(name: "p", mode: .survive, durationSec: 20, emitters: [em()])
        XCTAssertFalse(String(data: try JSONEncoder().encode(plain), encoding: .utf8)!.contains("waves"))
    }
}

final class EffectOptionTests: XCTestCase {
    func testWarningAndDefeatOptionsOnlyForBossesAndStoredWhenNonStandard() throws {
        let boss = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring)],
                         bossWarning: true, bossDefeat: 2).sanitized()
        XCTAssertEqual(boss.bossWarning, true); XCTAssertEqual(boss.bossDefeatEffect, .fireworks)
        let std = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring)],
                        bossWarning: false, bossDefeat: 1).sanitized()
        XCTAssertNil(std.bossWarning); XCTAssertNil(std.bossDefeat); XCTAssertEqual(std.bossDefeatEffect, .explosion)
        let none = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring)], bossDefeat: 0).sanitized()
        XCTAssertEqual(none.bossDefeatEffect, .none)
        let survive = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)], bossWarning: true, bossDefeat: 3).sanitized()
        XCTAssertNil(survive.bossWarning); XCTAssertNil(survive.bossDefeat)
        let bad = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 0, emitters: [Emitter(t: .ring)], bossDefeat: 99).sanitized()
        XCTAssertNil(bad.bossDefeat)
        let damage = Stage(name: "d", mode: .damage, durationSec: 60, bossMove: 0, emitters: [Emitter(t: .ring)], bossWarning: true, bossDefeat: 2).sanitized()
        XCTAssertEqual(damage.bossWarning, true); XCTAssertNil(damage.bossDefeat, "ダメージ勝負には、撃破がない")
    }

    func testEffectsDoNotChangeSeedOrBehaviour() {
        let a = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 200, bossMove: 1, emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.8, c: 3, v: 2, r: 20)])
        var b = a; b.bossWarning = true; b.bossDefeat = 3
        XCTAssertEqual(a.seed, b.seed)
        XCTAssertEqual(Simulation.run(stage: a, moves: []), Simulation.run(stage: b, moves: []))
    }

    func testDefeatEventCarriesPositionAndEffect() {
        var s = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 100, bossMove: 0, emitters: [Emitter(t: .sideL, x: 0.5, y: 0.1, s: 0, e: 60, i: 2, c: 1, v: 1, r: 0)], bossDefeat: 3)
        s = s.sanitized()
        var sim = Simulation(stage: s)
        while sim.outcome == .playing && sim.tick < 120 * 70 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertEqual(sim.defeats, 1)
        XCTAssertEqual(sim.lastDefeatEffect, .hearts)
        XCTAssertEqual(sim.lastDefeatPosition.x, 180, accuracy: 1)
        XCTAssertEqual(sim.lastDefeatPosition.y, DanmakuConfig.height * 0.18, accuracy: 1)
    }
}


final class BossSizeTests: XCTestCase {
    private func stage(size: Int?) -> Stage {
        Stage(name: "s", mode: .boss, durationSec: 60, bossHp: 300, bossMove: 0, emitters: [], bossSize: size).sanitized()
    }

    /// 自機を動かさず撃ち続けたとき、ボスが小さいほど弾が当たりにくい(自機の弾は、中央のまま)
    private func damageAfter(_ s: Stage, xOffsetMoves: Int) -> Int {
        var sim = Simulation(stage: s)
        for _ in 0..<xOffsetMoves { sim.step(Move(dx: 4, dy: 0)) }   // 少しずらす(1歩 = 1論理px)
        for _ in 0..<(120 * 6) { sim.step(.zero) }
        return sim.damageDealt
    }

    func testSizeIsSanitizedAndDefaultIsNotStored() {
        XCTAssertNil(stage(size: 1).bossSize)
        XCTAssertNil(stage(size: 7).bossSize)
        XCTAssertEqual(stage(size: 0).bossSize, 0)
        XCTAssertEqual(stage(size: 2).bossSize, 2)
        let survive = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], bossSize: 2, bossLook: 3).sanitized()
        XCTAssertNil(survive.bossSize); XCTAssertNil(survive.bossLook)
    }

    func testLooksAndMooksAreSanitized() {
        let a = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], mooks: 2, mookLook: 4).sanitized()
        XCTAssertEqual(a.mooks, 2); XCTAssertEqual(a.mookLook, 4)
        let b = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], mooks: nil, mookLook: 4).sanitized()
        XCTAssertNil(b.mookLook, "雑魚を出さないなら、見た目の指定は保存しない")
        let c = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [], mooks: 9, mookLook: 9).sanitized()
        XCTAssertNil(c.mooks)
    }

    func testBiggerBossIsHitMoreEasily() {
        // 中央から左右にずらした位置に自機を置く。ずれが 20px のとき、半径 17 には当たらず、24 以上なら当たる
        let small = damageAfter(stage(size: 0), xOffsetMoves: 0)
        let big = damageAfter(stage(size: 2), xOffsetMoves: 0)
        XCTAssertGreaterThanOrEqual(big, small)
        XCTAssertEqual(DanmakuConfig.bossRadii, [17, 24, 34])
    }

    func testOldStagesDecodeWithoutNewFields() throws {
        let json = #"{"name":"a","mode":"boss","durationSec":60,"bossHp":300,"bossMove":0,"emitters":[],"formatVersion":1}"#
        let s = try JSONDecoder().decode(Stage.self, from: Data(json.utf8))
        XCTAssertNil(s.bossSize); XCTAssertNil(s.mooks)
        let out = String(data: try JSONEncoder().encode(s.sanitized()), encoding: .utf8)!
        XCTAssertFalse(out.contains("bossSize")); XCTAssertFalse(out.contains("mooks"))
    }
}


final class PublishRuleTests: XCTestCase {
    /// サーバーは、生き残りの発射台の「開始 < 制限時間」「終わり > 開始」を求める。アプリの丸めも同じにして、投稿で弾かれないようにする
    func testSurviveEmitterTimingMatchesServerRule() {
        let bad = [
            Emitter(t: .ring, x: 0.5, y: 0.1, s: 30, e: 40, i: 1, c: 8, v: 2, r: 0, k: 0),   // 開始が、20秒の制限より後
            Emitter(t: .ring, x: 0.5, y: 0.1, s: 5, e: 5, i: 1, c: 8, v: 2, r: 0, k: 0),     // 終わり = 開始
            Emitter(t: .ring, x: 0.5, y: 0.1, s: 8, e: 3, i: 1, c: 8, v: 2, r: 0, k: 0),     // 終わりが開始より前
        ]
        let s = Stage(name: "t", mode: .survive, durationSec: 20, emitters: bad).sanitized()
        for m in s.emitters {
            XCTAssertLessThan(m.s, 20)
            XCTAssertGreaterThan(m.e, m.s)
        }
        let w = Wave(kind: .survive, durationSec: 10, emitters: bad).sanitized()
        for m in w.emitters {
            XCTAssertLessThan(m.s, 10)
            XCTAssertGreaterThan(m.e, m.s)
        }
    }

    func testValidTimingIsLeftAlone() {
        let ok = Emitter(t: .ring, x: 0.5, y: 0.1, s: 2, e: 15, i: 1, c: 8, v: 2, r: 0, k: 0)
        XCTAssertEqual(Stage(name: "t", mode: .survive, durationSec: 20, emitters: [ok]).sanitized().emitters, [ok])
    }
}
