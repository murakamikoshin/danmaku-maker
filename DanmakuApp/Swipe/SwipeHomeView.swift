import SpriteKit
import SwiftUI
import UIKit
import DanmakuCore

/// 「スワイプ弾幕 β」の画面（タイトル → プレイ → 結果）。仕様書 7 章
struct SwipeHomeView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @StateObject private var service: SwipeService
    @StateObject private var model: SwipeModel
    @State private var scene: SwipeScene?
    @State private var showStamina = false
    @State private var showRanking = false
    @State private var busy = false
    @State private var runsSinceAd = 0
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var cosmetics = CosmeticsStore.shared

    init() {
        let s = SwipeService()
        _service = StateObject(wrappedValue: s)
        _model = StateObject(wrappedValue: SwipeModel(service: s))
    }

    var body: some View {
        ZStack {
            Color(uiColor: SwipePalette.background).ignoresSafeArea()
            if let scene, model.phase != .title { SpriteView(scene: scene, preferredFramesPerSecond: 60).ignoresSafeArea() }
            switch model.phase {
            case .title: TitleView(start: { start(author: nil) }, ranking: { showRanking = true }, service: service, model: model, openStamina: { showStamina = true })
            case .starting, .transition: ProgressView().tint(.white).scaleEffect(1.4)
            case .go, .playing: PlayHUD(model: model, filter: { start(author: model.currentAuthorUid, name: model.clipAuthor) }, exitFilter: { model.backToTitle() })
            case .cleared, .failed: PlayHUD(model: model, filter: {}, exitFilter: {}, showSwipeHint: model.phase == .cleared)
            case .over: SwipeResultView(model: model, service: service, again: { start(author: model.filterAuthor, name: model.filterAuthorName) }, quit: { model.backToTitle(); breakAd() },
                                   ranking: { showRanking = true }, retry: { Task { await model.submit() } }, openStamina: { showStamina = true })
            }
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).font(.system(size: 13, weight: .heavy)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(PixelRect(cornerRadius: 8).fill(Color.black.opacity(0.75))).foregroundStyle(.white).padding(.bottom, 80) }
                    .transition(.opacity).allowsHitTesting(false)
                    .task { try? await Task.sleep(nanoseconds: 2_200_000_000); model.toast = nil }
            }
        }
        .overlay(alignment: .top) {
            if let key = model.errorKey, model.phase == .title { Text(LocalizedStringKey(key)).font(.system(size: 13, weight: .bold)).padding(10).background(PixelRect(cornerRadius: 8).fill(Color.red.opacity(0.85))).foregroundStyle(.white).padding(.top, 8) }
        }
        .sheet(isPresented: $showStamina) { StaminaSheet(service: service, close: { showStamina = false }) }
        .sheet(isPresented: $showRanking, onDismiss: { breakAd() }) { SwipeRankingView(service: service) }
        .task { await service.refresh() }
        .onChange(of: scenePhase) { p in if p == .active { Task { await service.refresh() } } }   // 回復した分を、戻ってきたときに反映する
        .onAppear {
            makeScene()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-swipe-stamina-sheet") { showStamina = true }
            #endif
        }
        .onChange(of: model.phase) { p in
            if p == .title || p == .over { SwipeAudio.shared.stop() }
            if p == .over { ads.countPlay() }   // 全画面広告の間隔の数え方に、スワイプ弾幕の1プレイも入れる
        }
        .onChange(of: cosmetics.effectsOn) { _ in makeScene() }
    }

    /// 区切りの良いところ(やめる・ランキングを閉じる)で、条件がそろっていれば全画面広告を出す。広告削除の購入者には出さない
    private func breakAd() {
        guard !purchases.isPremium else { return }
        Task { try? await Task.sleep(nanoseconds: 600_000_000); await ads.showInterstitialIfDue() }   // 画面が閉じ終わってから
    }

    private func makeScene() {
        let sc = SwipeScene(model: model, effects: cosmetics.effectsOn)
        sc.onAdvance = {
            Task { @MainActor in
                await model.advanceAfterResult()
            }
        }
        scene = sc
    }

    private func start(author: String?, name: String = "") {
        guard !busy else { return }
        busy = true
        // 結果画面から「もう一度」を2回押すごとに、全画面広告を挟む(広告削除の購入者には出さない)
        let fromResult = model.phase == .over
        model.displayName = DisplayNameStore.shared.publicName   // 名前の出し方の設定に従う(ユーザー名がなければ匿名)
        Task {
            if fromResult, !purchases.isPremium {
                runsSinceAd += 1
                if runsSinceAd >= 2 { runsSinceAd = 0; await ads.showInterstitialNow() }
            }
            await model.begin(author: author, authorName: name, blocked: Set(blocks.blocked.keys), myUid: auth.uid)
            busy = false
            if model.errorKey == "swipe.error.stamina" { await service.refresh(); showStamina = true; model.clearError() }
            if model.phase != .title { makeScene() }
        }
    }
}

