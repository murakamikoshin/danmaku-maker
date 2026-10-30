import Foundation

/// 広告を見て、1日1つもらえる報酬(365個)。演出と称号で、遊びやランキングには影響しない。演出は、自分の画面に出すほか、ステージ作成で選ぶと(Stage.rewardFx)そのステージを遊ぶ全員に出せる
public enum RewardKind: Int, CaseIterable, Codable, Sendable {
    /// 自機の軌跡
    case trail
    /// 弾が当たったときの光
    case hitSpark
    /// 自機のまわりのオーラ
    case aura
    /// ボスを倒したときの演出
    case burst
    /// 称号(プロフィールなどに付く飾り)
    case badge

    public var nameKey: String { "reward.kind.\(self)" }
}

/// 演出のかたち。種類ごとに、描き方が少しずつ違う
public enum RewardStyle: Int, CaseIterable, Codable, Sendable {
    case dots, ring, star, wave

    public var nameKey: String { "reward.style.\(self)" }
}

public struct Reward: Hashable, Codable, Sendable {
    /// 0...364。この番号の順に、1日1つずつもらえる
    public let index: Int

    public init?(index: Int) {
        guard (0..<DailyRewards.total).contains(index) else { return nil }
        self.index = index
    }

    public var kind: RewardKind { RewardKind.allCases[index % RewardKind.allCases.count] }
    /// 種類ごとの通し番号(0...72)
    public var variant: Int { index / RewardKind.allCases.count }
    /// 色の番号(0..<DailyRewards.colorCount)。7つずつ飛ばして割り当てて、続けてもらう報酬どうしで色が大きく変わるようにする
    public var colorIndex: Int { (index * 7) % DailyRewards.colorCount }
    /// かたち。5つごとに変わり、120番ごとのずれで、(種類・色・かたち)の組み合わせがすべて違うようにする
    public var style: RewardStyle { RewardStyle.allCases[(variant + index / 120) % RewardStyle.allCases.count] }
    /// 色の色相(0...1)。色の番号を、色相環に等間隔で置く
    public var hue: Double { Double(colorIndex) / Double(DailyRewards.colorCount) }
    public var id: String { "reward.\(index)" }

    /// ステージに付けられる演出の種類(称号は、ゲーム中の演出ではないので除く)
    public static let stageKinds: [RewardKind] = [.trail, .hitSpark, .aura, .burst]

    /// ステージに付ける演出の番号を整える。範囲外・称号・同じ種類の2つ目は捨て、種類の順に並べる。空なら nil。サーバーの検証と同じ規則
    public static func sanitizedFx(_ indices: [Int]?) -> [Int]? {
        var byKind: [Int: Int] = [:]
        for i in indices ?? [] {
            guard let r = Reward(index: i), stageKinds.contains(r.kind), byKind[r.kind.rawValue] == nil else { continue }
            byKind[r.kind.rawValue] = i
        }
        let list = byKind.sorted { $0.key < $1.key }.map(\.value)
        return list.isEmpty ? nil : list
    }
}

public enum DailyRewards {
    /// 報酬の数(5種類 × 73通り)
    public static let total = 365
    public static let colorCount = 24

    public static var all: [Reward] { (0..<total).compactMap(Reward.init(index:)) }
}

/// 受け取りの記録。端末の日付(1970年1月1日からの日数)で、1日1回に制限する
public struct DailyRewardState: Equatable, Codable, Sendable {
    /// これまでに受け取った数(= 次にもらう報酬の番号)
    public private(set) var claimed: Int
    /// 最後に受け取った日(日数)。まだ受け取っていなければ nil
    public private(set) var lastDay: Int?

    public init(claimed: Int = 0, lastDay: Int? = nil) {
        self.claimed = max(0, min(claimed, DailyRewards.total))
        self.lastDay = lastDay
    }

    /// 今日、受け取れるか。端末の日付を戻しても、受け取り済みの日より前なら受け取れない
    public func canClaim(today: Int) -> Bool {
        guard claimed < DailyRewards.total else { return false }
        guard let last = lastDay else { return true }
        return today > last
    }

    /// 受け取る。受け取れないときは nil
    public mutating func claim(today: Int) -> Reward? {
        guard canClaim(today: today), let reward = Reward(index: claimed) else { return nil }
        claimed += 1
        lastDay = today
        return reward
    }

    /// もう持っている報酬か
    public func has(_ reward: Reward) -> Bool { reward.index < claimed }

    /// 持っている報酬(種類を絞れる)
    public func owned(_ kind: RewardKind? = nil) -> [Reward] {
        (0..<claimed).compactMap(Reward.init(index:)).filter { kind == nil || $0.kind == kind }
    }

    /// 日付(Date)から日数を出す。端末のタイムゾーンの0時で日付が変わる
    public static func day(of date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let ref = calendar.startOfDay(for: Date(timeIntervalSince1970: 0))
        return calendar.dateComponents([.day], from: ref, to: start).day ?? 0
    }
}

/// いま選んでいる報酬(種類ごとに1つ)。持っていないものを指していたら、使わない
public struct RewardLoadout: Equatable, Codable, Sendable {
    public var selected: [Int: Int] = [:]  // RewardKind.rawValue → Reward.index

    public init() {}

    public func reward(for kind: RewardKind, state: DailyRewardState) -> Reward? {
        guard let i = selected[kind.rawValue], let r = Reward(index: i), r.kind == kind, state.has(r) else { return nil }
        return r
    }

    public mutating func select(_ reward: Reward?, kind: RewardKind) {
        if let reward, reward.kind == kind { selected[kind.rawValue] = reward.index } else { selected[kind.rawValue] = nil }
    }
}
