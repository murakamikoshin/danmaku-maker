import XCTest
@testable import DanmakuCore

final class ReplayTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let moves = scriptedMoves(count: 5000) + Array(repeating: Move.zero, count: 3000)
        let replay = Replay(moves: moves)
        let text = replay.encoded()
        XCTAssertEqual(Replay(encoded: text), replay)
    }

    func testLongRunsOver255() {
        let replay = Replay(moves: Array(repeating: Move(dx: 3, dy: -2), count: 1000))
        XCTAssertEqual(Replay(encoded: replay.encoded()), replay)
    }

    func testRejectsGarbage() {
        XCTAssertNil(Replay(encoded: "not base64!!"))
        XCTAssertNil(Replay(encoded: ""))
    }

    func testReplayPlaysSameAsOriginal() {
        let stage = Stage(name: "r", mode: .survive, durationSec: 20, emitters: [
            em(.ring, c: 12, r: 5), em(.aim, s: 2, i: 0.8, c: 5, v: 3, r: 40)]).sanitized()
        let moves = scriptedMoves(count: 3000)
        let original = Simulation.run(stage: stage, moves: moves)
        let restored = Replay(encoded: Replay(moves: moves).encoded())!
        XCTAssertEqual(Simulation.run(stage: stage, moves: restored.moves), original)
    }

    func testReplaySizeIsSmall() {
        // 120 秒ぶん（14,400 ステップ）で、ゆるい動きなら数KBに収まる
        var moves: [Move] = []
        for n in 0..<14_400 {
            let dx = Int8((n / 40) % 5) - 2
            let dy = Int8((n / 90) % 3) - 1
            moves.append(Move(dx: dx, dy: dy))
        }
        XCTAssertLessThan(Replay(moves: moves).encoded().count, 8_000)
    }
}
