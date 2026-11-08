import XCTest
@testable import DanmakuCore

/// サーバーに残った「ずれた提出」(swipeMismatches)を、アプリと同じ計算で遊び直す調査用。SWIPE_MISMATCH があるときだけ動く
func mmLog(_ s: String) {
    guard let p = ProcessInfo.processInfo.environment["SWIPE_LOG"] else { return }
    if let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); try? h.close() }
}

final class SwipeMismatchReplayTests: XCTestCase {
    func testReplayMismatch() throws {
        guard let path = ProcessInfo.processInfo.environment["SWIPE_MISMATCH"] else { throw XCTSkip("調査用") }
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        func strings(_ k: String) -> [String] { ((root[k] as! [String: Any])["arrayValue"] as! [String: Any])["values"].map { ($0 as! [[String: Any]]).map { $0["stringValue"] as! String } } ?? [] }
        let ids = strings("clipIDs")
        let clips = ((root["clips"] as! [String: Any])["arrayValue"] as! [String: Any])["values"] as! [[String: Any]]
        if let poolPath = ProcessInfo.processInfo.environment["SWIPE_POOL"] {
            let pj = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: poolPath))) as! [String: Any]
            let pool = (pj["pool"] as! [[String: Any]]).map { SwipeFeed.Entry(id: $0["id"] as! String, d: $0["d"] as! Int, author: $0["author"] as! String) }
            let seed = UInt32((root["seed"] as! [String: Any])["integerValue"] as! String)!
            var used = Set<String>()
            var picked: [String] = []
            for i in 0..<ids.count {
                let e = SwipeFeed.pick(pool: pool, seed: seed, index: i, streak: i, used: used, excludedAuthors: [])!
                used.insert(e.id); picked.append(e.id)
            }
            mmLog("MISMATCH アプリ側の選び方: \(picked)")
            mmLog("MISMATCH サーバー記録    : \(ids)")
        }
        var scoring = SwipeScoring()
        var result = SwipeRun.Result()
        for (i, id) in ids.enumerated() {
            let f = (clips[i]["mapValue"] as! [String: Any])["fields"] as! [String: Any]
            let go = Replay(encoded: (f["go"] as! [String: Any])["stringValue"] as! String)!.moves
            let mv = Replay(encoded: (f["moves"] as! [String: Any])["stringValue"] as! String)!.moves
            let g = SwipeGenerator.parse(id: id)!
            let stage = SwipeGenerator.stage(seed: g.seed, hard: g.hard)
            do {
                var sc3 = scoring
                var p3 = SwipeClipPlayer(stage: stage, at: SwipeGenerator.clipAt, scoring: &sc3)
                for m in go.prefix(SwipeClip.goSteps) { p3.nudge(m) }
                var near = 0, tie = 0, grazes = 0
                for m in mv.prefix(SwipeClip.playSteps) {
                    let px = p3.sim.player.x, py = p3.sim.player.y
                    let before = p3.sim.bullets
                    _ = before
                    let ev = p3.advance(m, scoring: &sc3)
                    grazes += ev.grazes.count
                    for (b, _) in ev.grazes {
                        let dx = b.x - p3.sim.player.x, dy = b.y - p3.sim.player.y
                        let d2 = dx * dx + dy * dy
                        mmLog("MISMATCH graze clip \(i) step \(p3.step) 余裕=\(b.grazeDistanceSquared - d2) 比=\(d2 / b.grazeDistanceSquared) 被弾の輪=\(d2 / b.hitDistanceSquared) 遮蔽=\(p3.sim.isShielded)")
                    }
                    for b in p3.sim.bullets where !b.isBeam && !b.isBlast && !b.grazed {
                        let dx = b.x - p3.sim.player.x, dy = b.y - p3.sim.player.y
                        let g = abs(dx * dx + dy * dy - b.grazeDistanceSquared)
                        if g < 1e-6 { near += 1 }
                        if g == 0 { tie += 1 }
                    }
                    _ = (px, py)
                    if ev.end != nil { break }
                }
                mmLog("MISMATCH clip \(i) かすり=\(grazes) 境目(差<1e-6)=\(near) 完全に同じ=\(tie)")
            }
            if i == ids.count - 1 {
                for pre in [0, 1, 5, 20, 30, 36, 37, 38, 39, 40, 41, 42] {
                    var sc4 = SwipeScoring(); sc4.beginClip()
                    for k in 0..<pre { _ = sc4.graze(step: k + 1) }
                    var p4 = SwipeClipPlayer(stage: stage, at: SwipeGenerator.clipAt, scoring: &sc4)
                    for m in go.prefix(SwipeClip.goSteps) { p4.nudge(m) }
                    var endStep = 0, endKind = "なし", bombAt: [Int] = []
                    for (n, m) in mv.prefix(SwipeClip.playSteps).enumerated() {
                        let ev = p4.advance(m, scoring: &sc4)
                        if ev.bomb != nil { bombAt.append(n + 1) }
                        if let e = ev.end { endStep = n + 1; endKind = "\(e)"; break }
                    }
                    mmLog("MISMATCH 事前のかすり=\(pre) → \(endKind) step=\(endStep) ボム=\(bombAt)")
                }
                var sc2 = scoring
                var pl = SwipeClipPlayer(stage: stage, at: SwipeGenerator.clipAt, scoring: &sc2)
                for m in go.prefix(SwipeClip.goSteps) { pl.nudge(m) }
                for (n, m) in mv.prefix(SwipeClip.playSteps).enumerated() {
                    let ev = pl.advance(m, scoring: &sc2)
                    var mg = Double.infinity
                    for b in pl.sim.bullets where !b.isBeam && !b.isBlast { let dx = b.x - pl.sim.player.x, dy = b.y - pl.sim.player.y; mg = min(mg, abs(dx * dx + dy * dy - b.hitDistanceSquared)) }
                    if mg < 1e-3 { mmLog("MISMATCH 境目 step \(n + 1) 差=\(mg)") }
                    if ev.bomb != nil { mmLog("MISMATCH bomb at step \(n + 1) shieldUntil=\(pl.sim.shieldUntilTick) tick=\(pl.sim.tick)") }
                    if ev.end != nil { mmLog("MISMATCH end \(String(describing: ev.end)) at step \(n + 1) player=\(pl.sim.player) bullets=\(pl.sim.bullets.count)"); break }
                }
            }
            let end = SwipeRun.playClip(stage: stage, at: SwipeGenerator.clipAt, input: SwipeRun.ClipInput(go: go, moves: mv, skipped: false), scoring: &scoring, result: &result)
            mmLog("MISMATCH clip \(i) \(id) moves=\(mv.count) -> \(end) score=\(scoring.score.description) bombs=\(result.bombs)")
        }
    }
}
