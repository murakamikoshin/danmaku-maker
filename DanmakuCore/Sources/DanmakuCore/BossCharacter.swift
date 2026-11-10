import Foundation

/// 専用の絵と動き・当たり判定を持つボス(ドット絵のキャラクター)。
/// ステージの `bossLook` の番号で選ぶ(0〜4 は図形のボス、5 以上がキャラクター)。
/// 位置と当たり判定は計算に関わる(サーバーと同じ値)。絵は DanmakuApp 側にある。
public enum BossCharacter: Int, CaseIterable, Sendable {
    /// 堕天使
    case fallenAngel = 5
    /// 九尾の巫女
    case kitsune = 6
    /// 雪の女王
    case iceQueen = 7
    /// 死神
    case reaper = 8
    /// 深海の魔女
    case witch = 9

    /// 図形のボスの数(0〜4)。bossLook がこれ以上ならキャラクター
    public static let firstCharacterLook = 5
    /// bossLook に入れられる最大の番号
    public static var maxLook: Int { allCases.map(\.rawValue).max() ?? firstCharacterLook - 1 }

    /// エディタで選べるか。買い切りと無料チケットの仕組みがそろったので、製品ビルドでも選べる
    public static var editorEnabled: Bool { true }

    /// 商品 ID に使う名前(com.koshin.danmakumaker.boss.<これ>)
    public var productKey: String {
        switch self {
        case .fallenAngel: return "fallen_angel"
        case .kitsune: return "kitsune"
        case .iceQueen: return "ice_queen"
        case .reaper: return "reaper"
        case .witch: return "witch"
        }
    }

    /// 無料チケットで手に入れられるか。課金専用のボスは false にする(サーバーの PAID_ONLY_BOSSES と同じにする)
    public var ticketEligible: Bool {
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch: return true
        }
    }

    public static func of(look: Int) -> BossCharacter? { BossCharacter(rawValue: look) }

    /// 弾(自機のショット)が当たる半径(論理px)。大きさの設定(小・中・大)は、キャラクターでは使わない
    public var hitRadius: Double {
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch: return 40
        }
    }

    /// ボスの中心。待機中にゆっくり揺れる(動きの設定(0〜2)は、キャラクターでは使わない)。
    /// 絵が大きいので、画面の上に切れないよう、図形のボスより下に置く。T(60fps のフレーム数)は秒に直して使う
    public func position(waveT: Double) -> Point {
        let t = max(0, waveT)
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch:
            return Point(x: DanmakuConfig.width / 2 + sin(t * 60 * 0.012) * 30,
                         y: 128 + sin(t * 60 * 0.02) * 5)
        }
    }

    /// 覚醒する段階として選べる値(第2段階・第3段階)
    public static let awakenPhases = [2, 3]
}
