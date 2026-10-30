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

/// ランキングとコメントに出す名前を、匿名(決まった言葉の名前)にするか、投稿者名にするか。端末に保存し、全ステージ共通
@MainActor
final class DisplayNameStore: ObservableObject {
    static let shared = DisplayNameStore()
    private let key = "display.useAuthorName"
    static let maxLength = 12
    @Published var useAuthorName: Bool { didSet { UserDefaults.standard.set(useAuthorName, forKey: key) } }

    init() { useAuthorName = UserDefaults.standard.bool(forKey: key) }

    /// サーバーに送る名前。投稿者名で出す設定で、名前が入っているときだけ。nil なら匿名で出る
    var publicName: String? {
        let n = AuthorName.current
        return useAuthorName && !n.isEmpty ? n : nil
    }

    /// 画面に出す、いまの名前(番号なし)
    func label(_ handle: PlayerHandle) -> String {
        publicName ?? PlayerHandle.name(a: handle.a, n: handle.n, num: 0).replacingOccurrences(of: "#0000", with: "").trimmingCharacters(in: .whitespaces)
    }
}

struct ScoreEntry: Identifiable, Equatable {
    var id: String { uid }
    let uid: String
    let a: Int
    let n: Int
    let num: Int
    /// 投稿者名で記録したときの名前。nil なら匿名(a, n, num の名前)
    var name: String? = nil
    let value: Int
    var displayName: String { name ?? PlayerHandle.name(a: a, n: n, num: num) }
}

struct SubmitOutcome {
    var accepted: Bool
    var improved: Bool
    var value: Int
    var rank: Int
    var reason: String?
}

enum RankingError: Error { case notCleared, tooFast, badName, unavailable, other }

/// 世界ランキング。ボス戦は「クリアまでの時間(短いほど上)」、ダメージ勝負は「与えたダメージ(多いほど上)」
enum RankingService {
    static let listSize = 30

    static func ranks(for mode: Mode) -> Bool { mode != .survive }
    /// 時間で競うモードか(ボス戦と連戦は、クリアまでの時間。ダメージ勝負は、ダメージ)
    static func byTime(_ mode: Mode) -> Bool { mode == .boss || mode == .sequence }

    static func top(stageID: String, mode: Mode) async throws -> [ScoreEntry] {
        let col = Firestore.firestore().collection("stages/\(stageID)/scores")
        let snap = try await col.order(by: "value", descending: !byTime(mode)).limit(to: listSize).getDocuments()
        return snap.documents.compactMap { doc in
            let d = doc.data()
            guard let uid = d["uid"] as? String, let value = (d["value"] as? NSNumber)?.intValue else { return nil }
            return ScoreEntry(uid: uid, a: (d["a"] as? NSNumber)?.intValue ?? 0, n: (d["n"] as? NSNumber)?.intValue ?? 0,
                              num: (d["num"] as? NSNumber)?.intValue ?? 0, name: (d["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }, value: value)
        }
    }

    /// 記録の表示(ボス戦は秒、ダメージ勝負はダメージ)
    static func format(_ value: Int, mode: Mode) -> String {
        if !byTime(mode) { return value.formatted() }
        return String(format: "%.2f", Double(value) * DanmakuConfig.step) + L("unit.s")
    }

    /// 操作記録(リプレイ)を送る。サーバーが再生して、本当にクリアできているか確かめてから載せる
    static func submit(stageID: String, moves: [Move], handle: PlayerHandle, name: String? = nil, shot: ShotType = .standard) async throws -> SubmitOutcome {
        guard Backend.isAvailable else { throw RankingError.unavailable }
        var payload: [String: Any] = [
            "stageId": stageID, "replay": Replay(moves: moves).encoded(), "shot": shot.rawValue,
            "handle": ["a": handle.a, "n": handle.n],
        ]
        if let name { payload["name"] = name }
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
            if "\(error)".contains("display-name") { throw RankingError.badName }
            throw RankingError.other
        }
    }
}
