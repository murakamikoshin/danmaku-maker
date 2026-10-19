import DanmakuCore
import Foundation

/// 作者名。全ステージで共通(同じ人が投稿したステージは、同じ名前で出る)。どのステージで変えても、全部に反映される
enum AuthorName {
    private static let key = "authorName"
    static var current: String { UserDefaults.standard.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? "" }
    static func set(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespaces)
        if !t.isEmpty { UserDefaults.standard.set(t, forKey: key) }
    }
    /// 共通の作者名が空なら、いままでのステージに入っていた名前を引き継ぐ
    static func migrate(from stages: [SavedStage]) {
        guard current.isEmpty, let n = stages.map(\.draft.authorName).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else { return }
        set(n)
    }
}

/// 保存したステージ(マイステージ)。作っただけで投稿しなくても、端末に残り、いつでも遊べる・直せる
struct SavedStage: Identifiable, Codable, Equatable {
    var id = UUID()
    var draft: Draft
    var updatedAt = Date()
    /// テストプレイでクリアしたときのステージ(確認済みの内容)とリプレイ。内容を変えると、確認は自動で外れる
    var verifiedStage: Stage?
    var verifiedReplay: String?
    /// 投稿した内容と、発行された ID(同じ内容を、二重に投稿しないため)
    var publishedStage: Stage?
    var publishedID: String?

    var stage: Stage { draft.stage }
    var isVerified: Bool { verifiedStage != nil && verifiedStage == stage }
    var isPublished: Bool { publishedStage != nil && publishedStage == stage && publishedID != nil }
    var displayName: String { draft.name.trimmingCharacters(in: .whitespaces).isEmpty ? L("mystage.unnamed") : draft.name }
}

/// マイステージの保存場所(アプリ専用の領域のファイル)。書き込みは、途中で切れても壊れないように一度に行う
@MainActor
final class LocalStageStore: ObservableObject {
    static let shared = LocalStageStore()
    static let maxStages = 100

    @Published private(set) var stages: [SavedStage] = []
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("saved_stages.json")
        load()
        migrateOldDraftIfNeeded()
        AuthorName.migrate(from: stages)
    }

    var canCreate: Bool { stages.count < Self.maxStages }

    func stage(id: UUID) -> SavedStage? { stages.first { $0.id == id } }

    /// 新しいステージを作って保存する(作者名は、前に使った名前を引き継ぐ)
    @discardableResult
    func create() -> SavedStage? {
        guard canCreate else { return nil }
        var d = Draft()
        d.authorName = AuthorName.current
        let s = SavedStage(draft: d)
        stages.insert(s, at: 0)
        persist()
        return s
    }

    func update(_ s: SavedStage) {
        guard let i = stages.firstIndex(where: { $0.id == s.id }) else { return }
        var v = s
        if stages[i].draft != s.draft { v.updatedAt = Date() }
        stages[i] = v
        persist()
    }

    func delete(id: UUID) {
        stages.removeAll { $0.id == id }
        persist()
    }

    /// 全部消す(アカウント削除のときではなく、端末内のデータの初期化用。テストでも使う)
    func removeAll() { stages = []; persist() }

    private func load() {
        guard let data = try? Data(contentsOf: url), let list = try? JSONDecoder().decode([SavedStage].self, from: data) else { return }
        stages = list
    }

    private func persist() {
        let sorted = stages.sorted { $0.updatedAt > $1.updatedAt }
        stages = sorted
        if let data = try? JSONEncoder().encode(sorted) { try? data.write(to: url, options: [.atomic, .completeFileProtection]) }
    }

    /// 前のバージョンの「下書き1つだけ」を、最初のマイステージとして引き継ぐ(一度だけ)
    private func migrateOldDraftIfNeeded() {
        let key = "editor.draft.v1"
        let flag = "mystage.migrated.v1"
        let d = UserDefaults.standard
        guard !d.bool(forKey: flag) else { return }
        d.set(true, forKey: flag)
        guard stages.isEmpty, let data = d.data(forKey: key), let draft = try? JSONDecoder().decode(Draft.self, from: data) else { return }
        if draft == Draft() { return }   // 手つかずの下書きは、引き継がない
        stages = [SavedStage(draft: draft)]
        persist()
    }
}
