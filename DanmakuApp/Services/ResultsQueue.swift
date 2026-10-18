import FirebaseFunctions
import Foundation

/// 挑戦・クリアは端末でためて、まとめて submitResults で送る（1プレイごとには書き込まない）
@MainActor
final class ResultsQueue {
    static let shared = ResultsQueue()
    private let key = "results.pending.v1"
    private var pending: [String: [Int]]   // stageId -> [plays, clears]
    private var flushing = false

    private init() {
        pending = (UserDefaults.standard.dictionary(forKey: key) as? [String: [Int]]) ?? [:]
    }

    func recordPlay(_ id: String) { pending[id, default: [0, 0]][0] += 1; persist() }
    func recordClear(_ id: String) { pending[id, default: [0, 0]][1] += 1; persist() }

    func flush() async {
        guard Backend.isAvailable, !flushing, !pending.isEmpty else { return }
        flushing = true
        defer { flushing = false }
        // サーバーの上限（1通30件・1件100回）に合わせて切り出す
        let batch = Array(pending.prefix(30)).map { (id: $0.key, plays: min($0.value[0], 100), clears: min($0.value[1], min($0.value[0], 100))) }
        let payload = batch.map { ["stageId": $0.id, "plays": $0.plays, "clears": $0.clears] as [String: Any] }
        do {
            _ = try await Backend.functions.httpsCallable("submitResults").call(["results": payload])
            for b in batch {
                guard var cur = pending[b.id] else { continue }
                cur[0] -= b.plays; cur[1] -= b.clears
                pending[b.id] = (cur[0] <= 0 && cur[1] <= 0) ? nil : [max(0, cur[0]), max(0, cur[1])]
            }
            persist()
        } catch {
            // 送れなかった分は残して、次の機会に再送する
        }
    }

    private func persist() { UserDefaults.standard.set(pending, forKey: key) }
}
