import SwiftUI

@main
struct DanmakuApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthService()
    @StateObject private var blocks = BlockStore()
    @StateObject private var deepLink = DeepLink()
    @StateObject private var ads = AdsService()
    @StateObject private var purchases = PurchaseService()
    @StateObject private var swipeConfig = SwipeConfig()
    @StateObject private var battleConfig = BattleConfig()
    @ObservedObject private var uiTheme = UIThemeStore.shared
    @Environment(\.scenePhase) private var scenePhase

    init() { Backend.configure() }

    /// スクリーンショット撮影用: DEBUG ビルドで `-no-ads` を付けると、同意ダイアログと広告を出さない
    private static var adsDisabledForScreenshots: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-no-ads") || ProcessInfo.processInfo.arguments.contains("-force-banner")
        #else
        false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                // メニューのテーマが変わったら、画面を作り直す(色・字体・角の形が、すべて入れ替わる)
                .id(uiTheme.theme)
                .preferredColorScheme(.dark)
                .environmentObject(auth)
                .environmentObject(blocks)
                .environmentObject(deepLink)
                .environmentObject(ads)
                .environmentObject(purchases)
                .environmentObject(swipeConfig)
                .environmentObject(battleConfig)
                .environmentObject(CosmeticsStore.shared)
                .environmentObject(RewardStore.shared)
                .environmentObject(AdPatternStore.shared)
                // トラッキング許可の前の説明画面。ほかの全画面(ごほうびのお知らせなど)と重ならないよう、重ねて出す
                .overlay {
                    if ads.showTrackingPrimer {
                        TrackingPrimerView { ads.continueFromTrackingPrimer() }
                            .preferredColorScheme(.dark)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: ads.showTrackingPrimer)
                .task {
                    auth.start()
                    Task { await swipeConfig.refresh(); await battleConfig.refresh() }
                    // 自分のステージへの反応の通知。開いたら、そのステージを開く
                    NotificationService.shared.onOpenStage = { deepLink.stageID = $0.uppercased() }
                    // ステージの共有ページ(招待リンク経由)から入れた人: そのステージを開く
                    InviteService.shared.onOpenStage = { deepLink.stageID = $0.uppercased() }
                    // ステージの共有リンクに付ける、自分の招待コードを用意しておく(サインインを待ってから)
                    Task { try? await Task.sleep(nanoseconds: 3_000_000_000); await InviteService.shared.ensureMyCode() }
                    NotificationService.shared.start()
                    purchases.start()
                    await purchases.refresh()
                    // 広告削除の購入者には、同意画面も広告も出さない
                    if !purchases.isPremium && !Self.adsDisabledForScreenshots { await ads.start() }
                    // 広告を出さない人には ATT を出さないので、計測はここで始める(出した人は ads.start の中で始まる)
                    else { AttributionService.shared.trackingDecided() }
                    await ResultsQueue.shared.flush()
                }
                .onChange(of: auth.uid) { uid in
                    if uid != nil { Task { await RemoteCatalog.shared.refresh() } }
                    Task { await CosmeticsStore.shared.refreshPosts(uid: uid); await CosmeticsStore.shared.refreshBossTickets(uid: uid) }
                    // 友達招待: 受け取ったコードの登録と、「初期プレイヤー」の称号(サインインできてから)
                    if uid != nil { Task { await InviteService.shared.registerPending(); await InviteService.shared.claimFounderIfNeeded(); await InviteService.shared.refresh(); await RewardNoticeService.shared.check() } }
                    // マイステージのバックアップ(入れ直したあとは、ここで戻る)
                    StageBackup.shared.attach(uid: uid)
                    Task { await purchases.identify(uid: uid) }
                    NotificationService.shared.attach(uid: uid)
                }
                .onOpenURL { deepLink.handle($0); AttributionService.shared.handle(url: $0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { deepLink.handle($0.webpageURL); AttributionService.shared.handle(userActivity: $0) }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { Task { await ResultsQueue.shared.flush() } }
                    if phase == .active { AudioManager.shared.resumeIfNeeded() } else { AudioManager.shared.pause() }
                    if phase == .active { Task { await RewardNoticeService.shared.check() } }   // 招待や月間ランキングのごほうびが届いていないか
                    // 設定アプリで通知の許可を変えて戻ってきたときに、表示を合わせる
                    if phase == .active { Task { await NotificationService.shared.refreshAuthorization() } }
                    // 起動時に広告を開始できなかった・読み込めなかったときは、前面に戻るたびにやり直す
                    // (最初の開始は上の .task で、購入状態を確かめてから行う)
                    if phase == .active && ads.attemptedStart && !purchases.isPremium && !Self.adsDisabledForScreenshots {
                        Task { await ads.start() }
                    }
                }
        }
    }
}

/// ユニバーサルリンク https://<ドメイン>/s/<ID> を受けて、そのステージの詳細を開く
@MainActor
final class DeepLink: ObservableObject {
    @Published var stageID: String?

    func handle(_ url: URL?) {
        // 招待リンク(OneLink)をアプリで直接開いたとき。コードは deep_link_sub1 に入っている
        if let url, let code = InviteService.code(from: url) {
            InviteService.shared.receive(code: code)
            if let id = InviteService.stageID(from: url) { stageID = id }
            return
        }
        guard let url, let id = Self.stageID(from: url) else { return }
        stageID = id
    }

    /// ステージのリンクから、5文字のステージIDを取り出す。
    /// https://danmaku-maker.web.app/s/ABCDE(Universal Links)と danmakumaker://s/ABCDE(共有ページの「アプリで遊ぶ」)の両方
    static func stageID(from url: URL) -> String? {
        let path = url.scheme?.lowercased() == "danmakumaker" ? "/" + (url.host ?? "") + url.path : url.path
        guard path.hasPrefix("/s/") else { return nil }
        let id = url.lastPathComponent.uppercased()
        return id.count == 5 ? id : nil
    }
}
