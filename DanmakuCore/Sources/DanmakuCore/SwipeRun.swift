/// スワイプ弾幕の 1 プレイ分を、記録（自機の動き）から最初から計算し直す（仕様書 `docs/SWIPE_MODE.md` 15.2 章）。
///
/// アプリは遊んだ結果の点数をこれと同じ手順で出し、サーバーは受け取った記録を同じ手順で計算し直して、
/// **サーバーの点数だけを**ランキングに載せる。アプリとサーバー（TypeScript）で 1 桁も違わないこと。
public enum SwipeRun {
    /// 1 本ぶんの記録
    public struct ClipInput: Equatable, Sendable {
        /// 「GO」の間（0.5 秒＝60 ステップまで）の自機の動き。弾は止まっている
        public var go: [Move]
        /// 遊んでいる間の自機の動き（1 ステップに 1 つ。1200 ステップまで）。被弾・クリアしたステップまで
        public var moves: [Move]
        /// スキップした（連続が 0 に戻る）。`moves` の数のステップを遊んだ後にスキップした
        public var skipped: Bool

        public init(go: [Move] = [], moves: [Move] = [], skipped: Bool = false) { self.go = go; self.moves = moves; self.skipped = skipped }
    }

    /// 次に流すクリップのステージと、切り出し位置（`clip.at`）を返す。見つからなければ nil
    public typealias ClipSource = (_ id: String) -> (stage: Stage, at: Double)?

    public struct Result: Equatable, Sendable {
        /// 今回のプレイの点数
        public var score = BigScore.zero
        /// 終わった時点の連続（被弾したら 0）と、今回の一番長かった連続
        public var streak = 0
        public var bestStreak = 0
        /// 始めた本数と、クリアした本数
        public var clipsPlayed = 0
        public var clipsCleared = 0
        /// 流れたクリップの ID（順番どおり）
        public var clipIDs: [String] = []
        /// 1 本ごとの、終わった時点の点数（10 進の文字列）。アプリとサーバーの照合に使う
        public var scoreAfterEachClip: [String] = []
        /// 出したボム・かすった数の合計
        public var bombs = 0
        public var grazes = 0
        /// 被弾で終わった
        public var endedByHit = false
        /// 記録が途中で尽きた（1 本の途中でやめた）。それまでの点数は残る
        public var abandoned = false
        /// 計算できなかった理由（候補が尽きた、ステージが見つからないなど）。あれば、記録は受け付けない
        public var invalid: String?
    }

    /// 1 本のクリップで、1 つの動きの後に起きたこと
    enum ClipEnd { case cleared, hit, skipped, abandoned }

    /// `clips` の順に遊んだものとして、点数を計算する。
    /// - `seed`・`pool`・`excludedAuthors`：並びの作り方（`SwipeFeed.pick`）に使う。プレイの始めにサーバーが決めたもの
    public static func play(seed: UInt32, pool: [SwipeFeed.Entry], excludedAuthors: Set<String> = [],
                            source: ClipSource, clips: [ClipInput]) -> Result {
        var result = Result()
        var scoring = SwipeScoring()
        var used = Set<String>()

        for (index, input) in clips.enumerated() {
            guard let entry = SwipeFeed.pick(pool: pool, seed: seed, index: index, streak: scoring.streak, used: used, excludedAuthors: excludedAuthors) else {
                result.invalid = "pool-exhausted"; break
            }
            guard let clip = source(entry.id) else { result.invalid = "missing-stage:\(entry.id)"; break }
            used.insert(entry.id)
            result.clipIDs.append(entry.id)
            result.clipsPlayed += 1

            let end = playClip(stage: clip.stage, at: clip.at, input: input, scoring: &scoring, result: &result)
            result.bestStreak = max(result.bestStreak, scoring.streak)
            result.scoreAfterEachClip.append(scoring.score.description)
            switch end {
            case .cleared: result.clipsCleared += 1
            case .skipped: break
            case .hit: result.endedByHit = true
            case .abandoned: result.abandoned = true
            }
            if end == .hit || end == .abandoned { break }
        }
        result.score = scoring.score
        result.streak = scoring.streak
        return result
    }

    /// 1 本を遊ぶ（早送り → 安全な位置 → GO の動き → 1200 ステップ）。手順は `SwipeClipPlayer`（アプリの画面と共通）
    static func playClip(stage: Stage, at seconds: Double, input: ClipInput, scoring: inout SwipeScoring, result: inout Result) -> ClipEnd {
        var player = SwipeClipPlayer(stage: stage, at: seconds, scoring: &scoring)
        for m in input.go.prefix(SwipeClip.goSteps) { player.nudge(m) }

        let moves = input.moves.prefix(SwipeClip.playSteps)
        for n in 1...SwipeClip.playSteps {
            guard n <= moves.count else {
                // 記録が尽きた。スキップならそこで終わり、そうでなければ途中でやめたことにする
                if input.skipped { scoring.skip(); return .skipped }
                return .abandoned
            }
            let ev = player.advance(moves[moves.startIndex + n - 1], scoring: &scoring)
            result.grazes += ev.grazes.count
            if ev.bomb != nil { result.bombs += 1 }
            switch ev.end {
            case .hit: return .hit
            case .cleared: return .cleared
            case nil: break
            }
        }
        return .cleared   // ここには来ない（ループは 1200 ステップ目で必ず終わる）
    }

    /// 金の粒になる弾の数。ビーム・爆風は粒にならない
    static func coinBullets(_ sim: Simulation) -> Int {
        sim.bullets.reduce(0) { $0 + ($1.isBeam || $1.isBlast ? 0 : 1) }
    }
}
