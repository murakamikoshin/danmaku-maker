/// 1 本のクリップを 1 ステップずつ遊ぶ（アプリの画面と、サーバーが検証する `SwipeRun` が、**同じ手順**を使う）。
/// 手順：早送り → 安全な位置 → バリア → GO の間は `nudge` → プレイは毎ステップ `advance`。
public struct SwipeClipPlayer {
    public private(set) var sim: Simulation
    /// プレイが何ステップ進んだか（GO の間は数えない）
    public private(set) var step = 0

    public enum End: Equatable, Sendable { case hit, cleared }

    /// 1 ステップで起きたこと
    public struct Events {
        /// かすった弾ごとの点（その場に火花を出す用に、弾も付ける）
        public var grazes: [(bullet: Bullet, graze: SwipeScoring.Graze)] = []
        /// ボムが出た（画面の弾は消えて、金の粒に変わる）。消える前の弾の位置
        public var bomb: (coins: SwipeScoring.Coins, bullets: [Bullet])?
        /// クリアしたとき。残った弾は金の粒になる
        public var clear: (result: SwipeScoring.Clear, bullets: [Bullet])?
        public var end: End?
        /// このステップの最初の被弾（自機が弾けた位置）
        public var hitAt: Point?
    }

    public init(stage: Stage, at seconds: Double, scoring: inout SwipeScoring) {
        sim = SwipeClip.prepare(stage: stage, at: seconds)
        scoring.beginClip()
    }

    /// GO の間の自機の動き（弾は止まったまま）。`SwipeClip.goSteps` 回まで
    public mutating func nudge(_ move: Move) { sim.nudgePlayer(move) }

    /// 1 ステップ進める。`SwipeClip.playSteps` 回まで。被弾かクリアで `end` が入る
    public mutating func advance(_ move: Move, scoring: inout SwipeScoring) -> Events {
        var ev = Events()
        guard step < SwipeClip.playSteps, sim.outcome == .playing else { return ev }
        step += 1
        sim.step(move)
        for b in sim.grazedThisStep { ev.grazes.append((b, scoring.graze(step: step))) }
        let hit = sim.outcome == .hit
        let before = sim.bullets
        if let coins = scoring.endStep(step: step, bulletCount: SwipeClipPlayer.coinBullets(sim), hit: hit) {
            ev.bomb = (coins, before)
            sim.clearBullets()
            sim.giveShield(steps: 120)
        }
        if hit {
            scoring.hit()
            ev.end = .hit
            ev.hitAt = sim.player
            return ev
        }
        // 最後のステップ（またはステージが終わったとき）は、ボム → クリアの順
        if step == SwipeClip.playSteps || sim.outcome == .cleared {
            let remaining = sim.bullets
            ev.clear = (scoring.clear(bulletCount: SwipeClipPlayer.coinBullets(sim)), remaining)
            ev.end = .cleared
        }
        return ev
    }

    /// 金の粒になる弾の数。ビーム・爆風は粒にならない
    static func coinBullets(_ sim: Simulation) -> Int {
        sim.bullets.reduce(0) { $0 + ($1.isBeam || $1.isBlast ? 0 : 1) }
    }
}
