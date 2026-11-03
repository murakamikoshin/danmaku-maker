import DanmakuCore
import Foundation
import SwiftUI

/// スワイプ弾幕の 1 プレイの進行（状態・点数・記録）。画面（SwiftUI）と描画（SwipeScene）の間に立つ。
/// 計算は DanmakuCore の SwipeClipPlayer / SwipeScoring / SwipeFeed が持つ。サーバーが同じ手順で計算し直す。
@MainActor
final class SwipeModel: ObservableObject {
    enum Phase: Equatable { case title, starting, transition, go, playing, cleared, failed, over }

    @Published private(set) var phase: Phase = .title {
        didSet {
            // 遊んでいる間はスワイプ専用の曲、タイトルに戻ったら通常の曲
            switch phase {
            case .go, .playing, .cleared, .failed, .transition: AudioManager.shared.play(.swipe)
            case .title: AudioManager.shared.play(.menu)
            default: break
            }
        }
    }
    @Published private(set) var scoring = SwipeScoring()
    @Published private(set) var clipName = ""
    @Published private(set) var clipAuthor = ""
    @Published private(set) var clipsPlayed = 0
    @Published private(set) var result: SwipeSubmitResult?
    @Published private(set) var submitting = false
    @Published private(set) var submitError = false
    @Published var toast: String?
    /// 作者で絞り込んでいるときの作者（uid）と名前
    @Published private(set) var filterAuthor: String?
    @Published private(set) var filterAuthorName = ""
    @Published private(set) var errorKey: String?
    /// 画面に出す、いまのクリップの作者（絞り込みに使う）
    private(set) var currentAuthorUid = ""

    private(set) var player: SwipeClipPlayer?
    /// 1 ステップごとの描画用（シーンが読む）
    private(set) var playStep = 0

    private let service: SwipeService
    private var run: SwipeRunStart?
    private var pool: [SwipeFeed.Entry] = []
    private var used = Set<String>()
    private var excluded = Set<String>()
    private var records: [SwipeClipRecord] = []
    private var current = SwipeClipRecord()
    private var currentClip: SwipeService.Clip?
    private var prefetch: Task<SwipeService.Clip?, Never>?
    private var prefetchKey = ""
    private var goStepsDone = 0
    /// 自己ベスト（連続数と点数は端末にも保存）
    @Published private(set) var bestStreak: Int = UserDefaults.standard.integer(forKey: "swipe.bestStreak")
    private let handles = HandleStore.shared
    var displayName: String?

    init(service: SwipeService) { self.service = service }

    // MARK: プレイの始まり

    func begin(author: String? = nil, authorName: String = "", blocked: Set<String>, myUid: String?) async {
        guard phase == .title || phase == .over else { return }
        errorKey = nil
        phase = .starting
        do {
            let start = try await service.start(author: author)
            let pool = try await service.loadPool(version: start.poolVersion)
            run = start
            self.pool = author == nil ? pool : pool.filter { $0.author == author }
            excluded = blocked
            if author == nil, let myUid { excluded.insert(myUid) }
            filterAuthor = author
            filterAuthorName = authorName
            used = []; records = []; current = SwipeClipRecord(); scoring = SwipeScoring(); clipsPlayed = 0
            result = nil; submitError = false; submitting = false
            await nextClip()
        } catch let e as SwipeError {
            errorKey = e == .noStamina ? "swipe.error.stamina" : e == .poolEmpty ? "swipe.error.pool" : e == .authorBlocked ? "swipe.error.blocked" : "swipe.error.network"
            phase = e == .noStamina ? .title : .title
        } catch {
            errorKey = "swipe.error.network"
            phase = .title
        }
    }

