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
///  2. 全画面広告: 結果画面から次へ進むときに、2回遊ぶごと・前の広告(リワード含む)から75秒以上あいているときだけ。始めたばかりの人(入れて24時間かつ10回まで)には出さない。
///     広告削除の購入者・テストプレイ・ステージ開始時・プレイ中には、出さない。
@MainActor
final class AdsService: NSObject, ObservableObject, FullScreenContentDelegate {
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

    /// 全画面で開いているゲームの画面(ステージのプレイ・エディタ・弾幕作成)の数。1つ以上ならバナーを外す
    /// (画面の裏に隠れたバナーが読み込み・更新を続けると、見られない広告になり、単価が下がる)
    @Published private(set) var coverCount = 0
    func coverAppeared() { coverCount += 1 }
    func coverDisappeared() { coverCount = max(0, coverCount - 1) }

    func setPlaying(tab: String, _ playing: Bool) {
        guard playingTabs.contains(tab) != playing else { return }
        if playing { playingTabs.insert(tab) } else { playingTabs.remove(tab) }
    }

    /// バナーだけ出さないタブ(タブは出す)。弾幕バトルで落ちた直後の待ちの間(指が画面の下に残っていて、
    /// そこへ広告が出ると誤タップになるため)
    @Published private(set) var quietTabs: Set<String> = []
    /// 下のタブを隠すタブ(スワイプ弾幕で、実際に弾をよけている間だけ。通信を待つ間は隠さない)
    @Published private(set) var lockedTabs: Set<String> = []
    func setLocked(tab: String, _ locked: Bool) {
        guard lockedTabs.contains(tab) != locked else { return }
        if locked { lockedTabs.insert(tab) } else { lockedTabs.remove(tab) }
    }
    func setQuiet(tab: String, _ quiet: Bool) {
        guard quietTabs.contains(tab) != quiet else { return }
        if quiet { quietTabs.insert(tab) } else { quietTabs.remove(tab) }
    }

