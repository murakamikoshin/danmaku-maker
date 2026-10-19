/// 自機の撃ち方。どれも1秒あたりの総ダメージは同じ（約22）で、強さではなく撃ち味が違う
public enum ShotType: String, CaseIterable, Codable, Sendable {
    /// 前に2本。課金なしの標準
    case standard
    /// 3方向に広がる。動きながらでも当てやすいが、近づかないと3発とも当たらない
    case spread
    /// 太い1発。当たる回数が少ない代わりに1発が重い。狙いを外すとダメージが出ない
    case heavy

    /// 1回の発射の間隔（秒）
    public var interval: Double {
        switch self {
        case .standard: return 0.09
        case .spread: return 0.135
        case .heavy: return 0.18
        }
    }

    public struct Spec: Equatable, Sendable {
        public var dx: Double
        public var vx: Double
        public var damage: Int
    }

    /// 1回の発射で出る弾（自機からの横ずれ、横速度、ダメージ）
    public var volley: [Spec] {
        switch self {
        case .standard: return [Spec(dx: -5, vx: 0, damage: 1), Spec(dx: 5, vx: 0, damage: 1)]
        case .spread: return [Spec(dx: -4, vx: -28, damage: 1), Spec(dx: 0, vx: 0, damage: 1), Spec(dx: 4, vx: 28, damage: 1)]
        case .heavy: return [Spec(dx: 0, vx: 0, damage: 4)]
        }
    }

    /// 1秒あたりの総ダメージ（全部当たった場合）
    public var damagePerSecond: Double {
        Double(volley.reduce(0) { $0 + $1.damage }) / interval
    }
}

/// 飛んでいる自機の弾
public struct PlayerShot: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var damage: Int
}
