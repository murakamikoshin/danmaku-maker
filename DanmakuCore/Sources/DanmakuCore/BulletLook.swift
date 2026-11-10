import Foundation

/// ボス専用の弾の見た目(Bullet.look の 16 以上)。0=標準、1=くの字、2=丸 は従来どおり。
/// look = 16 + 種類 × 2 + (覚醒なら 1)。見た目は描画だけに使うが、**当たる半径は種類ごとに決まっていて、計算に効く**
/// (半径は弾そのものの大きさ。自機の当たり判定 2.5px を足した距離で当たる。標準の弾は 3 + 2.5 = 5.5px)。
public enum BulletLook {
    public static let firstSpecial: UInt8 = 16
    /// 並びは変えない(look の番号になる)。足すときは必ず後ろへ
    public enum Kind: Int, CaseIterable, Sendable {
        case fox, ofuda, plankton, bubble, ink, missile, hex, shell, flake, icicle, shard, soul, blade, chain, jelly, eye, tooth, goo
    }
    /// 各種類の、弾そのものの半径(px)
    static let bodyRadius: [Double] = [3, 3, 2.5, 4, 6, 3, 3, 2, 3, 3, 2.5, 3, 3, 2.5, 3.5, 4, 2.5, 2.5]
    /// 自機の当たり判定の半径(px)
    static let playerRadius = 2.5

    public static func code(_ k: Kind, awakened: Bool = false) -> UInt8 {
        firstSpecial + UInt8(k.rawValue * 2 + (awakened ? 1 : 0))
    }
    public static func kind(of look: UInt8) -> Kind? {
        guard look >= firstSpecial else { return nil }
        return Kind(rawValue: Int(look - firstSpecial) / 2)
    }
    public static func isAwakened(_ look: UInt8) -> Bool { look >= firstSpecial && (look - firstSpecial) % 2 == 1 }
    /// 自機に当たる距離(px)。専用の弾でなければ nil
    public static func hitDistance(_ look: UInt8) -> Double? {
        kind(of: look).map { bodyRadius[$0.rawValue] + playerRadius }
    }
    /// 進む向きへ回して描く弾か(ほかは回さない)
    public static func isOriented(_ k: Kind) -> Bool {
        switch k {
        case .fox, .ofuda, .missile, .shell, .icicle, .shard, .soul, .chain, .tooth: return true
        default: return false
        }
    }
}
