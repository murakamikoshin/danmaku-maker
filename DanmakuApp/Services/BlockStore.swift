import Foundation

/// ブロックした作者。端末に保存し、ブロック中の作者のステージは一覧に出さない
@MainActor
final class BlockStore: ObservableObject {
    private let key = "blocked.authors.v1"
    @Published private(set) var blocked: [String: String]   // uid -> 作者名

    init() {
        blocked = (UserDefaults.standard.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    func isBlocked(_ uid: String) -> Bool { blocked[uid] != nil }

    func block(uid: String, name: String) {
        guard !uid.isEmpty else { return }
        blocked[uid] = name
        UserDefaults.standard.set(blocked, forKey: key)
    }

    /// 自分が通報したステージ(その場で、自分の一覧からは消す。ほかの人には、通報が集まるまで出る)
    private let reportedKey = "reported.stages.v1"
    /// 通報した順に並べる(古いものから捨てて、500件まで覚える)
    @Published private(set) var reportedStages: [String] = UserDefaults.standard.stringArray(forKey: "reported.stages.v1") ?? []

    func isHiddenStage(_ id: String) -> Bool { reportedStages.contains(id) }

    func hideReported(stageID: String) {
        guard !reportedStages.contains(stageID) else { return }
        reportedStages.append(stageID)
        if reportedStages.count > 500 { reportedStages.removeFirst(reportedStages.count - 500) }
        UserDefaults.standard.set(reportedStages, forKey: reportedKey)
    }

    func unblock(uid: String) {
        blocked[uid] = nil
        UserDefaults.standard.set(blocked, forKey: key)
    }
}
