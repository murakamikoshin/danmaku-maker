import SwiftUI
import DanmakuCore

extension Emitter {
    /// パターンごとの初期値（試作の DEF と同じ）
    static func make(_ t: Pattern, end: Double) -> Emitter {
        switch t {
        case .ring: return Emitter(t: t, e: end, i: 1, c: 16, v: 2, r: 6)
        case .spiral: return Emitter(t: t, e: end, i: 0.1, c: 3, v: 2, r: 11)
        case .aim: return Emitter(t: t, e: end, i: 0.8, c: 5, v: 3, r: 40)
        case .rain: return Emitter(t: t, y: 0, e: end, i: 0.25, c: 2, v: 2, r: 0)
        case .sweep: return Emitter(t: t, e: end, i: 0.15, c: 5, v: 2.5, r: 60)
        }
    }

    /// パターンを変えたとき、位置・タイミング・色は残して、弾の設定だけ初期値に戻す
    mutating func changePattern(to p: Pattern) {
        let d = Emitter.make(p, end: e)
        t = p; i = d.i; c = d.c; v = d.v; r = d.r
    }
}

struct Draft: Codable, Equatable {
    var name = ""
    var authorName = ""
    var mode: Mode = .survive
    var duration = 20
    var bossHp = 400
    var bossMove = 1
    var emitters: [Emitter] = [Emitter.make(.spiral, end: 20)]
}

@MainActor
final class EditorModel: ObservableObject {
    static let draftKey = "editor.draft.v1"
    static let maxName = 20
    static let maxAuthor = 12

    @Published var draft: Draft
    /// テストプレイでクリアしたときのステージとリプレイ。内容が変わると一致しなくなり、確認は自動でリセットされる
    @Published private(set) var verifiedStage: Stage?
    @Published private(set) var clearReplay: Replay?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: EditorModel.draftKey),
           let d = try? JSONDecoder().decode(Draft.self, from: data) {
            draft = d
        } else {
            draft = Draft()
        }
    }

    var stage: Stage {
        Stage(name: draft.name, mode: draft.mode, durationSec: draft.duration,
              bossHp: draft.mode == .boss ? draft.bossHp : nil,
              bossMove: draft.mode == .boss ? draft.bossMove : nil,
              emitters: draft.emitters).sanitized()
    }

    var isVerified: Bool { verifiedStage != nil && verifiedStage == stage }
    var durations: [Int] { Stage.durations[draft.mode]! }
    var canAdd: Bool { draft.emitters.count < DanmakuConfig.maxEmitters }

    func save() {
        if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: EditorModel.draftKey) }
    }

    func setMode(_ m: Mode) {
        guard m != draft.mode else { return }
        draft.mode = m
        if !durations.contains(draft.duration) { setDuration(durations[1]) }
    }

    /// 時間を変えたとき、「最後まで」の発射台は新しい終わりに追従する
    func setDuration(_ n: Int) {
        let old = Double(draft.duration)
        for i in draft.emitters.indices where draft.emitters[i].e >= old { draft.emitters[i].e = Double(n) }
        draft.duration = n
    }

    func addEmitter() {
        guard canAdd else { return }
        draft.emitters.append(Emitter.make(.ring, end: Double(draft.duration)))
    }

    func removeEmitter(at index: Int) {
        guard draft.emitters.count > 1, draft.emitters.indices.contains(index) else { return }
        draft.emitters.remove(at: index)
    }

    /// 投稿には、ステージ名と作者名が必要
    var canPublish: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.authorName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 投稿が済んだら、下書きと確認状態を空にして次のステージを作れるようにする
    func published() {
        let author = draft.authorName
        draft = Draft()
        draft.authorName = author
        verifiedStage = nil
        clearReplay = nil
    }

    func markVerified(stage: Stage, replay: Replay) {
        verifiedStage = stage
        clearReplay = replay
    }
}
