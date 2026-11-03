import FirebaseRemoteConfig
import Foundation

/// スワイプ弾幕 β を出すか（Remote Config の `swipe_enabled`）。取れなかったときは、前回の値（初回はオフ）
@MainActor
final class SwipeConfig: ObservableObject {
    @Published private(set) var enabled: Bool = UserDefaults.standard.bool(forKey: "swipe.enabled.cached")

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-open-swipe") { enabled = true; return }
        #endif
        guard Backend.isAvailable else { return }
        let rc = RemoteConfig.remoteConfig()
        rc.setDefaults(["swipe_enabled": false as NSNumber])
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        rc.configSettings = settings
        _ = try? await rc.fetchAndActivate()
        enabled = rc.configValue(forKey: "swipe_enabled").boolValue
        UserDefaults.standard.set(enabled, forKey: "swipe.enabled.cached")
    }
}
