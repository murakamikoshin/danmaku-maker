import FirebaseFirestore
import Foundation

struct StageComment: Identifiable, Equatable {
    let id: String
    let uid: String
    let a: Int
    let n: Int
    let num: Int
    let text: String
    let createdAt: Date?
    var displayName: String { PlayerHandle.name(a: a, n: n, num: num) }
}

enum CommentError: Error { case signIn, ngWord, link, tooLong, tooFast, other }

/// ステージへのコメント。書けるのは Apple でサインインした人だけ。通報・ブロック・削除ができる
enum CommentService {
    static let maxLength = 80
    static let pageSize = 30

    static func list(stageID: String) async throws -> [StageComment] {
        let col = Firestore.firestore().collection("stages/\(stageID)/comments")
        let snap = try await col.whereField("status", isEqualTo: "published").order(by: "createdAt", descending: true).limit(to: pageSize).getDocuments()
        return snap.documents.compactMap { doc in
            let d = doc.data()
            guard let uid = d["uid"] as? String, let text = d["text"] as? String else { return nil }
            return StageComment(id: doc.documentID, uid: uid, a: (d["a"] as? NSNumber)?.intValue ?? 0, n: (d["n"] as? NSNumber)?.intValue ?? 0,
                                num: (d["num"] as? NSNumber)?.intValue ?? 0, text: text, createdAt: (d["createdAt"] as? Timestamp)?.dateValue())
        }
    }

    static func post(stageID: String, text: String, handle: PlayerHandle) async throws {
        do {
            _ = try await Backend.functions.httpsCallable("postComment").call(
                ["stageId": stageID, "text": text, "handle": ["a": handle.a, "n": handle.n]] as [String: Any])
        } catch {
            let m = "\(error)"
            if m.contains("sign-in-required") { throw CommentError.signIn }
            if m.contains("comment-ng-word") { throw CommentError.ngWord }
            if m.contains("comment-link") { throw CommentError.link }
            if m.contains("comment-length") { throw CommentError.tooLong }
            if m.contains("too-fast") { throw CommentError.tooFast }
            throw CommentError.other
        }
    }

    static func delete(stageID: String, commentID: String) async throws {
        _ = try await Backend.functions.httpsCallable("deleteComment").call(["stageId": stageID, "commentId": commentID])
    }

    static func report(stageID: String, commentID: String, reason: String) async throws {
        _ = try await Backend.functions.httpsCallable("reportComment").call(["stageId": stageID, "commentId": commentID, "reason": reason])
    }
}
