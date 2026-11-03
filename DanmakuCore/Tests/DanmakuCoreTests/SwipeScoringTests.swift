import XCTest
@testable import DanmakuCore

/// スワイプ弾幕の点数の計算（仕様書 5 章）。正解の値は、同じ式を Python の整数で別に書いて計算したもの
final class SwipeScoringTests: XCTestCase {
    private func big(_ s: String) -> BigScore { BigScore(s)! }

    func testGrazePointsMatchTheFormula() {
        let table: [(Int, Int, String)] = [
            (0, 0, "100"),
            (1, 0, "112"),       // 100 × 9 ÷ 8 = 112.5 → 切り捨て
            (7, 0, "187"),
            (8, 0, "200"),       // 8 コンボで 2 倍
            (9, 0, "225"),
            (15, 3, "10125"),
            (11, 20, "958865710275"),
            (60, 15, "275499014400"),
            (200, 120, "6029765991177838786848673449305163565252709720387615237585711923200"),
            (37, 7, "5686200"),
        ]
        for (combo, streak, expected) in table {
            XCTAssertEqual(SwipeScoring.grazePoints(combo: combo, streak: streak).description, expected, "コンボ \(combo)・連続 \(streak)")
        }
    }

    func testGrazePointsNeverDecreaseWithComboOrStreak() {
        for streak in [0, 1, 5] {
            var last = BigScore.zero
            for combo in 0...80 {
                let p = SwipeScoring.grazePoints(combo: combo, streak: streak)
                XCTAssertTrue(p >= last, "コンボ \(combo)・連続 \(streak)")
                last = p
            }
        }
        XCTAssertTrue(SwipeScoring.grazePoints(combo: 5, streak: 3) > SwipeScoring.grazePoints(combo: 5, streak: 2))
    }

    func testClearBonusMatchesTheFormula() {
        let table: [(Int, Int, String)] = [
            (0, 0, "150000"),
            (5, 0, "150000"),
            (17, 2, "5400000"),
            (48, 9, "188956800000"),
            (64, 30, "7906219472434521600000"),
        ]
        for (combo, before, expected) in table {
            XCTAssertEqual(SwipeScoring.clearBonus(combo: combo, streakBefore: before).description, expected, "コンボ \(combo)・連続 \(before)")
        }
    }

    // MARK: 1 プレイを通した流れ（Python の正解と 1 桁も違わないこと）

    func testWholeRunMatchesThePythonModel() {
        var s = SwipeScoring()
        // クリップ 1: 10 ステップごとに 17 回かする
        s.beginClip()
        for i in 1...17 {
            let g = s.graze(step: 10 * i)
            XCTAssertEqual(g.combo, i)
            s.endStep(step: 10 * i, bulletCount: 30)
        }
        XCTAssertEqual(s.score.description, "4198")
        XCTAssertEqual(s.combo, 17)
        XCTAssertEqual(s.gauge, 17)
        // 前のかすり（170）から 179 ステップ後はまだ生きていて、180 ステップ後に切れる
        s.endStep(step: 349, bulletCount: 30)
        XCTAssertEqual(s.combo, 17)
        s.endStep(step: 350, bulletCount: 30)
        XCTAssertEqual(s.combo, 0)
        // クリア（弾 12 発）
        let clear = s.clear(bulletCount: 12)
        XCTAssertEqual(clear.bonus.description, "150000")
        XCTAssertEqual(clear.streak, 1)
        XCTAssertEqual(clear.coins.count, 12)
        XCTAssertEqual(clear.coins.each.description, "150", "連続 +1 の後の値（100 × 3 ÷ 2）")
        XCTAssertEqual(clear.coins.total.description, "1800")
        XCTAssertEqual(s.score.description, "155998")

        // クリップ 2: 5 ステップごとに 30 回かする。ゲージは 17 から持ち越して、23 回目に 40 に届く
        s.beginClip()
        XCTAssertEqual(s.gauge, 17, "ゲージはクリップをまたいで持ち越す")
        XCTAssertEqual(s.combo, 0, "コンボは新しいクリップで 0 に戻る")
        var bombs: [(Int, Int, String)] = []
        for i in 1...30 {
            let g = s.graze(step: 5 * i)
            if g.bombQueued {
                XCTAssertTrue(s.bombPending)
                XCTAssertEqual(s.gauge, 0, "ゲージはその場で 0 に戻る")
            }
            if let coins = s.endStep(step: 5 * i, bulletCount: 40) { bombs.append((i, s.combo, coins.total.description)) }
        }
        XCTAssertEqual(bombs.count, 1)
        XCTAssertEqual(bombs[0].0, 23)
        XCTAssertEqual(bombs[0].1, 23)
        XCTAssertEqual(bombs[0].2, "45000")
        XCTAssertEqual(s.score.description, "247942")
        XCTAssertEqual(s.combo, 30)
        XCTAssertEqual(s.gauge, 7)

        // 被弾: 連続が終わる。点数は残る
        XCTAssertEqual(s.hit(), 1)
        XCTAssertEqual(s.streak, 0)
        XCTAssertEqual(s.combo, 0)
        XCTAssertEqual(s.score.description, "247942")
    }

    // MARK: 決まりごと

