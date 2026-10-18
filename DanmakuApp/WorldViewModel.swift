import FirebaseFirestore
import Foundation

@MainActor
final class WorldViewModel: ObservableObject {
    @Published private(set) var stages: [RemoteStage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var failed = false
    @Published private(set) var reachedEnd = false
    @Published var sort: StageSort = .popular

    private var cursor: DocumentSnapshot?
    private let repo = StageRepository()
    private var generation = 0

    func reload() async {
        generation += 1
        cursor = nil; reachedEnd = false; stages = []; failed = false
        await loadMore()
    }

    func loadMore() async {
        guard !isLoading, !reachedEnd, Backend.isAvailable else { return }
        isLoading = true
        failed = false
        let gen = generation
        defer { if gen == generation { isLoading = false } }
        do {
            let page = try await repo.fetch(sort, after: cursor)
            guard gen == generation else { return }
            stages += page.stages.filter { s in !stages.contains { $0.id == s.id } }
            cursor = page.cursor
            reachedEnd = page.reachedEnd
        } catch {
            if gen == generation { failed = true }
        }
    }
}
