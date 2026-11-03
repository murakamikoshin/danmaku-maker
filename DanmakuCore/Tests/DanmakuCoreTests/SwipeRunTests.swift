import XCTest
@testable import DanmakuCore

/// 1 プレイ分の記録からの点数の計算し直し（仕様書 15.2 章）
final class SwipeRunTests: XCTestCase {
    /// 弾が 1 発もない 10 秒のステージ。止まっていてもクリアできる
    private let quiet = Stage(name: "静か", mode: .survive, durationSec: 10, emitters: [])
    /// 自機めがけて、ゆっくり 1 発だけ飛んでくる。止まっていると当たる（バリアが切れた後に着く）
    private let headOn = Stage(name: "直撃", mode: .survive, durationSec: 10,
                               emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 30, i: 100, c: 1, v: 1, r: 0, k: 0, a: 0)])
    /// 自機から少しずれた向きに、次々と弾が飛んでくる。止まっていれば当たらず、かすり続ける（ボムも出る）
    private let grazing = Stage(name: "かすり", mode: .survive, durationSec: 10,
                                emitters: [Emitter(t: .aim, x: 0.5, y: 0.2, s: 0, e: 30, i: 0.05, c: 1, v: 3, r: 0, k: 0, a: 3)])

    private let pool = (0..<40).map { SwipeFeed.Entry(id: String(format: "R%03d", $0), d: 850, author: "u\($0 % 3)") }
    private let still = [Move](repeating: .zero, count: SwipeClip.playSteps)

    /// 呼ばれた順に、決めたステージを返す
    private func source(_ stages: [Stage]) -> SwipeRun.ClipSource {
        var calls = 0
        return { _ in defer { calls += 1 }; return calls < stages.count ? (stages[calls], 0) : nil }
    }

    private func run(_ stages: [Stage], _ clips: [SwipeRun.ClipInput], seed: UInt32 = 3) -> SwipeRun.Result {
        SwipeRun.play(seed: seed, pool: pool, source: source(stages), clips: clips)
    }

    // MARK: 手で計算できるもの

    func testClearingQuietClipsGivesTheClearBonusesOnly() {
        let r = run([quiet, quiet, quiet], [.init(moves: still), .init(moves: still), .init(moves: still)])
        XCTAssertNil(r.invalid)
        XCTAssertEqual(r.clipsPlayed, 3)
        XCTAssertEqual(r.clipsCleared, 3)
        XCTAssertEqual(r.streak, 3)
        XCTAssertEqual(r.bestStreak, 3)
        XCTAssertFalse(r.endedByHit)
        XCTAssertEqual(r.grazes, 0)
        // 100 × 500 × 3^(連続) = 150000, 450000, 1350000
        XCTAssertEqual(r.scoreAfterEachClip, ["150000", "600000", "1950000"])
        XCTAssertEqual(r.score.description, "1950000")
    }

    func testSkippingResetsTheStreak() {
        let r = run([quiet, quiet, quiet], [.init(moves: still), .init(skipped: true), .init(moves: still)])
        XCTAssertEqual(r.clipsCleared, 2)
        XCTAssertEqual(r.clipsPlayed, 3)
        XCTAssertEqual(r.bestStreak, 1)
        XCTAssertEqual(r.streak, 1)
        XCTAssertEqual(r.scoreAfterEachClip, ["150000", "150000", "300000"], "スキップでは点は入らず、次のクリアは連続 1 からやり直し")
    }

    func testSkipAfterSomeSteps() {
        let some = [Move](repeating: .zero, count: 300)
        let r = run([quiet, quiet], [.init(go: [Move(dx: 4, dy: 0)], moves: some, skipped: true), .init(moves: still)])
        XCTAssertEqual(r.clipsCleared, 1)
        XCTAssertEqual(r.scoreAfterEachClip, ["0", "150000"])
    }

    func testAHitEndsTheRunAndKeepsTheScore() {
        let r = run([quiet, headOn, quiet], [.init(moves: still), .init(moves: still), .init(moves: still)])
        XCTAssertTrue(r.endedByHit)
        XCTAssertEqual(r.clipsPlayed, 2, "被弾で終わり。3 本目は遊ばない")
        XCTAssertEqual(r.clipsCleared, 1)
        XCTAssertEqual(r.streak, 0, "被弾で連続は 0")
        XCTAssertEqual(r.bestStreak, 1)
        // 1 本目のクリア 150000 + 2 本目で当たる手前に 1 回かすった分（コンボ 1 なので 100 × 9 ÷ 8 = 112（切り捨て）、連続 1 なので × 3 = 336）
        XCTAssertEqual(r.grazes, 1)
        XCTAssertEqual(r.score.description, "150336")
        XCTAssertEqual(r.scoreAfterEachClip, ["150000", "150336"])
    }

    func testARecordThatRunsOutIsAbandonedNotCleared() {
        let r = run([quiet, quiet], [.init(moves: still), .init(moves: Array(still.prefix(500)))])
        XCTAssertTrue(r.abandoned)
        XCTAssertFalse(r.endedByHit)
        XCTAssertEqual(r.clipsCleared, 1)
        XCTAssertEqual(r.score.description, "150000", "途中でやめた分は、点が入らないだけ")
    }

    func testAnEmptyRunScoresNothing() {
        let r = run([], [])
        XCTAssertEqual(r.score, .zero)
        XCTAssertEqual(r.clipsPlayed, 0)
        XCTAssertNil(r.invalid)
    }

    // MARK: 計算できないとき

    func testMissingStagesAndExhaustedPoolsAreInvalid() {
        let r = run([quiet], [.init(moves: still), .init(moves: still)])
        XCTAssertNotNil(r.invalid)
        XCTAssertTrue(r.invalid!.hasPrefix("missing-stage:"), r.invalid ?? "")
        XCTAssertEqual(r.clipsCleared, 1, "それまでの分は計算してある")

        let empty = SwipeRun.play(seed: 1, pool: [], source: source([quiet]), clips: [.init(moves: still)])
        XCTAssertEqual(empty.invalid, "pool-exhausted")
    }

    func testTooLongRecordsAreCutAtTheLimits() {
        let tooMany = [Move](repeating: .zero, count: 5000)
        let r = run([quiet], [.init(go: [Move](repeating: Move(dx: 1, dy: 0), count: 500), moves: tooMany)])
        XCTAssertEqual(r.clipsCleared, 1, "1200 ステップを超えた分は使わない")
        XCTAssertEqual(r.score.description, "150000")
    }

    // MARK: 並びと再現

    func testTheClipsFollowTheSeedAndTheStreak() {
        let ids = { (seed: UInt32) in self.run([self.quiet, self.quiet, self.quiet], [.init(moves: self.still), .init(moves: self.still), .init(moves: self.still)], seed: seed).clipIDs }
        XCTAssertEqual(ids(3), ids(3))
        XCTAssertEqual(Set(ids(3)).count, 3, "同じプレイで同じクリップは出ない")
        XCTAssertNotEqual(ids(3), ids(4))
        // 並びは SwipeFeed.pick と同じ
        var used = Set<String>(), expected: [String] = []
        for i in 0..<3 {
            let e = SwipeFeed.pick(pool: pool, seed: 3, index: i, streak: i, used: used)!
            used.insert(e.id); expected.append(e.id)
        }
        XCTAssertEqual(ids(3), expected)
    }

    func testExcludedAuthorsAreNeverShown() {
        let r = SwipeRun.play(seed: 5, pool: pool, excludedAuthors: ["u0", "u1"], source: source([quiet, quiet, quiet, quiet]),
                              clips: (0..<4).map { _ in .init(moves: still) })
        XCTAssertEqual(r.clipsCleared, 4)
        for id in r.clipIDs { XCTAssertEqual(pool.first(where: { $0.id == id })!.author, "u2") }
    }

    // MARK: かすりとボム

    func testGrazingBuildsUpComboAndFiresBombs() {
        let r = run([grazing], [.init(moves: still)])
        XCTAssertNil(r.invalid)
        XCTAssertFalse(r.endedByHit, "ずれた向きの弾は、止まっていれば当たらない")
        XCTAssertEqual(r.clipsCleared, 1)
        XCTAssertGreaterThan(r.grazes, 80)
        XCTAssertGreaterThanOrEqual(r.bombs, 2, "かすり 40 回ごとにボム")
        XCTAssertGreaterThan(r.score, BigScore(150_000), "クリアの点より、かすりの分だけ多い")
    }

    func testTheRunMatchesAnIndependentStepByStepReplay() {
        // 同じ手順を、テストの中で 1 ステップずつ書いて、結果が 1 桁も違わないことを確かめる
        var sim = SwipeClip.prepare(stage: grazing, at: 0)
        var s = SwipeScoring()
        s.beginClip()
        var bombs = 0
        for n in 1...SwipeClip.playSteps {
            sim.step(.zero)
            for _ in sim.grazedThisStep { s.graze(step: n) }
            let coinBullets = sim.bullets.filter { !$0.isBeam && !$0.isBlast }.count
            if s.endStep(step: n, bulletCount: coinBullets, hit: sim.outcome == .hit) != nil { sim.clearBullets(); sim.giveShield(steps: 120); bombs += 1 }
            XCTAssertNotEqual(sim.outcome, .hit)
            if n == SwipeClip.playSteps || sim.outcome == .cleared {
                _ = s.clear(bulletCount: sim.bullets.filter { !$0.isBeam && !$0.isBlast }.count)
                break
            }
        }
        let r = run([grazing], [.init(moves: still)])
        XCTAssertEqual(r.score, s.score)
        XCTAssertEqual(r.bombs, bombs)
    }

    func testTheSameRecordAlwaysGivesTheSameScore() {
        let moves = scriptedMoves(count: SwipeClip.playSteps)
        let a = run([grazing, grazing], [.init(go: Array(moves.prefix(60)), moves: moves), .init(moves: moves)])
        let b = run([grazing, grazing], [.init(go: Array(moves.prefix(60)), moves: moves), .init(moves: moves)])
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a.score, .zero)
    }

    func testTheGoMovesChangeWhereTheShipStarts() {
        let a = run([grazing], [.init(moves: still)])
        let moved = run([grazing], [.init(go: [Move](repeating: Move(dx: 100, dy: -50), count: 60), moves: still)])
        XCTAssertNotEqual(a.score, moved.score, "GO の間に動かすと、始まりの位置が変わる")
    }
}
