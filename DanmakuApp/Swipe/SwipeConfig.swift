import FirebaseRemoteConfig
import Foundation

/// スワイプ弾幕を出すか（Remote Config の `swipe_enabled`）。取れなかったときは、前回の値（初回はオフ）。
/// TestFlight と審査用のビルド（サンドボックスのレシート）では、設定に関わらず出す（実機確認と、Apple の審査のため）
@MainActor
final class SwipeConfig: ObservableObject {
    @Published private(set) var enabled: Bool = SwipeConfig.isSandbox || UserDefaults.standard.bool(forKey: "swipe.enabled.cached")

    /// TestFlight・審査・Xcode から入れたビルドか（App Store で配信されたものは "receipt"）
    static var isSandbox: Bool { Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" }

    func refresh() async {
        #if DEBUG
        // 画面確認用: -open-swipe はスワイプのタブを開く。-swipe-on はタブを出すだけ(本番と同じ4タブで撮るため)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-open-swipe") || args.contains("-swipe-on") { enabled = true; return }
        #endif
        guard Backend.isAvailable else { return }
        let rc = RemoteConfig.remoteConfig()
        rc.setDefaults(["swipe_enabled": false as NSNumber])
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 3600
        rc.configSettings = settings
        _ = try? await rc.fetchAndActivate()
        enabled = SwipeConfig.isSandbox || rc.configValue(forKey: "swipe_enabled").boolValue
        UserDefaults.standard.set(rc.configValue(forKey: "swipe_enabled").boolValue, forKey: "swipe.enabled.cached")
    }
}
