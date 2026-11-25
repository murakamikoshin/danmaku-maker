import Foundation

/// 買って手に入れる、雑魚(発射点にいる小さな敵)の見た目のセット。見た目だけで、計算には関わらない。
/// ステージの `mookLook` の番号で選ぶ(0〜4 は最初から使える図形、5 以降がセットの絵)。
/// ボスと同じで、**遊ぶのは誰でもできる**。持っている必要があるのは、ステージを公開するときだけ。
/// 古い版(1.4.2 まで)は 5 以降を知らないので、標準の見た目で出る(遊べる。needs は付けない)
public enum MookPack: String, CaseIterable, Sendable {
    /// クリスマス(雪だるま・プレゼント箱・ジンジャーブレッドマン・鈴)。1.5.0。期間限定で売る
    case xmas

    /// このセットの見た目の番号
    public var looks: ClosedRange<Int> {
        switch self {
        case .xmas: return 5...8
        }
    }

    /// 商品 ID の末尾(`mooks.<これ>`)。サーバーの MOOK_PACKS と同じにする
    public var productKey: String { rawValue }

    /// 期間限定で売るセットの、販売期間の名前。nil は、いつでも売っているセット
    public var season: SaleSeason? {
        switch self {
        case .xmas: return .xmas
        }
    }

    /// いま売り場(ショップ)に出すか。所持の判定(Ownership.has)には使わない: 売り場から消えても、買った人・永久買い切りパックの人は使える
    public func onShelf(_ open: Set<SaleSeason>) -> Bool {
        guard let season else { return true }
        return open.contains(season)
    }

    /// その見た目の番号が入っているセット(最初から使える 0〜4 は nil)
    public static func of(look: Int) -> MookPack? { allCases.first { $0.looks.contains(look) } }

    /// 最初から使える見た目の数(0〜4)
    public static let freeLooks = 5
    /// mookLook に入れられる番号の数
    public static var lookCount: Int { (allCases.map(\.looks.upperBound).max() ?? freeLooks - 1) + 1 }
}
