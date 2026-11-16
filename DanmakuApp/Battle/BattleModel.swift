import DanmakuCore
import FirebaseAuth
import FirebaseDatabase
import FirebaseFirestore
import Foundation
import SpriteKit

/// 弾幕バトルの画面の流れ: 入口 → 相手を探す(10 秒) → 相手が決まる(3・2・1) → 対戦 → (相手を待つ) → 結果
@MainActor
final class BattleModel: ObservableObject {
    enum Phase: Equatable {
        case title
        case searching(left: Int)
        case found(countdown: Int)
        case playing
        /// 自分は落ちた。人の相手が終わるのを待っている
        case waiting
        case result(BattleService.Result)
        case failed
    }

    /// 相手を探す時間(サーバーの SEARCH_MS と同じ)
    static let searchSeconds = 10

    @Published private(set) var phase: Phase = .title {
        didSet {
            // 相手が見つかったら効果音。3・2・1 と対戦の間は、バトル専用の激しい曲(メニューのゆったりした曲のままだった)
            if case .found = phase, !{ if case .found = oldValue { return true }; return false }() { AudioManager.shared.se(.match) }
            playMusic()
        }
    }
    /// バトルのタブが見えているか。見えていないときは曲を変えない(スワイプのプレイ中に、バトルの結果でメニューの曲に変わらないように)
    private var tabVisible = true
    private func playMusic() {
        guard tabVisible else { return }
        switch phase {
        case .found, .playing, .waiting: AudioManager.shared.play(.battle)
        case .title, .searching, .result, .failed: AudioManager.shared.play(.menu)
        }
    }
    @Published private(set) var status: BattleService.Status?
    @Published private(set) var match: BattleService.Match?
    /// 相手を待っている間、「待つのをやめる」を出すか(人同士で、30秒待ったら)と、押したけれど相手がまだ遊んでいたか
    @Published private(set) var canStopWaiting = false
    @Published private(set) var opponentStillPlaying = false
    private var waitTask: Task<Void, Never>?
    /// アプリが前面にあるか(画面の scenePhase を写す。少し離れただけかを、あとで確かめるため)
    var appActive = true
    /// 下のタブでバトルの画面が見えているか。見えていない間は、対戦の画面の描画を止める
    func setVisible(_ visible: Bool) {
        tabVisible = visible
        // バトルのタブに戻ったら、いまの場面の曲にする
        if visible { playMusic() }
        // 止めるのは、相手を待つ間と結果のときだけ(3・2・1 と対戦の間はタブを移れないので触らない。カウントダウンの止め方を崩さないように)
        if !visible, phase == .waiting || isResult { scene?.isPaused = true; pausedByTab = true }
        if visible, pausedByTab { scene?.isPaused = false; pausedByTab = false }
        // 相手を探している間にほかのタブへ移ったら、探すのをやめる(見えないまま対戦が始まって負けないように)
        if !visible, case .searching = phase { cancel() }
    }
    private var pausedByTab = false
    /// 相手探しを始めた回数(取り消した古い探索が、新しい探索の待ち列の行を消さないように見分ける)
    private var searchGen = 0

    /// 前面から離れた回数(3秒の降参の判定で、どの「離れた」かを見分けるため)
    var inactiveSeq = 0
    /// 対戦中の表示: 自分の秒、相手が生きているか・落ちた秒
    @Published private(set) var myTime = 0.0
    @Published private(set) var opponentAlive = true
    @Published private(set) var opponentTime = 0.0
    private(set) var scene: GameScene?

    private var uid: String? { Auth.auth().currentUser?.uid }
    private var queueHandle: DatabaseHandle?
    private var oppHandle: DatabaseHandle?
    private var resultListener: ListenerRegistration?
    private var searchTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    /// 人の相手の、届いた最新の位置
    private var remote: (x: Double, y: Double, tick: Int, dead: Bool)?
    /// ボットの相手: 同じステージを、記録どおりに同じ歩調で進める
    private var botSim: Simulation?
    private var botDeadTick: Int?
    private var lastSent = -100
    /// 人の相手が生き残ったステップ数(サーバーが計算し終えた値)。自分がこれを越えたら、その場で勝ちとして終える
    private var opponentFinalTicks: Int?
    private var oppResultListener: ListenerRegistration?

    func loadStatus() async {
        status = try? await BattleService.status()
    }

    // MARK: 相手を探す

