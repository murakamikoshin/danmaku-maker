import Foundation
import SwiftUI
import DanmakuCore

/// 広告を見て1日1つ(「もう1つ」を足して最大3つ)もらえる報酬の、受け取り記録と、いま選んでいるもの。端末に保存する
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

    /// 今日の分(1日の最初の1つ)を受け取れるか
    var canClaim: Bool { state.canClaim(today: today) }
    /// 今日の分のあと、今日あと何回「もう1つ」をもらえるか
    var extraLeft: Int { state.extraLeft(today: today) }
    var canClaimExtra: Bool { extraLeft > 0 }

    /// 今日もらえる報酬と、その先の報酬(最大 count 個)。先の報酬も見せて、楽しみにしてもらう
    var upcoming: [Reward] {
        (state.claimed..<min(state.claimed + 8, DailyRewards.total)).compactMap(Reward.init(index:))
    }

    func refreshDay() { today = DailyRewardState.day(of: Date()) }

    /// 受け取る(広告を見終えたあと、または広告削除の購入者がそのまま呼ぶ)。extra なら「もう1つ」。受け取れたら、すぐ使える状態にする
    @discardableResult
    func claim(extra: Bool = false) -> Reward? {
        refreshDay()
        var next = state
        guard let reward = extra ? next.claimExtra(today: today) : next.claim(today: today) else { return nil }
        state = next
        if let d = try? JSONEncoder().encode(next) { defaults.set(d, forKey: Self.stateKey) }
        // 種類ごとに最初の1つは、そのまま使う(あとから変えられる)
        if loadout.selected[reward.kind.rawValue] == nil { loadout.select(reward, kind: reward.kind) }
        justClaimed = reward
        return reward
    }

    /// 画面のボタンから受け取る: 広告を見終えたら(広告削除の購入者は広告なしで)受け取り、鳴らす。
    /// 今日の分が受け取れる日は今日の分、受け取り済みなら「もう1つ」
    func claimFromButton(ads: AdsService, purchases: PurchaseService) async {
        // 日付が変わっていたら、先に今日にそろえる(前の日の「もう1つ」のつもりで押しても、今日の分としてもらえるように)
        refreshDay()
        guard canClaim || canClaimExtra else { return }
        if !purchases.isPremium {
            guard await ads.showRewarded() else { return }
        }
        // 広告を見ている間に日付が変わることもあるので、もらう種類は見終わってから決める
        refreshDay()
        let extra = !canClaim
        if claim(extra: extra) != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioManager.shared.se(.get)
        }
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
