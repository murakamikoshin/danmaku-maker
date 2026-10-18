import XCTest
@testable import DanmakuCore

/// tools/make_reference.mjs が試作の JS を実際に動かして作った正解データと比べる
final class PrototypeParityTests: XCTestCase {
    struct Snap: Decodable { var tick: Int; var count: Int; var hp: Int; var phase: Int; var sumX: Double; var sumY: Double; var firstX: Double; var firstY: Double }
    struct Over: Decodable { var tick: Int; var kind: String; var hp: Int }
    struct Case: Decodable { var name: String; var seed: UInt32; var stage: Stage; var snapshots: [Snap]; var over: Over? }

    func testMatchesPrototypeStepByStep() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "reference", withExtension: "json", subdirectory: "Resources"))
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: url))
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let stage = c.stage.sanitized()
            XCTAssertEqual(stage, c.stage, "\(c.name): 正解データのステージは丸め済みのはず")
            var sim = Simulation(stage: stage, seed: c.seed)
            var snaps = c.snapshots[...]
            var overTick: Int?
            for tick in 1...8000 {
                sim.step(.zero)
                if sim.outcome != .playing { overTick = tick; break }
                if let s = snaps.first, s.tick == tick {
                    snaps = snaps.dropFirst()
                    XCTAssertEqual(sim.bullets.count, s.count, "\(c.name) tick \(tick) 弾数")
                    XCTAssertEqual(sim.hp, s.hp, "\(c.name) tick \(tick) HP")
                    XCTAssertEqual(sim.phase, s.phase, "\(c.name) tick \(tick) 段階")
                    XCTAssertEqual(sim.bullets.reduce(0) { $0 + $1.x }, s.sumX, accuracy: 1e-6, "\(c.name) tick \(tick) x合計")
                    XCTAssertEqual(sim.bullets.reduce(0) { $0 + $1.y }, s.sumY, accuracy: 1e-6, "\(c.name) tick \(tick) y合計")
                    XCTAssertEqual(sim.bullets.first?.x ?? 0, s.firstX, accuracy: 1e-9, "\(c.name) tick \(tick)")
                    XCTAssertEqual(sim.bullets.first?.y ?? 0, s.firstY, accuracy: 1e-9, "\(c.name) tick \(tick)")
                }
            }
            XCTAssertTrue(snaps.isEmpty, "\(c.name): 比べ損ねたスナップショットあり")
            XCTAssertEqual(overTick, c.over?.tick, "\(c.name) 終了ステップ")
            XCTAssertEqual(sim.outcome == .cleared, c.over?.kind == "win", "\(c.name) 勝敗")
            XCTAssertEqual(sim.hp, c.over?.hp, "\(c.name) 終了時HP")
        }
    }
}
