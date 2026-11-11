import FirebaseRemoteConfig
import SwiftUI
import UIKit

/// 古い版で開かれたときに、アップデートを案内する(1.2.0 から)。目安の版は Remote Config で、ビルドを出し直さずに変えられる。
/// - `update_latest_version`: これより古ければ「新しいバージョンがあります」(あとで、で閉じられる。同じ版では一度だけ)
/// - `update_min_version`: これより古ければ「アップデートが必要です」(閉じられない。古い版のままだと壊れるときだけ使う)
/// どちらも空なら何も出さない
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6824245206")!

    @Published var required = false
    @Published var suggested = false
    private var latest = ""
    private static let dismissedKey = "update.dismissed"

    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    func refresh() async {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-no-update-check") { return }
        #endif
        guard Backend.isAvailable else { return }
        let rc = RemoteConfig.remoteConfig()
        _ = try? await rc.fetchAndActivate()
        let minV = rc.configValue(forKey: "update_min_version").stringValue.trimmingCharacters(in: .whitespaces)
        latest = rc.configValue(forKey: "update_latest_version").stringValue.trimmingCharacters(in: .whitespaces)
        required = !minV.isEmpty && Self.isOlder(Self.current, than: minV)
        suggested = !required && !latest.isEmpty && Self.isOlder(Self.current, than: latest)
            && UserDefaults.standard.string(forKey: Self.dismissedKey) != latest
    }

    /// 「あとで」: 同じ版の案内は、もう出さない
    func later() {
        UserDefaults.standard.set(latest, forKey: Self.dismissedKey)
        suggested = false
    }

    func openStore() { UIApplication.shared.open(Self.appStoreURL) }

    /// 版の比べ方: 「1.10.0」は「1.9.2」より新しい(数字ごとに比べる)
    nonisolated static func isOlder(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p < q }
        }
        return false
    }
}

/// アップデートが必要なとき(閉じられない)
struct UpdateRequiredView: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "arrow.down.app.fill").font(.system(size: 56, weight: .bold)).foregroundStyle(GameStyle.yellow)
            Text("update.required.title").font(.display(24)).foregroundStyle(GameStyle.text).multilineTextAlignment(.center)
            Text("update.required.message").font(.system(size: 15, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.85))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            GameActionButton(title: "update.open", systemImage: "arrow.up.forward.app", fill: GameStyle.gold) { UpdateChecker.shared.openStore() }
                .accessibilityIdentifier("update.open")
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GameStyle.night.ignoresSafeArea())
        .interactiveDismissDisabled()
    }
}