    func testComboRestartsAfterALongGap() {
        var s = SwipeScoring()
        s.beginClip()
        XCTAssertEqual(s.graze(step: 100).combo, 1)
        XCTAssertEqual(s.graze(step: 100 + 179).combo, 2, "180 ステップ未満なら続く")
        XCTAssertEqual(s.graze(step: 100 + 179 + 180).combo, 1, "180 ステップ空いたら 1 から（endStep を呼ばなくても）")
    }

    func testLevelAndDoubling() {
        var s = SwipeScoring()
        s.beginClip()
        XCTAssertEqual(s.level, 1)
        for i in 1...7 { XCTAssertFalse(s.graze(step: i).doubled) }
        XCTAssertTrue(s.graze(step: 8).doubled, "8 コンボ")
        XCTAssertEqual(s.level, 2)
        XCTAssertEqual(s.multiplier.description, "2")
        for i in 9...63 { s.graze(step: i) }
        XCTAssertEqual(s.combo, 63)
        XCTAssertEqual(s.level, 8, "上限 8")
        s.graze(step: 64)
        s.graze(step: 65)
        XCTAssertEqual(s.level, 8)
        XCTAssertEqual(s.multiplier.description, "256", "2^(65÷8 = 8)。演出の段階は 8 で止まるが、倍率は止まらない")
    }

    func testMultiplierCombinesComboAndStreak() {
        var s = SwipeScoring()
        s.beginClip()
        _ = s.clear(bulletCount: 0)
        _ = s.clear(bulletCount: 0)
        XCTAssertEqual(s.streak, 2)
        XCTAssertEqual(s.multiplier.description, "9")
        for i in 1...16 { s.graze(step: i) }
        XCTAssertEqual(s.multiplier.description, "36", "2^2 × 3^2")
    }

    func testBombIsResolvedAtTheEndOfTheStepWithTheBulletsLeft() {
        var s = SwipeScoring()
        s.beginClip()
        for i in 1..<40 { s.graze(step: i) }
        XCTAssertFalse(s.bombPending)
        let before = s.score
        let last = s.graze(step: 40)
        XCTAssertTrue(last.bombQueued)
        XCTAssertEqual(s.score, before + last.points, "かすりの最中には、粒の点は入らない")
        let coins = s.endStep(step: 40, bulletCount: 25)!
        XCTAssertEqual(coins.count, 25)
        XCTAssertEqual(coins.each, s.currentGrazePoints.divided(by: 2))
        XCTAssertEqual(s.score, before + last.points + coins.total)
        XCTAssertFalse(s.bombPending, "出したら印は消える")
        XCTAssertNil(s.endStep(step: 41, bulletCount: 25), "次のステップでは出ない")
    }

    func testBombIsNotFiredOnTheStepOfAHit() {
        var s = SwipeScoring()
        s.beginClip()
        for i in 1...40 { s.graze(step: i) }
        XCTAssertTrue(s.bombPending)
        let before = s.score
        XCTAssertNil(s.endStep(step: 40, bulletCount: 50, hit: true))
        XCTAssertEqual(s.score, before)
        XCTAssertFalse(s.bombPending)
    }

    func testAPendingBombDoesNotLeakIntoTheNextClip() {
        var s = SwipeScoring()
        s.beginClip()
        for i in 1...40 { s.graze(step: i) }
        s.beginClip()   // ボムを出さないまま次のクリップへ（呼び出し側の間違いでも、前のボムが残らない）
        XCTAssertFalse(s.bombPending)
        XCTAssertEqual(s.gauge, 0)
    }

    func testSkipResetsTheStreakButKeepsTheScore() {
        var s = SwipeScoring()
        s.beginClip()
        _ = s.clear(bulletCount: 0)
        _ = s.clear(bulletCount: 0)
        let score = s.score
        s.skip()
        XCTAssertEqual(s.streak, 0)
        XCTAssertEqual(s.multiplier, BigScore(1))
        XCTAssertEqual(s.score, score)
        XCTAssertEqual(s.currentGrazePoints.description, "100", "連続 0 に戻ったので、かすりの点も戻る")
    }

    func testClearAddsThePointsOfTheRemainingBullets() {
        var s = SwipeScoring()
        s.beginClip()
        for i in 1...8 { s.graze(step: i) }   // コンボ 8 → 2 倍
        let before = s.score
        let c = s.clear(bulletCount: 10)
        XCTAssertEqual(c.bonus.description, "300000", "100 × 500 × 2 × 3^1")
        XCTAssertEqual(c.coins.each.description, "300", "100 × 2 × 3 ÷ 2")
        XCTAssertEqual(s.score, before + c.bonus + c.coins.total)
        let none = s.clear(bulletCount: 0)
        XCTAssertEqual(none.coins.total, .zero)
    }

    func testTheScoreKeepsGrowingPastTheInt64Limit() {
        var s = SwipeScoring()
        for _ in 0..<60 {   // 60 連続クリア
            s.beginClip()
            for i in 1...20 { s.graze(step: i) }
            _ = s.clear(bulletCount: 100)
        }
        XCTAssertEqual(s.streak, 60)
        XCTAssertGreaterThan(s.score.digitCount, 30, "Int64（19 桁）を大きく超える")
        XCTAssertGreaterThan(s.score, BigScore(UInt64.max))
        XCTAssertEqual(ScoreFormat.full(BigScore(s.score.description)!, .english).filter { $0 != "," }, s.score.description)
    }
}
