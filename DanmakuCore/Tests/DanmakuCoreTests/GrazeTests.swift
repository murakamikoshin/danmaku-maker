import XCTest
@testable import DanmakuCore

/// スワイプ弾幕のかすり（仕様書 5 章）と、`Simulation` に足したスワイプ用の操作（3.2 章）
final class GrazeTests: XCTestCase {
    /// 自機狙いの弾を 1 発だけ撃つステージ。自機は初期位置（180, 459）で動かない。
    /// 発射台は (180, 108)。向きを `offsetDegrees` だけずらすと、弾は自機のそばを「距離 351 × sin(角度)」だけ離れて通り過ぎる
    private func singleShot(offsetDegrees a: Int) -> Stage {
        Stage(name: "かすり", mode: .survive, durationSec: 10,
              emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 30, i: 100, c: 1, v: 3, r: 0, k: 0, a: a)])
    }

    private func play(_ stage: Stage, steps: Int = 1600) -> Simulation {
        var sim = Simulation(stage: stage)
        for _ in 0..<steps where sim.outcome == .playing { sim.step(.zero) }
        return sim
    }

    // MARK: 距離

    func testGrazeDistances() {
        XCTAssertEqual(DanmakuConfig.grazeRadius, 18, "ふつうの弾は 18px（仕様書 5 章）")
        XCTAssertEqual(DanmakuConfig.grazeRadiusSquared, 324)
        let normal = Bullet(x: 0, y: 0, vx: 0, vy: 0, color: 0)
        XCTAssertEqual(normal.grazeDistanceSquared, 324)
        let giant = Bullet(x: 0, y: 0, vx: 0, vy: 0, color: 0, script: Bullet.giantScript)
        XCTAssertEqual(giant.grazeDistanceSquared, 32.5 * 32.5, accuracy: 1e-9, "巨大弾は当たり判定 20px + 12.5px")
        let bubble = Bullet(x: 0, y: 0, vx: 0, vy: 0, color: 0, radius: 10)
        XCTAssertEqual(bubble.grazeDistanceSquared, 28 * 28, accuracy: 1e-9, "広い弾は 5.5 + 10 + 12.5")
        for b in [normal, giant, bubble] {
            XCTAssertGreaterThan(b.grazeDistanceSquared, b.hitDistanceSquared, "かするほうが必ず外側（でないと、かする前に当たってしまう）")
        }
    }

    // MARK: 判定

    func testABulletThatPassesCloseButMissesIsGrazedOnce() {
        for a in [-2, 2] {   // 自機から 12px ほど離れて通る（当たり判定 5.5px より外、かすり 18px より内）
            let sim = play(singleShot(offsetDegrees: a))
            XCTAssertEqual(sim.outcome, .cleared, "当たっていない（角度 \(a)）")
            XCTAssertEqual(sim.grazeCount, 1, "弾 1 発につき 1 回（角度 \(a)）")
        }
    }

    func testABulletThatPassesFarIsNotGrazed() {
        for a in [-3, 3, 10] {   // 18px より外を通る
            let sim = play(singleShot(offsetDegrees: a))
            XCTAssertEqual(sim.outcome, .cleared)
            XCTAssertEqual(sim.grazeCount, 0, "角度 \(a)")
        }
    }

    func testTheClosestMissIsStillAGrazeNotAHit() {
        let sim = play(singleShot(offsetDegrees: 1))   // 6px で通る。当たり判定の 5.5px のすぐ外
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertEqual(sim.grazeCount, 1)
    }

    func testAHeadOnBulletGrazesJustBeforeItHits() {
        let sim = play(singleShot(offsetDegrees: 0))
        XCTAssertEqual(sim.outcome, .hit)
        XCTAssertEqual(sim.grazeCount, 1, "当たる弾も、当たる手前の 18px に入った時点で 1 回かすっている（仕様書 5 章）")
    }

    func testGrazedThisStepListsOnlyTheLatestStep() {
        var sim = Simulation(stage: singleShot(offsetDegrees: 2))
        var stepsWithGraze = 0
        var total = 0
        for _ in 0..<1600 where sim.outcome == .playing {
            sim.step(.zero)
            if !sim.grazedThisStep.isEmpty { stepsWithGraze += 1; total += sim.grazedThisStep.count }
        }
        XCTAssertEqual(stepsWithGraze, 1)
        XCTAssertEqual(total, sim.grazeCount)
    }

    func testGrazedBulletsKeepTheirMarkSoTheyAreNotCountedTwice() {
        var sim = Simulation(stage: singleShot(offsetDegrees: 2))
        var seenGrazed = false
        for _ in 0..<1600 where sim.outcome == .playing {
            sim.step(.zero)
            if sim.bullets.contains(where: { $0.grazed }) { seenGrazed = true }
        }
        XCTAssertTrue(seenGrazed, "かすった弾は、画面にいる間「かすり済み」の印を持つ")
        XCTAssertEqual(sim.grazeCount, 1)
    }

    func testGrazeCountingCanBeSwitchedOff() {
        var sim = Simulation(stage: singleShot(offsetDegrees: 2))
        sim.countsGrazes = false
        for _ in 0..<1600 where sim.outcome == .playing { sim.step(.zero) }
        XCTAssertEqual(sim.grazeCount, 0)
        XCTAssertFalse(sim.bullets.contains(where: { $0.grazed }))
    }

    // MARK: 本編を変えない

    func testCountingGrazesNeverChangesTheGame() {
        let stages = [
            Stage(name: "A", mode: .survive, durationSec: 20, emitters: [em(.ring, c: 24, v: 2.5, r: 7), em(.aim, y: 0.1, i: 0.6, c: 5, v: 3, r: 40), em(.rain, i: 0.2, c: 2)]),
            Stage(name: "B", mode: .survive, durationSec: 20, emitters: [em(.spiral, x: 0.3, i: 0.1, c: 3, r: 11), em(.sweep, x: 0.7, i: 0.15, c: 5, v: 2.5, r: 60)]),
        ]
        let moves = scriptedMoves(count: 3000)
        for stage in stages {
            var on = Simulation(stage: stage), off = Simulation(stage: stage)
            off.countsGrazes = false
            for n in 0..<3000 where on.outcome == .playing && off.outcome == .playing {
                on.step(moves[n]); off.step(moves[n])
                XCTAssertEqual(on.player, off.player)
                XCTAssertEqual(on.bullets.count, off.bullets.count, "ステップ \(n)")
            }
            XCTAssertEqual(on.outcome, off.outcome, stage.name)
            XCTAssertEqual(on.result, off.result, "かすりを数えても、弾の位置・結果は 1 桁も変わらない（\(stage.name)）")
            XCTAssertGreaterThan(on.grazeCount, 0, "動き回れば、どれかはかする（\(stage.name)）")
        }
    }

    // MARK: スワイプ用の操作

    func testPlaceClampsInsideTheScreen() {
        var sim = Simulation(stage: singleShot(offsetDegrees: 0))
        sim.place(at: Point(x: 100, y: 300))
        XCTAssertEqual(sim.player, Point(x: 100, y: 300))
        sim.place(at: Point(x: -50, y: 9999))
        XCTAssertEqual(sim.player, Point(x: 6, y: DanmakuConfig.height - 6))
        sim.place(at: Point(x: 9999, y: -1))
        XCTAssertEqual(sim.player, Point(x: DanmakuConfig.width - 6, y: 6))
    }

    func testNudgeMovesOnlyThePlayer() {
        var sim = Simulation(stage: singleShot(offsetDegrees: 0))
        for _ in 0..<300 { sim.step(.zero) }
        let (tick, t, bullets) = (sim.tick, sim.t, sim.bullets)
        let before = sim.player
        sim.nudgePlayer(Move(dx: 7, dy: -4))
        XCTAssertEqual(sim.player.x, before.x + 7 * Move.unit, accuracy: 1e-12)
        XCTAssertEqual(sim.player.y, before.y - 4 * Move.unit, accuracy: 1e-12)
        XCTAssertEqual(sim.tick, tick, "時間は進まない")
        XCTAssertEqual(sim.t, t)
        XCTAssertEqual(sim.bullets, bullets, "弾は止まったまま")
        sim.place(at: Point(x: 7, y: 7))
        for _ in 0..<100 { sim.nudgePlayer(Move(dx: -127, dy: -127)) }
        XCTAssertEqual(sim.player, Point(x: 6, y: 6), "端を越えない")
    }

    func testShieldProtectsExactlyTheRequestedNumberOfSteps() {
        // 弾が自機に届くステップを調べる
        var probe = Simulation(stage: singleShot(offsetDegrees: 0))
        while probe.outcome == .playing { probe.step(.zero) }
        let hitTick = probe.tick
        XCTAssertGreaterThan(hitTick, 200)

        // 当たるのは hitTick ステップ目。giveShield(steps: n) は「次の n ステップ」を守るので、hitTick - n ステップ進めた所で呼べば、当たるステップまで守れる
        func outcome(shieldedSteps n: Int) -> Outcome {
            var sim = Simulation(stage: singleShot(offsetDegrees: 0))
            for _ in 0..<(hitTick - n) { sim.step(.zero) }
            sim.giveShield(steps: n)
            for _ in 0..<(n + 5) where sim.outcome == .playing { sim.step(.zero) }
            return sim.outcome
        }
        XCTAssertEqual(outcome(shieldedSteps: 1), .playing, "当たるステップだけ守れば、弾は消えるだけ")
        XCTAssertEqual(outcome(shieldedSteps: 3), .playing)
        // 1 ステップ足りないと（当たるステップの 1 つ前までしか守らないと）当たる
        var short = Simulation(stage: singleShot(offsetDegrees: 0))
        for _ in 0..<(hitTick - 4) { short.step(.zero) }
        short.giveShield(steps: 3)
        for _ in 0..<10 where short.outcome == .playing { short.step(.zero) }
        XCTAssertEqual(short.outcome, .hit, "守りが当たる 1 ステップ前に切れる")
        var noShield = Simulation(stage: singleShot(offsetDegrees: 0))
        for _ in 0..<(hitTick - 10) { noShield.step(.zero) }
        noShield.giveShield(steps: 3)   // 当たる 10 ステップ前に 3 ステップだけ守っても、当たる時には切れている
        while noShield.outcome == .playing && noShield.tick < hitTick + 5 { noShield.step(.zero) }
        XCTAssertEqual(noShield.outcome, .hit)
    }

    func testClearBulletsRemovesEverything() {
        var sim = Simulation(stage: Stage(name: "x", mode: .survive, durationSec: 10, emitters: [em(.ring, c: 20, v: 2)]))
        for _ in 0..<400 { sim.step(.zero) }
        XCTAssertFalse(sim.bullets.isEmpty)
        sim.clearBullets()
        XCTAssertTrue(sim.bullets.isEmpty)
    }

    func testFastForwardIsInvincibleSilentAndRestoresTheFlags() {
        // 弾は自機に当たる向き。早送りの間は無敵なので、当たっても終わらず、かすりも数えない
        var sim = Simulation(stage: singleShot(offsetDegrees: 0))
        sim.fastForward(toTick: 500)
        XCTAssertEqual(sim.tick, 500)
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.grazeCount, 0)
        XCTAssertFalse(sim.invincible, "終わったら元に戻る")
        XCTAssertTrue(sim.countsGrazes)

        // 元から無敵なら、無敵のまま
        var inv = Simulation(stage: singleShot(offsetDegrees: 0))
        inv.invincible = true
        inv.fastForward(toTick: 10)
        XCTAssertTrue(inv.invincible)

        // 同じ早送りは、毎回同じ弾の配置になる
        var a = Simulation(stage: singleShot(offsetDegrees: 2)), b = Simulation(stage: singleShot(offsetDegrees: 2))
        a.fastForward(toTick: 300); b.fastForward(toTick: 300)
        XCTAssertEqual(a.result, b.result)
        // 途中で止めて続けても、続けて進めても同じ
        var c = Simulation(stage: singleShot(offsetDegrees: 2))
        c.fastForward(toTick: 100); c.fastForward(toTick: 300)
        XCTAssertEqual(a.result, c.result)
    }

    func testFastForwardStopsWhenTheStageEnds() {
        var sim = Simulation(stage: Stage(name: "短い", mode: .survive, durationSec: 10, emitters: [em(.ring, c: 4, v: 1)]))
        sim.fastForward(toTick: 999_999)
        XCTAssertEqual(sim.outcome, .cleared)
        // 準備の 1.2 秒 + 10 秒 = 1344 ステップ前後で止まる（時間は 1/120 を足していくので、1 ステップの前後はありうる）
        XCTAssertTrue((1342...1346).contains(sim.tick), "tick \(sim.tick)")
    }
}
