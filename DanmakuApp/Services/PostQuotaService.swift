import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// 1日(日本時間)に世界へ公開できる数。ふつうは5本まで。それ以上は、広告を見るごとに1本ぶん増える。
/// 広告削除・永久買い切りパックの購入者は上限なし。数えるのはサーバー(functions/src/quota.ts と同じ規則)
struct PostQuota: Equatable {
    static let free = 5
    var used = 0
    var extra = 0

    /// あと何本公開できるか(購入者は nil = 上限なし)
    func remaining(premium: Bool) -> Int? { premium ? nil : max(0, Self.free + extra - used) }

    /// 日本時間の日付の番号(1970年1月1日からの日数)
    static func jstDay(_ date: Date = Date()) -> Int { Int(floor((date.timeIntervalSince1970 * 1000 + 9 * 3600 * 1000) / 86_400_000)) }
}

enum PostQuotaService {
    static func fetch(uid: String) async -> PostQuota? {
        guard Backend.isAvailable, let snap = try? await Firestore.firestore().document("users/\(uid)").getDocument() else { return nil }
        guard let d = snap.data() else { return PostQuota() }   // まだ一度も投稿していない
        func n(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        let today = n("postDay") == PostQuota.jstDay()
        return PostQuota(used: today ? n("postsToday") : 0, extra: n("extraPosts"))
    }

    /// 広告を見たことを報告して、追加で1本公開できる券をもらう
    static func grantExtra() async -> Bool {
        guard Backend.isAvailable else { return false }
        return (try? await Backend.functions.httpsCallable("grantExtraPost").call([:] as [String: Any])) != nil
    }
}
