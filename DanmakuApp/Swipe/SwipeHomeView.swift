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
            case .go, .playing: PlayHUD(model: model, skip: { Task { await model.skip() } }, filter: { start(author: model.currentAuthorUid, name: model.clipAuthor) }, exitFilter: { model.backToTitle() })
            case .cleared, .failed: PlayHUD(model: model, skip: {}, filter: {}, exitFilter: {}, showSwipeHint: model.phase == .cleared)
            case .over: SwipeResultView(model: model, service: service, again: { start(author: model.filterAuthor, name: model.filterAuthorName) }, quit: { model.backToTitle() },
                                   ranking: { showRanking = true }, retry: { Task { await model.submit() } }, openStamina: { showStamina = true })
            }
            if let toast = model.toast {
                VStack { Spacer(); Text(toast).font(.system(size: 13, weight: .heavy, design: .rounded)).padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.75))).foregroundStyle(.white).padding(.bottom, 80) }
                    .transition(.opacity).allowsHitTesting(false)
                    .task { try? await Task.sleep(nanoseconds: 2_200_000_000); model.toast = nil }
            }
        }
        .overlay(alignment: .top) {
            if let key = model.errorKey, model.phase == .title { Text(LocalizedStringKey(key)).font(.system(size: 13, weight: .bold)).padding(10).background(Capsule().fill(Color.red.opacity(0.85))).foregroundStyle(.white).padding(.top, 8) }
        }
        .sheet(isPresented: $showStamina) { StaminaSheet(service: service, close: { showStamina = false }) }
        .sheet(isPresented: $showRanking) { SwipeRankingView(service: service) }
        .task { await service.refresh() }
        .onAppear { makeScene() }
        .onChange(of: model.phase) { p in if p == .title || p == .over { SwipeAudio.shared.stop() } }
        .onChange(of: cosmetics.effectsOn) { _ in makeScene() }
    }

    private func makeScene() {
        let sc = SwipeScene(model: model, effects: cosmetics.effectsOn)
        sc.onAdvance = { Task { @MainActor in await model.advanceAfterResult() } }
        scene = sc
    }

    private func start(author: String?, name: String = "") {
        guard !busy else { return }
        busy = true
        model.displayName = nil
        Task {
            await model.begin(author: author, authorName: name, blocked: Set(blocks.blocked.keys), myUid: auth.uid)
            busy = false
            if model.errorKey == "swipe.error.stamina" { showStamina = true; model.clearError() }
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
            Text("swipe.title.name").font(.custom("DelaGothicOne-Regular", size: 40)).foregroundStyle(
                LinearGradient(colors: [.white, Color(uiColor: SwipePalette.gold), Color(uiColor: SwipePalette.pink)], startPoint: .top, endPoint: .bottom))
                .multilineTextAlignment(.center)
            Text("swipe.beta").font(.system(size: 11, weight: .black)).padding(.horizontal, 8).padding(.vertical, 2)
                .background(Capsule().fill(Color(uiColor: SwipePalette.pink))).foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(["swipe.rule.1", "swipe.rule.2", "swipe.rule.3", "swipe.rule.4", "swipe.rule.5", "swipe.rule.6"], id: \.self) { k in
                    Text(LocalizedStringKey(k)).font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Color(uiColor: SwipePalette.text).opacity(0.9))
                }
            }.padding(.horizontal, 28)
            StaminaBar(info: service.stamina).onTapGesture(perform: openStamina)
            Button(action: start) {
                VStack(spacing: 1) {
                    Text("swipe.start").font(.custom("DelaGothicOne-Regular", size: 22))
                    Text(service.stamina.unlimited ? "swipe.start.unlimited" : "swipe.start.cost").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white).padding(.horizontal, 44).padding(.vertical, 12)
                .background(Capsule().fill(Color(uiColor: SwipePalette.pink)))
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
            if info.unlimited {
                Text("swipe.stamina.unlimited").font(.system(size: 13, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold))
            } else {
                HStack(spacing: 4) {
                    ForEach(0..<StaminaInfo.max, id: \.self) { i in
                        Image(systemName: "bolt.fill").foregroundStyle(i < info.value ? Color(uiColor: SwipePalette.gold) : Color.white.opacity(0.18))
                            .shadow(color: i < info.value ? Color(uiColor: SwipePalette.gold).opacity(0.8) : .clear, radius: 4)
                    }
                }
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(label(now: ctx.date)).font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(Color(uiColor: SwipePalette.dim))
                }
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
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
    let skip: () -> Void
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
                            Text("\(sc.streak)").font(.custom("DelaGothicOne-Regular", size: 28))
                                .foregroundStyle(sc.streak >= 5 ? Color(uiColor: SwipePalette.pink) : .white)
                                .shadow(color: sc.streak >= 5 ? Color(uiColor: SwipePalette.pink) : .clear, radius: 6)
                            if sc.streak > 0 { Text("×3^\(sc.streak)").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(uiColor: SwipePalette.cyan)) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            ScoreText(score: sc.score, lang: lang)
                            if sc.combo > 0 {
                                Text("×" + ScoreFormat.short(sc.multiplier, lang)).font(.system(size: 15, weight: .black, design: .rounded))
                                    .foregroundStyle(Color(uiColor: sc.level >= 6 ? SwipePalette.pink : sc.level >= 4 ? SwipePalette.gold : SwipePalette.cyan))
                            }
                            if model.phase == .go || model.phase == .playing {
                                Button(action: skip) { Text("swipe.skip").font(.system(size: 12, weight: .heavy)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
                                    .background(Capsule().fill(Color.white.opacity(0.14))) }
                            }
                        }
                    }
                    .padding(.horizontal, 14).padding(.top, 16)
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.clipName).font(.system(size: 17, weight: .black)).foregroundStyle(.white).lineLimit(1)
                            Button(action: filter) {
                                HStack(spacing: 3) { Image(systemName: "person.fill").font(.system(size: 10)); Text(model.clipAuthor).lineLimit(1); Image(systemName: "line.3.horizontal.decrease").font(.system(size: 9)) }
                                    .font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.cyan))
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
            .font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(.white)
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
                RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.12)).frame(width: 5)
                RoundedRectangle(cornerRadius: 2).fill(Color(uiColor: SwipePalette.gold)).frame(width: 5, height: 190 * f)
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
            Text(ScoreFormat.full(model.result?.score ?? model.scoring.score, lang)).font(.custom("DelaGothicOne-Regular", size: 26)).foregroundStyle(Color(uiColor: SwipePalette.gold))
                .multilineTextAlignment(.center).padding(.horizontal, 20).minimumScaleFactor(0.5)
            Text(String(format: L("swipe.over.counts"), model.scoring.streak, model.clipsPlayed)).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            if model.submitting { ProgressView().tint(.white) }
            else if model.submitError {
                Text("swipe.over.submit.failed").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(uiColor: SwipePalette.pink))
                Button(action: retry) { Text("swipe.over.retry").font(.system(size: 13, weight: .heavy)).padding(.horizontal, 16).padding(.vertical, 6).background(Capsule().fill(Color.white.opacity(0.16))) }.foregroundStyle(.white)
            } else if let r = model.result {
                if r.improved { Text("swipe.over.newbest").font(.system(size: 15, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold)) }
                if !r.ranked { Text(model.filterAuthor != nil ? "swipe.over.unranked.filter" : "swipe.over.unranked.signin").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(uiColor: SwipePalette.dim)).multilineTextAlignment(.center).padding(.horizontal, 24) }
            }
            StaminaBar(info: service.stamina).onTapGesture(perform: openStamina)
            Button(action: again) {
                Text(service.stamina.unlimited ? "swipe.again.unlimited" : "swipe.again").font(.custom("DelaGothicOne-Regular", size: 18)).foregroundStyle(.white)
                    .padding(.horizontal, 36).padding(.vertical, 10).background(Capsule().fill(Color(uiColor: SwipePalette.pink)))
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
            Text(service.stamina.value == 0 && !service.stamina.unlimited ? "swipe.out.title" : "swipe.stamina.title").font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(.white)
            StaminaBar(info: service.stamina)
            if !service.stamina.unlimited {
                Button(action: refillByAd) {
                    VStack(spacing: 2) {
                        Text(service.stamina.adRefillUsed ? "swipe.ad.used" : "swipe.ad.refill").font(.system(size: 15, weight: .black))
                        if !service.stamina.adRefillUsed { Text("swipe.ad.once").font(.system(size: 10, weight: .bold)) }
                    }.frame(maxWidth: .infinity).padding(.vertical, 10).foregroundStyle(.black)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: SwipePalette.gold).opacity(service.stamina.adRefillUsed ? 0.35 : 1)))
                }.disabled(service.stamina.adRefillUsed || busy)
                if service.stamina.drinks > 0 {
                    Button(action: useDrink) { Text(String(format: L("swipe.drink.use"), service.stamina.drinks)).font(.system(size: 15, weight: .black)).frame(maxWidth: .infinity).padding(.vertical, 10)
                        .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: SwipePalette.pink))) }.disabled(busy)
                }
                Button(action: { Task { busy = true; await purchases.buyDrink(); await service.refresh(); busy = false } }) {
                    Text(String(format: L("swipe.drink.buy"), purchases.drinkPrice ?? "¥120")).font(.system(size: 14, weight: .heavy)).frame(maxWidth: .infinity).padding(.vertical, 9)
                        .foregroundStyle(.white).background(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.4)))
                }.disabled(busy)
                Button(action: { Task { busy = true; await purchases.buyPass(); await service.refresh(); busy = false } }) {
                    VStack(spacing: 1) {
                        Text(String(format: L("swipe.pass.buy"), purchases.passPrice ?? "¥980")).font(.system(size: 14, weight: .heavy))
                        Text("swipe.pass.sub").font(.system(size: 10, weight: .semibold)).opacity(0.8)
                    }.frame(maxWidth: .infinity).padding(.vertical, 9).foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color(uiColor: SwipePalette.pink).opacity(0.7), Color(uiColor: SwipePalette.cyan).opacity(0.5)], startPoint: .leading, endPoint: .trailing)))
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
    @State private var rows: [SwipeRankRow] = []
    @State private var myRank: Int?
    @State private var myScore: BigScore?
    @State private var loading = true
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if let r = myRank, let s = myScore {
                    Section { HStack { Text(String(format: L("swipe.rank.mine"), r)).font(.system(size: 14, weight: .black)); Spacer()
                        Text(ScoreFormat.short(s, SwipePalette.scoreStyle)).font(.system(size: 14, weight: .black)).foregroundStyle(Color(uiColor: SwipePalette.gold)) } }
                }
                Section {
                    ForEach(rows) { row in
                        HStack(spacing: 10) {
                            Text("\(row.rank)").font(.system(size: 14, weight: .black, design: .rounded)).frame(width: 34, alignment: .trailing)
                                .foregroundStyle(row.rank <= 3 ? Color(uiColor: SwipePalette.gold) : .white)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.name).font(.system(size: 13, weight: .bold)).lineLimit(1)
                                Text(String(format: L("swipe.rank.streak"), row.bestStreak)).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ScoreFormat.short(row.score, SwipePalette.scoreStyle)).font(.system(size: 14, weight: .black, design: .rounded)).foregroundStyle(Color(uiColor: SwipePalette.gold))
                        }.listRowBackground(row.mine ? Color(uiColor: SwipePalette.pink).opacity(0.18) : nil)
                    }
                } footer: { Text("swipe.rank.footer") }
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if failed { Text("swipe.error.network").foregroundStyle(.secondary) }
            }
            .navigationTitle("swipe.ranking").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("swipe.close") { dismiss() } } }
        }
        .task {
            do { let r = try await service.ranking(); rows = r.rows; myRank = r.myRank; myScore = r.myScore } catch { failed = true }
            loading = false
        }
    }
}
