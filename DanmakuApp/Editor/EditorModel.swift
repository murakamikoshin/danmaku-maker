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
        case .sideL, .sideR: return Emitter(t: t, e: end, i: 0.5, c: 2, v: 2.5, r: 10)
        case .corner: return Emitter(t: t, e: end, i: 1.2, c: 3, v: 2.5, r: 30)
        case .homing: return Emitter(t: t, e: end, i: 1.6, c: 2, v: 1.6, r: 45)
        case .flower: return Emitter(t: t, e: end, i: 0.9, c: 30, v: 2, r: 6)
        case .star: return Emitter(t: t, e: end, i: 0.9, c: 30, v: 2, r: 6)
        case .heart: return Emitter(t: t, e: end, i: 1.0, c: 36, v: 2, r: 0)
        case .beam: return Emitter(t: t, e: end, i: 0.9, c: 8, v: 2, r: 0)
        case .cross: return Emitter(t: t, e: end, i: 0.4, c: 8, v: 1.8, r: 8)
        case .accel: return Emitter(t: t, e: end, i: 0.8, c: 5, v: 2.2, r: 50)
        case .bounce: return Emitter(t: t, e: end, i: 0.7, c: 4, v: 2.4, r: 40)
        case .stopgo: return Emitter(t: t, e: end, i: 1.0, c: 5, v: 2.4, r: 60)
        case .split: return Emitter(t: t, e: end, i: 1.1, c: 3, v: 2.4, r: 50)
        case .timed: return Emitter(t: t, e: end, i: 1.6, c: 16, v: 2.0, r: 8)
        case .angelTwin: return Emitter(t: t, e: end, i: 0.1, c: 4, v: 2.3, r: 10)
        case .angelFeather: return Emitter(t: t, e: end, i: 0.5, c: 7, v: 3.8, r: 0)
        case .angelHalo: return Emitter(t: t, e: end, i: 2.0, c: 22, v: 4.2, r: 0)
        case .angelCross: return Emitter(t: t, e: end, i: 2.0, c: 1, v: 2.0, r: 0)
        case .angelParadise: return Emitter(t: t, e: end, i: 1.2, c: 23, v: 1.05, r: 29)
        case .kitsuneLanterns: return Emitter(t: t, e: end, i: 0.1, c: 9, v: 3.2, r: 0)
        case .kitsuneBarrier: return Emitter(t: t, e: end, i: 0.65, c: 12, v: 2.0, r: 0)
        case .kitsuneSunshower: return Emitter(t: t, e: end, i: 0.05, c: 8, v: 2.2, r: 0)
        case .kitsuneTorii: return Emitter(t: t, e: end, i: 0.45, c: 22, v: 1.4, r: 60)
        case .kitsuneDance: return Emitter(t: t, e: end, i: 0.05, c: 9, v: 2.2, r: 0)
        default:
            // 広告で解放するパターン: 表の初期値
            let d = t.recipeDefaults ?? (i: 1.0, c: 8, v: 2.0, r: 0)
            return Emitter(t: t, e: end, i: d.i, c: d.c, v: d.v, r: d.r)
        }
    }

    /// パターンを変えたとき、位置・タイミング・色は残して、弾の設定だけ初期値に戻す
    mutating func changePattern(to p: Pattern) {
        let d = Emitter.make(p, end: e)
        t = p; i = d.i; c = d.c; v = d.v; r = d.r
        if p != .custom { path = nil }
        if !canRotate { a = 0 }
    }
}

