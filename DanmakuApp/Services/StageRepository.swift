import DanmakuCore
import FirebaseFirestore
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

    var clearRatePercent: Int? { plays > 0 ? Int((Double(clears) / Double(plays) * 100).rounded()) : nil }
    static func == (a: RemoteStage, b: RemoteStage) -> Bool { a.id == b.id && a.likes == b.likes && a.plays == b.plays && a.clears == b.clears }
    func hash(into h: inout Hasher) { h.combine(id) }
}

enum StageSort: String, CaseIterable, Identifiable {
    case popular, new, hard, trending
    var id: String { rawValue }
    var titleKey: String { "world.sort.\(rawValue)" }
}

struct StagePage {
    var stages: [RemoteStage]
    var cursor: DocumentSnapshot?
    var reachedEnd: Bool
}

/// 世界のステージの取得。一覧には必ず件数制限(20件)とページングを付ける
struct StageRepository {
    static let pageSize = 20

    func fetch(_ sort: StageSort, after cursor: DocumentSnapshot?) async throws -> StagePage {
        var q: Query = Firestore.firestore().collection("stages").whereField("status", isEqualTo: "published")
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

    func find(id: String) async throws -> RemoteStage? {
        let snap = try await Firestore.firestore().document("stages/\(id)").getDocument()
        return Self.parse(snap)
    }

    func isLiked(id: String, uid: String) async -> Bool {
        (try? await Firestore.firestore().document("stages/\(id)/likes/\(uid)").getDocument().exists) ?? false
    }

    static func parse(_ doc: DocumentSnapshot) -> RemoteStage? {
        guard let d = doc.data(), d["status"] as? String == "published" else { return nil }
        var json: [String: Any] = [:]
        for key in ["name", "mode", "durationSec", "bossHp", "bossMove", "emitters"] {
            if let v = d[key], !(v is NSNull) { json[key] = v }
        }
        json["formatVersion"] = 1
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let stage = try? JSONDecoder().decode(Stage.self, from: data) else { return nil }
        func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        return RemoteStage(id: doc.documentID, authorUid: d["authorUid"] as? String ?? "", authorName: d["authorName"] as? String ?? "",
                           name: stage.name, stage: stage.sanitized(), plays: int("plays"), clears: int("clears"), likes: int("likes"))
    }
}
