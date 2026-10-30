import DanmakuCore
import FirebaseFirestore
import Foundation

@MainActor
final class WorldViewModel: ObservableObject {
    @Published private(set) var stages: [RemoteStage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var reachedEnd = false
    @Published var sort: StageSort = .popular
    /// クリア条件(モード)での絞り込み。nil はすべて
    @Published var mode: Mode?
    /// ステージ名の検索語。空なら、一覧(並べ替え)を出す
    @Published var query = ""
    @Published private(set) var searching = false

    private var cursor: DocumentSnapshot?
    private let repo = StageRepository()
    private var generation = 0

    func reload() async {
        generation += 1
        cursor = nil; reachedEnd = false; stages = []; failed = false
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searching = !q.isEmpty
        if searching { await runSearch(q) } else { await loadMore() }
    }

    private func runSearch(_ q: String) async {
        guard Backend.isAvailable else { return }
        isLoading = true
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            let found = try await repo.search(q, mode: mode)
            guard gen == generation else { return }
            stages = found
            reachedEnd = true
        } catch {
            if gen == generation { failed = true }
        }
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, !searching, Backend.isAvailable else { return }
        isLoading = true
        failed = false
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            let page = try await repo.fetch(sort, mode: mode, after: cursor)
            guard gen == generation else { return }
            stages += page.stages.filter { s in !stages.contains { $0.id == s.id } }
            cursor = page.cursor
            reachedEnd = page.reachedEnd
        } catch {
            if gen == generation { failed = true }
        }
    }
}
