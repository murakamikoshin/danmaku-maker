/// スワイプ弾幕の 1 本のクリップ（仕様書 `docs/SWIPE_MODE.md` 3 章）。
/// ステージの途中から 10 秒を切り出して遊ぶ。アプリとサーバー（クリップの検証・ランキング）が、**同じ手順で同じ状態**から始める。
public enum SwipeClip {
    /// 遊ぶ長さ（ステップ）。10 秒
    public static let playSteps = 1200
    /// 「GO」の間に自機を動かせるステップ数。0.5 秒。弾は止まったまま
    public static let goSteps = 60
    /// 遊び始めのバリア。0.7 秒。GO の間は数えない
    public static let startShieldSteps = 84
    /// ステージの開始（秒 0）に着くまでの、準備のステップ数（READY 1.2 秒）
    public static let readySteps = Int((DanmakuConfig.readySeconds / DanmakuConfig.step).rounded())

    /// 切り出しの始まり（ステージの開始から何秒目か）を、シミュレーションのステップ数にする
    public static func startTick(at seconds: Double) -> Int {
        readySteps + Int((seconds / DanmakuConfig.step).rounded())
    }

    /// そのクリップを、遊び始める直前の状態にする：
    /// 自機を動かさず無敵で `at` 秒目まで早送り → 自機を一番安全な場所に置く → バリアをつける。
    /// 時間は進めない（GO の間の自機の動きは、弾を止めたまま `Simulation.nudgePlayer` で当てる）
    public static func prepare(stage: Stage, at seconds: Double) -> Simulation {
        var sim = Simulation(swipeStage: stage)
        sim.fastForward(toTick: startTick(at: seconds))
        sim.place(at: safestPosition(among: sim.bullets))
        sim.giveShield(steps: startShieldSteps)
        return sim
    }

    // MARK: 一番安全な場所

    /// 候補点の並べ方：横 12 × 縦 8 の 96 点（x = 30 + 300/11 × i、y = 270 + 226.8/7 × j）
    static let columns = 12, rows = 8

    /// 弾から一番遠い場所。候補点ごとに「一番近い弾までの距離」を求め、真ん中寄りを少し優先する。
    /// 弾は「今・0.3 秒後・0.6 秒後」の位置（今の速度のまま進めた位置）で見る。
    /// 同じ点数なら、先に調べた点（左から、上から）を選ぶ。点数は 0.01px に丸めて比べる（三角関数の最後の桁の違いで、アプリとサーバーの選ぶ場所が分かれないように）
    public static func safestPosition(among bullets: [Bullet]) -> Point {
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        var best = -Double.infinity
        var at = Point(x: W / 2, y: H * 0.85)
        for gx in 0..<columns {
            for gy in 0..<rows {
                let x = 30 + Double(gx) * 300 / 11
                let y = H * 0.5 + Double(gy) * H * 0.42 / 7
                var m = 1e9
                for b in bullets {
                    let d = distanceSquared(from: b, to: x, y)
                    if d < m { m = d }
                }
                let score = ((m.squareRoot() - abs(x - W / 2) * 0.03) * 100).rounded()
                if score > best { best = score; at = Point(x: x, y: y) }
            }
        }
        return at
    }

    /// 点 (x, y) から、その弾までの距離の 2 乗（小さいほど危ない）。
    /// ふつうの弾は今・0.3 秒後・0.6 秒後の位置。ビームは光線までの距離（ためている間も、これから撃つので同じ）。爆風は縁までの距離
    static func distanceSquared(from b: Bullet, to x: Double, _ y: Double) -> Double {
        if b.isBeam {
            let rx = x - b.x, ry = y - b.y
            let along = rx * b.vx + ry * b.vy
            return along < 0 ? rx * rx + ry * ry : rx * rx + ry * ry - along * along
        }
        if b.isBlast {
            let dx = x - b.x, dy = y - b.y
            let edge = max(0, (dx * dx + dy * dy).squareRoot() - b.radius)
            return edge * edge
        }
        var m = Double.infinity
        for k in [0.0, 0.3, 0.6] {
            let dx = b.x + b.vx * k - x, dy = b.y + b.vy * k - y
            let d = dx * dx + dy * dy
            if d < m { m = d }
        }
        return m
    }
}
