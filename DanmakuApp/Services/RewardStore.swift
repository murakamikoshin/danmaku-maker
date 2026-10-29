import Foundation
import SwiftUI
import DanmakuCore

/// 広告を見て1日1つもらえる報酬の、受け取り記録と、いま選んでいるもの。端末に保存する
@MainActor
final class RewardStore: ObservableObject {
    static let shared = RewardStore()

    @Published private(set) var state: DailyRewardState
    @Published var loadout: RewardLoadout { didSet { save() } }
    /// 直前に受け取った報酬(画面でお祝いを出すため)
    @Published var justClaimed: Reward?
    /// 日付が変わったときに画面を更新するための、今日の日数
    @Published private(set) var today: Int

    private let defaults: UserDefaults
    private static let stateKey = "rewards.state"
    private static let loadoutKey = "rewards.loadout"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = defaults.data(forKey: Self.stateKey).flatMap { try? JSONDecoder().decode(DailyRewardState.self, from: $0) } ?? DailyRewardState()
        loadout = defaults.data(forKey: Self.loadoutKey).flatMap { try? JSONDecoder().decode(RewardLoadout.self, from: $0) } ?? RewardLoadout()
        today = DailyRewardState.day(of: Date())
        #if DEBUG
        // 画面確認用: -rewards-claimed N で、N個もらった状態にする(種類ごとに、最初の1つを使う)
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-rewards-claimed"), args.indices.contains(i + 1), let n = Int(args[i + 1]) {
            state = DailyRewardState(claimed: n, lastDay: n > 0 ? today : nil)
            loadout = RewardLoadout()
            for k in RewardKind.allCases { loadout.select(state.owned(k).first, kind: k) }
        }
        #endif
    }

    var canClaim: Bool { state.canClaim(today: today) }

    /// 今日もらえる報酬と、その先の報酬(最大 count 個)。先の報酬も見せて、楽しみにしてもらう
    var upcoming: [Reward] {
        (state.claimed..<min(state.claimed + 8, DailyRewards.total)).compactMap(Reward.init(index:))
    }

    func refreshDay() { today = DailyRewardState.day(of: Date()) }

    /// 受け取る(広告を見終えたあと、または広告削除の購入者がそのまま呼ぶ)。受け取れたら、すぐ使える状態にする
    @discardableResult
    func claim() -> Reward? {
        refreshDay()
        var next = state
        guard let reward = next.claim(today: today) else { return nil }
        state = next
        if let d = try? JSONEncoder().encode(next) { defaults.set(d, forKey: Self.stateKey) }
        // 種類ごとに最初の1つは、そのまま使う(あとから変えられる)
        if loadout.selected[reward.kind.rawValue] == nil { loadout.select(reward, kind: reward.kind) }
        justClaimed = reward
        return reward
    }

    func select(_ reward: Reward?, kind: RewardKind) {
        if let reward, !state.has(reward) { return }
        loadout.select(reward, kind: kind)
    }

    /// 選んでいる報酬(持っていないものは除く)
    func selected(_ kind: RewardKind) -> Reward? { loadout.reward(for: kind, state: state) }

    private func save() {
        if let d = try? JSONEncoder().encode(loadout) { defaults.set(d, forKey: Self.loadoutKey) }
    }
}
