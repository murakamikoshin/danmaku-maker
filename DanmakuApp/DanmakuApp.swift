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
                .preferredColorScheme(.dark)
                .environmentObject(auth)
                .environmentObject(blocks)
                .environmentObject(deepLink)
                .environmentObject(ads)
                .environmentObject(purchases)
                .environmentObject(swipeConfig)
                .environmentObject(CosmeticsStore.shared)
                .environmentObject(RewardStore.shared)
                .environmentObject(AdPatternStore.shared)
                .task {
                    auth.start()
                    Task { await swipeConfig.refresh() }
                    // 自分のステージへの反応の通知。開いたら、そのステージを開く
                    NotificationService.shared.onOpenStage = { deepLink.stageID = $0.uppercased() }
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
                    Task { await CosmeticsStore.shared.refreshPosts(uid: uid); await CosmeticsStore.shared.refreshBossTickets(uid: uid) }
                    // 友達招待: 受け取ったコードの登録と、「初期プレイヤー」の称号(サインインできてから)
                    if uid != nil { Task { await InviteService.shared.registerPending(); await InviteService.shared.claimFounderIfNeeded() } }
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
        if let url, let code = InviteService.code(from: url) { InviteService.shared.receive(code: code); return }
        guard let url, url.path.hasPrefix("/s/") else { return }
        let id = url.lastPathComponent.uppercased()
        if id.count == 5 { stageID = id }
    }
}
