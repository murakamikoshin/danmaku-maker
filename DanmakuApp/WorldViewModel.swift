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
        // 前の読み込みの途中でも、新しい条件で読み込み直せるようにする(古い読み込みの結果は generation で捨てる)
        isLoading = false
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

    /// 次のページを読む。`isVisible` は一覧に出すステージか(ブロックした人のものは出さない)。
    /// 読んだページに、一覧に出るものが1つも増えなかったときは、続けて次のページを読む
    /// (一覧の最後の行が画面に出たときに次を読む作りなので、増えないと、そこで止まって古いステージが出てこなかった)
    func loadMore(isVisible: (RemoteStage) -> Bool = { _ in true }) async {
        guard !isLoading, !reachedEnd, !searching, Backend.isAvailable else { return }
        isLoading = true
        failed = false
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            for _ in 0..<10 {
                let page = try await repo.fetch(sort, mode: mode, after: cursor)
                guard gen == generation else { return }
                let added = page.stages.filter { s in !stages.contains { $0.id == s.id } }
                stages += added
                // 読めなかったステージがあっても、続きはそのページの最後の次から読む
                if page.cursor != nil { cursor = page.cursor }
                reachedEnd = page.reachedEnd
                if reachedEnd || added.contains(where: isVisible) { break }
            }
        } catch {
            if gen == generation { failed = true }
        }
    }
}
