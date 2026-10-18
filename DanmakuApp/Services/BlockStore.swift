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

    func unblock(uid: String) {
        blocked[uid] = nil
        UserDefaults.standard.set(blocked, forKey: key)
    }
}
