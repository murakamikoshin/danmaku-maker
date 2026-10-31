import FirebaseFirestore
import Foundation

/// マイステージのバックアップ。アプリを消して入れ直すと、端末のファイル(マイステージ)は消えてしまうので、
/// 保存するたびにサーバー(users/{uid}/savedStages/{ステージのID})にも書いておき、
/// 入れ直したあと(この端末で、その人の分をまだ戻していないとき)に、端末にないものを戻す。
/// - ログイン(匿名も含む)している人のだけ。Firebase のログイン状態は、アプリを消しても端末に残るので、同じ人として戻せる
/// - じぶんの画像(ボス・弾・自機の画像)は端末にしかないので、戻らない(ステージは標準の見た目で戻る)
@MainActor
final class StageBackup {
    static let shared = StageBackup()

    private let store = LocalStageStore.shared
    private var uid: String?
    private var pending: Task<Void, Never>?
    private var restoring = false
    /// 最後にサーバーへ書いた、ステージごとの更新時刻(書き直しを減らす)。uid ごとに分ける
    private var synced: [String: Double] = [:]

    private init() {}

    private static func syncedKey(_ uid: String) -> String { "backup.synced.\(uid)" }
    private static func restoredKey(_ uid: String) -> String { "backup.restored.\(uid)" }

    /// ログインしている人が決まったら(変わったら)呼ぶ
    func attach(uid: String?) {
        guard Backend.isAvailable, uid != self.uid else { return }
        self.uid = uid
        guard let uid else { return }
        synced = (UserDefaults.standard.dictionary(forKey: Self.syncedKey(uid)) as? [String: Double]) ?? [:]
        store.onPersist = { [weak self] list in self?.schedule(list) }
        Task { await restoreIfNeeded(uid: uid) }
    }

    /// この人の分をまだ戻していなければ、サーバーにあって端末にないものを戻す。そのあと、端末の分をサーバーに書く
    /// (アプリを入れ直すと「戻した」印も消えるので、入れ直したあとの最初の起動で戻る。別のアカウントに切り替えたときも、その人の分が戻る)
    private func restoreIfNeeded(uid: String) async {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.restoredKey(uid)) {
            restoring = true
            defer { restoring = false }
            // 端末に残っている控え(キャッシュ)ではなく、必ずサーバーから読む。読めなければ、次の起動でやり直す
            guard let snap = try? await collection(uid).getDocuments(source: .server) else { return }
            guard self.uid == uid else { return }
            let list = snap.documents.compactMap { doc -> SavedStage? in
                guard let json = doc.get("data") as? String, let data = json.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(SavedStage.self, from: data)
            }
            // 戻したものは、サーバーと同じなので書き直さない
            for s in list { synced[s.id.uuidString] = s.updatedAt.timeIntervalSince1970 }
            saveSynced(uid)
            defaults.set(true, forKey: Self.restoredKey(uid))
            store.restore(list)
        }
        schedule(store.stages)
    }

    /// 少し待ってから(続けて保存されたときに、まとめて)サーバーに書く
    private func schedule(_ list: [SavedStage]) {
        guard !restoring, uid != nil else { return }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.upload(list)
        }
    }

    private func upload(_ list: [SavedStage]) async {
        guard let uid else { return }
        let col = collection(uid)
        let batch = Firestore.firestore().batch()
        var next = synced
        var changes = 0
        let ids = Set(list.map { $0.id.uuidString })
        for s in list {
            let key = s.id.uuidString, stamp = s.updatedAt.timeIntervalSince1970
            // 中身が変わっていなくても、確認済み・投稿済みの印が変わることがあるので、エンコードした内容で比べる代わりに、
            // 更新時刻と、その印を合わせた値で判断する
            let mark = stamp + (s.isVerified ? 0.25 : 0) + (s.publishedID != nil ? 0.5 : 0)
            guard synced[key] != mark else { continue }
            guard let data = try? JSONEncoder().encode(s), let json = String(data: data, encoding: .utf8), json.utf8.count < 900_000 else { continue }
            batch.setData(["data": json, "updatedAt": Timestamp(date: s.updatedAt)], forDocument: col.document(key))
            next[key] = mark
            changes += 1
        }
        // 端末で消したものは、サーバーからも消す
        for key in synced.keys where !ids.contains(key) {
            batch.deleteDocument(col.document(key))
            next[key] = nil
            changes += 1
        }
        guard changes > 0, changes <= 450 else {
            if changes > 450 { await uploadInChunks(list) }
            return
        }
        do {
            try await batch.commit()
            guard self.uid == uid else { return }
            synced = next
            saveSynced(uid)
        } catch {
            // 失敗したら、次に保存したときに、まとめて書き直す
        }
    }

    /// 書く数が多いとき(初めてのバックアップなど)は、1件ずつ書く
    private func uploadInChunks(_ list: [SavedStage]) async {
        guard let uid else { return }
        let col = collection(uid)
        for s in list {
            guard let data = try? JSONEncoder().encode(s), let json = String(data: data, encoding: .utf8), json.utf8.count < 900_000 else { continue }
            do {
                try await col.document(s.id.uuidString).setData(["data": json, "updatedAt": Timestamp(date: s.updatedAt)])
                synced[s.id.uuidString] = s.updatedAt.timeIntervalSince1970 + (s.isVerified ? 0.25 : 0) + (s.publishedID != nil ? 0.5 : 0)
            } catch { break }
        }
        saveSynced(uid)
    }

    private func saveSynced(_ uid: String) {
        UserDefaults.standard.set(synced, forKey: Self.syncedKey(uid))
    }

    private func collection(_ uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("savedStages")
    }
}
