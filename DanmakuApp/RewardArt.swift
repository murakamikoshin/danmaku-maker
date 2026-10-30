import SwiftUI
import UIKit
import DanmakuCore

/// 報酬の見た目を決める計算。ショップの見本も、ゲーム中の演出も、ここを使う(見た目だけ似せた別実装にしない)
enum RewardArt {
    static func uiColor(_ r: Reward) -> UIColor {
        UIColor(hue: CGFloat(r.hue), saturation: 0.72, brightness: 1.0, alpha: 1)
    }

    static func color(_ r: Reward) -> Color { Color(uiColor(r)) }

    static func symbol(_ kind: RewardKind) -> String {
        switch kind {
        case .trail: return "wind"
        case .hitSpark: return "sparkle"
        case .aura: return "circle.dotted"
        case .burst: return "burst.fill"
        case .badge: return "rosette"
        }
    }

    static func name(_ r: Reward) -> String {
        String(format: L("reward.name"), r.index + 1, L(r.kind.nameKey), L(r.style.nameKey))
    }

    /// 種類ごとの、ゲーム中の粒の数・大きさ・広がり(見本と本番で同じ値を使う)
    static func particleCount(_ r: Reward) -> Int {
        switch r.style {
        case .dots: return 8
        case .ring: return 12
        case .star: return 6
        case .wave: return 10
        }
    }

    /// 見た目の少し違う色(2色目)。色の番号から決める
    static func accent(_ r: Reward) -> UIColor {
        UIColor(hue: CGFloat((r.hue + 0.5).truncatingRemainder(dividingBy: 1)), saturation: 0.5, brightness: 1.0, alpha: 1)
    }
}

/// 報酬の見本。かたち(点・輪・星・波)と色で、どんな演出かが分かる
struct RewardSwatch: View {
    let reward: Reward
    var size: CGFloat = 64
    var locked = false

    var body: some View {
        let c = RewardArt.color(reward)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Color(Palette.background))
            RoundedRectangle(cornerRadius: size * 0.22).stroke(c.opacity(0.6), lineWidth: 1.5)
            Canvas { ctx, sz in
                let mid = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let r = min(sz.width, sz.height) * 0.3
                let n = RewardArt.particleCount(reward)
                switch reward.style {
                case .dots:
                    for i in 0..<n {
                        let a = Double(i) / Double(n) * 2 * .pi
                        let p = CGPoint(x: mid.x + CGFloat(cos(a)) * r, y: mid.y + CGFloat(sin(a)) * r)
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 2.5, y: p.y - 2.5, width: 5, height: 5)), with: .color(c))
                    }
                case .ring:
                    ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: r * 2, height: r * 2)), with: .color(c), lineWidth: 3)
                    ctx.stroke(Path(ellipseIn: CGRect(x: mid.x - r * 0.55, y: mid.y - r * 0.55, width: r * 1.1, height: r * 1.1)), with: .color(Color(RewardArt.accent(reward))), lineWidth: 2)
                case .star:
                    var p = Path()
                    for i in 0..<10 {
                        let a = Double(i) / 10 * 2 * .pi - .pi / 2
                        let rad = i % 2 == 0 ? r : r * 0.45
                        let pt = CGPoint(x: mid.x + CGFloat(cos(a)) * rad, y: mid.y + CGFloat(sin(a)) * rad)
                        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    p.closeSubpath()
                    ctx.fill(p, with: .color(c))
                case .wave:
                    var p = Path()
                    for i in 0...20 {
                        let x = mid.x - r + CGFloat(i) / 20 * r * 2
                        let y = mid.y + CGFloat(sin(Double(i) / 20 * 4 * .pi)) * r * 0.45
                        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            Image(systemName: RewardArt.symbol(reward.kind))
                .font(.system(size: size * 0.2, weight: .bold)).foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(size * 0.08)
            if locked {
                Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: size * 0.22))
                Image(systemName: "lock.fill").font(.system(size: size * 0.28)).foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: size, height: size)
    }
}

/// ゲーム中に使う、選んでいる報酬の演出(種類ごとに1つ)
struct RewardFX {
    var trail: Reward?
    var hitSpark: Reward?
    var aura: Reward?
    var burst: Reward?

    static let none = RewardFX()

    @MainActor static func current(_ store: RewardStore = .shared) -> RewardFX {
        RewardFX(trail: store.selected(.trail), hitSpark: store.selected(.hitSpark), aura: store.selected(.aura), burst: store.selected(.burst))
    }

    /// このステージで使う演出。作者がステージに付けた種類はそれを使い、付けていない種類は、遊ぶ人が選んでいるものを使う
    @MainActor static func resolved(for stage: Stage, store: RewardStore = .shared) -> RewardFX {
        var fx = current(store)
        for r in (stage.rewardFx ?? []).compactMap(Reward.init(index:)) {
            switch r.kind {
            case .trail: fx.trail = r
            case .hitSpark: fx.hitSpark = r
            case .aura: fx.aura = r
            case .burst: fx.burst = r
            case .badge: break
            }
        }
        return fx
    }
}
