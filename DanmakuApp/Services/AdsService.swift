import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// リワード広告（被弾したときの「広告を見て復活」だけ）。広告の前に同意(UMP)とトラッキング許可(ATT)を取る。
/// ステージ開始ごとのインタースティシャルは出さない。
@MainActor
final class AdsService: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published private(set) var isReady = false

    private var rewarded: GADRewardedAd?
    private var started = false
    private var loading = false
    private var onDismiss: ((Bool) -> Void)?
    private var earned = false

    /// Info.plist 経由（ビルド設定 ADMOB_REWARDED_UNIT_ID）。開発中は Google のテスト広告 ID
    private var unitID: String {
        Bundle.main.object(forInfoDictionaryKey: "ADMOB_REWARDED_UNIT_ID") as? String ?? "ca-app-pub-3940256099942544/1712485313"
    }

    /// 同意 → トラッキング許可 → SDK 開始 → 広告の読み込み。広告削除の購入者には呼ばない
    func start() async {
        guard !started else { return }
        started = true
        await requestConsent()
        await requestTracking()
        guard UMPConsentInformation.sharedInstance.canRequestAds else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in c.resume() }
        }
        await load()
    }

    private func requestConsent() async {
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false
        let updated: Bool = await withCheckedContinuation { c in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) { error in c.resume(returning: error == nil) }
        }
        // 取得できなくても、前回の同意状態（canRequestAds）に従う
        guard updated, let vc = Self.topViewController() else { return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            UMPConsentForm.loadAndPresentIfRequired(from: vc) { _ in c.resume() }
        }
    }

    private func requestTracking() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // アプリが前面に出ていないと許可ダイアログが出ないので、少し待つ
        for _ in 0..<10 where UIApplication.shared.applicationState != .active { try? await Task.sleep(nanoseconds: 300_000_000) }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    func load() async {
        guard UMPConsentInformation.sharedInstance.canRequestAds, rewarded == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let ad: GADRewardedAd? = await withCheckedContinuation { c in
            GADRewardedAd.load(withAdUnitID: unitID, request: GADRequest()) { ad, _ in c.resume(returning: ad) }
        }
        ad?.fullScreenContentDelegate = self
        rewarded = ad
        isReady = ad != nil
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
