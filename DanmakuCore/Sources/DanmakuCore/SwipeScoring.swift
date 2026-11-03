/// スワイプ弾幕の点数の計算（仕様書 `docs/SWIPE_MODE.md` 5 章）。
///
/// 1 プレイ分の「点数・連続・コンボ・ボムのゲージ」を持つ。描画や音には関わらない。
/// アプリの表示と、サーバーでリプレイから点数を計算し直すとき（15 章）の、**どちらの基準にもなる**。
/// 時間はすべてステップ数（1/120 秒）で数える。
///
/// 1 ステップの呼び出し順：
/// 1. 弾を動かして、かすった弾ごとに `graze(step:)`
/// 2. `endStep(step:bulletCount:hit:)`（コンボが切れるか調べ、ボムが出ていればまとめて加点）
/// 3. 最後のステップなら、続けて `clear(bulletCount:)`。被弾したなら `hit()`
public struct SwipeScoring: Equatable, Sendable {
    /// かすり 1 回の基本の点
    public static let grazeBase: UInt32 = 100
    /// クリアの基本の点（100 × 500）
    public static let clearBase: UInt32 = 50_000
    /// 前のかすりからこのステップ数以上空くと、コンボが切れる（1.5 秒）
    public static let comboLapseSteps = 180
    /// ボムが出るかすりの回数
    public static let bombGauge = 40
    /// 8 コンボごとに点が 2 倍になる
    public static let comboPerDoubling = 8

    /// 今回のプレイの点数
    public private(set) var score = BigScore.zero
    /// 連続クリア数（被弾・スキップで 0）
    public private(set) var streak = 0
    /// 今のクリップのコンボ（クリップごとに 0 から）
    public private(set) var combo = 0
    /// ボムのゲージ（クリップをまたいで持ち越す）
    public private(set) var gauge = 0
    /// ゲージが満たされて、このステップの最後に出すボムがあるか
    public private(set) var bombPending = false

    private var lastGrazeStep = 0
    /// 3^連続（かすりのたびに計算し直さないよう、持っておく）
    private var streakFactor = BigScore(1)

    public init() {}

    // MARK: 式（どれも割り算は整数の切り捨て）

    /// かすり 1 回の点：`100 × 2^(コンボ÷8) × (8 + コンボ mod 8) ÷ 8 × 3^連続`。次の 2 倍までの間も 1/8 ずつ上がる
    public static func grazePoints(combo: Int, streak: Int) -> BigScore {
        grazePoints(combo: combo, streakFactor: BigScore.power(3, streak))
    }

    private static func grazePoints(combo: Int, streakFactor: BigScore) -> BigScore {
        let c = max(0, combo)
        let doubled = BigScore.power(2, c / comboPerDoubling) * (grazeBase * UInt32(comboPerDoubling + c % comboPerDoubling))
        return doubled.divided(by: UInt32(comboPerDoubling)) * streakFactor
    }

    /// クリアの点：`100 × 500 × 2^(コンボ÷8) × 3^(連続 + 1)`。`streakBefore` はクリアする前の連続数
    public static func clearBonus(combo: Int, streakBefore: Int) -> BigScore {
        let doublings = BigScore.power(2, max(0, combo) / comboPerDoubling) * BigScore(UInt64(clearBase))
        return doublings * BigScore.power(3, streakBefore + 1)
    }

    // MARK: 状態

    /// 演出の強さ（1〜8）。背景の色・火花の数・「+点」の大きさに使う
    public var level: Int { min(8, 1 + combo / SwipeScoring.comboPerDoubling) }

    /// 画面に出す倍率：`2^(コンボ÷8) × 3^連続`
    public var multiplier: BigScore { BigScore.power(2, combo / SwipeScoring.comboPerDoubling) * streakFactor }

    /// 今のコンボと連続での、かすり 1 回の点
    public var currentGrazePoints: BigScore { SwipeScoring.grazePoints(combo: combo, streakFactor: streakFactor) }

