import AppTrackingTransparency
import GoogleMobileAds
import UIKit

/// 広告の前にトラッキング許可(ATT)を取る。
/// ⚠️同意(UMP)は一旦外している(2026-10-31): UMP の canRequestAds が偽のままで SDK が始まらず、
/// AdMob のリクエストが0だった疑いがあるため。トレカダッシュと同じく、UMP なしで SDK を始める。
/// 広告が出るようになったら、UMP を戻す(取れないときだけ個人に合わせない広告にする)か決める。
/// パッケージ(project.yml の UserMessagingPlatform)は戻しやすいように残してある。
///  1. リワード広告: 被弾したときの「広告を見て復活」(見るかどうかは、プレイヤーが選ぶ)
///  2. 全画面広告: 結果画面から次へ進むときに、3回遊ぶごと・前の広告から2分以上あいているときだけ。
///     広告削除の購入者・テストプレイ・ステージ開始時・プレイ中には、出さない。
@MainActor
final class AdsService: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published private(set) var isReady = false
    /// SDK を開始できたか。バナーを出してよいかの目安
    @Published private(set) var canShowBanner = false

    private var rewarded: GADRewardedAd?
    private var interstitial: GADInterstitialAd?
    private var loadingInterstitial = false
    private var interstitialDismiss: (() -> Void)?
    /// 全画面広告を出す間隔: 遊んだ回数と、最後に広告を出した時刻
    private var playsSinceAd = 0
    private var lastAdAt = Date()
    static let playsBetweenInterstitials = 3
    static let minSecondsBetweenAds: TimeInterval = 120
    /// 広告 SDK を開始できたか。開始できるまでは、アプリが前面に戻るたびにやり直す
    private var sdkStarted = false
    private var starting = false
    /// 起動時の start() がもう呼ばれたか(前面復帰時のやり直しは、これが立ってから)
    private(set) var attemptedStart = false
    private var loading = false
    private var onDismiss: ((Bool) -> Void)?
    private var earned = false

    override init() {
        super.init()
        #if DEBUG
        // 画面確認用: 同意ダイアログを待たずに、バナー(テスト広告)の場所を出す
        if ProcessInfo.processInfo.arguments.contains("-force-banner") { canShowBanner = true }
        #endif
    }

    /// Info.plist 経由（ビルド設定 ADMOB_REWARDED_UNIT_ID）。開発中は Google のテスト広告 ID
    private var unitID: String {
        Bundle.main.object(forInfoDictionaryKey: "ADMOB_REWARDED_UNIT_ID") as? String ?? "ca-app-pub-3940256099942544/1712485313"
    }
    var bannerUnitID: String {
        Bundle.main.object(forInfoDictionaryKey: "ADMOB_BANNER_UNIT_ID") as? String ?? "ca-app-pub-3940256099942544/2435281174"
    }
    private var interstitialUnitID: String {
        Bundle.main.object(forInfoDictionaryKey: "ADMOB_INTERSTITIAL_UNIT_ID") as? String ?? "ca-app-pub-3940256099942544/4411468910"
    }

    /// トラッキング許可 → SDK 開始 → 広告の読み込み。広告削除の購入者には呼ばない
    /// 何度呼んでもよい。開始済みなら、読み込めていない広告だけ読み込み直す
    func start() async {
        attemptedStart = true
        guard !starting else { return }
        if sdkStarted {
            await load()
            await loadInterstitial()
            return
        }
        starting = true
        defer { starting = false }
        await requestTracking()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in c.resume() }
        }
        sdkStarted = true
        canShowBanner = true
        await load()
        await loadInterstitial()
    }

    private func requestTracking() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // アプリが前面に出ていないと許可ダイアログが出ないので、少し待つ
        for _ in 0..<10 where UIApplication.shared.applicationState != .active { try? await Task.sleep(nanoseconds: 300_000_000) }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    func load() async {
        guard sdkStarted, rewarded == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let ad: GADRewardedAd? = await withCheckedContinuation { c in
            GADRewardedAd.load(withAdUnitID: unitID, request: GADRequest()) { ad, _ in c.resume(returning: ad) }
        }
        ad?.fullScreenContentDelegate = self
        rewarded = ad
        isReady = ad != nil
    }

    func loadInterstitial() async {
        guard sdkStarted, interstitial == nil, !loadingInterstitial else { return }
        loadingInterstitial = true
        defer { loadingInterstitial = false }
        let ad: GADInterstitialAd? = await withCheckedContinuation { c in
            GADInterstitialAd.load(withAdUnitID: interstitialUnitID, request: GADRequest()) { ad, _ in c.resume(returning: ad) }
        }
        ad?.fullScreenContentDelegate = self
        interstitial = ad
    }

    /// 結果画面が出たとき(テストプレイ以外)に数える
    func countPlay() { playsSinceAd += 1 }

    /// 次へ進むときに、出す条件がそろっていれば全画面広告を出す(閉じるまで待つ)。出さなかったら false
    @discardableResult
    func showInterstitialIfDue() async -> Bool {
        guard playsSinceAd >= Self.playsBetweenInterstitials,
              Date().timeIntervalSince(lastAdAt) >= Self.minSecondsBetweenAds,
              let ad = interstitial, let vc = Self.topViewController() else { return false }
        playsSinceAd = 0
        lastAdAt = Date()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            interstitialDismiss = { cont.resume() }
            ad.present(fromRootViewController: vc)
        }
        return true
    }

    /// 回数や間隔に関係なく、読み込めていれば全画面広告を出す(閉じるまで待つ)。
    /// コース投稿の「アップロード待ち」のように、もともと待ち時間がある場面で使う。出さなかったら false
    @discardableResult
    func showInterstitialNow() async -> Bool {
        guard let ad = interstitial, let vc = Self.topViewController() else { return false }
        playsSinceAd = 0
        lastAdAt = Date()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            interstitialDismiss = { cont.resume() }
            ad.present(fromRootViewController: vc)
        }
        return true
    }

    /// 広告を見終えて報酬を得たら true
    func showRewarded() async -> Bool {
        guard let ad = rewarded, let vc = Self.topViewController() else { return false }
        earned = false
        return await withCheckedContinuation { cont in
            onDismiss = { cont.resume(returning: $0) }
            ad.present(fromRootViewController: vc) { [weak self] in self?.earned = true }
        }
    }

    // MARK: GADFullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in await finishPresentation() }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in earned = false; await finishPresentation() }
    }

    private func finishPresentation() async {
        if interstitialDismiss != nil {
            interstitial = nil
            let h = interstitialDismiss
            interstitialDismiss = nil
            lastAdAt = Date()
            h?()
            await loadInterstitial()
            return
        }
        rewarded = nil
        isReady = false
        let handler = onDismiss
        onDismiss = nil
        handler?(earned)
        await load()
    }

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var vc = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }
}
