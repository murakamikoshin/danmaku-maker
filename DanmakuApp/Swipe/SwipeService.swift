import DanmakuCore
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// スタミナの表示用の値（サーバーが数えたもの）
struct StaminaInfo: Equatable {
    var value = 5
    var nextAt: Date?
    var drinks = 0
    var unlimited = false
    var adRefillUsed = false
    /// サーバーから受け取った値か(まだなら、満タンに見せない)
    var known = false
    static let max = 5
}

struct SwipeRunStart {
    let runId: String
    let seed: UInt32
    let poolVersion: String
}

/// 1 本ぶんの記録（サーバーに送る形）
struct SwipeClipRecord {
    var go: [Move] = []
    var moves: [Move] = []
    var skipped = false
    /// 途中経過(アプリとサーバーの計算がずれたとき、最初にずれた場所を探す用。点数には使わない)
    var gaugeAtStart = 0
    var grazes = 0
    var bombSteps: [Int] = []
    var checkpoints: [Int] = []
    var endStep = 0
    var scoreAtEnd = ""
}

struct SwipeSubmitResult {
    var score = BigScore.zero
    var clipsCleared = 0
    var bestStreak = 0
    var ranked = false
    var improved = false
    /// このプレイで新しくもらった称号(スコア達成)
    var newTitles: [String] = []
}

struct SwipeRankRow: Identifiable {
    let id: Int
    let rank: Int
    let mine: Bool
    let score: BigScore
    let bestStreak: Int
    let name: String
    var title: String?
    var crown = 0
    var medal = false
    var badge: ProfileBadge { ProfileBadge(title: title, crown: crown, medal: medal) }
}

/// ランキングの取得結果(今月か累計か)
struct SwipeRanking {
    var rows: [SwipeRankRow] = []
    var myRank: Int?
    var myScore: BigScore?
    /// 今月のとき: 月の ID(例 2026-11)・終わる時刻・参加人数
    var month: String?
    var endsAt: Date?
    var total: Int?
}

enum SwipeError: Error, Equatable {
    case noStamina, noDrink, adRefillUsed, poolEmpty, authorBlocked, offline, other(String)
}

/// スワイプ弾幕のサーバーとのやりとり（スタミナ・プレイの開始・記録の提出・ランキング）と、クリップの先読み
@MainActor
final class SwipeService: ObservableObject {
    @Published private(set) var stamina = StaminaInfo()
    @Published private(set) var loaded = false

    private var clipCache: [String: (stage: Stage, at: Double, authorName: String, name: String)] = [:]

    private func call(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        guard Backend.isAvailable else { throw SwipeError.offline }
        do {
            let r = try await Backend.functions.httpsCallable(name).call(data)
            return r.data as? [String: Any] ?? [:]
        } catch let e as NSError {
            let msg = (e.userInfo[NSLocalizedDescriptionKey] as? String) ?? e.localizedDescription
            if msg.contains("no-stamina") { throw SwipeError.noStamina }
            if msg.contains("no-drink") { throw SwipeError.noDrink }
            if msg.contains("ad-refill-used") { throw SwipeError.adRefillUsed }
            if msg.contains("pool-empty") { throw SwipeError.poolEmpty }
            if msg.contains("author-blocked") { throw SwipeError.authorBlocked }
            if e.domain == NSURLErrorDomain { throw SwipeError.offline }
            throw SwipeError.other(msg)
        }
    }