    // MARK: できごと

    /// 新しいクリップを始める。コンボは 0 から。ゲージ・連続・点数はそのまま
    public mutating func beginClip() {
        combo = 0
        lastGrazeStep = 0
        bombPending = false
    }

    public struct Graze: Equatable, Sendable {
        /// このかすりで入った点
        public let points: BigScore
        public let combo: Int
        public let level: Int
        /// コンボが 8 の倍数になった（画面中央に「×倍率」を出す）
        public let doubled: Bool
        /// ゲージが満たされた（このステップの最後にボムが出る）
        public let bombQueued: Bool
    }

    /// 弾 1 発をかすった。`step` はこのクリップの何ステップ目か
    @discardableResult
    public mutating func graze(step: Int) -> Graze {
        if combo > 0 && step - lastGrazeStep < SwipeScoring.comboLapseSteps { combo += 1 } else { combo = 1 }
        lastGrazeStep = step
        let points = currentGrazePoints
        score += points
        gauge += 1
        var queued = false
        if gauge >= SwipeScoring.bombGauge { gauge = 0; bombPending = true; queued = true }
        return Graze(points: points, combo: combo, level: level, doubled: combo % SwipeScoring.comboPerDoubling == 0, bombQueued: queued)
    }

    public struct Coins: Equatable, Sendable {
        /// 金の粒の数（そのステップの弾の処理が終わった後に、画面に残っていた弾の数）
        public let count: Int
        /// 粒 1 個の点
        public let each: BigScore
        /// 入った点の合計
        public let total: BigScore
    }

    /// 1 ステップの最後。コンボが切れていれば 0 に戻し、出ているボムがあれば画面の弾を金の粒に変えて加点する。
    /// `hit` が true（このステップで被弾した）ときは、ボムを出さない（そのプレイは終わり）。
    /// ボムが出たら、その粒の情報を返す
    @discardableResult
    public mutating func endStep(step: Int, bulletCount: Int, hit: Bool = false) -> Coins? {
        if combo > 0 && step - lastGrazeStep >= SwipeScoring.comboLapseSteps { combo = 0 }
        defer { bombPending = false }
        guard bombPending, !hit else { return nil }
        return collectCoins(bulletCount: bulletCount)
    }

    public struct Clear: Equatable, Sendable {
        public let bonus: BigScore
        /// クリアした後の連続数
        public let streak: Int
        /// 残った弾が変わる金の粒
        public let coins: Coins
    }

    /// 10 秒生き残った。クリアの点を入れ、連続を +1 して、画面に残った弾を金の粒に変えて加点する（粒の点は +1 した後の連続で数える）
    public mutating func clear(bulletCount: Int) -> Clear {
        let doublings = BigScore.power(2, combo / SwipeScoring.comboPerDoubling) * BigScore(UInt64(SwipeScoring.clearBase))
        let bonus = doublings * (streakFactor * 3)
        score += bonus
        streak += 1
        streakFactor = streakFactor * 3
        return Clear(bonus: bonus, streak: streak, coins: collectCoins(bulletCount: bulletCount))
    }

    /// 被弾した。連続とコンボを 0 に戻す。終わった連続数を返す（点数はそのまま）
    @discardableResult
    public mutating func hit() -> Int {
        let ended = streak
        resetStreak()
        combo = 0
        bombPending = false
        return ended
    }

    /// スキップした。連続は 0 に戻る（難しい 1 本だけ飛ばして倍率を守れないように）
    public mutating func skip() { resetStreak() }

    private mutating func resetStreak() { streak = 0; streakFactor = BigScore(1) }

    private mutating func collectCoins(bulletCount: Int) -> Coins {
        let each = currentGrazePoints.divided(by: 2)
        let total = each * BigScore(max(0, bulletCount))
        score += total
        return Coins(count: max(0, bulletCount), each: each, total: total)
    }
}
