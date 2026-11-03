/// スワイプ弾幕の「ランダム生成ステージ」。みんなのステージだけでは数が足りないとき・序盤用に、種と難しさから 12 秒のステージを作る。
/// 同じ（種, 難しさ）からは、アプリでもサーバーでも（TypeScript）まったく同じステージができる（整数で作るので、小数の誤差が出ない）。
/// 使える弾幕だけで作り、広告で解放するパターン・ビーム・描いた軌道は使わない。
public enum SwipeGenerator {
    /// ステージの長さ（秒）と、クリップの開始位置（ステージの開始から何秒目か）。10 秒遊ぶので、1.5 + 10 < 12
    public static let duration = 12
    public static let clipAt = 1.5
    /// 難しさの最大（0 が易しく 999 が難しい）
    public static let maxHard = 999
    /// 使うパターン。並びを変えると、同じ種でも別のステージになるので変えない
    public static let patterns: [Pattern] = [.ring, .spiral, .aim, .rain, .sideL, .sideR, .corner, .flower, .star, .cross, .sweep]

    /// 種と難しさ（0〜999）からステージを作る
    public static func stage(seed: UInt32, hard: Int) -> Stage {
        let h = min(max(hard, 0), maxHard)
        var rng = Mulberry32(seed: seed)
        let count = 2 + h / 350
        var emitters: [Emitter] = []
        for _ in 0..<count {
            // 値は毎回すべて引く（パターンによって使わなくても）。順番を固定して、サーバーと同じにする
            let pattern = patterns[Int(rng.next() * Double(patterns.count))]
            let x = Double(Int(rng.next() * 60) + 20) / 100
            let y = Double(Int(rng.next() * 25) + 8) / 100
            let s = Double(Int(rng.next() * 10)) / 10
            let intervalBase = Int(rng.next() * 30) + 60
            let countBase = Int(rng.next() * 6) + 6
            let speedBase = Int(rng.next() * 10) + 14
            let spin = Double(Int(rng.next() * 20) + 3)
            let spread = Double(Int(rng.next() * 60) + 10)
            let color = Int(rng.next() * 5)
            let turn = (Int(rng.next() * 8) - 4) * 45

            let interval = max(15, intervalBase * (1000 - h * 55 / 100) / 1000)
            let c = countBase + h * 14 / 1000
            let v = Double(speedBase + h * 8 / 1000) / 10
            let aimed: [Pattern] = [.aim, .corner]
            let r = aimed.contains(pattern) ? spread : spin
            var e = Emitter(t: pattern, x: x, y: y, s: s, e: Double(duration), i: Double(interval) / 100, c: c, v: v, r: r, k: color)
            if e.canRotate { e.a = turn }
            emitters.append(e)
        }
        return Stage(name: "random", mode: .survive, durationSec: duration, emitters: emitters)
    }

    // MARK: クリップの ID（候補の一覧に入れる名前）。`G` + 種（16 進 8 桁）+ 難しさ（3 桁）

    public static func id(seed: UInt32, hard: Int) -> String {
        let hex = String(seed, radix: 16)
        return "G" + String(repeating: "0", count: 8 - hex.count) + hex + String(format: "%03d", min(max(hard, 0), maxHard))
    }

    public static func parse(id: String) -> (seed: UInt32, hard: Int)? {
        guard id.count == 12, id.first == "G" else { return nil }
        let body = Array(id.dropFirst())
        guard let seed = UInt32(String(body[0..<8]), radix: 16), let hard = Int(String(body[8..<11])) else { return nil }
        return (seed, hard)
    }

    /// 生成したクリップの作者名の印（ブロックや自分のステージの除外に引っかからない）
    public static let author = "gen"
}
