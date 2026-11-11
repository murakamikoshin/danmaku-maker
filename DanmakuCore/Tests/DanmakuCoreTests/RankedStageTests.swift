import XCTest
@testable import DanmakuCore

/// ランク戦のステージと勝ち負け。サーバー(TypeScript)との照合データも、ここで書き出す
final class RankedStageTests: XCTestCase {
    func testStageShape() {
        let st = RankedStage.stage(seed: 12345)
        XCTAssertEqual(st.mode, .survive)
        XCTAssertEqual(st.durationSec, 180)
        XCTAssertEqual(st.lifeMode, .lives)
        XCTAssertEqual(st.lifeCount, 1)
        // 区切りが進むほど、発射台が多い(難しい)
        func count(_ k: Int) -> Int { st.emitters.filter { Int($0.s) / RankedStage.segmentSeconds == k }.count }
        XCTAssertLessThanOrEqual(count(0), count(11))
        XCTAssertEqual(RankedStage.hard(segment: 0), 60)
        XCTAssertEqual(RankedStage.hard(segment: 11), 995)
        // どの発射台も、自分の区切りの中で始まって終わる
        for e in st.emitters {
            let k = Int(e.s) / RankedStage.segmentSeconds
            XCTAssertEqual(e.e, Double((k + 1) * RankedStage.segmentSeconds))
            XCTAssertLessThan(e.s, e.e)
        }
        XCTAssertEqual(RankedStage.stage(seed: 12345), st, "同じ種なら同じステージ")
        XCTAssertNotEqual(RankedStage.stage(seed: 12346).emitters, st.emitters)
    }

    func testSegmentSeedWraps() {
        XCTAssertEqual(RankedStage.segmentSeed(0xFFFF_FFFF, 1), 0xFFFF_FFFF &+ 0x9E37_79B1)
        XCTAssertEqual(RankedStage.segmentSeed(7, 0), 7)
    }

    func testScoreAndCompare() {
        let still = RankedStage.score(seed: 99, moves: Array(repeating: .zero, count: 30_000))
        XCTAssertGreaterThan(still.ticks, 0)
        XCTAssertLessThanOrEqual(still.ticks, 180 * 120 + 1)
        // 記録が途中で尽きたら、そこで終わり
        let short = RankedStage.score(seed: 99, moves: Array(repeating: .zero, count: 50))
        XCTAssertLessThanOrEqual(short.ticks, 50)
        XCTAssertEqual(RankedStage.compare(.init(ticks: 100, grazes: 0), .init(ticks: 99, grazes: 50)), 1)
        XCTAssertEqual(RankedStage.compare(.init(ticks: 100, grazes: 3), .init(ticks: 100, grazes: 5)), -1)
        XCTAssertEqual(RankedStage.compare(.init(ticks: 100, grazes: 5), .init(ticks: 100, grazes: 5)), 0)
    }

    /// 無敵で最後まで進めると、180 秒で終わる(上限)
    func testEndsAt180() {
        var sim = Simulation(stage: RankedStage.stage(seed: 5))
        sim.invincible = true
        while sim.outcome == .playing && sim.tick < 200 * 120 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .cleared)
        XCTAssertGreaterThanOrEqual(sim.t, 180)
        XCTAssertLessThan(sim.t, 181)
    }

    // MARK: サーバーとの照合データ(EXPORT_RANKED_FIXTURES にファイルの場所を渡したときだけ書き出す)

    struct Fixture: Codable {
        var seed: UInt32
        var stage: Stage
        var style: Int
        var replay: String
        var steps: Int
        var ticks: Int
        var grazes: Int
        /// 無敵で最後まで進めたときの、弾の数・位置(丸め)・かすった数(後半の区切りまで一致を確かめる)
        var fullBullets: Int
        var fullHashCoarse: UInt32
        var fullGrazes: Int
        var fullTicks: Int
    }

    private struct XorShift {
        var s: UInt64
        mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
        mutating func unit() -> Double { Double(next() % 1_000_000) / 1_000_000 }
    }

    private func moves(style: Int, count: Int, seed: UInt64) -> [Move] {
        var r = XorShift(s: seed &* 2654435761 &+ 88172645463325252)
        var out: [Move] = []
        var dx = 0, dy = 0
        for i in 0..<count {
            switch style {
            case 0: out.append(.zero)
            case 1:
                if i % 24 == 0 { dx = Int(r.unit() * 8) - 4; dy = Int(r.unit() * 6) - 3 }
                out.append(Move(dx: Int8(dx), dy: Int8(dy)))
            case 2: out.append(Move(dx: Int8((i / 90) % 2 == 0 ? 3 : -3), dy: 0))
            default:
                if i % 12 == 0 { dx = Int(r.unit() * 40) - 20; dy = Int(r.unit() * 30) - 15 }
                out.append(Move(dx: Int8(dx), dy: Int8(dy)))
            }
        }
        return out
    }

    func testExportFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["EXPORT_RANKED_FIXTURES"] else { throw XCTSkip("書き出し先が無いので飛ばす") }
        var out: [Fixture] = []
        let seeds: [UInt32] = [1, 42, 777, 9_999, 123_456, 0xDEAD_BEEF, 0xFFFF_FFFF, 31_337]
        var rs: UInt64 = 10
        for seed in seeds {
            let st = RankedStage.stage(seed: seed)
            var full = Simulation(stage: st)
            full.invincible = true
            while full.outcome == .playing && full.tick < 200 * 120 { full.step(.zero) }
            let fr = full.result
            for style in 0..<4 {
                rs += 1
                let mv = moves(style: style, count: 24_000, seed: rs)
                let sc = RankedStage.score(seed: seed, moves: mv)
                let used = Array(mv.prefix(sc.ticks))
                out.append(Fixture(seed: seed, stage: st, style: style, replay: Replay(moves: used).encoded(), steps: used.count,
                                   ticks: sc.ticks, grazes: sc.grazes, fullBullets: fr.bulletCount, fullHashCoarse: fr.bulletHashCoarse,
                                   fullGrazes: full.grazeCount, fullTicks: full.tick))
            }
        }
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(out).write(to: URL(fileURLWithPath: path))
        print("ranked fixtures:", out.count, "ticks:", out.map(\.ticks))
    }
}