/// 連戦の1つの場面(編集中の形)
struct DraftWave: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: WaveKind
    var duration: Int
    var bossHp = 400
    var bossMove = 1
    var warning = true
    var defeat = DefeatEffect.standard.rawValue
    /// ボスの大きさ(0=小 1=中 2=大)と見た目、雑魚の姿の大きさ(nil は出さない)と見た目。なければ標準
    var bossSize: Int?
    var bossLook: Int?
    var mooks: Int?
    var mookLook: Int?
    /// ボスの位置(動きの中心。画面に対する割合。nil は標準)
    var bossX: Double?
    var bossY: Double?
    /// 覚醒する段階(2 か 3)。nil は覚醒しない
    var awaken: Int?
    var emitters: [Emitter]

    init(kind: WaveKind) {
        self.kind = kind
        duration = kind == .boss ? 60 : 20
        warning = kind == .boss
        emitters = [Emitter.make(kind == .boss ? .ring : .swirl, end: Double(kind == .boss ? 60 : 20))]
    }

    var wave: Wave {
        Wave(kind: kind, durationSec: duration, bossHp: kind == .boss ? bossHp : nil, bossMove: kind == .boss ? bossMove : nil,
             emitters: emitters, warning: kind == .boss && warning ? true : nil, defeat: kind == .boss ? defeat : nil,
             bossSize: bossSize, mooks: mooks, bossLook: bossLook, mookLook: mookLook, awaken: kind == .boss ? awaken : nil,
             bossX: kind == .boss ? bossX : nil, bossY: kind == .boss ? bossY : nil)
    }

    var durations: [Int] { kind == .boss ? Wave.bossDurations : Wave.surviveDurations }

    mutating func setKind(_ k: WaveKind) {
        guard k != kind else { return }
        kind = k
        if !durations.contains(duration) { duration = k == .boss ? 60 : 20 }
        warning = k == .boss
        for i in emitters.indices where k == .survive { emitters[i].ph = 0; emitters[i].p = 0 }
    }

    /// 時間を変えたとき、「最後まで」の発射台は新しい終わりに追従する
    mutating func setDuration(_ n: Int) {
        let old = Double(duration)
        for i in emitters.indices where emitters[i].e >= old { emitters[i].e = Double(n) }
        duration = n
    }
}

struct Draft: Codable, Equatable {
    var name = ""
    var authorName = ""
    var mode: Mode = .survive
    var duration = 20
    var bossHp = 400
    var bossMove = 1
    /// 自機の耐久。標準はライフ1(1回当たったら終わり)
    var lifeMode: LifeMode = .lives
    var lifeCount = 1
    /// 選んだ BGM の番号(nil はモードごとの標準)
    var bgm: Int?
    /// ステージの見た目(作者が決める。遊ぶ全員に、そう見える)
    var themeBullets: Theme = .classic
    var themeBackground: Theme = .classic
    var themeShip: Theme = .classic
    /// 発射位置の予告(点線)を出さない(生き残りだけ)
    var hideMarkers = false
    /// 世界のステージ一覧のプレビュー: 開始秒(0 は最初から)と、見せない設定(ネタバレ防止)
    var previewStart = 0
    var noPreview = false
    /// じぶんの画像を使うか(この端末で遊ぶときだけ。投稿すると外れる)
    var customBoss = false
    var customBullet = false
    var customShip = false
    var emitters: [Emitter] = [Emitter.make(.swirl, end: 20)]
    /// 連戦の場面(モードが連戦のとき)
    var waves: [DraftWave] = [DraftWave(kind: .survive), DraftWave(kind: .boss)]
    /// ボス戦・ダメージ勝負の、開始前の警告と、撃破の演出(DefeatEffect の番号)
    var bossWarning = false
    var bossDefeat = DefeatEffect.standard.rawValue
    /// 自機の撃ち方(ステージごと。遊ぶ全員が、この撃ち方になる)
    var shot = ShotType.standard
    /// 毎日のごほうびの演出(Reward の番号。種類ごとに1つまで。遊ぶ全員に出る)
    var rewardFx: [Int] = []
    /// ボスの大きさ・見た目、雑魚の姿の大きさ(nil は出さない)・見た目
    var bossSize = 1
    var bossLook = 0
    var mooks: Int?
    var mookLook = 0
    /// ボスの位置(動きの中心。画面に対する割合。nil は標準)
    var bossX: Double?
    var bossY: Double?
    /// 覚醒する段階(2 か 3)。nil は覚醒しない
    var awaken: Int?