// MARK: タイトル

private struct TitleView: View {
    let start: () -> Void
    let ranking: () -> Void
    @ObservedObject var service: SwipeService
    @ObservedObject var model: SwipeModel
    let openStamina: () -> Void
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 20)
            Text("swipe.title.eyebrow").font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.cyan))
            Text("swipe.title.name").font(.display(40)).multilineTextAlignment(.center).minimumScaleFactor(0.6)
                .thick(GameStyle.yellow, shade: GameStyle.yellowShade, depth: 4)
            Text("swipe.beta").font(.system(size: 11, weight: .black)).padding(.horizontal, 8).padding(.vertical, 2)
                .background(PixelRect(cornerRadius: 8).fill(Color(uiColor: SwipePalette.pink))).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(["swipe.rule.1", "swipe.rule.2", "swipe.rule.3", "swipe.rule.4", "swipe.rule.5"], id: \.self) { k in
                    Text(LocalizedStringKey(k)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color(uiColor: SwipePalette.text).opacity(0.9))
                }
            }.padding(.horizontal, 28)
            StaminaBar(info: service.stamina).onTapGesture(perform: openStamina)
            Button(action: start) {
                VStack(spacing: 1) {
                    Text("swipe.start").font(.display(22))
                    Text(service.stamina.unlimited ? "swipe.start.unlimited" : "swipe.start.cost").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(GameStyle.ink).padding(.horizontal, 44).padding(.vertical, 12)
                .background(KeyCap(fill: GameStyle.yellow, radius: 14))
                .scaleEffect(pulse ? 1.05 : 1)
            }
            .buttonStyle(.plain)
            .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true } }
            HStack(spacing: 18) {
                if model.bestStreak > 0 { Text(String(format: L("swipe.best.streak"), model.bestStreak)).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.gold)) }
                Button(action: ranking) { Label("swipe.ranking", systemImage: "trophy.fill").font(.system(size: 12, weight: .heavy)) }.foregroundStyle(Color(uiColor: SwipePalette.cyan))
            }
            Spacer(minLength: 30)
        }
    }
}

