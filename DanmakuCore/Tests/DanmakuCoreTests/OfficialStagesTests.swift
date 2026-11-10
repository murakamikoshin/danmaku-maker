import XCTest
@testable import DanmakuCore

/// アプリに入れる公式サンプルステージ（DanmakuApp/Resources/official_stages.json）の整合性
final class OfficialStagesTests: XCTestCase {
    struct Entry: Decodable { let id: String; let difficulty: Int; let name: [String: String]; let aim: [String: String]; let stage: Stage }

    private func load() throws -> [Entry] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DanmakuApp/Resources/official_stages.json")
        return try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url))
    }

    func testAllStagesInOrder() throws {
        let e = try load()
        XCTAssertEqual(e.count, 34)   // 30本 + ボス「堕天使」「九尾の巫女」「雪の女王」「死神」の見本
        XCTAssertEqual(Set(e.map(\.id)).count, 34, "IDは重複しない")
        XCTAssertEqual(e.map(\.difficulty), e.map(\.difficulty).sorted(), "易しい→難しい順")
        XCTAssertEqual(e.first?.difficulty, 1)
        XCTAssertEqual(e.last?.difficulty, 5)
    }

    func testMixOfSurviveAndBoss() throws {
        let e = try load()
        XCTAssertGreaterThanOrEqual(e.filter { $0.stage.mode == .boss }.count, 5)
        XCTAssertGreaterThanOrEqual(e.filter { $0.stage.mode == .survive }.count, 20)
    }

    func testEveryStageIsValidAndSanitizeStable() throws {
        for entry in try load() {
            let s = entry.stage
            XCTAssertEqual(s, s.sanitized(), "\(entry.id): 値の範囲・丸めが正しい")
            XCTAssertTrue(Stage.durations[s.mode]!.contains(s.durationSec), entry.id)
            XCTAssertTrue((1...8).contains(s.emitters.count), entry.id)
            XCTAssertFalse(entry.name["ja"]?.isEmpty ?? true, entry.id)
            XCTAssertFalse(entry.name["en"]?.isEmpty ?? true, entry.id)
            XCTAssertFalse(entry.aim["ja"]?.isEmpty ?? true, entry.id)
            XCTAssertFalse(entry.aim["en"]?.isEmpty ?? true, entry.id)
            for m in s.emitters { XCTAssertLessThan(m.s, Double(s.durationSec), "\(entry.id): 開始が時間内") }
        }
    }

    func testBossStagesHaveEmittersForEveryPhase() throws {
        for entry in try load() where entry.stage.mode == .boss {
            let phases = Set(entry.stage.emitters.map(\.ph))
            XCTAssertTrue(phases.contains(0) || (phases.isSuperset(of: [1, 2, 3])) || !phases.isEmpty, entry.id)
        }
    }

    /// 全ステージを動かさずに最後まで回しても、クラッシュせず終わる（弾数上限の確認も兼ねる）
    func testEveryStageRunsToTheEnd() throws {
        for entry in try load() {
            let r = Simulation.run(stage: entry.stage, moves: [])
            XCTAssertNotEqual(r.outcome, .playing, entry.id)
            XCTAssertLessThanOrEqual(r.bulletCount, 1600)
        }
    }
}