    init() {}

    /// 前のバージョンで保存した下書き(耐久の項目がない)も読めるようにする
    init(from decoder: Decoder) throws {
        enum K: String, CodingKey { case name, authorName, mode, duration, bossHp, bossMove, lifeMode, lifeCount, bgm, emitters, themeBullets, themeBackground, themeShip, hideMarkers, customBoss, customBullet, customShip, waves, bossWarning, bossDefeat, shot, rewardFx, bossSize, bossLook, mooks, mookLook, awaken, previewStart, noPreview, bossX, bossY }
        let c = try decoder.container(keyedBy: K.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        mode = try c.decodeIfPresent(Mode.self, forKey: .mode) ?? .survive
        duration = try c.decodeIfPresent(Int.self, forKey: .duration) ?? 20
        bossHp = try c.decodeIfPresent(Int.self, forKey: .bossHp) ?? 400
        bossMove = try c.decodeIfPresent(Int.self, forKey: .bossMove) ?? 1
        lifeMode = try c.decodeIfPresent(LifeMode.self, forKey: .lifeMode) ?? .lives
        lifeCount = try c.decodeIfPresent(Int.self, forKey: .lifeCount) ?? 1
        bgm = try c.decodeIfPresent(Int.self, forKey: .bgm)
        themeBullets = (try? c.decodeIfPresent(Theme.self, forKey: .themeBullets)) ?? .classic
        themeBackground = (try? c.decodeIfPresent(Theme.self, forKey: .themeBackground)) ?? .classic
        themeShip = (try? c.decodeIfPresent(Theme.self, forKey: .themeShip)) ?? .classic
        hideMarkers = try c.decodeIfPresent(Bool.self, forKey: .hideMarkers) ?? false
        previewStart = try c.decodeIfPresent(Int.self, forKey: .previewStart) ?? 0
        noPreview = try c.decodeIfPresent(Bool.self, forKey: .noPreview) ?? false
        customBoss = try c.decodeIfPresent(Bool.self, forKey: .customBoss) ?? false
        customBullet = try c.decodeIfPresent(Bool.self, forKey: .customBullet) ?? false
        customShip = try c.decodeIfPresent(Bool.self, forKey: .customShip) ?? false
        waves = try c.decodeIfPresent([DraftWave].self, forKey: .waves) ?? [DraftWave(kind: .survive), DraftWave(kind: .boss)]
        bossWarning = try c.decodeIfPresent(Bool.self, forKey: .bossWarning) ?? false
        bossDefeat = try c.decodeIfPresent(Int.self, forKey: .bossDefeat) ?? DefeatEffect.standard.rawValue
        shot = (try? c.decodeIfPresent(ShotType.self, forKey: .shot)) ?? .standard
        rewardFx = (try? c.decodeIfPresent([Int].self, forKey: .rewardFx)) ?? []
        bossSize = try c.decodeIfPresent(Int.self, forKey: .bossSize) ?? 1
        bossLook = try c.decodeIfPresent(Int.self, forKey: .bossLook) ?? 0
        mooks = try c.decodeIfPresent(Int.self, forKey: .mooks)
        mookLook = try c.decodeIfPresent(Int.self, forKey: .mookLook) ?? 0
        awaken = try c.decodeIfPresent(Int.self, forKey: .awaken)
        bossX = try c.decodeIfPresent(Double.self, forKey: .bossX)
        bossY = try c.decodeIfPresent(Double.self, forKey: .bossY)
        emitters = try c.decodeIfPresent([Emitter].self, forKey: .emitters) ?? [Emitter.make(.swirl, end: 20)]
    }

    /// 遊べる・投稿できるステージのデータ(丸めた内容)。じぶんの画像の設定は、含まれない
    var stage: Stage {
        let isSeq = mode == .sequence
        return Stage(name: name, mode: mode, durationSec: isSeq ? 0 : duration,
              bossHp: mode == .boss ? bossHp : nil,
              bossMove: (mode == .boss || mode == .damage) ? bossMove : nil,
              emitters: isSeq ? [] : emitters,
              lifeMode: lifeMode, lifeCount: lifeCount, bgm: bgm,
              themeBullets: themeBullets, themeBackground: themeBackground, themeShip: themeShip,
              hideMarkers: hideMarkers ? true : nil,
              waves: isSeq ? waves.map(\.wave) : nil,
              bossWarning: bossWarning ? true : nil,
              bossDefeat: mode == .boss ? bossDefeat : nil,
              bossSize: bossSize, mooks: isSeq ? nil : mooks, bossLook: bossLook, mookLook: mookLook,
              shot: shot, rewardFx: rewardFx, awaken: awaken,
              previewStart: previewStart > 0 ? previewStart : nil, noPreview: noPreview ? true : nil,
              bossX: bossX, bossY: bossY).sanitized()
    }

    /// このステージで使う、じぶんの画像の設定(この端末で遊ぶときだけ)
    var customImages: CustomImageChoice { CustomImageChoice(boss: customBoss, bullet: customBullet, ship: customShip) }
}

/// じぶんの画像を、どこに使うか
struct CustomImageChoice: Equatable {
    var boss = false
    var bullet = false
    var ship = false
    static let none = CustomImageChoice()
}

@MainActor
final class EditorModel: ObservableObject {
    static let maxName = 20
    static let maxAuthor = 12

