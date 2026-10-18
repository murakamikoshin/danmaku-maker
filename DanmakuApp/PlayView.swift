import SwiftUI
import SpriteKit
import DanmakuCore

struct PlayResult {
    var outcome: Outcome
    var time: Double
    var hp: Int
    var duration: Int
    var isBoss: Bool
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
    /// 被弾したときの「復活しますか？」の表示
    @Published private(set) var reviveOffer = false
    /// 復活を出せるか（テストプレイでは出さない。広告の準備ができているか／購入者かは view 側で判定）
    var canRevive: () -> Bool = { false }
    private var usedAdRevive = false
    private var pending: PlayResult?
    private var pendingMoves: [Move] = []

    init(stage: Stage, loadout: Loadout = Loadout()) {
        self.stage = stage
        self.loadout = loadout
        remaining = Double(stage.durationSec)
        scene = GameScene(stage: stage, loadout: loadout)
        wire()
    }

    private func wire() {
        scene.onTime = { [weak self] t in
            guard let self else { return }
            let rounded = (t * 10).rounded() / 10
            if rounded != self.remaining { self.remaining = rounded }
        }
        scene.onFinish = { [weak self] sim, moves in
            guard let self else { return }
            let r = PlayResult(outcome: sim.outcome, time: max(0, sim.t), hp: sim.hp,
                               duration: sim.stage.durationSec, isBoss: sim.isBoss)
            if sim.outcome == .hit, self.canRevive() {
                self.pending = r; self.pendingMoves = moves
                self.reviveOffer = true
            } else {
                self.result = r
                self.onResult?(r, moves)
            }
        }
    }

    /// 復活する（広告を見終えたあと／購入者）
    func revive(free: Bool) {
        if !free { usedAdRevive = true }
        reviveOffer = false
        pending = nil
        scene.revive()
    }

    func giveUp() {
        reviveOffer = false
        if let r = pending { result = r; onResult?(r, pendingMoves) }
        pending = nil
    }

    /// 広告での復活は1プレイ1回まで
    var adReviveAvailable: Bool { !usedAdRevive }

    func restart() {
        usedAdRevive = false
        reviveOffer = false
        pending = nil
        result = nil
        remaining = Double(stage.durationSec)
        scene = GameScene(stage: stage, loadout: loadout)
        generation += 1
        wire()
    }
}

struct PlayView: View {
    let title: String
    let isTest: Bool
    let share: ShareContext?
    let onStart: (() -> Void)?
    let onExit: () -> Void
    @StateObject private var model: PlayModel
    @State private var startedOnce = false
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @State private var showStore = false

    init(stage: Stage, title: String, isTest: Bool = false, share: ShareContext? = nil, onStart: (() -> Void)? = nil,
         onResult: ((PlayResult, [Move]) -> Void)? = nil, onExit: @escaping () -> Void) {
        self.title = title
        self.isTest = isTest
        self.share = share
        self.onStart = onStart
        self.onExit = onExit
        let m = PlayModel(stage: stage, loadout: CosmeticsStore.shared.forPlay(isTest: isTest))
        m.onResult = onResult
        _model = StateObject(wrappedValue: m)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("play.quit", action: onExit)
                    .buttonStyle(.bordered)
                    .tint(.white)
                    .accessibilityIdentifier("play.quit")
                Text(title).font(.headline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", model.remaining))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(Color(Palette.gold))
            }
            .foregroundStyle(Color(Palette.text))
            .padding(.horizontal, 16).padding(.vertical, 10)

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
                .overlay { if let r = model.result { ResultView(result: r, isTest: isTest, share: share, retry: { model.restart(); onStart?() }, back: onExit) } }
                .frame(maxHeight: .infinity)

            Text("play.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            if !startedOnce { startedOnce = true; onStart?() }
            model.canRevive = { !isTest && (purchases.isPremium || (ads.isReady && model.adReviveAvailable)) }
        }
        .sheet(isPresented: $showStore) { StoreView() }
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

struct ResultView: View {
    let result: PlayResult
    var isTest = false
    var share: ShareContext?
    let retry: () -> Void
    let back: () -> Void

    private var win: Bool { result.outcome == .cleared }
    private var timeText: String { String(format: "%.1f", result.time) }

    private var headline: String {
        switch result.outcome {
        case .cleared: return L(result.isBoss ? "result.boss.win" : "result.clear")
        case .timeUp: return L("result.timeup")
        default: return L("result.hit")
        }
    }

    private var message: String {
        if isTest { return L(win ? "result.test.ok" : "result.test.ng") }
        switch result.outcome {
        case .cleared:
            return result.isBoss ? String(format: L("result.msg.boss"), timeText)
                                 : String(format: L("result.msg.survive"), result.duration)
        case .timeUp: return String(format: L("result.msg.timeup"), result.hp)
        default: return String(format: L("result.msg.hit"), timeText)
        }
    }

    var body: some View {
        ZStack {
            Color(Palette.background).opacity(0.72)
            VStack(spacing: 14) {
                Text(headline)
                    .accessibilityIdentifier("result.headline")
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(win ? Color(Palette.gold) : Color(Palette.pink))
                Text(message).font(.footnote).foregroundStyle(.secondary)
                if let share, !isTest {
                    let text = ShareText.player(share, result: result)
                    HStack {
                        ShareLink(item: text) { Label("detail.share", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered)
                        if let url = ShareText.xIntentURL(text) { Link("detail.share.x", destination: url).buttonStyle(.bordered) }
                    }
                }
                HStack {
                    Button("result.retry", action: retry).accessibilityIdentifier("result.retry").buttonStyle(.borderedProminent).tint(Color(Palette.pink))
                    Button("result.back", action: back).buttonStyle(.bordered).tint(.white)
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.09, blue: 0.25)))
            .padding(30)
        }
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
            Color(Palette.background).opacity(0.72)
            VStack(spacing: 14) {
                Text("result.hit").font(.system(size: 34, weight: .heavy)).foregroundStyle(Color(Palette.pink))
                Button(action: onRevive) {
                    Text(isPremium ? "revive.free" : "revive.ad").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(Color(Palette.bullets[1]))
                .accessibilityIdentifier("revive.button")
                Button("revive.giveup", action: onGiveUp).buttonStyle(.bordered).tint(.white)
                    .accessibilityIdentifier("revive.giveup")
                if !isPremium {
                    Button(action: onStore) { Text("revive.removeads").font(.footnote) }
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.09, blue: 0.25)))
            .padding(30)
        }
    }
}
