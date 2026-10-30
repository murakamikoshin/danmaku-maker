import SwiftUI
import SpriteKit
import DanmakuCore

struct PlayResult {
    var outcome: Outcome
    var time: Double
    /// クリアまでの固定ステップ数(ランキングの記録に使う)
    var ticks: Int
    var hp: Int
    var duration: Int
    var isBoss: Bool
    var isDamage: Bool
    var damage: Int
    var shot: ShotType
    /// 復活を使ったか(使ったクリアは、ランキングとクリア数に数えない)
    var revived = false
}

/// ランキングに記録するために必要な情報(世界のステージを遊んでいるとき)
struct RankingContext {
    var stageID: String
    var stage: Stage
}

@MainActor
final class PlayModel: ObservableObject {
    let stage: Stage
    private let loadout: Loadout
    var onResult: ((PlayResult, [Move]) -> Void)?
    @Published private(set) var scene: GameScene
    @Published private(set) var generation = 0
    @Published private(set) var remaining: Double
    @Published private(set) var result: PlayResult?
    /// 結果が出たプレイの操作記録(ランキングへ送るため)
    @Published private(set) var finalMoves: [Move] = []
    @Published private(set) var lifeLeft: Int
    @Published private(set) var damage = 0
    /// 被弾したときの「復活しますか？」の表示
    @Published private(set) var reviveOffer = false
    /// 復活を出せるか（テストプレイでは出さない。広告の準備ができているか／購入者かは view 側で判定）
    var canRevive: () -> Bool = { false }
    private var usedAdRevive = false
    /// このプレイで、復活を使ったか(広告でも、広告削除の購入者の無料復活でも)
    private var revivedThisRun = false
    private var pending: PlayResult?
    private var pendingMoves: [Move] = []

    init(stage: Stage, loadout: Loadout = Loadout()) {
        self.stage = stage
        self.loadout = loadout
        remaining = stage.isUnlimitedTime ? 0 : Double(stage.durationSec)
        lifeLeft = stage.effectiveLifeCount
        scene = GameScene(stage: stage, loadout: loadout, effects: CosmeticsStore.shared.effectsOn, rewardFX: RewardFX.resolved(for: stage))
        wire()
    }

    private func wire() {
        scene.onTime = { [weak self] t in
            guard let self else { return }
            let rounded = (t * 10).rounded() / 10
            if rounded != self.remaining { self.remaining = rounded }
        }
        scene.onStatus = { [weak self] left, _, dmg in
            guard let self else { return }
            if left != self.lifeLeft { self.lifeLeft = left }
            if dmg != self.damage { self.damage = dmg }
        }
        scene.onFinish = { [weak self] sim, moves in
            guard let self else { return }
            let r = PlayResult(outcome: sim.outcome, time: max(0, sim.t), ticks: sim.tick, hp: sim.hp,
                               duration: sim.stage.durationSec, isBoss: sim.stage.hasRanking, isDamage: sim.stage.mode == .damage,
                               damage: sim.damageDealt, shot: sim.shotType, revived: self.revivedThisRun)
            if sim.outcome == .hit { AudioManager.shared.se(.hit) }
            if sim.outcome == .hit, self.canRevive() {
                self.pending = r; self.pendingMoves = moves
                self.reviveOffer = true
            } else {
                self.finalMoves = moves
                self.result = r
                self.onResult?(r, moves)
            }
        }
    }

    /// 復活する（広告を見終えたあと／購入者）
    func revive(free: Bool) {
        revivedThisRun = true
        if !free { usedAdRevive = true }
        reviveOffer = false
        pending = nil
        scene.revive()
    }

    func giveUp() {
        reviveOffer = false
        if let r = pending { finalMoves = pendingMoves; result = r; onResult?(r, pendingMoves) }
        pending = nil
    }

    /// 広告での復活は1プレイ1回まで
    var adReviveAvailable: Bool { !usedAdRevive }

    func restart() {
        usedAdRevive = false
        revivedThisRun = false
        reviveOffer = false
        pending = nil
        result = nil
        finalMoves = []
        remaining = stage.isUnlimitedTime ? 0 : Double(stage.durationSec)
        lifeLeft = stage.effectiveLifeCount
        damage = 0
        scene = GameScene(stage: stage, loadout: loadout, effects: CosmeticsStore.shared.effectsOn, rewardFX: RewardFX.resolved(for: stage))
        generation += 1
        wire()
    }
}

struct PlayView: View {
    let title: String
    let isTest: Bool
    let share: ShareContext?
    let ranking: RankingContext?
    let onStart: (() -> Void)?
    let onExit: () -> Void
    @StateObject private var model: PlayModel
    @State private var startedOnce = false
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @State private var showStore = false

