import DanmakuCore
import FirebaseRemoteConfig
import Foundation

/// 期間限定のボスを、いま売り場(ショップ)に出すか。Remote Config の `<期間>_boss_on_sale`(例: `xmas_boss_on_sale`)で決める。
/// **端末の時計は使わない**(時計を進めたり戻したりしても変わらない)。期間の始まりと終わりは、Remote Config の日時の条件でサーバー側が切り替える。
/// 取れなかったときは前回の値(初回はオフ = 売り場に出さない)。
/// ここで決めるのは「売り場に出すか」だけ。使えるかどうか(Ownership.has)には関わらない: 買った人・永久買い切りパックの人は、いつでも使える。
/// TestFlight と審査用のビルドでは、設定に関わらず出す(実機確認と、Apple が商品を審査できるように。SwipeConfig と同じ考え方)
@MainActor
final class SeasonConfig: ObservableObject {
    /// いま販売中の期間
    @Published private(set) var open: Set<SaleSeason> = SeasonConfig.cached()

    private static func cacheKey(_ s: SaleSeason) -> String { "season.\(s.rawValue).cached" }

    private static func cached() -> Set<SaleSeason> {
        if SwipeConfig.isSandbox { return Set(SaleSeason.allCases) }
        return Set(SaleSeason.allCases.filter { UserDefaults.standard.bool(forKey: cacheKey($0)) })
    }

    /// そのボスを、いま売り場に出すか
    func onShelf(_ boss: BossCharacter) -> Bool { boss.onShelf(open) }

    /// ショップで、そのボスへ案内するときの行き先。売り場に出ていない期間限定のボスは、永久買い切りパックのカードへ
    func shopFocus(for boss: BossCharacter) -> String { onShelf(boss) ? "boss.\(boss.productKey)" : "lifetime" }

    func refresh() async {
        #if DEBUG
        // 画面確認用: -season-on は全部の期間を販売中に、-season-off は全部を期間外にする
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-season-on") { open = Set(SaleSeason.allCases); return }
        if args.contains("-season-off") { open = []; return }
        #endif
        guard Backend.isAvailable else { return }
        let rc = RemoteConfig.remoteConfig()
        var defaults: [String: NSObject] = [:]
        for s in SaleSeason.allCases { defaults[s.configKey] = false as NSNumber }
        rc.setDefaults(defaults)
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        rc.configSettings = settings
        _ = try? await rc.fetchAndActivate()
        var now: Set<SaleSeason> = []
        for s in SaleSeason.allCases {
            let on = rc.configValue(forKey: s.configKey).boolValue
            UserDefaults.standard.set(on, forKey: Self.cacheKey(s))
            if on || SwipeConfig.isSandbox { now.insert(s) }
        }
        open = now
    }
}
