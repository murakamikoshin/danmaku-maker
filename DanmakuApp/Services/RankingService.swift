import DanmakuCore
import FirebaseFirestore
import Foundation

/// ランキングに出る名前。自由入力にせず、決まった言葉の組み合わせ(番号で選ぶ)にする
struct PlayerHandle: Codable, Equatable {
    static let choices = 16
    var a: Int
    var n: Int

    static func random() -> PlayerHandle { PlayerHandle(a: Int.random(in: 0..<choices), n: Int.random(in: 0..<choices)) }

    /// 画面に出す名前。言葉は端末の言語で表示される(同じ記録でも、見る人の言語になる)
    static func name(a: Int, n: Int, num: Int) -> String {
        let adj = L("handle.adj.\(min(max(a, 0), choices - 1))")
        let animal = L("handle.animal.\(min(max(n, 0), choices - 1))")
        return String(format: L("handle.format"), adj, animal, num)
    }
}

/// 自分のランキング名(端末に保存)
@MainActor
final class HandleStore: ObservableObject {
    static let shared = HandleStore()
    private let key = "ranking.handle.v1"
    @Published var handle: PlayerHandle { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: key), let h = try? JSONDecoder().decode(PlayerHandle.self, from: d) {
            handle = h
        } else {
            handle = .random()
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(handle) { UserDefaults.standard.set(d, forKey: key) }
    }
}

struct ScoreEntry: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let a: Int
    let n: Int
    let num: Int
    let value: Int
    var displayName: String { PlayerHandle.name(a: a, n: n, num: num) }
}

struct SubmitOutcome {
    var accepted: Bool
    var improved: Bool
    var value: Int
    var rank: Int
    var reason: String?
}

enum RankingError: Error { case notCleared, tooFast, unavailable, other }

/// 世界ランキング。ボス戦は「クリアまでの時間(短いほど上)」、ダメージ勝負は「与えたダメージ(多いほど上)」
enum RankingService {
    static let listSize = 30

    static func ranks(for mode: Mode) -> Bool { mode != .survive }

    static func top(stageID: String, mode: Mode) async throws -> [ScoreEntry] {
        let col = Firestore.firestore().collection("stages/\(stageID)/scores")
        let snap = try await col.order(by: "value", descending: mode == .damage).limit(to: listSize).getDocuments()
        return snap.documents.compactMap { doc in
            let d = doc.data()
            guard let uid = d["uid"] as? String, let value = (d["value"] as? NSNumber)?.intValue else { return nil }
            return ScoreEntry(uid: uid, a: (d["a"] as? NSNumber)?.intValue ?? 0, n: (d["n"] as? NSNumber)?.intValue ?? 0,
                              num: (d["num"] as? NSNumber)?.intValue ?? 0, value: value)
        }
    }

    /// 記録の表示(ボス戦は秒、ダメージ勝負はダメージ)
    static func format(_ value: Int, mode: Mode) -> String {
        if mode == .damage { return value.formatted() }
        return String(format: "%.2f", Double(value) * DanmakuConfig.step) + L("unit.s")
    }

    /// 操作記録(リプレイ)を送る。サーバーが再生して、本当にクリアできているか確かめてから載せる
    static func submit(stageID: String, moves: [Move], handle: PlayerHandle) async throws -> SubmitOutcome {
        guard Backend.isAvailable else { throw RankingError.unavailable }
        let payload: [String: Any] = [
            "stageId": stageID, "replay": Replay(moves: moves).encoded(), "shot": "standard",
            "handle": ["a": handle.a, "n": handle.n],
        ]
        do {
            let r = try await Backend.functions.httpsCallable("submitScore").call(payload)
            let d = r.data as? [String: Any] ?? [:]
            if d["accepted"] as? Bool != true { throw RankingError.notCleared }
            return SubmitOutcome(accepted: true, improved: d["improved"] as? Bool ?? false,
                                 value: (d["value"] as? NSNumber)?.intValue ?? 0, rank: (d["rank"] as? NSNumber)?.intValue ?? 0)
        } catch let e as RankingError {
            throw e
        } catch {
            if "\(error)".contains("too-fast") { throw RankingError.tooFast }
            throw RankingError.other
        }
    }
}
