import DanmakuCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation

struct RemoteStage: Identifiable, Hashable {
    let id: String
    let authorUid: String
    let authorName: String
    let name: String
    let stage: Stage
    let plays: Int
    let clears: Int
    let likes: Int
    /// コメントの数(古いステージは項目がないので 0)
    let comments: Int
    /// 遊ぶのに必要な内容のレベル(サーバーが付ける。ないステージは 1)
    var needs = 1
    /// 作者が決めた見せ場の静止画があるか(あれば一覧はそれを出す。なければ動くプレビュー)
    var hasPreviewImage = false
    var previewImageURL: URL { AppConfig.webBase.appendingPathComponent("pv/\(id).png") }
    /// このアプリより新しい内容が要るか(要るなら、遊ばせずにアップデートを案内する)
    var needsNewerApp: Bool { needs > DanmakuConfig.contentLevel }

    var clearRatePercent: Int? { plays > 0 ? Int((Double(clears) / Double(plays) * 100).rounded()) : nil }
    static func == (a: RemoteStage, b: RemoteStage) -> Bool { a.id == b.id && a.likes == b.likes && a.comments == b.comments && a.plays == b.plays && a.clears == b.clears }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// クリア率での難しさの絞り込み(マリオメーカー2と同じ考え方。挑戦が10回以上のステージだけが対象)。
/// サーバーの hardRate(クリア数 ÷ 挑戦数)の範囲で絞る
enum WorldDifficulty: String, CaseIterable, Identifiable {
    case easy, normal, hard, oni
    var id: String { rawValue }
    var titleKey: String { "world.diff.\(rawValue)" }
    /// hardRate の範囲 [from, to)
    var range: (from: Double, to: Double) {
        switch self {
        case .easy: return (0.5, 1.0001)
        case .normal: return (0.2, 0.5)
        case .hard: return (0.05, 0.2)
        case .oni: return (0, 0.05)
        }
    }
}

enum StageSort: String, CaseIterable, Identifiable {
    case popular, new, hard, trending
    var id: String { rawValue }
    var titleKey: String { "world.sort.\(rawValue)" }
}

/// 自分の投稿の実績(もらったハート、遊ばれた数、クリアされた数、コメント数の合計)と、投稿の一覧
struct MyStageSummary {
    var stages = 0, likes = 0, plays = 0, clears = 0, comments = 0
    var list: [RemoteStage] = []
}

struct StagePage {
    var stages: [RemoteStage]
    var cursor: DocumentSnapshot?
    var reachedEnd: Bool
}

/// 世界のステージの取得。一覧には必ず件数制限(20件)とページングを付ける
struct StageRepository {
    static let pageSize = 20

    func fetch(_ sort: StageSort, mode: Mode? = nil, difficulty: WorldDifficulty? = nil, after cursor: DocumentSnapshot?) async throws -> StagePage {
        var q: Query = Firestore.firestore().collection("stages").whereField("status", isEqualTo: "published")
        if let mode { q = q.whereField("mode", isEqualTo: mode.rawValue) }
        if let difficulty {
            // 難しさで絞るときは、クリア率の高い(やさしい)順に並べる。値が入っているのは、挑戦10回以上のステージだけ
            q = q.whereField("hardRate", isGreaterThanOrEqualTo: difficulty.range.from).whereField("hardRate", isLessThan: difficulty.range.to)
                .order(by: "hardRate", descending: true)
            if let cursor { q = q.start(afterDocument: cursor) }
            let snap = try await q.limit(to: Self.pageSize).getDocuments()
            return StagePage(stages: snap.documents.compactMap(Self.parse), cursor: snap.documents.last, reachedEnd: snap.documents.count < Self.pageSize)
        }
        switch sort {
        case .popular: q = q.order(by: "likes", descending: true)
        case .new: q = q.order(by: "createdAt", descending: true)
        case .hard: q = q.order(by: "hardRate", descending: false)   // 挑戦10回以上のものだけに値が入る
        case .trending: q = q.order(by: "trending", descending: true)
        }
        if let cursor { q = q.start(afterDocument: cursor) }
        let snap = try await q.limit(to: Self.pageSize).getDocuments()
        return StagePage(stages: snap.documents.compactMap(Self.parse), cursor: snap.documents.last,
                         reachedEnd: snap.documents.count < Self.pageSize)
    }

