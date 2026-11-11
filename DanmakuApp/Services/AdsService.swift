import AppTrackingTransparency
import GoogleMobileAds
import UIKit
import UserMessagingPlatform

/// 広告の前に、同意(UMP。ヨーロッパなど法律で要る地域だけ画面が出る)→ 説明画面 → トラッキング許可(ATT)を取る。
/// - 同意は「待たずに SDK を始める」: 2026-10-31 に、canRequestAds が偽のまま SDK が始まらず広告が0になった疑いがあったため、
///   同意の結果で SDK の開始を止めない(本当の原因は app-ads.txt だった)。同意の内容は、SDK が自動で読んで広告に反映する
///   (同意しない人には、個人に合わせない広告が出る)。同意情報の取得は 8 秒で打ち切る。
/// - ATT の前に、自前の説明画面を1枚出す(許可する人が増えると広告の単価が上がる)。ボタンは「続ける」1つだけで、
///   押すと必ず OS の許可ダイアログに進む(Apple の決まり: 説明画面で許可を誘導・強制しない、ダイアログを真似しない)。
///  1. リワード広告: 被弾したときの「広告を見て復活」(見るかどうかは、プレイヤーが選ぶ)
///  2. 全画面広告: 結果画面から次へ進むときに、2回遊ぶごと・前の広告から60秒以上あいているときだけ。
///     広告削除の購入者・テストプレイ・ステージ開始時・プレイ中には、出さない。
@MainActor
final class AdsService: NSObject, ObservableObject, GADFullScreenContentDelegate {
    @Published private(set) var isReady = false
    /// SDK を開始できたか。バナーを出してよいかの目安
    @Published private(set) var canShowBanner = false
    /// ATT の前の説明画面を出しているか(DanmakuApp が画面の一番上に重ねて出す)
    @Published private(set) var showTrackingPrimer = false
    /// ヨーロッパなどで、せっていに「広告の同意の設定」を出す必要があるか
    @Published private(set) var privacyOptionsRequired = false
    private var primerContinuation: CheckedContinuation<Void, Never>?
    /// 遊んでいる最中のタブ(スワイプ弾幕・バトル)。その間はバナーを出さない
    /// (指の近くの広告は誤タップを招き、Google の規約違反や単価の低下につながる。見られない広告は単価も低い)
    @Published private(set) var playingTabs: Set<String> = []

    func setPlaying(tab: String, _ playing: Bool) {
        guard playingTabs.contains(tab) != playing else { return }
        if playing { playingTabs.insert(tab) } else { playingTabs.remove(tab) }
    }

    private var rewarded: GADRewardedAd?
    private var interstitial: GADInterstitialAd?
    private var loadingInterstitial = false
    private var interstitialDismiss: (() -> Void)?
    /// 全画面広告を出す間隔: 遊んだ回数と、最後に広告を出した時刻
    private var playsSinceAd = 0
    private var lastAdAt = Date()
    static let playsBetweenInterstitials = 2
    static let minSecondsBetweenAds: TimeInterval = 60
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
        await requestConsent()
        await requestTracking()
        // ATT の結果が出たので、広告の効果計測(AppsFlyer)を始めてよい
        AttributionService.shared.trackingDecided()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            GADMobileAds.sharedInstance().start { _ in c.resume() }
        }
        sdkStarted = true
        canShowBanner = true
        await load()
        await loadInterstitial()
    }

    /// 同意情報を取りに行き、要る地域なら同意の画面を出す。失敗しても、ここで止めずに先へ進む
    private func requestConsent() async {
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false
        let updated = await Self.finishWithin(seconds: 8) { done in
            UMPConsentInformation.sharedInstance.requestConsentInfoUpdate(with: params) { error in done(error == nil) }
        }
        if updated, let vc = Self.topViewController() {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                UMPConsentForm.loadAndPresentIfRequired(from: vc) { _ in c.resume() }
            }
        }
        privacyOptionsRequired = UMPConsentInformation.sharedInstance.privacyOptionsRequirementStatus == .required
    }

    /// せっていの「広告の同意の設定」から、同意の画面をもう一度出す
    func presentPrivacyOptions() {
        guard let vc = Self.topViewController() else { return }
        UMPConsentForm.presentPrivacyOptionsForm(from: vc) { _ in }
    }

    /// 終わりの合図(done)が来るか、時間切れまで待つ。時間切れなら false
    private static func finishWithin(seconds: Double, _ body: (@escaping (Bool) -> Void) -> Void) async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            var finished = false
            let finish: (Bool) -> Void = { value in
                DispatchQueue.main.async {
                    guard !finished else { return }
                    finished = true
                    c.resume(returning: value)
                }
            }
            body(finish)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { finish(false) }
        }
    }

    private func requestTracking() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // アプリが前面に出ていないと許可ダイアログが出ないので、少し待つ
        await waitUntilActive()
        if !Self.skipTrackingPrimer {
            // 説明画面。「続ける」を押すまで待つ
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                primerContinuation = c
                showTrackingPrimer = true
            }
            // 説明画面が消えきってから、許可ダイアログを出す
            try? await Task.sleep(nanoseconds: 400_000_000)
            await waitUntilActive()
        }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// 説明画面の「続ける」
    func continueFromTrackingPrimer() {
        showTrackingPrimer = false
        primerContinuation?.resume()
        primerContinuation = nil
    }

    private func waitUntilActive() async {
        for _ in 0..<10 where UIApplication.shared.applicationState != .active { try? await Task.sleep(nanoseconds: 300_000_000) }
    }

    /// 自動テスト(UI テスト)では、説明画面を出さない(押す人がいないので、先へ進めなくなる)
    private static var skipTrackingPrimer: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-uitest-invincible")
        #else
        false
        #endif
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

    /// 「もう一度」を押した回数。画面を出入りしても数え直さない(戻って入り直す抜け道をふさぐ)。3回ごとに true
    private var retries = 0
    func countRetryIsDue() -> Bool {
        retries += 1
        if retries >= 3 { retries = 0; return true }
        return false
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
