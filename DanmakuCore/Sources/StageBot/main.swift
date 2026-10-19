import DanmakuCore
import Foundation

/// 公式ステージを自動プレイして、クリアできる並びになっているか確認するボット。
/// 使い方: swift run -c release StageBot <official_stages.json> [ステージID...]
/// 「弱いボット」は遅い自機・短い先読み、「強いボット」は人間の指の最大速度に近い自機・長い先読み。

struct Entry: Decodable {
    let id: String
    let difficulty: Int
    let name: [String: String]
    let stage: Stage
}

struct Profile {
    let label: String
    let units: Int       // 1ステップの最大移動量（0.25px 単位）。7 = 約 210px/秒
    let horizon: Int     // 先読みのステップ数
    let hold: Int        // 同じ動きを続けるステップ数
}

let weak = Profile(label: "weak", units: 4, horizon: 24, hold: 6)
let strong = Profile(label: "strong", units: 7, horizon: 40, hold: 6)

func candidates(_ units: Int) -> [Move] {
    let u = Int8(units)
    var out = [Move.zero]
    for dx in [-1, 0, 1] { for dy in [-1, 0, 1] where !(dx == 0 && dy == 0) { out.append(Move(dx: Int8(dx) * u, dy: Int8(dy) * u)) } }
    return out
}

func clearance(_ s: Simulation) -> Double {
    var best = 80.0
    for b in s.bullets {
        let dx = b.x - s.player.x, dy = b.y - s.player.y
        let d = (dx * dx + dy * dy).squareRoot()
        if d < best { best = d }
    }
    return best
}

func choose(_ sim: Simulation, _ p: Profile, _ cands: [Move]) -> Move {
    var bestMove = Move.zero
    var bestScore = -Double.infinity
    for c in cands {
        var s = sim
        var survived = p.horizon
        for k in 0..<p.horizon {
            s.step(k < p.hold ? c : .zero)
            if s.outcome == .hit { survived = k; break }
        }
        var score = Double(survived) * 100
        if survived == p.horizon {
            score += clearance(s)
            score -= abs(s.player.y - 459) * 0.04
            score -= abs(s.player.x - 180) * 0.02
        }
        if sim.isBoss {
            let bx = sim.bossPosition.x
            score -= abs(s.player.x - bx) * 0.15
        }
        if c == .zero { score += 0.5 }
        if score > bestScore { bestScore = score; bestMove = c }
    }
    return bestMove
}

struct Outcome { let result: String; let seconds: Double; let hp: Int }

func play(_ stage: Stage, _ p: Profile) -> Outcome {
    var sim = Simulation(stage: stage.sanitized())
    let cands = candidates(p.units)
    let limit = (stage.durationSec + 3) * 120 + 144
    while sim.outcome == .playing && sim.tick < limit {
        let m = choose(sim, p, cands)
        for _ in 0..<p.hold where sim.outcome == .playing { sim.step(m) }
    }
    let r: String
    switch sim.outcome {
    case .cleared: r = "CLEAR"
    case .timeUp: r = "TIME"
    case .hit: r = "HIT"
    case .playing: r = "?"
    }
    return Outcome(result: r, seconds: max(0, sim.t), hp: sim.hp)
}

let args = CommandLine.arguments
guard args.count >= 2, let data = FileManager.default.contents(atPath: args[1]) else {
    print("usage: StageBot <official_stages.json> [ids...]"); exit(1)
}
let only = Set(args.dropFirst(2))
let entries = try JSONDecoder().decode([Entry].self, from: data).filter { only.isEmpty || only.contains($0.id) }
print("id   Lv  mode    dur  weak(slow,short)      strong(fast,long)     name")
for e in entries {
    let w = play(e.stage, weak)
    let s = play(e.stage, strong)
    func fmt(_ o: Outcome, _ boss: Bool) -> String {
        let t = String(format: "%5.1fs", o.seconds)
        return boss ? "\(o.result.padding(toLength: 5, withPad: " ", startingAt: 0)) \(t) hp\(o.hp)".padding(toLength: 22, withPad: " ", startingAt: 0)
                    : "\(o.result.padding(toLength: 5, withPad: " ", startingAt: 0)) \(t)".padding(toLength: 22, withPad: " ", startingAt: 0)
    }
    let boss = e.stage.mode != .survive
    print("\(e.id)  \(e.difficulty)   \(boss ? "boss   " : "survive") \(String(format: "%3d", e.stage.durationSec))  \(fmt(w, boss)) \(fmt(s, boss)) \(e.name["en"] ?? "")")
    fflush(stdout)
}
