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
}