    init(stage: Stage, title: String, isTest: Bool = false, customs: CustomImageChoice = .none, share: ShareContext? = nil, ranking: RankingContext? = nil,
         onStart: (() -> Void)? = nil, onResult: ((PlayResult, [Move]) -> Void)? = nil, onExit: @escaping () -> Void) {
        self.title = title
        self.isTest = isTest
        self.share = share
        self.ranking = ranking
        self.onStart = onStart
        self.onExit = onExit
        let m = PlayModel(stage: stage, loadout: CosmeticsStore.shared.forPlay(stage: stage, isTest: isTest, customs: customs))
        m.onResult = onResult
        _model = StateObject(wrappedValue: m)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            hud
            SpriteView(scene: model.scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder],
                       debugOptions: Self.debugOptions)
                .id(model.generation)
                .aspectRatio(CGFloat(DanmakuConfig.width / DanmakuConfig.height), contentMode: .fit)
                .overlay {
                    if model.reviveOffer {
                        ReviveView(isPremium: purchases.isPremium, price: purchases.priceText,
                                   onRevive: { Task { await revive() } }, onGiveUp: { model.giveUp() }, onStore: { showStore = true })
                    }
                }
                .overlay {
                    if let r = model.result {
                        ResultView(result: r, isTest: isTest, share: share, ranking: ranking, moves: model.finalMoves,
                                   retry: { Task { await adBreak(); model.restart(); onStart?() } },
                                   back: { Task { await adBreak(); onExit() } })
                    }
                }
                .frame(maxHeight: .infinity)

