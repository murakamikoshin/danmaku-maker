/// ステージの中から、スワイプ弾幕に使う 10 秒の区間を選ぶ（仕様書 `docs/SWIPE_MODE.md` 4 章）。
/// 投稿時にサーバーが計算して `clip.at` に保存する。**アプリとサーバーで同じ結果になること**（サーバーは TypeScript で同じ手順を書く）。
public enum SwipeClipPicker {
    /// 弾の数を数える間隔（ステップ）。0.5 秒
    public static let sampleEverySteps = 60
    /// 1 つの区間を作るサンプルの数。10 秒 ÷ 0.5 秒
    public static let windowSamples = SwipeClip.playSteps / sampleEverySteps
    /// 開始からこの数のサンプル（2 秒）以内に始まる区間は避ける（弾がまだ少ない）。ほかに選べるものがないときだけ使う
    public static let skipLeadingSamples = 4
    /// 区間の平均の弾の数がこれ未満のステージは、クリップにしない
    public static let minimumAverage = 15
    /// 試す区間の最大数（盛り上がっている順）
    public static let maxCandidates = 5
    /// 試す区間どうしの間隔の最小（サンプルの数。5 秒）。似た区間ばかり試さないため
    public static let minimumSpacingSamples = 10

    /// 区間の候補
    public struct Candidate: Equatable, Sendable {
        /// 開始（ステージの開始から何秒目か。0.5 秒刻み）
        public let at: Double
        /// 区間の弾の数の合計（20 サンプル）。大きいほど盛り上がっている
        public let total: Int
        /// 平均の弾の数
        public var average: Double { Double(total) / Double(SwipeClipPicker.windowSamples) }
        /// 見積もりのクリア率（0〜1）。新しいステージの難しさの目安（仕様書 3.3 章）
        public var estimatedClearRate: Double { SwipeClipPicker.estimatedClearRate(averageBullets: average) }
    }

    /// 平均の弾の数から、クリア率を見積もる：`clamp(1.1 − 平均 ÷ 250, 0.05, 0.95)`。挑戦が 10 回たまるまでの仮の値
    public static func estimatedClearRate(averageBullets: Double) -> Double {
        min(0.95, max(0.05, 1.1 - averageBullets / 250))
    }

    /// ステージを、自機を初期位置から動かさず無敵で最後まで進めて、0.5 秒ごとの弾の数を数える。
    /// `counts[i]` は、ステージの開始から `i × 0.5` 秒目の弾の数。`gaps[i]` は、そのとき連戦の切り替えの間か
    public static func sample(stage: Stage) -> (counts: [Int], gaps: [Bool]) {
        var sim = Simulation(swipeStage: stage)
        sim.invincible = true
        sim.countsGrazes = false
        var counts: [Int] = [], gaps: [Bool] = []
        // 終わらないステージはないが、念のための上限（連戦の最長を超える長さ）
        let cap = SwipeClip.readySteps + 120 * (Stage.sequenceTotalSeconds(stage.waves ?? []) + Stage.unlimitedCapSec + 10)
        while sim.outcome == .playing && sim.tick < cap {
            if sim.tick >= SwipeClip.readySteps && (sim.tick - SwipeClip.readySteps) % sampleEverySteps == 0 {
                counts.append(sim.bullets.count)
                gaps.append(sim.isIntermission)
            }
            sim.step(.zero)
        }
        return (counts, gaps)
    }

    /// 盛り上がっている順の候補（最大 5 つ）。ひとつもなければ、クリップにしないステージ。
    /// - 区間 `j` は、サンプル j〜j+19（`at = 0.5 × j` 秒から 10 秒）。ステージの最後までに収まるものだけ
    /// - 連戦の切り替えの間をまたぐ区間は選ばない（区間の終わりの瞬間が切り替えの間のものも含む）
    /// - 開始の 2 秒以内に始まる区間は、ほかに選べるものがあるかぎり選ばない（短いステージだけ、先頭から）
    /// - 平均が 15 発未満の区間は選ばない
    /// - 合計が大きい順（同じなら早い順）。すでに選んだ区間と 5 秒以上離れたものだけを続けて選ぶ
    public static func candidates(stage: Stage) -> [Candidate] {
        let (counts, gaps) = sample(stage: stage)
        return candidates(counts: counts, gaps: gaps)
    }

    /// 弾の数の並びから候補を選ぶ部分（テストと、サーバーとの照合用に切り出してある）
    public static func candidates(counts: [Int], gaps: [Bool]) -> [Candidate] {
        let w = windowSamples
        guard counts.count >= w else { return [] }
        let last = counts.count - w
        // 開始 2 秒以内を避けた先に、1 つでも区間が取れるか
        let first = last >= skipLeadingSamples ? skipLeadingSamples : 0

        // 区間の合計と、切り替えの間の数を、先頭からの累計で求める
        var sum = [0], gapSum = [0]
        for i in 0..<counts.count { sum.append(sum[i] + counts[i]); gapSum.append(gapSum[i] + (gaps[i] ? 1 : 0)) }
        var windows: [(j: Int, total: Int)] = []
        for j in first...last {
            let total = sum[j + w] - sum[j]
            // 区間の終わりの瞬間（次のサンプル）が切り替えの間のときも、またいでいるとみなす（0.5 秒おきに数えているので、境目を見逃さないため）
            let gapCount = gapSum[min(j + w + 1, counts.count)] - gapSum[j]
            if gapCount == 0 && total >= minimumAverage * w { windows.append((j, total)) }
        }
        windows.sort { $0.total != $1.total ? $0.total > $1.total : $0.j < $1.j }

        var picked: [(j: Int, total: Int)] = []
        for c in windows {
            if picked.count == maxCandidates { break }
            if picked.allSatisfy({ abs($0.j - c.j) >= minimumSpacingSamples }) { picked.append(c) }
        }
        return picked.map { Candidate(at: Double($0.j) * 0.5, total: $0.total) }
    }
}
