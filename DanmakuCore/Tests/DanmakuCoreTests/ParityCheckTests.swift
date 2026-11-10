import XCTest
@testable import DanmakuCore
/// 速い照合用(tools/parity.sh から使う。環境変数 PARITY_PATTERNS が無いときは何もしない)
final class ParityCheckTests: XCTestCase {
    func testWrite() throws {
        guard let list = ProcessInfo.processInfo.environment["PARITY_PATTERNS"] else { throw XCTSkip("") }
        var out: [[String: Any]] = []
        let look = Int(ProcessInfo.processInfo.environment["PARITY_LOOK"] ?? "7")!
        for spec in list.split(separator: ",") {
            let f = spec.split(separator: ":").map(String.init)
            let name = f[0]
            guard let t = DanmakuCore.Pattern(rawValue: name) else { XCTFail("unknown \(name)"); continue }
            let d = Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 20, i: Double(f[1])!, c: Int(f[2])!, v: Double(f[3])!, r: Double(f[4])!, k: 0)
            for aw in [nil, 2] as [Int?] {
                for mir in [nil, 1] as [Int?] {
                    var e = d; e.s = 0; e.e = 20; e.x = 0.5; e.y = 0.2; e.k = 0; e.mir = mir
                    let st = Stage(name: "p", mode: .boss, durationSec: 20, bossHp: 99999, emitters: [e], lifeMode: .hp, lifeCount: 400, bossLook: look, awaken: aw).sanitized()
                    let r = Simulation.run(stage: st, moves: [])
                    out.append(["t": "\(name)", "aw": aw ?? 0, "mir": mir ?? 0, "stage": try JSONSerialization.jsonObject(with: JSONEncoder().encode(st)), "outcome": "\(r.outcome)", "steps": r.steps, "n": r.bulletCount, "coarse": r.bulletHashCoarse])
                }
            }
        }
        try JSONSerialization.data(withJSONObject: out).write(to: URL(fileURLWithPath: "/tmp/parity_swift.json"))
    }
}
