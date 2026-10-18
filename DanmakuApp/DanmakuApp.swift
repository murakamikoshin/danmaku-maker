import SwiftUI

@main
struct DanmakuApp: App {
    @StateObject private var auth = AuthService()
    @StateObject private var blocks = BlockStore()
    @StateObject private var deepLink = DeepLink()
    @Environment(\.scenePhase) private var scenePhase

    init() { Backend.configure() }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(auth)
                .environmentObject(blocks)
                .environmentObject(deepLink)
                .task { auth.start(); await ResultsQueue.shared.flush() }
                .onOpenURL { deepLink.handle($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { deepLink.handle($0.webpageURL) }
                .onChange(of: scenePhase) { phase in
                    if phase == .background { Task { await ResultsQueue.shared.flush() } }
                }
        }
    }
}

/// ユニバーサルリンク https://<ドメイン>/s/<ID> を受けて、そのステージの詳細を開く
@MainActor
final class DeepLink: ObservableObject {
    @Published var stageID: String?

    func handle(_ url: URL?) {
        guard let url, url.path.hasPrefix("/s/") else { return }
        let id = url.lastPathComponent.uppercased()
        if id.count == 5 { stageID = id }
    }
}