    func start() {
        guard let uid, phase == .title || isResult else { return }
        cleanup()
        phase = .searching(left: Self.searchSeconds)
        searchGen += 1
        let gen = searchGen
        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let id = try await BattleService.join()
                // 待ち列に入る通信の間に、やめていたら(タブを移ったなど)、入った分を抜けてから終わる(待ち列に残らないように)
                // ただし、すぐに探し直していたら(新しい探索が始まっていたら)、新しい待ち列の行を消さないように抜けない
                guard !Task.isCancelled, case .searching = self.phase else { if self.searchGen == gen { await BattleService.leave() }; return }
                if let id { await self.goLive(id: id, uid: uid); return }
            } catch { if case .searching = self.phase { self.phase = .failed }; return }
            self.queueHandle = BattleService.observeQueue(uid: uid) { [weak self] id in
                Task { @MainActor in await self?.goLive(id: id, uid: uid) }
            }
            for left in stride(from: Self.searchSeconds, through: 1, by: -1) {
                if Task.isCancelled { return }
                guard case .searching = self.phase else { return }
                self.phase = .searching(left: left)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            guard case .searching = self.phase else { return }
            await self.goBot(uid: uid)
        }
    }

    /// 探すのをやめる
    func cancel() {
        cleanup()
        phase = .title
        Task { await BattleService.leave() }
    }

    private var isResult: Bool { if case .result = phase { return true }; return phase == .failed }

    private func stopQueue() {
        if let h = queueHandle, let uid { BattleService.stopQueue(uid: uid, handle: h) }
        queueHandle = nil
    }

    private func goLive(id: String, uid: String) async {
        guard case .searching = phase else { return }
        stopQueue()
        searchTask?.cancel()
        phase = .found(countdown: 3)
        do {
            let m = try await BattleService.liveMatch(id: id, myUid: uid)
            await begin(m)
        } catch { phase = .failed }
    }

    private func goBot(uid: String) async {
        stopQueue()
        phase = .found(countdown: 3)
        do {
            let r = try await BattleService.bot()
            if let m = r.match { await begin(m) } else { await begin(try await BattleService.liveMatch(id: r.id, myUid: uid)) }
        } catch { phase = .failed }
    }

    // MARK: 対戦

    private func begin(_ m: BattleService.Match) async {
        match = m
        let offset = await BattleService.serverOffset()
        let stage = RankedStage.stage(seed: m.seed)
        let loadout = CosmeticsStore.shared.forPlay(stage: stage, isTest: false)
        let scene = GameScene(stage: stage, loadout: loadout, effects: CosmeticsStore.shared.effectsOn)
        if m.botMoves != nil { botSim = Simulation(stage: stage) }
        remote = nil; botDeadTick = nil; opponentAlive = true; opponentTime = 0; myTime = 0; lastSent = -100
        scene.ghostPosition = { [weak self] in self?.ghost() }
        scene.onStep = { [weak self] sim in self?.step(sim) }
        scene.onTime = { [weak self] t in self?.myTime = max(0, t) }
        scene.onFinish = { [weak self] sim, moves in Task { @MainActor in await self?.finish(sim: sim, moves: moves) } }
        scene.isPaused = true
        scene.holding = true
        opponentFinalTicks = nil
        self.scene = scene
        if let opp = m.opponentUid, let uid {
            oppHandle = BattleService.observeOpponent(match: m.id, uid: opp) { [weak self] x, y, t, dead in
                Task { @MainActor in
                    guard let self else { return }
                    self.remote = (x, y, t, dead)
                    if dead && self.opponentAlive { self.opponentAlive = false; self.opponentTime = Double(t) / 120 }
                    else if !dead { self.opponentTime = Double(t) / 120 }
                }
            }
            BattleService.sendPosition(match: m.id, uid: uid, x: DanmakuConfig.width / 2, y: DanmakuConfig.height * 0.85, tick: 0, dead: false)
            oppResultListener = BattleService.listenOpponentTicks(match: m.id, opponent: opp) { [weak self] t in
                Task { @MainActor in self?.opponentFinalTicks = t }
            }
        }
        // サーバーの時計で決めた時刻に、二人同時に始める
        startTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let leftMs = m.startAt - (Date().timeIntervalSince1970 * 1000 + offset)
                if leftMs <= 0 { break }
                self.phase = .found(countdown: max(1, Int(ceil(leftMs / 1000))))
                try? await Task.sleep(nanoseconds: UInt64(min(leftMs, 200) * 1_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.phase = .playing
            self.scene?.holding = false
            self.scene?.isPaused = false
        }
    }

    /// 自機が 1 ステップ進むごと: ボットを同じ歩調で進める・自分の位置を送る(1 秒に 10 回)
    private func step(_ sim: Simulation) {
        // ボットは、自分と同じ歩調で 1 ステップ進める(その場で書き換えて、毎回の複製を避ける)
        if let moves = match?.botMoves, botSim != nil, botDeadTick == nil {
            let t = botSim!.tick
            if botSim!.outcome == .playing && t < moves.count { botSim!.step(moves[t]) }
            let now = botSim!.tick
            // 記録が尽きたか、当たったら、その時点で落ちた(サーバーの計算と同じ)
            if botSim!.outcome != .playing || now >= moves.count {
                botDeadTick = now
                opponentAlive = false
            }
            opponentTime = Double(now) / 120
        }
        // 相手が先に落ちて、自分がその時間を越えたら、その場で勝ちとして終える(最後まで一人で避け続けなくていい)。
        // ボットは記録から、人はサーバーが計算し終えた値から(相手の端末の申告だけでは決めない)。同じ時間で並んだときは、続けてかすりで決める
        if let d = botDeadTick, sim.tick > d { scene?.endAfterThisStep() }
        if let t = opponentFinalTicks, sim.tick > t { scene?.endAfterThisStep() }
        // 位置は 1 秒に 20 回送る(相手の画面で、弾と重なって見えるずれを小さくする)
        if let m = match, m.opponentUid != nil, let uid, sim.tick - lastSent >= 6 {
            lastSent = sim.tick
            BattleService.sendPosition(match: m.id, uid: uid, x: sim.player.x, y: sim.player.y, tick: sim.tick, dead: false)
        }
    }

    private func ghost() -> (x: Double, y: Double, alive: Bool)? {
        if let b = botSim { return (b.player.x, b.player.y, botDeadTick == nil) }
        if let r = remote { return (r.x, r.y, !r.dead) }
        return nil
    }

    private func finish(sim: Simulation, moves: [Move]) async {
        guard let m = match, let uid else { return }
        if m.opponentUid != nil {
            BattleService.sendPosition(match: m.id, uid: uid, x: sim.player.x, y: sim.player.y, tick: sim.tick, dead: true)
        }
        // ボット戦は、相手の残りを一気に進めて、すぐ結果へ
        if let moves2 = m.botMoves, botSim != nil, botDeadTick == nil {
            while botSim!.outcome == .playing && botSim!.tick < moves2.count { botSim!.step(moves2[botSim!.tick]) }
            botDeadTick = botSim!.tick; opponentTime = Double(botSim!.tick) / 120
        }
        phase = .waiting
        do {
            if let r = try await BattleService.submit(match: m.id, moves: moves) {
                show(r)
            } else {
                resultListener = BattleService.listenResult(match: m.id, uid: uid) { [weak self] r in
                    Task { @MainActor in self?.show(r) }
                }
                // 相手がアプリを閉じたときなど、待たされ続けないように、30秒たったら「待つのをやめる」を出す
                canStopWaiting = false; opponentStillPlaying = false
                waitTask?.cancel()
                waitTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    guard !Task.isCancelled else { return }
                    await MainActor.run { if self?.phase == .waiting { self?.canStopWaiting = true } }
                }
            }
        } catch { phase = .failed }
    }

    private func show(_ r: BattleService.Result) {
        guard !isResult else { return }
        phase = .result(r)
        // 3連勝したら、評価をお願いする(連勝の数は端末に覚える)
        let key = "battle.winStreak"
        let streak = r.outcome == .win ? UserDefaults.standard.integer(forKey: key) + 1 : 0
        UserDefaults.standard.set(streak, forKey: key)
        if streak >= 3 { ReviewPrompt.maybeAsk(.battleStreak3) }
        status?.rating = r.ratingAfter
        status?.rank = r.rank
        Task { await loadStatus() }
    }

    /// 待つのをやめる: 相手の通信が途絶えている・締め切りを過ぎたなら、サーバーがその場で決着する
    func stopWaiting() async {
        guard let m = match, phase == .waiting else { return }
        canStopWaiting = false
        do {
            if let r = try await BattleService.claimWin(match: m.id) { show(r) } else { opponentStillPlaying = true; canStopWaiting = true }
        } catch { canStopWaiting = true }
    }

    /// 対戦中にやめる(降参)。その時点で落ちた扱い
    func forfeit() {
        guard phase == .playing else { return }
        scene?.forfeit()
    }

    /// 結果から入口へ戻る
    func backToTitle() {
        cleanup()
        phase = .title
    }

    func cleanup() {
        waitTask?.cancel(); waitTask = nil; canStopWaiting = false; opponentStillPlaying = false
        searchTask?.cancel(); searchTask = nil
        startTask?.cancel(); startTask = nil
        stopQueue()
        if let h = oppHandle, let opp = match?.opponentUid, let id = match?.id { BattleService.stopOpponent(match: id, uid: opp, handle: h) }
        oppHandle = nil
        resultListener?.remove(); resultListener = nil
        oppResultListener?.remove(); oppResultListener = nil
        opponentFinalTicks = nil
        scene?.isPaused = true
        scene = nil
        botSim = nil
    }
}

extension Notification.Name {
    /// 下のタブが変わった(object は、バトルのタブが見えているか)
    static let battleTabVisible = Notification.Name("battleTabVisible")
    /// ほかの画面を開くので、相手探しをやめてほしい(通知やリンクからステージを開いたときなど)
    static let cancelBattleSearch = Notification.Name("cancelBattleSearch")
}
