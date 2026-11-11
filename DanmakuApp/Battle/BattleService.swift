import DanmakuCore
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import FirebaseFunctions
import Foundation

/// 弾幕バトル(リアルタイム対戦)のサーバーとのやりとり。サーバーの処理は firebase/functions/src/rankedfns.ts
enum BattleService {
    struct Status: Equatable {
        var rating = 1000, games = 0, wins = 0, losses = 0, draws = 0, best = 1000
        var rank = "silver"
        /// 最初の 10 戦は「暫定」(段位を出さない)
        var provisional: Bool { games < 10 }
    }

    struct Opponent: Equatable {
        var name: String
        var rating: Int
        var title: String?
    }

    struct Match: Equatable {
        var id: String
        var seed: UInt32
        /// 始まる時刻(サーバーの時計、ミリ秒)
        var startAt: Double
        var opponent: Opponent
        /// 人の相手(位置を受け取る)。ボットなら nil
        var opponentUid: String?
        /// ボットの相手の動き。人なら nil
        var botMoves: [Move]?
    }

    struct Result: Equatable {
        enum Outcome: String { case win, lose, draw }
        var outcome: Outcome
        var me: RankedStage.Score
        var opp: RankedStage.Score
        var ratingBefore: Int
        var ratingAfter: Int
        var rank: String
    }

    enum Failure: Error { case unavailable, broken }

    private static func call(_ name: String, _ data: [String: Any] = [:]) async throws -> [String: Any] {
        guard Backend.isAvailable else { throw Failure.unavailable }
        let r = try await Backend.functions.httpsCallable(name).call(data)
        guard let d = r.data as? [String: Any] else { throw Failure.broken }
        return d
    }

    private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
    private static func score(_ v: Any?) -> RankedStage.Score {
        let d = v as? [String: Any] ?? [:]
        return RankedStage.Score(ticks: int(d["ticks"]), grazes: int(d["grazes"]))
    }

    static func status() async throws -> Status {
        let d = try await call("rankedGetStatus")
        return Status(rating: int(d["rating"]), games: int(d["games"]), wins: int(d["wins"]), losses: int(d["losses"]),
                      draws: int(d["draws"]), best: int(d["best"]), rank: d["rank"] as? String ?? "silver")
    }

    /// 待ち行列に入る。すぐ決まれば対戦の ID、まだなら nil(rq/{uid}/m を待つ)
    static func join() async throws -> String? {
        try await call("rankedJoinQueue")["matchId"] as? String
    }

    static func leave() async { _ = try? await call("rankedLeaveQueue") }

    /// 相手が見つからなかった: ボット戦を始める(直前に人と決まっていれば、その ID だけが返る)
    static func bot() async throws -> (id: String, match: Match?) {
        let lang = Locale.preferredLanguages.first ?? "en"
        let d = try await call("rankedStartBot", ["lang": lang])
        guard let id = d["matchId"] as? String else { throw Failure.broken }
        guard let seed = d["seed"] as? NSNumber, let start = d["startAt"] as? NSNumber, let o = d["opponent"] as? [String: Any],
              let replay = d["replay"] as? String, let moves = Replay(encoded: replay)?.moves else { return (id, nil) }
        let opp = Opponent(name: o["name"] as? String ?? "", rating: int(o["rating"]), title: o["title"] as? String)
        return (id, Match(id: id, seed: seed.uint32Value, startAt: start.doubleValue, opponent: opp, opponentUid: nil, botMoves: moves))
    }

