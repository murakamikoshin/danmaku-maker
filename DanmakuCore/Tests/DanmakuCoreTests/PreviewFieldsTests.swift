import XCTest
@testable import DanmakuCore

/// 世界のステージ一覧のプレビュー(開始秒・プレビューなし)。見た目だけの項目で、計算には関わらない
final class PreviewFieldsTests: XCTestCase {
    private func survive(_ d: Int, start: Int? = nil, off: Bool? = nil) -> Stage {
        Stage(name: "p", mode: .survive, durationSec: d, emitters: [], previewStart: start, noPreview: off)
    }

    func testMaxIsThirtyPercentRoundedDown() {
        XCTAssertEqual(Stage.maxPreviewStart(durationSec: 20), 6)
        XCTAssertEqual(Stage.maxPreviewStart(durationSec: 10), 3)
        XCTAssertEqual(Stage.maxPreviewStart(durationSec: 45), 13)
        XCTAssertEqual(Stage.maxPreviewStart(durationSec: 0), 0)   // 時間無制限のボス戦は選べない
    }

    func testSanitizedClampsAndDropsDefault() {
        XCTAssertEqual(survive(20, start: 6).sanitized().previewStart, 6)
        XCTAssertEqual(survive(20, start: 99).sanitized().previewStart, 6)
        XCTAssertNil(survive(20, start: 0).sanitized().previewStart)
        XCTAssertNil(survive(20, start: -5).sanitized().previewStart)
        XCTAssertNil(survive(20).sanitized().previewStart)
        XCTAssertEqual(survive(20, off: true).sanitized().noPreview, true)
        XCTAssertNil(survive(20, off: false).sanitized().noPreview)
    }

    func testEffectiveStartAndHides() {
        XCTAssertEqual(survive(20, start: 4).effectivePreviewStart, 4)
        XCTAssertEqual(survive(20, start: 50).effectivePreviewStart, 6)
        XCTAssertEqual(survive(20).effectivePreviewStart, 0)
        XCTAssertTrue(survive(20, off: true).hidesPreview)
        XCTAssertFalse(survive(20).hidesPreview)
    }

    func testOldStageWithoutFieldsStillDecodes() throws {
        let json = #"{"name":"old","mode":"survive","durationSec":20,"emitters":[],"formatVersion":1}"#
        let s = try JSONDecoder().decode(Stage.self, from: Data(json.utf8))
        XCTAssertNil(s.previewStart)
        XCTAssertNil(s.noPreview)
        XCTAssertEqual(s.effectivePreviewStart, 0)
    }

    func testRoundTripAndUnknownKeysIgnored() throws {
        let s = survive(30, start: 5, off: nil).sanitized()
        let back = try JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.previewStart, 5)
    }

    func testSequenceUsesTotalLength() {
        let waves = [Wave(kind: .survive, durationSec: 30, emitters: []),
                     Wave(kind: .boss, durationSec: 60, bossHp: 200, bossMove: 0, emitters: [])]
        let s = Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], waves: waves, previewStart: 99).sanitized()
        XCTAssertEqual(s.previewStart, Stage.maxPreviewStart(durationSec: s.durationSec))
    }
}