    @Published var draft: Draft
    /// エディタで試聴中の BGM の番号(テストプレイから戻ったとき、続きを流すため。画面の更新には使わない)
    var previewingBGM: Int?
    /// 「元に戻す」の戻り先。画面を開いたとき、またはクリア・投稿したときの内容
    private var baseline: Draft
    private var entry: SavedStage
    private let store: LocalStageStore

    init(entry: SavedStage, store: LocalStageStore = .shared) {
        self.entry = entry
        self.store = store
        var d = entry.draft
        // 作者名は全ステージ共通
        if !AuthorName.current.isEmpty { d.authorName = AuthorName.current }
        draft = d
        baseline = d
    }

    var canRevert: Bool { draft != baseline }
    func revert() { draft = baseline }

    var entryID: UUID { entry.id }
    var stage: Stage { draft.stage }

    /// テストプレイでクリアした内容と、いまの内容が同じか(変えると、自動で外れる)
    var isVerified: Bool { entry.verifiedStage.map { $0.samePlay(as: stage) } ?? false }
    var clearReplay: Replay? { entry.verifiedReplay.flatMap { Replay(encoded: $0) } }
    /// いまの内容を、すでに投稿したか
    var isPublished: Bool { entry.publishedStage != nil && entry.publishedStage == stage && entry.publishedID != nil }
    var publishedID: String? { isPublished ? entry.publishedID : nil }

    var durations: [Int] { Stage.durations[draft.mode] ?? [] }
    var canAdd: Bool { draft.emitters.count < DanmakuConfig.maxEmitters }

    /// 自動保存(内容が変わるたびに、マイステージへ書く)
    func save() {
        AuthorName.set(draft.authorName)
        entry.draft = draft
        store.update(entry)
    }

    func setMode(_ m: Mode) {
        guard m != draft.mode else { return }
        draft.mode = m
        if m == .sequence { return }   // 連戦の長さは、場面の合計
        // 選べない長さになったら、標準(生き残りは20秒、ボス戦とダメージ勝負は60秒)にする
        if !durations.contains(draft.duration) { setDuration(m == .survive ? 20 : 60) }
        if m != .survive && m != .sequence { draft.hideMarkers = false }   // 予告を出さない設定は、生き残りと連戦(の雑魚の場面)だけ
    }

