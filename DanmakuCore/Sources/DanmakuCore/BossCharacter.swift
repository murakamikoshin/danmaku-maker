import Foundation

/// 期間限定の販売の名前。販売中かどうかは端末の時計では決めず、Remote Config の `<rawValue>_boss_on_sale` をサーバー側で切り替える
public enum SaleSeason: String, CaseIterable, Sendable {
    case xmas
    /// Remote Config のキー
    public var configKey: String { rawValue + "_boss_on_sale" }
}

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
    /// 機神
    case mech = 10
    /// ぷにまる(ギャップボス。覚醒は秘密)
    case puni = 11
    /// 金魚姫(金魚すくいの金魚娘)
    case hire = 12
    /// 竜王(技で本体が動く・範囲攻撃・段階ごとに姿を選ぶ。Dragon.swift)
    case dragon = 13
    /// サンタ娘(クリスマスの期間限定で売るボス。1.5.0)。売り場に出すのは期間中だけ。持っている人・永久買い切りパックの人は、いつでも使える
    case santa = 14

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
        case .mech: return "mech"
        case .puni: return "puni"
        case .hire: return "hire"
        case .dragon: return "dragon"
        case .santa: return "santa"
        }
    }

    /// 無料チケットで手に入れられるか。課金専用のボスは false にする(サーバーの PAID_ONLY_BOSSES と同じにする)
    public var ticketEligible: Bool {
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch, .mech, .hire, .dragon: return true
        case .puni, .santa: return false
        }
    }

    /// 無料チケットで手に入れるのに使う枚数(サーバーの TICKET_COST と同じにする)。竜王は 3 枚
    public var ticketCost: Int { self == .dragon ? 3 : 1 }

    /// 招待限定のボスか(買えず、チケットでも手に入らない。招待の特典としてだけ手に入る)。サーバーの INVITE_ONLY_BOSSES と同じにする
    public var inviteLimited: Bool { self == .puni }
    /// 商品として存在するか(= 永久買い切りパックに含むか)。**「いま売り場に出すか」ではない**。
    /// 期間限定のボスも、期間に関係なく true(false にすると、永久買い切りパックの人が使えなくなり、買った人の復元もできなくなる)。
    /// いま売り場に出すかは onShelf(_:) で決める
    public var purchasable: Bool { !inviteLimited }

    /// 期間限定で売るボスの、販売期間の名前(Remote Config の `<これ>_boss_on_sale` で切り替える)。nil は、いつでも売っているボス
    public var season: SaleSeason? { self == .santa ? .xmas : nil }

    /// いま売り場(ショップ)に出すか。期間限定のボスは、その期間の販売がオンのときだけ。
    /// 所持の判定(Ownership.has)には使わない: 売り場から消えても、買った人・永久買い切りパックの人は使える
    public func onShelf(_ open: Set<SaleSeason>) -> Bool {
        guard purchasable else { return false }
        guard let season else { return true }
        return open.contains(season)
    }

    public static func of(look: Int) -> BossCharacter? { BossCharacter(rawValue: look) }

    /// 弾(自機のショット)が当たる半径(論理px)。大きさの設定(小・中・大)は、キャラクターでは使わない
    public var hitRadius: Double {
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch, .mech, .puni, .hire, .santa: return 40
        case .dragon: return 56
        }
    }

    /// ボスの中心。待機中にゆっくり揺れる(動きの設定(0〜2)は、キャラクターでは使わない)。
    /// 絵が大きいので、画面の上に切れないよう、図形のボスより下に置く。T(60fps のフレーム数)は秒に直して使う
    public func position(waveT: Double) -> Point {
        let t = max(0, waveT)
        switch self {
        case .fallenAngel, .kitsune, .iceQueen, .reaper, .witch, .mech, .puni, .hire, .santa:
            return Point(x: DanmakuConfig.width / 2 + sin(t * 60 * 0.012) * 30,
                         y: 128 + sin(t * 60 * 0.02) * 5)
        case .dragon:
            // 竜王は大きいので、横の揺れを小さく(試射場と同じ)
            return Point(x: DanmakuConfig.width / 2 + sin(t * 60 * 0.012) * 12,
                         y: 128 + sin(t * 60 * 0.02) * 5)
        }
    }

    /// 動きを指定したときの、図形のボスの動きからの下へのずれ(px)。絵が大きいので、画面の上に切れないよう、定位置と同じ高さに下げる
    public static let moveYOffset = 128 - DanmakuConfig.height * 0.18

    /// 覚醒する段階として選べる値(第2段階・第3段階)
    public static let awakenPhases = [2, 3]
}
