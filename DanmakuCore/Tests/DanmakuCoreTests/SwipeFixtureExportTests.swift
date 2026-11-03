import XCTest
@testable import DanmakuCore

/// サーバー(TypeScript)のスワイプ弾幕の計算が、この Swift 版と一致するかを確かめる「正解データ」を書き出す。
/// 環境変数 EXPORT_SWIPE_FIXTURES にファイルの場所を渡したときだけ動く。
final class SwipeFixtureExportTests: XCTestCase {
    struct Prepared: Codable { var at: Double; var px: Double; var py: Double; var bulletCount: Int; var hashCoarse: UInt32; var tick: Int }
    struct Cand: Codable { var at: Double; var total: Int }
    struct RunClip: Codable { var go: [Int]; var moves: [Int]; var skipped: Bool }
    struct RunCase: Codable {
        var seed: UInt32
        var clips: [RunClip]
        var clipIDs: [String]; var scoreAfterEachClip: [String]; var score: String
        var streak: Int; var bestStreak: Int; var clipsPlayed: Int; var clipsCleared: Int
        var bombs: Int; var grazes: Int; var endedByHit: Bool; var abandoned: Bool; var invalid: String?
    }
    struct Case: Codable {
        var name: String
        var stage: Stage
        var counts: [Int]; var gaps: [Bool]
        var candidates: [Cand]
        var prepared: [Prepared]
        var runs: [RunCase]
    }
    struct Out: Codable { var pool: [SwipeFeed.Entry]; var cases: [Case] }

    private func clipMoves(style: Int, count: Int, seed: Int) -> [Int] {
        var s = UInt64(seed) &* 2654435761 &+ 88172645463325252
        func next() -> Double { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return Double(s % 1_000_000) / 1_000_000 }
        var out: [Int] = []
        var dx = 0, dy = 0
        for i in 0..<count {
            switch style {
            case 0: dx = 0; dy = 0
            case 1: if i % 24 == 0 { dx = Int(next() * 8) - 4; dy = Int(next() * 6) - 3 }
            case 2: dx = (i / 90) % 2 == 0 ? 3 : -3; dy = 0
            default: if i % 12 == 0 { dx = Int(next() * 40) - 20; dy = Int(next() * 30) - 15 }
            }
            out.append(dx); out.append(dy)
        }
        return out
    }

    static func clipAt(_ id: String) -> Double { Double((Int(id.dropFirst()) ?? 0) % 4) * 2 }

    func testExportSwipeFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["EXPORT_SWIPE_FIXTURES"] else { throw XCTSkip("書き出し先が未指定") }
        let all = DanmakuCore.Pattern.allCases
        var stages: [(String, Stage)] = []
        func em(_ p: DanmakuCore.Pattern, _ idx: Int, boss: Bool) -> Emitter {
            Emitter(t: p, x: 0.3 + 0.1 * Double(idx % 5), y: 0.15 + 0.05 * Double(idx % 4), s: boss ? 0 : Double(idx % 3) * 0.7, e: 30,
                    i: [0.35, 0.5, 0.2, 0.8][idx % 4], c: [6, 10, 3, 16][idx % 4], v: [2, 2.5, 3, 1.5][idx % 4],
                    r: [12, 40, -25, 90][idx % 4], k: idx % 5, ph: boss ? idx % 4 : 0, a: [0, 45, -90, 135][idx % 4],
                    path: p == .custom ? FixtureExportTests.samplePath : nil)
        }
        for (i, p) in all.enumerated() {
            stages.append(("survive-\(p.rawValue)", Stage(name: "s", mode: .survive, durationSec: 20, emitters: [em(p, i, boss: false), em(all[(i + 5) % all.count], i + 1, boss: false), em(.ring, 2, boss: false)]).sanitized()))
        }
        stages.append(("boss-mix", Stage(name: "b", mode: .boss, durationSec: 40, bossHp: 200, bossMove: 1, emitters: [.ring, .aim, .sweep, .corner, .spiral].enumerated().map { em($1, $0, boss: true) }).sanitized()))
        stages.append(("damage-mix", Stage(name: "d", mode: .damage, durationSec: 30, bossMove: 2, emitters: [.ring, .aim, .rain].enumerated().map { em($1, $0, boss: true) }).sanitized()))
        let seqEm = [em(.spiral, 0, boss: false), em(.aim, 1, boss: false), em(.ring, 2, boss: false)]
        let bossEm = [em(.ring, 0, boss: true), em(.homing, 1, boss: true), em(.flower, 2, boss: true), em(.aim, 3, boss: true)]
        stages.append(("seq-mix", Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: [
            Wave(kind: .survive, durationSec: 20, emitters: seqEm),
            Wave(kind: .boss, durationSec: 30, bossHp: 150, bossMove: 1, emitters: bossEm),
            Wave(kind: .survive, durationSec: 15, emitters: seqEm)]).sanitized()))

        let pool = (0..<40).map { SwipeFeed.Entry(id: String(format: "R%03d", $0), d: [900, 700, 500, 300, 100, 850, 450][$0 % 7], author: "u\($0 % 4)") }
        var cases: [Case] = []
        for (n, (name, st)) in stages.enumerated() {
            let (counts, gaps) = SwipeClipPicker.sample(stage: st)
            let cands = SwipeClipPicker.candidates(counts: counts, gaps: gaps).map { Cand(at: $0.at, total: $0.total) }
            var prepared: [Prepared] = []
            for at in [0.0, 2.0, 6.0] {
                let sim = SwipeClip.prepare(stage: st, at: at)
                prepared.append(Prepared(at: at, px: sim.player.x, py: sim.player.y, bulletCount: sim.bullets.count, hashCoarse: sim.result.bulletHashCoarse, tick: sim.tick))
            }
            var runs: [RunCase] = []
            for style in 0..<4 {
                let clips = (0..<3).map { k in
                    RunClip(go: clipMoves(style: (style + k) % 4, count: 60, seed: n * 100 + style * 10 + k),
                            moves: clipMoves(style: style, count: 1200, seed: n * 1000 + style * 10 + k),
                            skipped: style == 1 && k == 1)
                }
                let seed = UInt32(n * 7 + style + 1)
                let r = SwipeRun.play(seed: seed, pool: pool, excludedAuthors: ["u3"], source: { id in (st, SwipeFixtureExportTests.clipAt(id)) },
                                      clips: clips.map { c in SwipeRun.ClipInput(go: stride(from: 0, to: c.go.count, by: 2).map { Move(dx: Int8(c.go[$0]), dy: Int8(c.go[$0 + 1])) },
                                                                                 moves: stride(from: 0, to: c.moves.count, by: 2).map { Move(dx: Int8(c.moves[$0]), dy: Int8(c.moves[$0 + 1])) },
                                                                                 skipped: c.skipped) })
                runs.append(RunCase(seed: seed, clips: clips, clipIDs: r.clipIDs, scoreAfterEachClip: r.scoreAfterEachClip, score: r.score.description,
                                    streak: r.streak, bestStreak: r.bestStreak, clipsPlayed: r.clipsPlayed, clipsCleared: r.clipsCleared,
                                    bombs: r.bombs, grazes: r.grazes, endedByHit: r.endedByHit, abandoned: r.abandoned, invalid: r.invalid))
            }
            cases.append(Case(name: name, stage: st, counts: counts, gaps: gaps, candidates: cands, prepared: prepared, runs: runs))
        }
        let enc = JSONEncoder()
        try enc.encode(Out(pool: pool, cases: cases)).write(to: URL(fileURLWithPath: path))
    }
}