struct StaminaBar: View {
    let info: StaminaInfo
    var body: some View {
        VStack(spacing: 4) {
            if !info.known {
                // サーバーの値を受け取るまでは、満タンに見せない
                HStack(spacing: 4) { ForEach(0..<StaminaInfo.max, id: \.self) { _ in Image(systemName: "bolt.fill").foregroundStyle(Color.white.opacity(0.18)) } }
                Text("…").font(.system(size: 11, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.dim))
            } else if info.unlimited {
                Text("swipe.stamina.unlimited").font(.system(size: 13, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold))
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<StaminaInfo.max, id: \.self) { i in
                        Image(systemName: "bolt.fill").foregroundStyle(i < info.value ? Color(uiColor: SwipePalette.gold) : Color.white.opacity(0.18))
                            .shadow(color: i < info.value ? Color(uiColor: SwipePalette.gold).opacity(0.8) : .clear, radius: 4)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(label(now: ctx.date)).font(.system(size: 11, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.dim))
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(PixelRect(cornerRadius: 12).fill(Color.white.opacity(0.06)))
    }

    private func label(now: Date) -> String {
        guard let next = info.nextAt, info.value < StaminaInfo.max else { return String(format: L("swipe.stamina.full"), info.value, StaminaInfo.max) }
        let s = max(0, Int(next.timeIntervalSince(now)))
        return String(format: L("swipe.stamina.next"), info.value, StaminaInfo.max, s / 3600, (s % 3600) / 60, s % 60)
    }
}

// MARK: プレイ中の表示

private struct PlayHUD: View {
    @ObservedObject var model: SwipeModel
    let filter: () -> Void
    let exitFilter: () -> Void
    var showSwipeHint = false
    @State private var bob = false

    var body: some View {
        let sc = model.scoring
        let lang = model.language
        GeometryReader { geo in
            ZStack {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("swipe.streak").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.dim))
                            Text("\(sc.streak)").font(.display(28))
                                .foregroundStyle(sc.streak >= 5 ? Color(uiColor: SwipePalette.pink) : .white)
                                .shadow(color: sc.streak >= 5 ? Color(uiColor: SwipePalette.pink) : .clear, radius: 6)
                            if sc.streak > 0 { Text("×3^\(sc.streak)").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.cyan)) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            ScoreText(score: sc.score, lang: lang)
                            if sc.combo > 0 {
                                Text("×" + ScoreFormat.short(sc.multiplier, lang)).font(.system(size: 15, weight: .black))
                                    .foregroundStyle(Color(uiColor: sc.level >= 6 ? SwipePalette.pink : sc.level >= 4 ? SwipePalette.gold : SwipePalette.cyan))
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 16)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.clipName).font(.system(size: 17, weight: .black)).foregroundStyle(.white).lineLimit(1)
                            if model.currentAuthorUid == SwipeGenerator.author {
                                Label("swipe.gen.tag", systemImage: "dice.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.dim))
                            } else {
                                Button(action: filter) {
                                    HStack(spacing: 3) { Image(systemName: "person.fill").font(.system(size: 10)); Text(model.clipAuthor).lineLimit(1); Image(systemName: "line.3.horizontal.decrease").font(.system(size: 9)) }
                                        .font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.cyan))
                                }
                            }
                            if let _ = model.filterAuthor {
                                Button(action: exitFilter) { Text(String(format: L("swipe.filter.only"), model.filterAuthorName) + " ✕").font(.system(size: 11, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.gold)) }
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                }
                // ボムのゲージ（左端）
                BombGauge(gauge: sc.gauge).frame(width: 12, height: 216).position(x: 10, y: geo.size.height / 2)
                if showSwipeHint {
                    VStack { Spacer(); Text("swipe.next.hint").font(.system(size: 13, weight: .heavy)).foregroundStyle(.white.opacity(0.9)).offset(y: bob ? -5 : 0).padding(.bottom, 70) }
                        .onAppear { withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bob = true } }
                }
            }
        }
        .allowsHitTesting(model.phase == .go || model.phase == .playing)
    }
}

private struct ScoreText: View {
    let score: BigScore
    let lang: ScoreFormat.Language
    var body: some View {
        Text(ScoreFormat.full(score, lang))
            .font(.display(22)).foregroundStyle(.white)
            .lineLimit(1).minimumScaleFactor(6 / 22).frame(maxWidth: 280, alignment: .trailing)
            .shadow(color: .black, radius: 2)
    }
}

private struct BombGauge: View {
    let gauge: Int
    var body: some View {
        let f = Double(gauge) / Double(SwipeScoring.bombGauge)
        VStack(spacing: 2) {
            ZStack(alignment: .bottom) {
                PixelRect(cornerRadius: 2).fill(Color.white.opacity(0.12)).frame(width: 5)
                PixelRect(cornerRadius: 2).fill(Color(uiColor: SwipePalette.gold)).frame(width: 5, height: 190 * f)
                    .opacity(f > 0.8 ? 0.65 + 0.35 * Double(Int(Date().timeIntervalSince1970 * 8) % 2) : 1)
            }.frame(height: 190)
            Text("B\nO\nM\nB").font(.system(size: 7, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.dim)).multilineTextAlignment(.center).lineSpacing(-1)
        }
    }
}

// MARK: 結果

private struct SwipeResultView: View {
    @ObservedObject var model: SwipeModel
    @ObservedObject var service: SwipeService
    let again: () -> Void
    let quit: () -> Void
    let ranking: () -> Void
    let retry: () -> Void
    let openStamina: () -> Void

