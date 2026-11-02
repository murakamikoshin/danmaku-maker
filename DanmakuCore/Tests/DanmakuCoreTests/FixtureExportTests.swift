import XCTest
@testable import DanmakuCore

/// サーバー(TypeScript)側のゲーム再現が、この Swift 版と一致するかを確かめるための「正解データ」を書き出す。
/// 環境変数 EXPORT_SIM_FIXTURES にファイルの場所を渡したときだけ動く(普段のテストでは何もしない)。
final class FixtureExportTests: XCTestCase {
    struct Case: Codable {
        var name: String
        var stage: Stage
        var shot: String
        var replay: String
        var steps: Int
        var expect: Expect
    }
    struct Expect: Codable {
        var outcome: String
        var tick: Int
        var hp: Int
        var damage: Int
        var lifeLeft: Int
        var wave: Int
        var defeats: Int
        var bulletCount: Int
        var bulletHash: UInt32
        var bulletHashCoarse: UInt32
    }

    /// 決まった乱数で、操作記録を作る
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
            case 0: out.append(.zero)                                       // 動かない
            case 1:                                                          // ランダムに動く(しばらく同じ向き)
                if i % 24 == 0 { dx = Int(r.unit() * 8) - 4; dy = Int(r.unit() * 6) - 3 }
                out.append(Move(dx: Int8(dx), dy: Int8(dy)))
            case 2: out.append(Move(dx: Int8((i / 90) % 2 == 0 ? 3 : -3), dy: 0))   // 左右に往復
            default:                                                         // 大きく速く動く
                if i % 12 == 0 { dx = Int(r.unit() * 40) - 20; dy = Int(r.unit() * 30) - 15 }
                out.append(Move(dx: Int8(dx), dy: Int8(dy)))
            }
        }
        return out
    }

    /// 弾幕作成モードで描いた軌道の見本(左右に揺れながら下へ進み、最後は速く横へ抜ける)
    static let samplePath: [Double] = PathData.sanitized((0..<36).flatMap { i -> [Double] in
        let t = Double(i)
        return [70 * sin(t * 0.3), t * 5.5 + (i > 30 ? Double(i - 30) * Double(i - 30) * 3 : 0)]
    }) ?? []

    private func emitters(_ patterns: [DanmakuCore.Pattern], boss: Bool) -> [Emitter] {
        let intervals: [Double] = [0.35, 0.5, 0.2, 0.8]
        let counts: [Int] = [6, 10, 3, 16]
        let speeds: [Double] = [2, 2.5, 3, 1.5]
        let angles: [Double] = [12, 40, -25, 90]
        var out: [Emitter] = []
        for (idx, p) in patterns.enumerated() {
            let x: Double = 0.3 + 0.1 * Double(idx % 5)
            let y: Double = 0.15 + 0.05 * Double(idx % 4)
            let s: Double = boss ? 0 : Double(idx) * 0.7
            let ph: Int = boss ? idx % 4 : 0
            out.append(Emitter(t: p, x: x, y: y, s: s, e: 30, i: intervals[idx % 4], c: counts[idx % 4],
                               v: speeds[idx % 4], r: angles[idx % 4], k: idx % 5, ph: ph, a: [0, 45, -90, 135][idx % 4],
                               path: p == .custom ? FixtureExportTests.samplePath : nil))
        }
        return out
    }

    func testExportFixtures() throws {
        guard let path = ProcessInfo.processInfo.environment["EXPORT_SIM_FIXTURES"] else { throw XCTSkip("書き出し先が未指定") }
        let all: [DanmakuCore.Pattern] = DanmakuCore.Pattern.allCases
        var stages: [(String, Stage)] = []
        for (i, p) in all.enumerated() {
            stages.append(("survive-\(p.rawValue)", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([p, all[(i + 3) % all.count]], boss: false)).sanitized()))
        }
        stages.append(("survive-all", Stage(name: "s", mode: .survive, durationSec: 30, emitters: Array(emitters(all, boss: false).prefix(8))).sanitized()))
        stages.append(("survive-all2", Stage(name: "s", mode: .survive, durationSec: 30, emitters: Array(emitters(Array(all.suffix(8)), boss: false))).sanitized()))
        stages.append(("survive-homing", Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .homing, x: 0.5, y: 0.1, s: 0, e: 20, i: 0.9, c: 3, v: 2, r: 60, k: 2)]).sanitized()))
        stages.append(("survive-lives3", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([.aim, .spiral], boss: false), lifeMode: .lives, lifeCount: 3).sanitized()))
        stages.append(("survive-hp8", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([.rain, .ring], boss: false), lifeMode: .hp, lifeCount: 8).sanitized()))
        // チャージビーム: ためてから撃つ光線(当たり方が弾と違う)。ライフ制・HP制・ボス戦で
        let beams = [Emitter(t: .chargeBeam, x: 0.5, y: 0.1, s: 0, e: 20, i: 1.6, c: 3, v: 2, r: 50, k: 1),
                     Emitter(t: .chargeBeam, x: 0.2, y: 0.3, s: 0.8, e: 20, i: 2.2, c: 1, v: 2, r: 0, k: 3)]
        stages.append(("survive-beam-lives3", Stage(name: "s", mode: .survive, durationSec: 20, emitters: beams, lifeMode: .lives, lifeCount: 3).sanitized()))
        stages.append(("survive-beam-hp6", Stage(name: "s", mode: .survive, durationSec: 20, emitters: beams + emitters([.ring], boss: false), lifeMode: .hp, lifeCount: 6).sanitized()))
        stages.append(("survive-giant-hp5", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([.giantOrb, .boomerang, .sweepLaser], boss: false), lifeMode: .hp, lifeCount: 5).sanitized()))
        stages.append(("boss-sweep-boomerang", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 250, bossMove: 2, emitters: emitters([.sweepLaser, .boomerang, .giantOrb], boss: true), lifeMode: .lives, lifeCount: 4).sanitized()))
        stages.append(("survive-pack2-hp8", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([.mine, .meteor, .gridLaser, .gravity], boss: false), lifeMode: .hp, lifeCount: 8).sanitized()))
        stages.append(("survive-pack2b-lives3", Stage(name: "s", mode: .survive, durationSec: 20, emitters: emitters([.orbit, .snake, .bubble, .mine], boss: false), lifeMode: .lives, lifeCount: 3).sanitized()))
        stages.append(("boss-pack2", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 250, bossMove: 1, emitters: emitters([.meteor, .orbit, .bubble, .gravity], boss: true), lifeMode: .hp, lifeCount: 10).sanitized()))
        stages.append(("boss-beam", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 200, bossMove: 1, emitters: emitters([.chargeBeam, .aim], boss: true), lifeMode: .lives, lifeCount: 3).sanitized()))
        for hp in [100, 300] {
            stages.append(("boss-hp\(hp)", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: hp, bossMove: 1, emitters: emitters([.ring, .aim, .sweep, .corner], boss: true)).sanitized()))
        }
        stages.append(("boss-lives5", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 200, bossMove: 2, emitters: emitters([.spiral, .sideL, .sideR], boss: true), lifeMode: .lives, lifeCount: 5).sanitized()))
        for size in [0, 2] {
            stages.append(("boss-size\(size)", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, bossMove: 1, emitters: emitters([.ring, .aim, .sweep], boss: true), bossSize: size, mooks: 1, bossLook: 2, mookLook: 3).sanitized()))
        }
        stages.append(("boss-unlimited", Stage(name: "b", mode: .boss, durationSec: 0, bossHp: 700, bossMove: 1, emitters: emitters([.ring, .homing, .sideL], boss: true)).sanitized()))
        stages.append(("boss-firepoint", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, bossMove: 1, emitters: [
            Emitter(t: .spiral, x: 0.15, y: 0.45, s: 0, e: 30, i: 0.2, c: 3, v: 2, r: 11, k: 1, ph: 0, p: 1),
            Emitter(t: .aim, x: 0.85, y: 0.3, s: 0, e: 30, i: 0.7, c: 5, v: 2.5, r: 40, k: 3, ph: 0, p: 1),
            Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 1.0, c: 12, v: 1.5, r: 6, k: 0, ph: 0, p: 0)]).sanitized()))
        let seqEm: [Emitter] = [
            Emitter(t: .spiral, x: 0.5, y: 0.15, s: 0, e: 20, i: 0.25, c: 3, v: 1.8, r: 11, k: 1),
            Emitter(t: .aim, x: 0.3, y: 0.3, s: 2, e: 20, i: 0.9, c: 3, v: 2, r: 30, k: 3)]
        let bossEm: [Emitter] = [
            Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 60, i: 1.0, c: 12, v: 1.5, r: 6, k: 0, ph: 0, p: 0),
            Emitter(t: .homing, x: 0.5, y: 0.2, s: 0, e: 60, i: 1.6, c: 2, v: 1.6, r: 45, k: 2, ph: 2, p: 0),
            Emitter(t: .flower, x: 0.2, y: 0.4, s: 0, e: 60, i: 0.9, c: 24, v: 1.8, r: 6, k: 4, ph: 3, p: 1)]
        stages.append(("seq-2waves", Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], lifeMode: .lives, lifeCount: 5, waves: [
            Wave(kind: .survive, durationSec: 10, emitters: seqEm),
            Wave(kind: .boss, durationSec: 60, bossHp: 150, bossMove: 1, emitters: bossEm)]).sanitized()))
        stages.append(("seq-4waves", Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], lifeMode: .hp, lifeCount: 15, waves: [
            Wave(kind: .boss, durationSec: 30, bossHp: 100, bossMove: 0, emitters: bossEm),
            Wave(kind: .boss, durationSec: 30, bossHp: 100, bossMove: 2, emitters: bossEm, warning: true, defeat: 3),
            Wave(kind: .survive, durationSec: 10, emitters: seqEm),
            Wave(kind: .boss, durationSec: 60, bossHp: 250, bossMove: 1, emitters: bossEm)]).sanitized()))
        stages.append(("seq-survive-only", Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: [
            Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .sideL, x: 0.5, y: 0.1, s: 0, e: 10, i: 2, c: 1, v: 1, r: 0)]),
            Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .sideR, x: 0.5, y: 0.1, s: 0, e: 10, i: 2, c: 1, v: 1, r: 0)])]).sanitized()))
        stages.append(("boss-unlimited-lives", Stage(name: "b", mode: .boss, durationSec: 0, bossHp: 400, bossMove: 0, emitters: emitters([.aim, .corner], boss: true), lifeMode: .lives, lifeCount: 5).sanitized()))
        stages.append(("damage-easy", Stage(name: "d", mode: .damage, durationSec: 30, bossMove: 1, emitters: emitters([.ring], boss: true)).sanitized()))
        stages.append(("damage-moving", Stage(name: "d", mode: .damage, durationSec: 30, bossMove: 2, emitters: emitters([.aim, .rain, .corner], boss: true), lifeMode: .hp, lifeCount: 12).sanitized()))
        stages.append(("damage-empty", Stage(name: "d", mode: .damage, durationSec: 60, bossMove: 0, emitters: [Emitter(t: .ring, x: 0.5, y: 0.2, s: 0, e: 30, i: 2, c: 1, v: 1, r: 0, k: 0, ph: 3)]).sanitized()))

        // 堕天使(専用の位置・当たり判定)と覚醒。ここより前の並びは変えない(操作記録の乱数が変わるため)
        stages.append(("boss-angel", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 300, emitters: emitters([.ring, .aim, .sweep], boss: true), bossLook: 5, awaken: 3).sanitized()))
        stages.append(("boss-angel-lives3", Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 200, emitters: emitters([.spiral, .homing], boss: true), lifeMode: .lives, lifeCount: 3, bossLook: 5, awaken: 2).sanitized()))
        stages.append(("damage-angel", Stage(name: "d", mode: .damage, durationSec: 30, emitters: emitters([.ring, .aim], boss: true), bossLook: 5).sanitized()))
        stages.append(("seq-angel", Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], lifeMode: .hp, lifeCount: 12, waves: [
            Wave(kind: .boss, durationSec: 30, bossHp: 100, bossMove: 2, emitters: bossEm),
            Wave(kind: .boss, durationSec: 60, bossHp: 250, bossMove: 0, emitters: bossEm, bossLook: 5, awaken: 3)]).sanitized()))

        var cases: [Case] = []
        var seed: UInt64 = 1
        for (name, st) in stages {
            for shot in ShotType.allCases {
                for style in 0..<4 {
                    seed += 1
                    let limit = (st.timeLimitSec + 3) * 120 + 144
                    let mv = moves(style: style, count: limit, seed: seed)
                    var sim = Simulation(stage: st, shotType: shot)
                    var used = 0
                    while sim.outcome == .playing && sim.tick < limit { sim.step(sim.tick < mv.count ? mv[sim.tick] : .zero); used += 1 }
                    let trimmed = Array(mv.prefix(used))
                    let r = sim.result
                    let outcome: String
                    switch sim.outcome { case .cleared: outcome = "cleared"; case .hit: outcome = "hit"; case .timeUp: outcome = "timeUp"; case .playing: outcome = "playing" }
                    cases.append(Case(name: "\(name)/\(shot.rawValue)/m\(style)", stage: st, shot: shot.rawValue,
                                      replay: Replay(moves: trimmed).encoded(), steps: used,
                                      expect: Expect(outcome: outcome, tick: sim.tick, hp: sim.hp, damage: sim.damageDealt,
                                                     lifeLeft: sim.lifeLeft, wave: sim.waveIndex, defeats: sim.defeats, bulletCount: r.bulletCount, bulletHash: r.bulletHash, bulletHashCoarse: r.bulletHashCoarse)))
                }
            }
        }
        // 偏りがないか(クリア・被弾・時間切れ)
        let counts = Dictionary(grouping: cases, by: { $0.expect.outcome }).mapValues(\.count)
        print("fixture outcomes:", counts, "total", cases.count)
        XCTAssertGreaterThan(counts["cleared"] ?? 0, 10)
        XCTAssertGreaterThan(counts["hit"] ?? 0, 10)
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(cases).write(to: URL(fileURLWithPath: path))
    }
}
