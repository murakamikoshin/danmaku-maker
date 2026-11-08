import AppsFlyerLib
import AppTrackingTransparency
import UIKit

/// 広告の効果計測(AppsFlyer)。X広告などから来た人がインストールしたかを、広告側に返す。
/// - キーはビルド設定 APPSFLYER_DEV_KEY(Info.plist 経由)。空なら何もしない(計測なしで普通に動く)
/// - SDK v7 の流れ: initialize → registerSessionReadyListener → (ATT を取り終えてから) start
/// - ATT のダイアログは AdsService.start() が出す。計測はその結果が出てから始める。
///   広告削除の購入者には ATT を出さないので、その人はすぐ始める(IDFA なし・SKAdNetwork での計測)
@MainActor
final class AttributionService {
    static let shared = AttributionService()

    private var configured = false
    private var sessionReady = false
    private var trackingSettled = false
    private var started = false

    private var devKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "APPSFLYER_DEV_KEY") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
    private var appleAppID: String {
        Bundle.main.object(forInfoDictionaryKey: "APPLE_APP_ID") as? String ?? ""
    }

    /// 起動直後(AppDelegate)に呼ぶ。ほかの AppsFlyer の呼び出しより先
    func configure(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
        guard !configured, !devKey.isEmpty, !appleAppID.isEmpty else { return }
        configured = true
        let af = AppsFlyerLib.shared()
        af.initialize(devKey: devKey, appId: appleAppID)
        #if DEBUG
        af.isDebug = true
        #endif
        af.handleLaunchOptions(launchOptions)
        af.registerSessionReadyListener { [weak self] in
            Task { @MainActor in
                self?.sessionReady = true
                self?.startIfReady()
            }
        }
    }

    /// ATT のダイアログが終わった(または出さないと決まった)ら呼ぶ
    func trackingDecided() {
        trackingSettled = true
        startIfReady()
    }

    private func startIfReady() {
        guard configured, sessionReady, trackingSettled, !started else { return }
        started = true
        AppsFlyerLib.shared().start()
    }
}
