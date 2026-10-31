// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。

import Foundation

/// 広告で解放する31パターンの、弾の出し方。サーバー(adpatterns.ts)にも同じ表と計算がある

public struct PatternRecipe: Sendable {
    public var mode: Int = 0
    public var fan: Double = 0.0
    public var spin: Double = 1.0
    public var sweepAmp: Double = 0.0
    public var sweepFreq: Double = 0.25
    public var layers: Int = 1
    public var layerAngle: Double = 0.0
    public var layerSpeed: Double = 1.0
    public var wobbleAmp: Double = 0.0
    public var wobbleFreq: Double = 1.0
    public var wobblePhase: Double = 0.0
    public var waveAmp: Double = 0.0
    public var waveFreq: Double = 1.0
    public var wavePhase: Double = 0.0
    public var speedStep: Double = 0.0
    public var speedCycle: Int = 0
    public var altSpeed: Double = 0.0
    public var speed0: Double = 1.0
    public var lineWidth: Double = 0.0
    public var scatter: Double = 0.0
    public var jitter: Double = 0.0
    public var turn: Double = 0.0
    public var accel: Double = 0.0
    public var maxMul: Double = 0.0
    public var bounces: Int = 0
    public var script: Int = 0
    public var beam: Int = 0
}

public extension Pattern {
    /// 広告を見て解放する、無料のパターン(解放する順)
    static let ad: [Pattern] = [.twinRing, .tripleRing, .pinwheel, .ripple, .chargeBeam, .whirl, .slither, .curtain, .swayFan, .drizzle, .comet, .shotgun, .sniper, .twinAim, .zigzagAim, .accelRing, .homingRing, .bounceRing, .freezeRing, .shatterRing, .pulseRing, .freezeCurtain, .splitCurtain, .wavyRing, .petalFan, .waveSpiral, .tide, .ladder, .helix, .rapidFan, .lightRain]
    var isAd: Bool { Pattern.ad.contains(self) }

    /// 弾の出し方の表(広告で解放するパターンだけ)
    var recipe: PatternRecipe? {
        switch self {
        case .twinRing: return PatternRecipe(mode: 0, layers: 2, layerSpeed: 0.6)
        case .tripleRing: return PatternRecipe(mode: 0, layers: 3, layerSpeed: 0.75)
        case .pinwheel: return PatternRecipe(mode: 0, altSpeed: 0.45)
        case .ripple: return PatternRecipe(mode: 0, spin: 0.0, layers: 4, layerAngle: 5.0, layerSpeed: 0.85)
        case .chargeBeam: return PatternRecipe(mode: 1, beam: 1)
        case .whirl: return PatternRecipe(mode: 0, speedStep: 0.035)
        case .slither: return PatternRecipe(mode: 2, wobbleAmp: 22.0, wobbleFreq: 1.1, wobblePhase: 0.6)
        case .curtain: return PatternRecipe(mode: 2, fan: -1.0, lineWidth: 330.0)
        case .swayFan: return PatternRecipe(mode: 2, fan: 70.0, lineWidth: 280.0, bounces: 2)
        case .drizzle: return PatternRecipe(mode: 2, fan: -1.0, speed0: 0.25, scatter: 340.0, accel: 1.0, maxMul: 2.6)
        case .comet: return PatternRecipe(mode: 1, speedStep: 0.15)
        case .shotgun: return PatternRecipe(mode: 1, jitter: 10.0)
        case .sniper: return PatternRecipe(mode: 2, fan: -1.0, lineWidth: 300.0, turn: 30.0)
        case .twinAim: return PatternRecipe(mode: 1, layers: 2, layerSpeed: 0.7, script: 3)
        case .zigzagAim: return PatternRecipe(mode: 1, wobbleAmp: 16.0, wobbleFreq: 2.3, wobblePhase: 0.9)
        case .accelRing: return PatternRecipe(mode: 0, speed0: 0.35, accel: 0.8, maxMul: 2.2)
        case .homingRing: return PatternRecipe(mode: 0, turn: 40.0)
        case .bounceRing: return PatternRecipe(mode: 0, bounces: 2)
        case .freezeRing: return PatternRecipe(mode: 0, script: 1)
        case .shatterRing: return PatternRecipe(mode: 0, script: 2)
        case .pulseRing: return PatternRecipe(mode: 2, fan: -1.0, scatter: 340.0, script: 1)
        case .freezeCurtain: return PatternRecipe(mode: 2, fan: -1.0, lineWidth: 300.0, script: 1)
        case .splitCurtain: return PatternRecipe(mode: 2, fan: -1.0, lineWidth: 300.0, script: 2)
        case .wavyRing: return PatternRecipe(mode: 0, waveAmp: 0.35, waveFreq: 3.0)
        case .petalFan: return PatternRecipe(mode: 1, waveAmp: 0.4, waveFreq: 3.0)
        case .waveSpiral: return PatternRecipe(mode: 0, waveAmp: 0.3, waveFreq: 1.7, wavePhase: 0.8)
        case .tide: return PatternRecipe(mode: 2, waveAmp: 0.5, waveFreq: 2.0, wavePhase: 1.3)
        case .ladder: return PatternRecipe(mode: 2, fan: -1.0, altSpeed: 0.6, lineWidth: 300.0)
        case .helix: return PatternRecipe(mode: 0, layers: 2, layerAngle: 8.0, layerSpeed: 1.15)
        case .rapidFan: return PatternRecipe(mode: 1, speedStep: 0.12, speedCycle: 3)
        case .lightRain: return PatternRecipe(mode: 2, fan: -1.0, speed0: 1.2, scatter: 340.0, jitter: 3.0)
        default: return nil
        }
    }