    /// 耐久の方式を変えたとき、数はその方式の標準(ライフ3 / HP10)にする。ライフ1の標準に戻したいときは数を1にする
    func setLifeMode(_ m: LifeMode) {
        guard m != draft.lifeMode else { return }
        draft.lifeMode = m
        draft.lifeCount = m == .lives ? 3 : 10
    }

    /// 時間を変えたとき、「最後まで」の発射台は新しい終わりに追従する(時間無制限=0 のときは、長い時間の終わりにしておく)
    func setDuration(_ n: Int) {
        let old = Double(draft.duration == 0 ? Stage.unlimitedCapSec : draft.duration)
        let new = Double(n == 0 ? Stage.unlimitedCapSec : n)
        for i in draft.emitters.indices where draft.emitters[i].e >= old || draft.emitters[i].e >= 180 { draft.emitters[i].e = min(new, 180) }
        draft.duration = n
    }

    // MARK: 連戦の場面

    var canAddWave: Bool { draft.waves.count < Wave.maxWaves }

    func addWave(_ kind: WaveKind) {
        guard canAddWave else { return }
        draft.waves.append(DraftWave(kind: kind))
    }

    func removeWave(_ id: UUID) {
        guard draft.waves.count > 1 else { return }
        draft.waves.removeAll { $0.id == id }
    }

    func moveWave(_ id: UUID, by delta: Int) {
        guard let i = draft.waves.firstIndex(where: { $0.id == id }) else { return }
        let j = i + delta
        guard draft.waves.indices.contains(j) else { return }
        draft.waves.swapAt(i, j)
    }

    /// ボスの見た目を変えるとき: キャラクター専用の技を、ふつうの放射(ring)に置き換える
    func convertCharacterPatterns() {
        for i in draft.emitters.indices where draft.emitters[i].t.bossCharacter != nil { draft.emitters[i].changePattern(to: .ring) }
    }

    func convertCharacterPatterns(inWave id: UUID) {
        guard let w = draft.waves.firstIndex(where: { $0.id == id }) else { return }
        for i in draft.waves[w].emitters.indices where draft.waves[w].emitters[i].t.bossCharacter != nil { draft.waves[w].emitters[i].changePattern(to: .ring) }
    }

    func addEmitter(toWave id: UUID) {
        guard let i = draft.waves.firstIndex(where: { $0.id == id }), draft.waves[i].emitters.count < DanmakuConfig.maxEmitters else { return }
        draft.waves[i].emitters.append(Emitter.make(.ring, end: Double(draft.waves[i].duration)))
    }

    func removeEmitter(_ index: Int, fromWave id: UUID) {
        guard let i = draft.waves.firstIndex(where: { $0.id == id }), draft.waves[i].emitters.count > 1, draft.waves[i].emitters.indices.contains(index) else { return }
        draft.waves[i].emitters.remove(at: index)
    }

    func addEmitter() {
        guard canAdd else { return }
        draft.emitters.append(Emitter.make(.ring, end: Double(min(draft.duration == 0 ? 180 : draft.duration, 180))))
    }

    func removeEmitter(at index: Int) {
        guard draft.emitters.count > 1, draft.emitters.indices.contains(index) else { return }
        draft.emitters.remove(at: index)
    }

    /// 投稿には、ステージ名と作者名が必要
    var canPublish: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.authorName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// 投稿が済んだら、投稿した内容と ID を残す(ステージは、マイステージに残る)
    func published(id: String) {
        entry.publishedStage = stage
        entry.publishedID = id
        entry.draft = draft
        baseline = draft
        store.update(entry)
    }

    func markVerified(stage: Stage, replay: Replay) {
        entry.verifiedStage = stage
        entry.verifiedReplay = replay.encoded()
        entry.draft = draft
        baseline = draft
        store.update(entry)
        objectWillChange.send()
    }
}