    private func apply(_ d: [String: Any]) {
        func int(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        var s = StaminaInfo()
        s.value = int("value")
        if let ms = (d["nextAt"] as? NSNumber)?.doubleValue { s.nextAt = Date(timeIntervalSince1970: ms / 1000) }
        s.drinks = int("drinks")
        s.unlimited = (d["unlimited"] as? Bool) ?? false
        s.adRefillUsed = (d["adRefillUsed"] as? Bool) ?? false
        s.known = true
        stamina = s
        loaded = true
    }

    func refresh() async {
        if let d = try? await call("swipeGetStamina") { apply(d) }
    }

    /// プレイを始める（スタミナを 1 使う。パスがあれば使わない）
    func start(author: String?) async throws -> SwipeRunStart {
        var payload: [String: Any] = [:]
        if let author { payload["author"] = author }
        let d = try await call("swipeUseStamina", payload)
        apply(d)
        guard let runId = d["runId"] as? String, let seed = (d["seed"] as? NSNumber)?.uint32Value, let ver = d["poolVersion"] as? String else { throw SwipeError.other("response") }
        return SwipeRunStart(runId: runId, seed: seed, poolVersion: ver)
    }

    func refillByAd() async throws { apply(try await call("swipeRefillByAd")) }
    func useDrink() async throws { apply(try await call("swipeUseDrink")) }

    /// 候補の一覧（その回の版）
    func loadPool(version: String) async throws -> [SwipeFeed.Entry] {
        guard Backend.isAvailable else { throw SwipeError.offline }
        let snap = try await Firestore.firestore().collection("swipePools/\(version)/chunks").getDocuments()
        var out: [SwipeFeed.Entry] = []
        for d in snap.documents {
            for e in d.data()["entries"] as? [[String: Any]] ?? [] {
                if let id = e["id"] as? String, let author = e["author"] as? String, let dd = (e["d"] as? NSNumber)?.intValue { out.append(.init(id: id, d: dd, author: author)) }
            }
        }
        return out
    }

    struct Clip { let id: String; let stage: Stage; let at: Double; let name: String; let authorName: String }

    /// クリップのステージ（先読みして使い回す）。見つからなければ nil
    func clip(id: String) async -> Clip? {
        // ランダム生成のクリップ: ID（種と難しさ）から、この端末で同じステージを作る（サーバーの検証と同じ）
        if let g = SwipeGenerator.parse(id: id) {
            return Clip(id: id, stage: SwipeGenerator.stage(seed: g.seed, hard: g.hard), at: SwipeGenerator.clipAt, name: L("swipe.gen.name"), authorName: "")
        }
        if let c = clipCache[id] { return Clip(id: id, stage: c.stage, at: c.at, name: c.name, authorName: c.authorName) }
        guard Backend.isAvailable, let snap = try? await Firestore.firestore().document("stages/\(id)").getDocument(),
              let remote = StageRepository.parse(snap), let at = (snap.data()?["clip"] as? [String: Any])?["at"] as? NSNumber else { return nil }
        clipCache[id] = (remote.stage, at.doubleValue, remote.authorName, remote.name)
        if clipCache.count > 60 { clipCache.removeValue(forKey: clipCache.keys.first!) }
        return Clip(id: id, stage: remote.stage, at: at.doubleValue, name: remote.name, authorName: remote.authorName)
    }

    func submit(runId: String, clips: [SwipeClipRecord], handle: PlayerHandle, name: String?) async throws -> SwipeSubmitResult {
        let payload: [[String: Any]] = clips.map {
            ["go": $0.go.isEmpty ? "" : Replay(moves: $0.go).encoded(), "moves": $0.moves.isEmpty ? "" : Replay(moves: $0.moves).encoded(), "skipped": $0.skipped,
             "diag": ["g0": $0.gaugeAtStart, "grazes": $0.grazes, "bombs": $0.bombSteps, "cp": $0.checkpoints, "end": $0.endStep, "score": $0.scoreAtEnd] as [String: Any]]
        }
        var body: [String: Any] = ["runId": runId, "clips": payload, "handle": ["a": handle.a, "n": handle.n]]
        if let name { body["name"] = name }
        let d = try await call("swipeSubmitRun", body)
        var r = SwipeSubmitResult()
        r.score = BigScore((d["score"] as? String) ?? "0") ?? .zero
        r.clipsCleared = (d["clipsCleared"] as? NSNumber)?.intValue ?? 0
        r.bestStreak = (d["bestStreak"] as? NSNumber)?.intValue ?? 0
        r.ranked = (d["ranked"] as? Bool) ?? false
        r.improved = (d["improved"] as? Bool) ?? false
        r.newTitles = ((d["newTitles"] as? [String]) ?? []).filter(TitleID.isValid)
        return r
    }

    /// ランキング。monthly が true なら今月(日本時間の毎月 1 日 0:00 にリセット)、false なら累計
    func ranking(monthly: Bool) async throws -> SwipeRanking {
        let d = try await call("swipeRanking", monthly ? ["period": "month"] : [:])
        let rows = (d["rows"] as? [[String: Any]] ?? []).enumerated().map { i, r -> SwipeRankRow in
            let name = (r["name"] as? String) ?? PlayerHandle.name(a: (r["a"] as? NSNumber)?.intValue ?? 0, n: (r["n"] as? NSNumber)?.intValue ?? 0, num: (r["num"] as? NSNumber)?.intValue ?? 0)
            return SwipeRankRow(id: i, rank: (r["rank"] as? NSNumber)?.intValue ?? i + 1, mine: (r["mine"] as? Bool) ?? false,
                                score: BigScore((r["score"] as? String) ?? "0") ?? .zero, bestStreak: (r["bestStreak"] as? NSNumber)?.intValue ?? 0, name: name,
                                title: (r["title"] as? String).flatMap { TitleID.isValid($0) ? $0 : nil },
                                crown: (r["crown"] as? NSNumber)?.intValue ?? 0, medal: (r["medal"] as? Bool) ?? false)
        }
        let my = d["my"] as? [String: Any]
        var out = SwipeRanking(rows: rows, myRank: (my?["rank"] as? NSNumber)?.intValue, myScore: (my?["score"] as? String).flatMap { BigScore($0) })
        if monthly {
            out.month = d["month"] as? String
            out.endsAt = (d["endsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
            out.total = (d["total"] as? NSNumber)?.intValue
        }
        return out
    }
}
