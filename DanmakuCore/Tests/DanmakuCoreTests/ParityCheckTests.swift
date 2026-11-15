import XCTest
@testable import DanmakuCore
/// 速い照合用(tools/parity.sh から使う。環境変数 PARITY_PATTERNS が無いときは何もしない)
final class ParityCheckTests: XCTestCase {
    func testWrite() throws {
        guard let list = ProcessInfo.processInfo.environment["PARITY_PATTERNS"] else { throw XCTSkip("") }
        var out: [[String: Any]] = []
        let look = Int(ProcessInfo.processInfo.environment["PARITY_LOOK"] ?? "7")!
        let size = ProcessInfo.processInfo.environment["PARITY_SIZE"].flatMap { Int($0) }
        for spec in list.split(separator: ",") {
            let f = spec.split(separator: ":").map(String.init)
            let name = f[0]
            guard let t = DanmakuCore.Pattern(rawValue: name) else { XCTFail("unknown \(name)"); continue }
            let d = Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 20, i: Double(f[1])!, c: Int(f[2])!, v: Double(f[3])!, r: Double(f[4])!, k: 0)
            for aw in [nil, 2] as [Int?] {
                for mir in [nil, 1] as [Int?] {
                    var e = d; e.s = 0; e.e = 20; e.x = 0.5; e.y = 0.2; e.k = 0; e.mir = mir
                    let st = Stage(name: "p", mode: .boss, durationSec: 20, bossHp: 99999, emitters: [e], lifeMode: .hp, lifeCount: 400, bossSize: size, bossLook: look, awaken: aw).sanitized()
                    let r = Simulation.run(stage: st, moves: [])
                    out.append(["t": "\(name)", "aw": aw ?? 0, "mir": mir ?? 0, "stage": try JSONSerialization.jsonObject(with: JSONEncoder().encode(st)), "outcome": "\(r.outcome)", "steps": r.steps, "n": r.bulletCount, "coarse": r.bulletHashCoarse])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: "/tmp/parity_swift.json"))
    }

    /// 狙い方(固定・ランダム)の一致を調べる(環境変数 PARITY_AIM があるときだけ。tools/parity.sh と同じ /tmp/parity_swift.json に書く)
    func testWriteAim() throws {
        guard ProcessInfo.processInfo.environment["PARITY_AIM"] != nil else { throw XCTSkip("") }
        var out: [[String: Any]] = []
        let pats = DanmakuCore.Pattern.allCases.filter { Emitter(t: $0).aimSupport != .none && $0 != .custom }
        for t in pats {
            for aim in [1, 2] {
                for mode in [Mode.boss, .survive] {
                    for mir in [nil, 1] as [Int?] {
                        let e = Emitter(t: t, x: 0.4, y: 0.25, s: 0, e: 12, i: 0.4, c: 5, v: 2, r: 15, k: 1, p: 1, mir: mir, aim: aim)
                        var st = Stage(name: "p", mode: mode, durationSec: 12, bossHp: mode == .boss ? 99999 : nil, emitters: [e], lifeMode: .hp, lifeCount: 400)
                        st = st.sanitized()
                        guard st.emitters.first?.t == t else { continue }
                        let r = Simulation.run(stage: st, moves: [], month: 24310 + aim)
                        out.append(["t": "\(t)/aim\(aim)/\(mode)", "aw": 0, "mir": mir ?? 0, "month": 24310 + aim, "stage": try JSONSerialization.jsonObject(with: JSONEncoder().encode(st)), "outcome": "\(r.outcome)", "steps": r.steps, "n": r.bulletCount, "coarse": r.bulletHashCoarse])
                    }
                }
            }
        }
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: "/tmp/parity_swift.json"))
    }

    /// 段階 4・5 と 1UP の一致を調べる(環境変数 PARITY_PHASES があるときだけ。/tmp/parity_swift.json に書く)
    func testWritePhasesAndOneUp() throws {
        guard ProcessInfo.processInfo.environment["PARITY_PHASES"] != nil else { throw XCTSkip("") }
        var out: [[String: Any]] = []
        func add(_ name: String, _ st: Stage, follow: Bool = false) throws {
            // 1UP を追いかける操作(拾う形の確認)。追わないときは操作なし
            var sim = Simulation(stage: st)
            var moves: [Move] = []
            let limit = (st.timeLimitSec + 3) * 120 + 144
            while sim.outcome == .playing && sim.tick < limit {
                var mv = Move.zero
                if follow, let item = sim.oneUpItem { mv.dx = item.x > sim.player.x + 1 ? 4 : item.x < sim.player.x - 1 ? -4 : 0 }
                // 追わないときは、1UP から離れる(取り逃して、画面の下で消える道筋も確かめる)
                else if !follow, let item = sim.oneUpItem { mv.dx = item.x < 100 ? 4 : -4 }
                moves.append(mv); sim.step(mv)
            }
            let r = sim.result
            out.append(["t": name, "aw": 0, "mir": 0, "stage": try JSONSerialization.jsonObject(with: JSONEncoder().encode(st)), "replay": Replay(moves: moves).encoded(),
                        "outcome": "\(r.outcome)", "steps": r.steps, "n": r.bulletCount, "coarse": r.bulletHashCoarse, "life": sim.lifeLeft, "taken": sim.oneUpsTaken])
        }
        for n in [4, 5] {
            for ph in [0, 1, n, 13, n == 5 ? 135 : 24, n == 5 ? 45 : 34] {
                var s = Stage(name: "p", mode: .boss, durationSec: 60, bossHp: 300, bossMove: 1, emitters: [Emitter(t: .ring, i: 0.4, c: 10, ph: ph), Emitter(t: .aim, i: 0.7, c: 3, ph: 0)], lifeMode: .hp, lifeCount: 20)
                s.phases = n
                try add("boss\(n)/ph\(ph)", s.sanitized())
                var d = Stage(name: "d", mode: .damage, durationSec: 30, emitters: [Emitter(t: .ring, i: 0.4, c: 10, ph: ph)], lifeMode: .hp, lifeCount: 20)
                d.phases = n
                try add("damage\(n)/ph\(ph)", d.sanitized())
            }
        }
        for oneUp in [1, 2] {
            for mode in [LifeMode.lives, .hp] {
                for follow in [false, true] {
                    var w1 = Wave(kind: .boss, durationSec: 60, bossHp: 100, bossMove: 2, emitters: [Emitter(t: .ring, i: 2.5, c: 3, v: 1)])
                    w1.oneUp = oneUp; w1.phases = 4
                    let w2 = Wave(kind: .survive, durationSec: 10, emitters: [Emitter(t: .aim, x: 0.5, y: 0.1, i: 1.5, c: 1)])
                    var w3 = Wave(kind: .boss, durationSec: 30, bossHp: 200, bossMove: 0, emitters: [Emitter(t: .ring, i: 0.5, c: 8)])
                    w3.phases = 5
                    let st = Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], lifeMode: mode, lifeCount: mode == .lives ? 3 : 12, waves: [w1, w2, w3]).sanitized()
                    try add("seq/oneUp\(oneUp)/\(mode)/follow\(follow)", st, follow: follow)
                }
            }
        }
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: "/tmp/parity_swift.json"))
    }
}
