import FirebaseRemoteConfig
import Foundation

/// 弾幕バトルのタブを出すか(Remote Config の `battle_enabled`)。取れなかったときは前回の値(初回はオフ)。
/// TestFlight と審査用のビルドでは、設定に関わらず出す(SwipeConfig と同じ考え方)
@MainActor
final class BattleConfig: ObservableObject {
    @Published private(set) var enabled: Bool = SwipeConfig.isSandbox || UserDefaults.standard.bool(forKey: "battle.enabled.cached")

    func refresh() async {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-open-battle") || args.contains("-battle-on") { enabled = true; return }
        #endif
        guard Backend.isAvailable else { return }
        let rc = RemoteConfig.remoteConfig()
        rc.setDefaults(["swipe_enabled": false as NSNumber, "battle_enabled": false as NSNumber])
        _ = try? await rc.fetchAndActivate()
        let on = rc.configValue(forKey: "battle_enabled").boolValue
        enabled = SwipeConfig.isSandbox || on
        UserDefaults.standard.set(on, forKey: "battle.enabled.cached")
    }
}