    /// その作者の公開中のステージ(いいねの多い順、20件ずつ)。クリア条件(モード)でも絞れる
    func fetchByAuthor(uid: String, mode: Mode? = nil, after cursor: DocumentSnapshot?) async throws -> StagePage {
        var q: Query = Firestore.firestore().collection("stages").whereField("status", isEqualTo: "published").whereField("authorUid", isEqualTo: uid)
        if let mode { q = q.whereField("mode", isEqualTo: mode.rawValue) }
        q = q.order(by: "likes", descending: true)
        if let cursor { q = q.start(afterDocument: cursor) }
        let snap = try await q.limit(to: Self.pageSize).getDocuments()
        return StagePage(stages: snap.documents.compactMap(Self.parse), cursor: snap.documents.last,
                         reachedEnd: snap.documents.count < Self.pageSize)
    }

    func find(id: String) async throws -> RemoteStage? {
        let snap = try await Firestore.firestore().document("stages/\(id)").getDocument()
        return Self.parse(snap)
    }

    /// その人が公開中のステージの数(サーバーに保存されているもの)。投稿数で解放される見た目の判定に使う
    func publishedCount(uid: String) async -> Int? {
        let q = Firestore.firestore().collection("stages").whereField("authorUid", isEqualTo: uid).whereField("status", isEqualTo: "published")
        let snap = try? await q.count.getAggregation(source: .server)
        return snap?.count.intValue
    }

    /// 自分が投稿したステージを、世界から消す(ランキング・コメント・いいねも一緒に消える)。成功したら true
    func deleteStage(id: String) async -> Bool {
        do {
            _ = try await Backend.functions.httpsCallable("deleteStage").call(["stageId": id])
            return true
        } catch { return false }
    }

    func isLiked(id: String, uid: String) async -> Bool {
        (try? await Firestore.firestore().document("stages/\(id)/likes/\(uid)").getDocument().exists) ?? false
    }

    /// ステージ名で探す(部分一致、最大30件、いいねの多い順)。サーバーが検索する
    func search(_ query: String, mode: Mode? = nil) async throws -> [RemoteStage] {
        var payload: [String: Any] = ["query": query]
        if let mode { payload["mode"] = mode.rawValue }
        let r = try await Backend.functions.httpsCallable("searchStages").call(payload)
        let rows = (r.data as? [String: Any])?["stages"] as? [[String: Any]] ?? []
        return rows.compactMap { Self.parse(data: $0, id: $0["id"] as? String ?? "") }
    }

    /// 自分が投稿したステージ(新しい順、最大50件)と、もらったハート・遊ばれた数などの合計
    func mine() async throws -> MyStageSummary {
        let r = try await Backend.functions.httpsCallable("myStages").call([:] as [String: Any])
        let d = r.data as? [String: Any] ?? [:]
        let t = d["totals"] as? [String: Any] ?? [:]
        func n(_ k: String) -> Int { (t[k] as? NSNumber)?.intValue ?? 0 }
        let rows = d["stages"] as? [[String: Any]] ?? []
        return MyStageSummary(stages: n("stages"), likes: n("likes"), plays: n("plays"), clears: n("clears"), comments: n("comments"),
                              list: rows.compactMap { Self.parse(data: $0, id: $0["id"] as? String ?? "") })
    }

    static func parse(_ doc: DocumentSnapshot) -> RemoteStage? {
        guard let d = doc.data() else { return nil }
        return parse(data: d, id: doc.documentID)
    }

    /// 検索結果や自分の投稿(関数が返す形)は status を持たないこともあるので、公開中・URL限定のものを通す
    static func parse(data d: [String: Any], id: String) -> RemoteStage? {
        if let st = d["status"] as? String, !["published", "unlisted"].contains(st) { return nil }
        var json: [String: Any] = [:]
        // Stage の全項目(見た目・撃ち方・連戦の場面なども)。足りないと、世界のステージで作者の設定が反映されない
        for key in ["name", "mode", "durationSec", "bossHp", "bossMove", "emitters", "lifeMode", "lifeCount", "bgm",
                    "themeBullets", "themeBackground", "themeShip", "hideMarkers", "waves", "bossWarning", "bossDefeat",
                    "bossSize", "mooks", "bossLook", "mookLook", "awaken", "shot", "rewardFx", "previewStart", "noPreview", "bossX", "bossY"] {
            if let v = d[key], !(v is NSNull) { json[key] = v }
        }
        json["formatVersion"] = 1
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let stage = try? JSONDecoder().decode(Stage.self, from: data) else { return nil }
        func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        return RemoteStage(id: id, authorUid: d["authorUid"] as? String ?? "", authorName: d["authorName"] as? String ?? "",
                           name: stage.name, stage: stage.sanitized(), plays: int("plays"), clears: int("clears"), likes: int("likes"), comments: int("comments"), needs: max(1, int("needs")), hasPreviewImage: (d["pv"] as? Bool) == true)
    }
}
