import Foundation
import DanmakuCore

/// 広告を見て1日1つ解放する34パターンの、解放の記録。端末に保存する
@MainActor
final class AdPatternStore: ObservableObject {
    static let shared = AdPatternStore()

    @Published private(set) var state: AdPatternState
    /// 日付が変わったときに画面を更新するための、今日の日数
    @Published private(set) var today: Int
    /// 直前に解放したパターン(画面でお祝いを出すため)
    @Published var justUnlocked: Pattern?

    private let defaults: UserDefaults
    static let stateKey = "adpatterns.state"

    /// 保存してある記録(ステージ作りの画面が、起動直後から使えるように、CosmeticsStore も読む)
    static func load(_ defaults: UserDefaults = .standard) -> AdPatternState {
        defaults.data(forKey: stateKey).flatMap { try? JSONDecoder().decode(AdPatternState.self, from: $0) } ?? AdPatternState()
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        state = Self.load(defaults)
        today = DailyRewardState.day(of: Date())
        #if DEBUG
        // 画面確認用: -adpatterns-claimed N で、N個解放した状態にする
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-adpatterns-claimed"), args.indices.contains(i + 1), let n = Int(args[i + 1]) {
            state = AdPatternState(claimed: n, lastDay: n > 0 ? today : nil)
            CosmeticsStore.shared.setAdPatterns(state.unlocked)
        }
        #endif
    }

    var canClaim: Bool { state.canClaim(today: today) }

    func refreshDay() { today = DailyRewardState.day(of: Date()) }

    /// 解放する(広告を見終えたあと、または広告削除・永久買い切りパックの購入者がそのまま呼ぶ)
    @discardableResult
    func claim() -> Pattern? {
        refreshDay()
        var next = state
        guard let p = next.claim(today: today) else { return nil }
        state = next
        if let d = try? JSONEncoder().encode(next) { defaults.set(d, forKey: Self.stateKey) }
        CosmeticsStore.shared.setAdPatterns(next.unlocked)
        justUnlocked = p
        return p
    }
}
