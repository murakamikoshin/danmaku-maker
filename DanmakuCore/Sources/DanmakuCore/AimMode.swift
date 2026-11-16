import Foundation

/// 狙い方(Emitter.aim)が、どのパターンに効くか。エディタは、効くパターンにだけ選ぶ欄を出す。
/// パターンごとの表を手で持つと、技を足したときに漏れるので、実際に1回撃ってみて決める
public enum AimSupport: Sendable {
    /// 狙い方は関係しない(輪・十字など、自機を見ないで決まった形に撃つもの)
    case none
    /// ランダムだけ効く(雨のように、自機は見ないが散らばり方に乱数を使うもの)
    case randomOnly
    /// 自機狙い・固定・ランダムのどれも効く(自機の位置を見て撃つもの)
    case full
}

extension Emitter {
    /// このパターンに、狙い方がどう効くか
    public var aimSupport: AimSupport { Emitter.aimSupportTable[t] ?? .none }
    /// パターンごとの、狙い方の効き方
    public static func aimSupport(of t: Pattern) -> AimSupport { aimSupportTable[t] ?? .none }

    private static let aimSupportTable: [Pattern: AimSupport] = {
        var table: [Pattern: AimSupport] = [:]
        for t in Pattern.allCases { table[t] = probe(t) }
        return table
    }()

    /// 同じ発射台を、狙う場所や乱数だけ変えて撃ち比べる
    private static func probe(_ t: Pattern) -> AimSupport {
        let path: [Double]? = t == .custom ? [0, 0, 0, 20, 0, 40] : nil
        let m = Emitter(t: t, x: 0.5, y: 0.2, s: 0, e: 30, i: 1, c: 8, v: 2, r: 10, k: 0, path: path)
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        func shoot(px: Double, py: Double, seed: UInt32) -> [Bullet] {
            var out: [Bullet] = []
            var rng = Mulberry32(seed: seed)
            for k in 0..<3 {
                Emit.emit(m, shot: k, cx: W * 0.5, cy: H * 0.2, px: px, py: py, rng: &rng, into: &out)
            }
            return out
        }
        let base = shoot(px: W * 0.3, py: H * 0.8, seed: 1)
        if base != shoot(px: W * 0.8, py: H * 0.6, seed: 1) { return .full }
        if base != shoot(px: W * 0.3, py: H * 0.8, seed: 2) { return .randomOnly }
        return .none
    }
}
