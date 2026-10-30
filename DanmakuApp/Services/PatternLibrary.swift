import DanmakuCore
import Foundation

/// 弾幕作成モードで作った弾幕。端末に保存する(ステージに使うと、軌道はそのステージのデータに入る)
struct CustomPattern: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// 描いた軌道(PathData: 発射位置を原点にした点を 0.1 秒ごとに並べたもの)
    var path: [Double]
    /// 同時に出す数(等間隔に回して出す)
    var copies: Int
    /// 進む速さ(2 で、描いたとおりの速さ)
    var speed: Double

    static let maxNameLength = 10
    static let copiesRange = 1...12

    /// ステージの発射台に入れるときの初期設定
    func emitter(end: Double) -> Emitter {
        Emitter(t: .custom, e: end, i: 1.2, c: copies, v: speed, r: 0, path: path)
    }
}

@MainActor
final class PatternLibrary: ObservableObject {
    static let shared = PatternLibrary()
    static let maxItems = 30
    private let key = "patternlibrary.v1"
    @Published private(set) var items: [CustomPattern]

    init(defaults: UserDefaults = .standard) {
        items = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode([CustomPattern].self, from: $0) } ?? []
    }

    var isFull: Bool { items.count >= Self.maxItems }

    /// 追加または上書き。いっぱいのときは false
    @discardableResult
    func save(_ p: CustomPattern) -> Bool {
        var q = p
        q.name = String(q.name.trimmingCharacters(in: .whitespaces).prefix(CustomPattern.maxNameLength))
        guard let clean = PathData.sanitized(q.path) else { return false }
        q.path = clean
        q.copies = min(CustomPattern.copiesRange.upperBound, max(CustomPattern.copiesRange.lowerBound, q.copies))
        q.speed = min(4, max(1, q.speed))
        if let i = items.firstIndex(where: { $0.id == q.id }) { items[i] = q }
        else if isFull { return false }
        else { items.insert(q, at: 0) }
        persist()
        return true
    }

    func delete(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let d = try? JSONEncoder().encode(items) { UserDefaults.standard.set(d, forKey: key) }
    }
}