    var body: some View {
        let lang = model.language
        VStack(spacing: 10) {
            Spacer()
            Text("swipe.over.title").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.dim))
            Text("swipe.over.score").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.dim))
            Text(ScoreFormat.full(model.result?.score ?? model.scoring.score, lang)).font(.display(26)).foregroundStyle(Color(uiColor: SwipePalette.gold))
                .multilineTextAlignment(.center).padding(.horizontal, 20).minimumScaleFactor(0.5)
            Text(String(format: L("swipe.over.counts"), model.scoring.streak, model.clipsPlayed)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            if model.submitting { ProgressView().tint(.white) }
            else if model.submitError {
                Text("swipe.over.submit.failed").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.pink))
                Button(action: retry) { Text("swipe.over.retry").font(.system(size: 13, weight: .heavy)).padding(.horizontal, 16).padding(.vertical, 6).background(PixelRect(cornerRadius: 8).fill(Color.white.opacity(0.16))) }.foregroundStyle(.white)
            } else if let r = model.result {
                if r.improved { Text("swipe.over.newbest").font(.system(size: 15, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold)) }
                if !r.ranked { Text(model.filterAuthor != nil ? "swipe.over.unranked.filter" : "swipe.over.unranked.signin").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(uiColor: SwipePalette.dim)).multilineTextAlignment(.center).padding(.horizontal, 24) }
            }
            StaminaBar(info: service.stamina).onTapGesture(perform: openStamina)
            Button(action: again) {
                Text(service.stamina.unlimited ? "swipe.again.unlimited" : "swipe.again").font(.display(18)).foregroundStyle(GameStyle.ink)
                    .padding(.horizontal, 36).padding(.vertical, 10).background(KeyCap(fill: GameStyle.yellow, radius: 14)).padding(.bottom, 4)
            }.disabled(model.submitting)
            HStack(spacing: 24) {
                Button(action: ranking) { Label("swipe.ranking", systemImage: "trophy.fill") }.foregroundStyle(Color(uiColor: SwipePalette.cyan))
                Button(action: quit) { Text("swipe.quit") }.foregroundStyle(Color(uiColor: SwipePalette.dim))
            }.font(.system(size: 13, weight: .heavy))
            Spacer()
        }
        .background(Color.black.opacity(0.55).ignoresSafeArea())
    }
}

// MARK: スタミナ切れ

private struct StaminaSheet: View {
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @ObservedObject var service: SwipeService
    let close: () -> Void
    @State private var message: String?
    @State private var busy = false