            Text("play.hint")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if !startedOnce { startedOnce = true; onStart?() }
            AudioManager.shared.play(.forNumber(model.stage.effectiveBGM))
            model.canRevive = { !isTest && (purchases.isPremium || (ads.isReady && model.adReviveAvailable)) }
        }
        .sheet(isPresented: $showStore) { StoreView() }
        .onChange(of: model.result?.outcome) { outcome in
            guard let outcome else { return }
            AudioManager.shared.stopBGM()
            AudioManager.shared.se(outcome == .cleared ? .clear : .fail)
            if !isTest { ads.countPlay() }
        }
        .onChange(of: model.generation) { _ in AudioManager.shared.play(.forNumber(model.stage.effectiveBGM)) }
        .onDisappear { AudioManager.shared.play(.menu) }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { gameTap(); onExit() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(Palette.text))
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2)))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(Text("play.quit"))
            .accessibilityIdentifier("play.quit")
            Text(title).font(.system(size: 16, weight: .heavy, design: .rounded)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text((model.stage.isUnlimitedTime ? "∞ " : "") + String(format: "%.1f", model.remaining))
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundStyle(Color(Palette.gold))
                .padding(.vertical, 5).padding(.horizontal, 12)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color(Palette.gold).opacity(0.4)))
        }
        .foregroundStyle(Color(Palette.text))
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    /// ライフ(ハート)・HP(目盛り)・ダメージの表示
    @ViewBuilder private var hud: some View {
        let stage = model.stage
        let showLife = stage.effectiveLifeCount > 1 || stage.effectiveLifeMode == .hp
        let showDamage = stage.mode == .damage
        if showLife || showDamage {
            HStack(spacing: 12) {
                if showLife { lifeView(stage) }
                Spacer(minLength: 0)
                if showDamage {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill").foregroundStyle(Color(Palette.gold))
                        Text(model.damage, format: .number)
                            .font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                            .contentTransition(.numericText())
                    }
                    .padding(.vertical, 4).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .accessibilityIdentifier("play.damage")
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 6)
        }
    }

    @ViewBuilder private func lifeView(_ stage: Stage) -> some View {
        let max = stage.effectiveLifeCount
        if stage.effectiveLifeMode == .lives {
            HStack(spacing: 4) {
                ForEach(0..<max, id: \.self) { i in
                    Image(systemName: i < model.lifeLeft ? "heart.fill" : "heart")
                        .font(.system(size: 18))
                        .foregroundStyle(i < model.lifeLeft ? Color(Palette.pink) : Color.white.opacity(0.3))
                        .shadow(color: Color(Palette.pink).opacity(i < model.lifeLeft ? 0.7 : 0), radius: 4)
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: model.lifeLeft)
        } else {
            HStack(spacing: 2) {
                ForEach(0..<max, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < model.lifeLeft ? Color(Palette.bullets[4]) : Color.white.opacity(0.15))
                        .frame(width: max > 12 ? 7 : 10, height: 14)
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            .animation(.easeOut(duration: 0.2), value: model.lifeLeft)
        }
    }

    /// 結果画面から次へ進むときの全画面広告。広告削除の購入者・テストプレイには出さない
    private func adBreak() async {
        guard !isTest, !purchases.isPremium else { return }
        await ads.showInterstitialIfDue()
    }

    private func revive() async {
        if purchases.isPremium { model.revive(free: true); return }
        if await ads.showRewarded() { model.revive(free: false) }
    }

    private static var debugOptions: SpriteView.DebugOptions {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-no-debug-overlay") ? [] : [.showsFPS, .showsNodeCount]
        #else
        []
        #endif
    }
}

// MARK: 結果

struct ResultView: View {
    let result: PlayResult
    var isTest = false
    var share: ShareContext?
    var ranking: RankingContext?
    var moves: [Move] = []
    let retry: () -> Void
    let back: () -> Void

    @EnvironmentObject private var rewardStore: RewardStore
    private var win: Bool { result.outcome == .cleared }
    private var timeText: String { String(format: "%.1f", result.time) }

    private var headline: String {
        switch result.outcome {
        case .cleared: return L(result.isDamage ? "result.damage.win" : result.isBoss ? "result.boss.win" : "result.clear")
        case .timeUp: return L("result.timeup")
        default: return L("result.hit")
        }
    }

    private var message: String {
        if isTest { return L(win ? "result.test.ok" : "result.test.ng") }
        switch result.outcome {
        case .cleared:
            if result.isDamage { return L("result.msg.damage") }
            return result.isBoss ? String(format: L("result.msg.boss"), timeText)
                                 : String(format: L("result.msg.survive"), result.duration)
        case .timeUp: return String(format: L("result.msg.timeup"), result.hp)
        default: return String(format: L("result.msg.hit"), timeText)
        }
    }

    var body: some View {
        ZStack {
            Color(Palette.background).opacity(0.78)
            ScrollView {
                VStack(spacing: 14) {
                    // 広告でもらった称号(自分の画面だけ)
                    if !isTest, let badge = rewardStore.selected(.badge) {
                        HStack(spacing: 8) {
                            RewardSwatch(reward: badge, size: 34)
                            Text(RewardArt.name(badge)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(RewardArt.color(badge))
                        }
                        .accessibilityIdentifier("result.badge")
                    }
                    Text(headline)
                        .accessibilityIdentifier("result.headline")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundStyle(win ? AnyShapeStyle(GameStyle.gold) : AnyShapeStyle(Color(Palette.pink)))
                        .shadow(color: (win ? Color(Palette.gold) : Color(Palette.pink)).opacity(0.7), radius: 10)
                    if win && result.isDamage {
                        VStack(spacing: 0) {
                            Text("result.damage.label").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                            Text(result.damage, format: .number)
                                .font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        }
                    } else if win && result.isBoss {
                        VStack(spacing: 0) {
                            Text("result.time.label").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                            Text(timeText + L("unit.s")).font(.system(size: 46, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        }
                    }
                    Text(message).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)

                    if result.revived && win && !isTest {
                        Label("result.revived", systemImage: "arrow.counterclockwise.circle.fill")
                            .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.bullets[1]))
                            .padding(.vertical, 6).padding(.horizontal, 12).background(Color(Palette.bullets[1]).opacity(0.14), in: Capsule())
                    }
                    if !isTest, win, result.isBoss, ranking != nil {
                        if result.revived {
                            Text("ranking.revived").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        } else if let ranking {
                            RankingSubmitPanel(context: ranking, result: result, moves: moves)
                        }
                    }

                    if let share, !isTest {
                        let text = ShareText.player(share, result: result)
                        HStack(spacing: 8) {
                            ShareLink(item: text) { smallButton("detail.share", "square.and.arrow.up") }
                            if let url = ShareText.xIntentURL(text) { Link(destination: url) { smallButton("detail.share.x", "xmark") } }
                        }
                    }
                    HStack(spacing: 10) {
                        GameActionButton(title: "result.retry", systemImage: "arrow.counterclockwise", fill: GameStyle.accent, action: retry)
                            .accessibilityIdentifier("result.retry")
                        Button { gameTap(); back() } label: {
                            Text("result.back").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2)))
                        }
                        .buttonStyle(BounceButtonStyle())
                    }
                }
                .padding(20)
                .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(win ? Color(Palette.gold).opacity(0.6) : GameStyle.edge, lineWidth: win ? 2 : 1))
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func smallButton(_ title: LocalizedStringKey, _ image: String) -> some View {
        Label(title, systemImage: image).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(Color.white.opacity(0.1), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.2)))
    }
}

struct ReviveView: View {
    let isPremium: Bool
    let price: String?
    let onRevive: () -> Void
    let onGiveUp: () -> Void
    let onStore: () -> Void

    var body: some View {
        ZStack {
            Color(Palette.background).opacity(0.78)
            VStack(spacing: 14) {
                Text("result.hit")
                    .font(.system(size: 38, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.pink))
                    .shadow(color: Color(Palette.pink).opacity(0.7), radius: 10)
                GameActionButton(title: isPremium ? "revive.free" : "revive.ad", systemImage: "play.rectangle.fill", fill: GameStyle.cyan, action: onRevive)
                    .accessibilityIdentifier("revive.button")
                Button { gameTap(); onGiveUp() } label: {
                    Text("revive.giveup").font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.2)))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityIdentifier("revive.giveup")
                if !isPremium {
                    Button(action: onStore) {
                        Text("revive.removeads").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.gold)).underline()
                    }
                }
            }
            .padding(22)
            .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(GameStyle.edge))
            .padding(30)
        }
    }
}