    /// 人同士の対戦の情報を読む(サーバーが書き終えるまで少し待つ)
    static func liveMatch(id: String, myUid: String) async throws -> Match {
        let ref = Backend.database.reference(withPath: "rm/\(id)/meta")
        for _ in 0..<20 {
            let snap = try await ref.getData()
            if let d = snap.value as? [String: Any], let seed = d["seed"] as? NSNumber, let start = d["startAt"] as? NSNumber,
               let players = d["players"] as? [String: Any], let (uid, p) = players.first(where: { $0.key != myUid }), let o = p as? [String: Any] {
                return Match(id: id, seed: seed.uint32Value, startAt: start.doubleValue,
                             opponent: Opponent(name: o["name"] as? String ?? "", rating: int(o["rating"]), title: o["title"] as? String),
                             opponentUid: uid, botMoves: nil)
            }
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        throw Failure.broken
    }

    /// 自分の待ち行列に、対戦が決まったら呼ぶ。返り値の handle で止める
    static func observeQueue(uid: String, onMatch: @escaping (String) -> Void) -> DatabaseHandle {
        Backend.database.reference(withPath: "rq/\(uid)/m").observe(.value) { snap in
            if let id = snap.value as? String { onMatch(id) }
        }
    }
    static func stopQueue(uid: String, handle: DatabaseHandle) {
        Backend.database.reference(withPath: "rq/\(uid)/m").removeObserver(withHandle: handle)
    }

    /// サーバーの時計とのずれ(ミリ秒)。サーバーの時刻 = 端末の時刻 + ずれ
    static func serverOffset() async -> Double {
        let ref = Backend.database.reference(withPath: ".info/serverTimeOffset")
        return await withCheckedContinuation { cont in
            ref.observeSingleEvent(of: .value) { snap in cont.resume(returning: (snap.value as? NSNumber)?.doubleValue ?? 0) }
        }
    }

    // MARK: 対戦中の位置

    static func sendPosition(match: String, uid: String, x: Double, y: Double, tick: Int, dead: Bool) {
        var v: [String: Any] = ["x": (x * 10).rounded() / 10, "y": (y * 10).rounded() / 10, "t": tick]
        if dead { v["dead"] = true }
        Backend.database.reference(withPath: "rm/\(match)/p/\(uid)").setValue(v)
    }

    static func observeOpponent(match: String, uid: String, onUpdate: @escaping (Double, Double, Int, Bool) -> Void) -> DatabaseHandle {
        Backend.database.reference(withPath: "rm/\(match)/p/\(uid)").observe(.value) { snap in
            guard let d = snap.value as? [String: Any] else { return }
            onUpdate((d["x"] as? NSNumber)?.doubleValue ?? 180, (d["y"] as? NSNumber)?.doubleValue ?? 459,
                     int(d["t"]), (d["dead"] as? Bool) ?? false)
        }
    }
    static func stopOpponent(match: String, uid: String, handle: DatabaseHandle) {
        Backend.database.reference(withPath: "rm/\(match)/p/\(uid)").removeObserver(withHandle: handle)
    }

    // MARK: 結果

    /// 記録を送る。決まれば結果、相手を待つなら nil
    static func submit(match: String, moves: [Move]) async throws -> Result? {
        let d = try await call("rankedSubmitRun", ["matchId": match, "replay": Replay(moves: moves).encoded()])
        return result(from: d)
    }

    static func result(from d: [String: Any]) -> Result? {
        guard (d["pending"] as? Bool) == false, let o = Result.Outcome(rawValue: d["result"] as? String ?? "") else { return nil }
        return Result(outcome: o, me: score(d["me"]), opp: score(d["opp"]), ratingBefore: int(d["ratingBefore"]),
                      ratingAfter: int(d["ratingAfter"]), rank: d["rank"] as? String ?? "silver")
    }

    /// 人同士の対戦で、相手の記録が届いて結果が決まるのを待つ(Firestore の対戦の記録を見張る)
    static func listenResult(match: String, uid: String, onResult: @escaping (Result) -> Void) -> ListenerRegistration {
        Firestore.firestore().document("rankedMatches/\(match)").addSnapshotListener { snap, _ in
            guard let m = snap?.data(), m["status"] as? String == "done",
                  let ch = (m["changes"] as? [String: Any])?[uid] as? [String: Any] else { return }
            let results = m["results"] as? [String: Any] ?? [:]
            let players = m["players"] as? [String] ?? []
            let oppUid = players.first { $0 != uid }
            let r = int(ch["result"]) == 1 ? Result.Outcome.win : (ch["result"] as? NSNumber)?.doubleValue == 0.5 ? .draw : .lose
            let after = int(ch["after"])
            onResult(Result(outcome: r, me: score(results[uid]), opp: score(oppUid.flatMap { results[$0] }),
                            ratingBefore: int(ch["before"]), ratingAfter: after, rank: rankOf(after)))
        }
    }

    /// サーバーの rankOf と同じ帯
    static func rankOf(_ rating: Int) -> String {
        switch rating {
        case 1600...: return "master"
        case 1450...: return "diamond"
        case 1300...: return "platinum"
        case 1150...: return "gold"
        case 1000...: return "silver"
        default: return "bronze"
        }
    }
}
