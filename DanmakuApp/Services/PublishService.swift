import DanmakuCore
import FirebaseFunctions
import Foundation

enum PublishService {
    /// 投稿して、発行された短縮IDを返す。失敗時は表示用の文言を持つ PublishError
    static func publish(stage: Stage, authorName: String, replay: Replay?, premium: Bool = false) async throws -> String {
        guard Backend.isAvailable else { throw PublishError(message: L("error.offline")) }
        var payload = (try? JSONSerialization.jsonObject(with: JSONEncoder().encode(stage))) as? [String: Any] ?? [:]
        payload["authorName"] = authorName.trimmingCharacters(in: .whitespaces)
        // クリア記録がなければ「URLを知っている人だけ」の投稿(一覧には載らない)
        if let replay { payload["clearReplay"] = replay.encoded() } else { payload["unlisted"] = true }
        payload["termsAccepted"] = true
        payload["premium"] = premium   // 広告削除・永久買い切りパックの購入者は、1日の公開数の上限がない
        payload["lang"] = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "und"
        do {
            let result = try await Backend.functions.httpsCallable("publishStage").call(payload)
            guard let id = (result.data as? [String: Any])?["id"] as? String else { throw PublishError(message: L("error.publish.generic")) }
            return id
        } catch let e as PublishError {
            throw e
        } catch {
            let code = (error as NSError).localizedDescription
            let key = "error.publish.\(code)"
            let text = L(key)
            throw PublishError(message: text == key ? L("error.publish.generic") : text)
        }
    }
}

extension PublishService {
    /// 投稿したステージの、一覧に出す見せ場の静止画を作って、サーバーに送る(失敗しても投稿はそのまま。一覧は動くプレビューのままになる)
    @MainActor static func uploadPreview(id: String, stage: Stage) async {
        guard Backend.isAvailable, let png = StageStillView.png(for: stage), png.count < 80_000 else { return }
        _ = try? await Backend.functions.httpsCallable("savePreviewImage").call(["stageId": id, "png": png.base64EncodedString(), "v": 2])
    }
}

struct PublishError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum StageActions {
    static func toggleLike(id: String) async throws -> (liked: Bool, likes: Int) {
        let r = try await Backend.functions.httpsCallable("toggleLike").call(["stageId": id])
        let d = r.data as? [String: Any] ?? [:]
        return (d["liked"] as? Bool ?? false, (d["likes"] as? NSNumber)?.intValue ?? 0)
    }

    static func report(id: String, reason: String) async throws {
        _ = try await Backend.functions.httpsCallable("reportStage").call(["stageId": id, "reason": reason])
    }
}