    /// エディタで選んだときの初期値(間隔・数・速さ・角度)
    var recipeDefaults: (i: Double, c: Int, v: Double, r: Double)? {
        switch self {
        case .twinRing: return (1.0, 14, 2.4, 6.0)
        case .tripleRing: return (1.2, 12, 2.6, 4.0)
        case .pinwheel: return (0.5, 8, 2.4, 9.0)
        case .ripple: return (1.4, 18, 2.4, 0.0)
        case .chargeBeam: return (2.4, 1, 2.0, 40.0)
        case .whirl: return (0.12, 4, 1.6, 13.0)
        case .slither: return (0.6, 7, 2.2, 26.0)
        case .curtain: return (0.9, 12, 1.8, 0.0)
        case .swayFan: return (1.3, 7, 2.0, 0.0)
        case .drizzle: return (0.25, 2, 2.0, 0.0)
        case .comet: return (1.0, 7, 1.8, 14.0)
        case .shotgun: return (0.9, 9, 2.6, 24.0)
        case .sniper: return (1.8, 6, 1.5, 0.0)
        case .twinAim: return (1.0, 7, 2.4, 50.0)
        case .zigzagAim: return (0.7, 8, 2.3, 30.0)
        case .accelRing: return (1.1, 16, 2.0, 7.0)
        case .homingRing: return (1.8, 8, 1.5, 10.0)
        case .bounceRing: return (1.3, 10, 2.2, 8.0)
        case .freezeRing: return (1.2, 14, 2.4, 6.0)
        case .shatterRing: return (1.6, 8, 2.2, 10.0)
        case .pulseRing: return (0.45, 3, 2.0, 0.0)
        case .freezeCurtain: return (1.3, 9, 2.4, 0.0)
        case .splitCurtain: return (1.5, 6, 1.8, 0.0)
        case .wavyRing: return (1.0, 24, 2.2, 6.0)
        case .petalFan: return (0.9, 13, 2.2, 60.0)
        case .waveSpiral: return (0.1, 3, 2.0, 11.0)
        case .tide: return (0.5, 9, 2.0, 70.0)
        case .ladder: return (0.8, 10, 2.0, 0.0)
        case .helix: return (0.1, 3, 2.0, 12.0)
        case .rapidFan: return (0.22, 6, 2.4, 36.0)
        case .lightRain: return (0.08, 2, 2.8, 0.0)
        default: return nil
        }
    }
}

extension Emit {
    /// 表(PatternRecipe)に従って弾を出す。部品の意味は tools/gen_ad_patterns.py を参照
    static func emitRecipe(_ r: PatternRecipe, _ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                           off: Double, sp: Double, n: Int, rng: inout Mulberry32, into out: inout [Bullet]) {
        let deg = Double.pi / 180
        let fanDeg = r.fan < 0 ? 0 : (r.fan > 0 ? r.fan : m.r)
        var layerSpeed = 1.0
        for layer in 0..<max(1, r.layers) {
            let layerShift = Double(layer) * r.layerAngle * deg
            let base: Double
            switch r.mode {
            case 0: base = Double(k) * m.r * deg * r.spin + off
            case 1: base = atan2(py - cy, px - cx) + off
            default: base = Double.pi / 2 + off + sin(Double(k) * r.sweepFreq) * m.r * deg * r.sweepAmp
            }
            for j in 0..<n {
                var a: Double
                if r.mode == 0 { a = base + Double(j) * 2 * Double.pi / Double(n) }
                else { a = base + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * fanDeg * deg : 0) }
                a += layerShift
                if r.wobbleAmp != 0 { a += r.wobbleAmp * deg * sin(Double(j) * r.wobbleFreq + Double(k) * r.wobblePhase) }
                if r.jitter != 0 { a += (rng.next() - 0.5) * 2 * r.jitter * deg }
                var f = r.speed0 * layerSpeed
                if r.speedStep != 0 { let jj = r.speedCycle > 0 ? j % r.speedCycle : j; f *= 1 + Double(jj) * r.speedStep }
                if r.altSpeed != 0 && j % 2 == 1 { f *= r.altSpeed }
                if r.waveAmp != 0 { f *= 1 + r.waveAmp * sin(Double(j) * r.waveFreq + Double(k) * r.wavePhase) }
                var x = cx
                if r.lineWidth != 0 { x += (n > 1 ? Double(j) / Double(n - 1) - 0.5 : 0) * r.lineWidth }
                if r.scatter != 0 { x += (rng.next() - 0.5) * r.scatter }
                guard out.count < DanmakuConfig.maxBullets else { continue }
                if r.beam != 0 {
                    // チャージビーム: その場に止まったまま、向き(長さ1)だけを持つ
                    out.append(Bullet.beam(x: x, y: cy, angle: a, color: m.k))
                } else {
                    out.append(Bullet(x: x, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k,
                                      turn: r.turn * deg, homeLeft: r.turn > 0 ? DanmakuConfig.homingSeconds : 0,
                                      accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces, script: r.script))
                }
            }
            layerSpeed *= r.layerSpeed
        }
    }
}
