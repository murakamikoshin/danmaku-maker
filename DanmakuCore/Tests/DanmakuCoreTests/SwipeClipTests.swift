import XCTest
@testable import DanmakuCore

/// スワイプ弾幕の 1 本のクリップ（仕様書 3 章）
final class SwipeClipTests: XCTestCase {
    private func still(_ x: Double, _ y: Double) -> Bullet { Bullet(x: x, y: y, vx: 0, vy: 0, color: 0) }

    // MARK: 数

    func testConstants() {
        XCTAssertEqual(SwipeClip.readySteps, 144, "READY の 1.2 秒")
        XCTAssertEqual(SwipeClip.playSteps, 1200, "10 秒")
        XCTAssertEqual(SwipeClip.goSteps, 60, "0.5 秒")
        XCTAssertEqual(SwipeClip.startShieldSteps, 84, "0.7 秒")
        XCTAssertEqual(SwipeClip.startTick(at: 0), 144)
        XCTAssertEqual(SwipeClip.startTick(at: 0.5), 204)
        XCTAssertEqual(SwipeClip.startTick(at: 12), 144 + 1440)
    }

    // MARK: 一番安全な場所

    func testAnEmptyFieldPicksTheTopOfTheMiddle() {
        let p = SwipeClip.safestPosition(among: [])
        XCTAssertEqual(p.x, 30 + 5 * 300.0 / 11, accuracy: 1e-9, "真ん中に一番近い 2 点が同点なら、先（左）を選ぶ")
        XCTAssertEqual(p.y, 270, accuracy: 1e-9, "縦は先（上）を選ぶ")
    }

    func testTheCandidateGridCoversTheLowerHalfOfTheScreen() {
        // 弾が左上に 1 発だけあれば、一番遠い右下の隅になる
        let p = SwipeClip.safestPosition(among: [still(30, 270)])
        XCTAssertEqual(p.x, 330, accuracy: 1e-9)
        XCTAssertEqual(p.y, 496.8, accuracy: 1e-9)
    }

    func testItStaysAwayFromABulletSittingOnTheBestSpot() {
        let empty = SwipeClip.safestPosition(among: [])
        let p = SwipeClip.safestPosition(among: [still(empty.x, empty.y)])
        XCTAssertNotEqual(p, empty)
        let d = ((p.x - empty.x) * (p.x - empty.x) + (p.y - empty.y) * (p.y - empty.y)).squareRoot()
        XCTAssertGreaterThan(d, 100, "最も遠い所を選ぶ")
    }

    func testBulletsAreJudgedWhereTheyAreGoing() {
        // 右へ進む弾: 今は遠い (60, 0) も、0.6 秒後には弾が来る
        let moving = Bullet(x: 0, y: 0, vx: 100, vy: 0, color: 0)
        XCTAssertEqual(SwipeClip.distanceSquared(from: moving, to: 60, 0), 0, accuracy: 1e-9, "0.6 秒後に重なる")
        XCTAssertEqual(SwipeClip.distanceSquared(from: moving, to: 45, 0), 225, accuracy: 1e-9, "0.6 秒後の位置 (60, 0) との距離 15")
        XCTAssertEqual(SwipeClip.distanceSquared(from: still(0, 0), to: 45, 0), 2025, accuracy: 1e-9, "止まった弾なら 45px")
        XCTAssertEqual(SwipeClip.distanceSquared(from: moving, to: -30, 0), 900, accuracy: 1e-9, "後ろ側は今の位置から")
    }

    func testBeamsAndBlastsAreJudgedByTheirReach() {
        let beam = Bullet.beam(x: 0, y: 0, angle: 0, color: 0)   // 右向きの光線
        XCTAssertEqual(SwipeClip.distanceSquared(from: beam, to: 50, 7), 49, accuracy: 1e-9, "光線の横 7px")
        XCTAssertEqual(SwipeClip.distanceSquared(from: beam, to: 500, 0), 0, accuracy: 1e-9, "光線の先でも、線の上は危ない")
        XCTAssertEqual(SwipeClip.distanceSquared(from: beam, to: -30, 0), 900, accuracy: 1e-9, "出る場所の後ろ側は、点との距離")
        let blast = Bullet.blast(x: 0, y: 0, radius: 20, warn: 1, color: 0)
        XCTAssertEqual(SwipeClip.distanceSquared(from: blast, to: 50, 0), 900, accuracy: 1e-9, "縁まで 30px")
        XCTAssertEqual(SwipeClip.distanceSquared(from: blast, to: 10, 0), 0, accuracy: 1e-9, "中なら 0")
    }

    func testAFarBulletAboveMakesTheBottomRowTheSafestRow() {
        XCTAssertEqual(SwipeClip.safestPosition(among: [still(180, -100)]).y, 496.8, accuracy: 1e-9, "上に離れた弾なら、できるだけ下")
    }

    // MARK: 始まりの状態

    private let stage = Stage(name: "クリップ", mode: .survive, durationSec: 30,
                              emitters: [em(.ring, c: 20, v: 2, r: 6), em(.aim, y: 0.1, i: 0.5, c: 5, v: 3, r: 40), em(.rain, i: 0.2, c: 2)])

