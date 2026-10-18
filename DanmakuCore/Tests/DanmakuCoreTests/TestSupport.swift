import Foundation
@testable import DanmakuCore

func em(_ t: Pattern, x: Double = 0.5, y: Double = 0.2, s: Double = 0, e: Double = 30, i: Double = 1,
        c: Int = 16, v: Double = 2, r: Double = 0, k: Int = 0, ph: Int = 0) -> Emitter {
    Emitter(t: t, x: x, y: y, s: s, e: e, i: i, c: c, v: v, r: r, k: k, ph: ph)
}

/// 毎ステップ違う動きをする、決まった入力列（乱数は使わない）
func scriptedMoves(count: Int) -> [Move] {
    (0..<count).map { n in
        Move(dx: Int8(truncatingIfNeeded: (n * 7 % 61) - 30), dy: Int8(truncatingIfNeeded: (n * 3 % 21) - 10))
    }
}