    /// 次のクリップを選んで、切り替え → GO の準備をする。選べなければ（全部遊んだ）プレイ終了
    private func nextClip() async {
        guard let run else { return }
        guard let entry = SwipeFeed.pick(pool: pool, seed: run.seed, index: records.count, streak: scoring.streak, used: used, excludedAuthors: excluded) else {
            await finish(); return
        }
        phase = .transition
        let key = "\(records.count)|\(scoring.streak)|\(entry.id)"
        let clip: SwipeService.Clip?
        if let p = prefetch, prefetchKey == key { clip = await p.value } else { clip = await service.clip(id: entry.id) }
        prefetch = nil
        guard let clip else {
            // ステージが読めない（消された・通信の失敗）。このクリップは遊べないので、プレイをここで終える
            errorKey = "swipe.error.network"
            await finish(); return
        }
        used.insert(entry.id)
        currentClip = clip
        clipName = clip.name
        clipAuthor = clip.authorName
        currentAuthorUid = entry.author
        var sc = scoring
        player = SwipeClipPlayer(stage: clip.stage, at: clip.at, scoring: &sc)
        scoring = sc
        current = SwipeClipRecord()
        playStep = 0; goStepsDone = 0
        phase = .go
        startPrefetch(after: records.count + 1, streak: scoring.streak + 1)
    }

    /// 次のクリップを先に読んでおく（クリアした場合の連続で選ぶ）
    private func startPrefetch(after index: Int, streak: Int) {
        guard let run else { return }
        var u = used
        if let id = currentClip?.id { u.insert(id) }
        guard let next = SwipeFeed.pick(pool: pool, seed: run.seed, index: index, streak: streak, used: u, excludedAuthors: excluded) else { return }
        prefetchKey = "\(index)|\(streak - 1)|\(next.id)"
        let svc = service
        prefetch = Task { await svc.clip(id: next.id) }
    }

    // MARK: 1 ステップ（シーンが固定間隔で呼ぶ）

    /// GO の間（弾は止まっている）。60 ステップで終わる
    func stepGo(_ move: Move) {
        guard phase == .go, player != nil else { return }
        player!.nudge(move)
        current.go.append(move)
        goStepsDone += 1
        if goStepsDone >= SwipeClip.goSteps { phase = .playing }
    }

    /// プレイ中の 1 ステップ。起きたことを返す（シーンが演出に使う）
    func stepPlay(_ move: Move) -> SwipeClipPlayer.Events? {
        guard phase == .playing, player != nil else { return nil }
        var sc = scoring
        let ev = player!.advance(move, scoring: &sc)
        current.moves.append(move)
        playStep = player!.step
        if !ev.grazes.isEmpty || ev.bomb != nil || ev.end != nil || sc.combo != scoring.combo { objectWillChange.send() }
        scoring = sc
        switch ev.end {
        case .hit?:
            phase = .failed
            record(skipped: false)
        case .cleared?:
            phase = .cleared
            clipsPlayed += 1
            record(skipped: false)
            if scoring.streak > bestStreak { bestStreak = scoring.streak; UserDefaults.standard.set(bestStreak, forKey: "swipe.bestStreak") }
        case nil: break
        }
        return ev
    }

    private func record(skipped: Bool) { current.skipped = skipped; records.append(current) }

    // MARK: 操作

    /// クリア画面から次へ（自動・上スワイプ・タップ）
    func advanceAfterResult() async {
        switch phase {
        case .cleared, .go, .playing: await nextClip()
        case .failed: await finish()
        default: break
        }
    }

    func finish() async {
        guard let run else { phase = .title; return }
        phase = .over
        player = nil
        await submit(run: run)
    }

    func submit(run: SwipeRunStart? = nil) async {
        guard let run = run ?? self.run else { return }
        submitting = true; submitError = false
        defer { submitting = false }
        do {
            result = try await service.submit(runId: run.runId, clips: records, handle: handles.handle, name: displayName)
        } catch {
            submitError = true
        }
        await service.refresh()
    }

    func clearError() { errorKey = nil }

    func backToTitle() { phase = .title; player = nil; result = nil }

    var language: ScoreFormat.Language { SwipePalette.scoreStyle }
}
