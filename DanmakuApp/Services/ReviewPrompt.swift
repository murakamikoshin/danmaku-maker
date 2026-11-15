import StoreKit
import UIKit

/// App Store の評価のお願い(Apple の評価ダイアログ)。気分が良い瞬間にだけ、控えめに出す。
/// - 出す場面: 世界のステージを初めてクリアした・自分のステージが10回遊ばれた・弾幕バトルで3連勝した
/// - 決まり: 入れてから3日たってから。同じ版では1回まで。前に出してから60日はあける(実際に出すかどうかは、さらに Apple が決める)
@MainActor
enum ReviewPrompt {
    enum Moment: String { case firstWorldClear, ownStagePlayed10, battleStreak3 }

    private static let firstSeenKey = "review.firstSeen"
    private static let lastVersionKey = "review.lastVersion"
    private static let lastAtKey = "review.lastAt"

    static func maybeAsk(_ moment: Moment) {
        let d = UserDefaults.standard
        let now = Date()
        let first = (d.object(forKey: firstSeenKey) as? Date) ?? { d.set(now, forKey: firstSeenKey); return now }()
        guard now.timeIntervalSince(first) >= 3 * 24 * 60 * 60 else { return }
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        guard d.string(forKey: lastVersionKey) != version else { return }
        if let last = d.object(forKey: lastAtKey) as? Date, now.timeIntervalSince(last) < 60 * 24 * 60 * 60 { return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        d.set(version, forKey: lastVersionKey)
        d.set(now, forKey: lastAtKey)
        // 結果の画面が出きってから(すぐに出すと、結果を見る前に重なる)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { SKStoreReviewController.requestReview(in: scene) }
    }

    /// 起動したときに呼ぶ(入れた日を覚えておく)
    static func noteLaunch() {
        let d = UserDefaults.standard
        if d.object(forKey: firstSeenKey) == nil { d.set(Date(), forKey: firstSeenKey) }
    }
}