    var body: some View {
        VStack(spacing: 14) {
            Text(service.stamina.value == 0 && !service.stamina.unlimited ? "swipe.out.title" : "swipe.stamina.title").font(.display(22)).foregroundStyle(.white)
            StaminaBar(info: service.stamina)
            if !service.stamina.unlimited {
                Button(action: refillByAd) {
                    VStack(spacing: 2) {
                        Text(service.stamina.adRefillUsed ? "swipe.ad.used" : "swipe.ad.refill").font(.system(size: 15, weight: .black))
                        if !service.stamina.adRefillUsed { Text("swipe.ad.once").font(.system(size: 10, weight: .bold)) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(.black)
                    .background(PixelRect(cornerRadius: 12).fill(Color(uiColor: SwipePalette.gold).opacity(service.stamina.adRefillUsed ? 0.35 : 1)))
                }.disabled(service.stamina.adRefillUsed || busy)
                if service.stamina.drinks > 0 {
                    Button(action: useDrink) { Text(String(format: L("swipe.drink.use"), service.stamina.drinks)).font(.system(size: 15, weight: .black)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.white).background(PixelRect(cornerRadius: 12).fill(Color(uiColor: SwipePalette.pink))) }.disabled(busy)
                }
                Button(action: { Task { busy = true; await purchases.buyDrink(); await service.refresh(); busy = false } }) {
                    Text(String(format: L("swipe.drink.buy"), purchases.drinkPrice ?? "¥120")).font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(.white).background(PixelRect(cornerRadius: 12).stroke(Color.white.opacity(0.4)))
                }.disabled(busy)
                Button(action: { Task { busy = true; await purchases.buyPass(); await service.refresh(); busy = false } }) {
                    VStack(spacing: 1) {
                        Text(String(format: L("swipe.pass.buy"), purchases.passPrice ?? "¥980")).font(.system(size: 14, weight: .heavy))
                        Text("swipe.pass.sub").font(.system(size: 10, weight: .semibold)).opacity(0.8)
                    }.frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(.white)
                    .background(PixelRect(cornerRadius: 12).fill(GameStyle.violet.opacity(0.4)))
                }.disabled(busy)
                Text("swipe.pass.legal").font(.system(size: 9.5)).foregroundStyle(Color(uiColor: SwipePalette.dim)).multilineTextAlignment(.center)
                HStack(spacing: 14) {
                    Link("swipe.terms", destination: AppConfig.termsURL); Link("swipe.privacy", destination: AppConfig.privacyURL)
                    Link("swipe.eula", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                }.font(.system(size: 10, weight: .bold))
            }
            if let message { Text(LocalizedStringKey(message)).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.pink)) }
            Button("swipe.close", action: close).font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.dim))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: SwipePalette.background).ignoresSafeArea())
        .presentationDetents([.large])
        .task { await purchases.loadSwipeProducts(); await service.refresh() }
    }

    private func refillByAd() {
        busy = true
        Task {
            defer { busy = false }
            if await ads.showRewarded() { do { try await service.refillByAd(); message = nil } catch { message = "swipe.error.network" } }
            else { message = "swipe.error.ad" }
        }
    }

    private func useDrink() {
        busy = true
        Task { defer { busy = false }; do { try await service.useDrink(); message = nil } catch { message = "swipe.error.network" } }
    }
}

// MARK: ランキング