    func testPrepareLeavesTheClipReadyToPlay() {
        let sim = SwipeClip.prepare(stage: stage, at: 5)
        XCTAssertEqual(sim.tick, SwipeClip.startTick(at: 5))
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.grazeCount, 0, "早送りの間のかすりは数えない")
        XCTAssertFalse(sim.bullets.contains(where: { $0.grazed }))
        XCTAssertTrue(sim.isShielded, "遊び始めのバリア")
        XCTAssertFalse(sim.invincible, "早送りの無敵は解く")
        XCTAssertFalse(sim.bullets.isEmpty, "弾が飛んでいる途中から始まる")
        XCTAssertGreaterThanOrEqual(sim.player.x, 6)
        XCTAssertLessThanOrEqual(sim.player.x, DanmakuConfig.width - 6)
        XCTAssertGreaterThanOrEqual(sim.player.y, 270)
        XCTAssertEqual(sim.player, SwipeClip.safestPosition(among: sim.bullets))
    }

    func testPrepareIsRepeatable() {
        let a = SwipeClip.prepare(stage: stage, at: 8.5), b = SwipeClip.prepare(stage: stage, at: 8.5)
        XCTAssertEqual(a.result, b.result)
        XCTAssertEqual(a.player, b.player)
        XCTAssertNotEqual(a.result, SwipeClip.prepare(stage: stage, at: 9).result, "切り出す場所が違えば、違う弾の配置")
    }

    func testTheBarrierLastsTheRequestedStepsAfterThePlayStarts() {
        var sim = SwipeClip.prepare(stage: stage, at: 5)
        // 遊び始めてから 84 ステップ目までは守られ、85 ステップ目から切れる
        let start = sim.tick
        for _ in 0..<SwipeClip.startShieldSteps { sim.step(.zero); XCTAssertTrue(sim.isShielded) }
        XCTAssertEqual(sim.tick, start + SwipeClip.startShieldSteps)
        sim.step(.zero)
        XCTAssertFalse(sim.isShielded)
    }

    func testGoMovesTheShipWithoutAdvancingTheClip() {
        var sim = SwipeClip.prepare(stage: stage, at: 5)
        let (tick, bullets) = (sim.tick, sim.bullets)
        for i in 0..<SwipeClip.goSteps { sim.nudgePlayer(Move(dx: i % 2 == 0 ? 6 : -2, dy: -3)) }
        XCTAssertEqual(sim.tick, tick)
        XCTAssertEqual(sim.bullets, bullets)
        XCTAssertTrue(sim.isShielded, "GO の間はバリアを減らさない")
    }

    // MARK: スワイプ用のシミュレーション

    func testASurviveStageBehavesTheSameApartFromTheLifeRule() {
        var normal = Simulation(stage: stage), swipe = Simulation(swipeStage: stage)
        normal.invincible = true; swipe.invincible = true
        for n in 0..<1500 { normal.step(Move(dx: Int8(n % 7) - 3, dy: 1)); swipe.step(Move(dx: Int8(n % 7) - 3, dy: 1)) }
        XCTAssertEqual(normal.result, swipe.result, "乱数の種もステージ内容も同じ。弾の動きは 1 桁も変わらない")
    }

    func testASwipeSimulationEndsOnTheFirstHitWhateverTheStageSays() {
        var tough = Stage(name: "頑丈", mode: .survive, durationSec: 10,
                          emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 30, i: 100, c: 1, v: 3, r: 0, k: 0, a: 0)])
        tough.lifeMode = .hp
        tough.lifeCount = 10
        var normal = Simulation(stage: tough), swipe = Simulation(swipeStage: tough)
        for _ in 0..<1600 { normal.step(.zero); swipe.step(.zero) }
        XCTAssertEqual(normal.outcome, .cleared, "HP 10 なら 1 発では終わらない")
        XCTAssertEqual(swipe.outcome, .hit, "スワイプ弾幕は 1 回被弾で終わり")
    }

    func testABossStageNeverEndsEarlyAndTheShipDoesNotShoot() {
        let boss = Stage(name: "ボス", mode: .boss, durationSec: 30, bossHp: 100, bossMove: 0,
                         emitters: [em(.ring, y: 0.2, i: 1, c: 12, v: 2, r: 5)])
        var normal = Simulation(stage: boss), swipe = Simulation(swipeStage: boss)
        normal.invincible = true; swipe.invincible = true
        for _ in 0..<2500 { normal.step(.zero); swipe.step(.zero) }
        XCTAssertEqual(normal.outcome, .cleared, "ふつうの本編なら、まっすぐ上へ撃つだけでボス（HP 100）は倒れる")
        XCTAssertEqual(swipe.outcome, .playing, "スワイプ弾幕では倒れない（30 秒の制限までは続く）")
        XCTAssertTrue(swipe.shots.isEmpty)
        XCTAssertEqual(swipe.damageDealt, 0)
        XCTAssertTrue(swipe.isDamageRaceLike)
    }
}

private extension Simulation {
    /// ボスの場面が「ダメージ勝負」と同じ扱い（HP は減らず、段階は時間で進む）か
    var isDamageRaceLike: Bool { isBoss && isDamageRace }
}
