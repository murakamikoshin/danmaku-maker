#if canImport(AppsFlyerLib)
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

    /// OneLink(招待リンク)を開いた・インストール後に最初に開いたとき、リンクの中身を受け取る(UDL)
    private final class LinkDelegate: NSObject, AppsFlyerDeepLinkDelegate {
        func didResolveDeepLink(_ result: DeepLinkResult) {
            guard result.status == .found, let link = result.deepLink,
                  let sub = link.clickEvent["deep_link_sub1"] as? String else { return }
            Task { @MainActor in InviteService.shared.receive(code: sub) }
        }
    }
    private let linkDelegate = LinkDelegate()

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
        af.deepLinkDelegate = linkDelegate
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

extension AttributionService {
    /// ユニバーサルリンク・URL スキームで開かれたとき、AppsFlyer に渡す(OneLink の判定のため)
    func handle(url: URL) {
        guard configured else { return }
        AppsFlyerLib.shared().handleOpen(url, options: nil)
    }
    func handle(userActivity: NSUserActivity) {
        guard configured else { return }
        AppsFlyerLib.shared().continue(userActivity, restorationHandler: nil)
    }
}
#else
import UIKit

/// AppsFlyer を入れずにビルドしたとき(この Mac の Xcode 15.2 では、AppsFlyer がリンクできないので、
/// ストア用スクリーンショットなどを撮るときだけ使う)。何もしない
@MainActor
final class AttributionService {
    static let shared = AttributionService()
    func configure(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {}
    func trackingDecided() {}
    func handle(url: URL) {}
    func handle(userActivity: NSUserActivity) {}
}
#endif