struct SwipeRankingView: View {
    @ObservedObject var service: SwipeService
    @State private var data = SwipeRanking()
    @State private var monthly = true
    @State private var loading = true
    @State private var failed = false
    @State private var editingName = false
    @State private var showTitles = false
    @ObservedObject private var names = DisplayNameStore.shared
    @ObservedObject private var titles = TitleService.shared
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            GameStyle.night.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    GameTabs(items: [(true, "swipe.rank.month"), (false, "swipe.rank.all")], selection: $monthly, idPrefix: "swipe.rank.tab")
                    if monthly, let m = data.month, let end = data.endsAt {
                        Text(String(format: L("swipe.rank.period"), monthLabel(m), remaining(end)))
                            .font(.system(size: 12, weight: .heavy)).foregroundStyle(GameStyle.text.opacity(0.7))
                    }
                    // 名前の出し方(匿名 / ユーザー名)と、称号。変えたあとのプレイから反映される
                    HStack(spacing: 10) {
                        tile(icon: "person.crop.circle", title: "handle.title") {
                            Text(names.publicName ?? L("handle.mode.anon")).lineLimit(1)
                        } action: { editingName = true }
                        tile(icon: "rosette", title: "title.button") {
                            if let t = titles.selected { TitleChip(id: t, size: 11) } else { Text("title.none") }
                        } action: { showTitles = true }
                        .accessibilityIdentifier("swipe.titles")
                    }
                    if let r = data.myRank, let s = data.myScore { mine(rank: r, score: s) }
                    VStack(spacing: 6) {
                        ForEach(data.rows) { row in rankRow(row) }
                    }
                    Text(monthly ? "swipe.rank.footer.month" : "swipe.rank.footer")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.55)).multilineTextAlignment(.center)
                    if loading { ProgressView().tint(GameStyle.pinkColor).padding(.vertical, 8) }
                    if failed { Text("swipe.error.network").font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $editingName) { HandleSheet() }
        .sheet(isPresented: $showTitles) { TitlePickerView() }
        .task { await titles.load(uid: auth.uid) }
        .task(id: monthly) { await load() }
    }

    private var header: some View {
        HStack {
            Text("swipe.ranking").font(.display(22)).foregroundStyle(GameStyle.yellow)
            Spacer()
            Button { gameTap(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(GameStyle.panelHi, in: Circle())
                    .overlay(Circle().stroke(GameStyle.edge))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(Text("swipe.close"))
        }
    }

    private func tile<V: View>(icon: String, title: LocalizedStringKey, @ViewBuilder value: () -> V, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon).font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.cyan))
                    Text(title).font(.system(size: 12, weight: .heavy)).foregroundStyle(GameStyle.text.opacity(0.7))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .heavy)).foregroundStyle(GameStyle.text.opacity(0.4))
                }
                value().font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameStyle.panel, in: PixelRect(cornerRadius: 16))
            .overlay(PixelRect(cornerRadius: 16).stroke(GameStyle.edge))
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func mine(rank: Int, score: BigScore) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(String(format: L("swipe.rank.mine"), rank)).font(.system(size: 15, weight: .black)).foregroundStyle(GameStyle.text)
                Spacer()
                Text(ScoreFormat.short(score, SwipePalette.scoreStyle)).font(.system(size: 17, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold))
            }
            if monthly, let total = data.total {
                HStack {
                    Text(String(format: L("swipe.rank.total"), total)).font(.system(size: 12, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.65))
                    Spacer()
                    if let goal = goalText(rank: rank, total: total) { Text(goal).font(.system(size: 12, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.cyan)) }
                }
            }
        }
        .padding(14)
        .background(LinearGradient(colors: [GameStyle.pinkColor.opacity(0.28), GameStyle.pinkColor.opacity(0.10)], startPoint: .leading, endPoint: .trailing), in: PixelRect(cornerRadius: 16))
        .overlay(PixelRect(cornerRadius: 16).stroke(GameStyle.pinkColor.opacity(0.6), lineWidth: 1.2))
    }

    /// 1 行: 順位・(王冠|メダル)と名前・名前の下に称号の札と連続本数・点数
    private func rankRow(_ row: SwipeRankRow) -> some View {
        let top = CrownStyle.color(row.rank)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill((top ?? Color.white).opacity(top == nil ? 0.08 : 0.22))
                Text("\(row.rank)").font(.system(size: row.rank >= 100 ? 11 : 14, weight: .black)).minimumScaleFactor(0.6)
                    .foregroundStyle(top ?? GameStyle.text)
            }.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                BadgedName(name: row.name, badge: row.badge, size: 14)
                HStack(spacing: 6) {
                    if let t = row.title { TitleChip(id: t, size: 9) }
                    Text(String(format: L("swipe.rank.streak"), row.bestStreak)).font(.system(size: 10, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.55))
                }
            }
            Spacer(minLength: 4)
            Text(ScoreFormat.short(row.score, SwipePalette.scoreStyle)).font(.system(size: 15, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold)).lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.vertical, 8).padding(.horizontal, 10)
        .background((row.mine ? GameStyle.pinkColor.opacity(0.2) : (top?.opacity(0.10) ?? Color.white.opacity(0.05))), in: PixelRect(cornerRadius: 14))
        .overlay(PixelRect(cornerRadius: 14).stroke(row.mine ? GameStyle.pinkColor.opacity(0.6) : (top?.opacity(0.45) ?? GameStyle.edge)))
    }

    private func load() async {
        loading = true; failed = false
        do { data = try await service.ranking(monthly: monthly) } catch { failed = true }
        loading = false
    }

    private func monthLabel(_ id: String) -> String {
        let p = id.split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]) else { return id }
        return String(format: L("swipe.rank.monthlabel"), y, m)
    }

    private func remaining(_ end: Date) -> String {
        let s = max(0, Int(end.timeIntervalSinceNow))
        let d = s / 86400, h = (s % 86400) / 3600
        return d > 0 ? String(format: L("swipe.rank.left.days"), d, h) : String(format: L("swipe.rank.left.hours"), h, (s % 3600) / 60)
    }

    /// 次の目標(上位 50% → 10% → 1%)まで、あと何位か
    private func goalText(rank: Int, total: Int) -> String? {
        for p in [50, 10, 1] {
            let limit = Int((Double(total) * Double(p) / 100).rounded(.up))
            if rank > limit { return String(format: L("swipe.rank.goal"), p, rank - limit) }
        }
        return nil
    }
}