    private var rewarded: RewardedAd?
    private var interstitial: InterstitialAd?
    /// 読み込んだ時刻。読み込んだ広告は1時間で期限切れになり、出せなくなる(出そうとして失敗する)ので、
    /// 50分たったものは捨てて読み込み直す
    private var rewardedLoadedAt = Date.distantPast
    private var interstitialLoadedAt = Date.distantPast
    static let adLifetime: TimeInterval = 50 * 60
    private var loadingInterstitial = false
    private var interstitialDismiss: (() -> Void)?
    /// 全画面広告を出す間隔: 遊んだ回数と、最後に広告を出した時刻
    private var playsSinceAd = 0
    private var lastAdAt = Date()
    static let playsBetweenInterstitials = 2
    /// 全画面広告どうしの間(秒)。どの場面の全画面広告も、この間をあける(リワード広告を見たあとも数える)
    static let minSecondsBetweenAds: TimeInterval = 75
    /// 始めたばかりの人には、全画面広告を出さない(入れてから24時間、または10回遊ぶまで)
    static let graceSeconds: TimeInterval = 24 * 60 * 60
    static let gracePlays = 10
    private static let firstSeenKey = "ads.firstSeen"
    private static let lifetimePlaysKey = "ads.lifetimePlays"
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
    /// 結果画面の中くらいの広告(レクタングル 300×250)。ビルド設定 ADMOB_MREC_UNIT_ID。空なら出さない
    var mrecUnitID: String? { Self.optionalUnit("ADMOB_MREC_UNIT_ID") }
    /// ビルド設定の広告ユニット ID(空・未設定なら nil)
    static func optionalUnit(_ key: String) -> String? {
        guard let v = Bundle.main.object(forInfoDictionaryKey: key) as? String, v.hasPrefix("ca-app-pub-") else { return nil }
        return v
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
            dropExpiredAds()
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
            MobileAds.shared.start { _ in c.resume() }
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
        // 同意の画面が実際に出るとき(同意が要る地域で、まだ同意していない)だけ、バトルの対戦が終わるのを待つ
        if updated, UMPConsentInformation.sharedInstance.consentStatus == .required,
           UMPConsentInformation.sharedInstance.formStatus == .available { await waitUntilNotBattling() }
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
        await waitUntilNotBattling()
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

    /// 弾幕バトルの対戦中(3・2・1 と対戦)は、同意や許可の画面を出さずに、終わるまで待つ。
    /// 相手探しの最中なら探すのをやめる(画面の裏で対戦が始まって、見えないまま負けないように)
    private func waitUntilNotBattling() async {
        NotificationCenter.default.post(name: .cancelBattleSearch, object: nil)
        while playingTabs.contains("battle") { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        // 待っている間に、新しく相手探しを始めていたら、それもやめる(このあと画面を重ねるため)
        NotificationCenter.default.post(name: .cancelBattleSearch, object: nil)
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

    /// 期限が近い広告を捨てる(前面に戻ったとき・出す直前)
    private func dropExpiredAds() {
        if rewarded != nil, Date().timeIntervalSince(rewardedLoadedAt) > Self.adLifetime, onDismiss == nil {
            rewarded = nil
            isReady = false
        }
        if interstitial != nil, Date().timeIntervalSince(interstitialLoadedAt) > Self.adLifetime, interstitialDismiss == nil {
            interstitial = nil
        }
    }

    /// 全画面広告が期限切れ間近なら、捨てて読み込み直す(読み込めれば、その場で出せる)
    private func refreshExpiredInterstitial() async {
        guard interstitial != nil, Date().timeIntervalSince(interstitialLoadedAt) > Self.adLifetime, interstitialDismiss == nil else { return }
        interstitial = nil
        await loadInterstitial()
    }

    func load() async {
        guard sdkStarted, rewarded == nil, !loading else { return }
        loading = true
        defer { loading = false }
        let ad: RewardedAd? = await withCheckedContinuation { c in
            RewardedAd.load(with: unitID, request: Request()) { ad, _ in c.resume(returning: ad) }
        }
        ad?.fullScreenContentDelegate = self
        rewarded = ad
        rewardedLoadedAt = Date()
        isReady = ad != nil
        // 読み込めなかったら、少しあけて読み直す(広告の在庫が少ない時期に、ごほうび・復活が「準備中」のままにならないように)。
        // 続けて失敗したら、間隔を延ばす(30秒・60秒・…最大5分)
        if ad == nil {
            rewardedRetries += 1
            let wait = UInt64(min(300, 30 * rewardedRetries)) * 1_000_000_000
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: wait)
                await self?.load()
            }
        } else {
            rewardedRetries = 0
        }
    }
    private var rewardedRetries = 0

    func loadInterstitial() async {
        guard sdkStarted, interstitial == nil, !loadingInterstitial else { return }
        loadingInterstitial = true
        defer { loadingInterstitial = false }
        let ad: InterstitialAd? = await withCheckedContinuation { c in
            InterstitialAd.load(with: interstitialUnitID, request: Request()) { ad, _ in c.resume(returning: ad) }
        }
        ad?.fullScreenContentDelegate = self
        interstitial = ad
        interstitialLoadedAt = Date()
    }

    /// 「もう一度」を押した回数。画面を出入りしても数え直さない(戻って入り直す抜け道をふさぐ)。3回ごとに true
    private var retries = 0
    func countRetryIsDue() -> Bool {
        retries += 1
        if retries >= 3 { retries = 0; return true }
        return false
    }

    /// 弾幕バトルの試合数。3試合ごとに true(結果から次へ進むときに、全画面広告を出す)。
    /// バトルの結果やレートには、広告は一切関係させない(リワードも付けない)
    static let battlesBetweenInterstitials = 3
    private var battles = 0
    func countBattleIsDue() -> Bool {
        battles += 1
        if battles >= Self.battlesBetweenInterstitials { battles = 0; return true }
        return false
    }

    /// 結果画面が出たとき(テストプレイ以外)に数える
    func countPlay() {
        playsSinceAd += 1
        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: Self.lifetimePlaysKey) + 1, forKey: Self.lifetimePlaysKey)
    }

    /// 始めたばかり(入れてから24時間たたず、まだ10回遊んでいない)か。この間は全画面広告を出さない
    var inNewPlayerGrace: Bool {
        let d = UserDefaults.standard
        let first: Date
        if let v = d.object(forKey: Self.firstSeenKey) as? Date { first = v } else {
            // 初めて調べるときは、アプリを入れた日(書類フォルダを作った日)にする。1.3.0 に上げただけの人に、猶予が始まらないように
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let created = docs.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.creationDate] as? Date }
            first = min(created ?? Date(), Date())
            d.set(first, forKey: Self.firstSeenKey)
        }
        return Date().timeIntervalSince(first) < Self.graceSeconds && d.integer(forKey: Self.lifetimePlaysKey) < Self.gracePlays
    }

    /// 全画面広告を出してよい間があいているか(前の全画面広告・リワード広告から minSecondsBetweenAds 秒)と、始めたばかりでないか
    private var interstitialAllowed: Bool {
        Date().timeIntervalSince(lastAdAt) >= Self.minSecondsBetweenAds && !inNewPlayerGrace
    }

    /// 次に結果画面から進むとき、全画面広告が出る見込みか(結果画面のレクタングルは、出ないときだけ出す)
    var interstitialIsDue: Bool {
        playsSinceAd >= Self.playsBetweenInterstitials && interstitialAllowed && interstitial != nil
    }

    /// 次へ進むときに、出す条件がそろっていれば全画面広告を出す(閉じるまで待つ)。出さなかったら false
    @discardableResult
    func showInterstitialIfDue() async -> Bool {
        await refreshExpiredInterstitial()
        guard playsSinceAd >= Self.playsBetweenInterstitials, interstitialAllowed,
              let ad = interstitial, let vc = Self.topViewController() else { return false }
        playsSinceAd = 0
        lastAdAt = Date()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            interstitialDismiss = { cont.resume() }
            AudioManager.shared.adWillShow()   // 広告の音と BGM を重ねない(閉じたら finishPresentation で戻す)
            ad.present(from: vc)
        }
        return true
    }

    /// 遊んだ回数に関係なく、読み込めていれば全画面広告を出す(閉じるまで待つ)。「もう一度」の3回ごと・投稿の待ち時間など。
    /// ただし、どの場面でも、前の広告からの間(minSecondsBetweenAds)と、始めたばかりの人を守る決まりは通す。出さなかったら false
    @discardableResult
    func showInterstitialNow() async -> Bool {
        await refreshExpiredInterstitial()
        guard interstitialAllowed, let ad = interstitial, let vc = Self.topViewController() else { return false }
        playsSinceAd = 0
        lastAdAt = Date()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            interstitialDismiss = { cont.resume() }
            AudioManager.shared.adWillShow()   // 広告の音と BGM を重ねない(閉じたら finishPresentation で戻す)
            ad.present(from: vc)
        }
        return true
    }

    /// 広告を見終えて報酬を得たら true
    func showRewarded() async -> Bool {
        guard let ad = rewarded, let vc = Self.topViewController() else { return false }
        earned = false
        return await withCheckedContinuation { cont in
            onDismiss = { cont.resume(returning: $0) }
            AudioManager.shared.adWillShow()   // 広告の音と BGM を重ねない(閉じたら finishPresentation で戻す)
            ad.present(from: vc) { [weak self] in self?.earned = true }
        }
    }

    // MARK: FullScreenContentDelegate

    nonisolated func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        Task { @MainActor in await finishPresentation() }
    }

    nonisolated func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in earned = false; await finishPresentation() }
    }

    private func finishPresentation() async {
        AudioManager.shared.adDidClose()
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
        // リワード広告のすぐあとに全画面広告が続かないように、これも「前の広告」として数える
        lastAdAt = Date()
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
