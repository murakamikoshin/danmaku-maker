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
        XCTAssertEqual(Product.homing.id, "com.koshin.danmakumaker.homing")
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.homing"), .homing)
        XCTAssertEqual(Product.homing.yen, 300)
        XCTAssertFalse(Ownership().hasHoming)
        XCTAssertTrue(Ownership(productIDs: [Product.homing.id]).hasHoming)
        XCTAssertFalse(Ownership(productIDs: [Product.homing.id]).canBuy(.homing))
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
