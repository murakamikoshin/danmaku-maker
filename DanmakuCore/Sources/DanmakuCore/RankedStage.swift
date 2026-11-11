/// ランク戦(リアルタイム対戦)のステージと、勝ち負けの決め方。仕様書「ランク戦 仕様書(リアルタイム対戦)」。
///
/// ステージは 1 つの数(種)から作る、だんだん激しくなる 180 秒の耐久。15 秒ごとの区切り 12 個に、
/// スワイプ弾幕のランダム生成(`SwipeGenerator`)で作った弾幕を、区切りが進むほど難しくして並べる。
/// 同じ種からは、アプリでもサーバー(TypeScript の `rankedStage`)でもまったく同じステージになる。
/// 自機はライフ 1(当たったら終わり)で、撃たない。
public enum RankedStage {
    /// 1 つの区切りの長さ(秒)と、区切りの数。合わせて 180 秒が上限
    public static let segmentSeconds = 15
    public static let segments = 12
    public static var durationSec: Int { segmentSeconds * segments }

    /// 区切りごとの難しさ(0〜999)。最初は易しく、最後は一番難しい
    public static func hard(segment k: Int) -> Int { min(SwipeGenerator.maxHard, 60 + k * 85) }

    /// 区切りごとの種(32 ビットで回り込む。サーバーと同じ計算)
    public static func segmentSeed(_ seed: UInt32, _ k: Int) -> UInt32 { seed &+ UInt32(truncatingIfNeeded: k) &* 0x9E37_79B1 }

    /// 種からステージを作る
    public static func stage(seed: UInt32) -> Stage {
        var emitters: [Emitter] = []
        for k in 0..<segments {
            let part = SwipeGenerator.stage(seed: segmentSeed(seed, k), hard: hard(segment: k))
            let start = Double(k * segmentSeconds)
            for var e in part.emitters {
                e.s += start
                e.e = start + Double(segmentSeconds)
                emitters.append(e)
            }
        }
        return Stage(name: "ranked", mode: .survive, durationSec: durationSec, emitters: emitters, lifeMode: .lives, lifeCount: 1)
    }

    /// 1 人ぶんの結果。サーバーが操作の記録から計算し直したものを使う
    public struct Score: Equatable, Sendable {
        /// 生き残ったステップ数(1 ステップ = 1/120 秒)。180 秒を生き切ったときは、その時点のステップ数
        public var ticks: Int
        /// かすった数(同じ秒で落ちたときの決め手)
        public var grazes: Int
        public init(ticks: Int, grazes: Int) { self.ticks = ticks; self.grazes = grazes }
    }

    /// 操作の記録から、結果を計算する(サーバーと同じ手順)。記録が尽きたら、その場で落ちたものとする
    public static func score(seed: UInt32, moves: [Move]) -> Score {
        var sim = Simulation(stage: stage(seed: seed))
        let limit = (durationSec + 3) * 120 + 144
        while sim.outcome == .playing && sim.tick < limit {
            guard sim.tick < moves.count else { break }
            sim.step(moves[sim.tick])
        }
        return Score(ticks: sim.tick, grazes: sim.grazeCount)
    }

    /// 勝ち負け。1 = a の勝ち、-1 = b の勝ち、0 = 引き分け。長く生き残った方、同じならかすった数が多い方
    public static func compare(_ a: Score, _ b: Score) -> Int {
        if a.ticks != b.ticks { return a.ticks > b.ticks ? 1 : -1 }
        if a.grazes != b.grazes { return a.grazes > b.grazes ? 1 : -1 }
        return 0
    }
}
