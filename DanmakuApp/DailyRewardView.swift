import SwiftUI
import DanmakuCore

/// ショップの「毎日のごほうび」。広告を見ると、1日1つ報酬がもらえる(広告削除の購入者は、広告なしで)
struct DailyRewardCard: View {
    @EnvironmentObject private var rewards: RewardStore
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.scenePhase) private var scenePhase
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("daily.title").font(.display(20))
                Spacer()
                Text(String(format: L("daily.progress"), rewards.state.claimed, DailyRewards.total))
                    .font(.footnote.bold()).foregroundStyle(GameStyle.yellow)
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                todayPanel
                if rewards.upcoming.count > 1 { upcomingRow }
                if rewards.state.claimed > 0 { collection }
            }
            .padding(14)
            .background(GameStyle.panel, in: PixelRect(cornerRadius: 18))
            .overlay(PixelRect(cornerRadius: 18).stroke(GameStyle.edge))

            Text(purchases.isPremium ? "daily.footer.premium" : "daily.footer")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .onAppear { rewards.refreshDay() }
        .onChange(of: scenePhase) { if $0 == .active { rewards.refreshDay() } }
        .accessibilityIdentifier("daily.card")
    }

    // MARK: 今日の報酬

    @ViewBuilder private var todayPanel: some View {
        if let next = rewards.upcoming.first {
            HStack(spacing: 14) {
                RewardSwatch(reward: next, size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    Text(RewardArt.name(next)).font(.display(15))
                    claimButton
                }
                Spacer(minLength: 0)
            }
        } else {
            Label("daily.complete", systemImage: "crown.fill").font(.headline).foregroundStyle(GameStyle.yellow)
        }
    }

    @ViewBuilder private var claimButton: some View {
        if !rewards.canClaim {
            Label("daily.claimed", systemImage: "checkmark.circle.fill")
                .font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
        } else {
            let ready = purchases.isPremium || ads.isReady
            Button {
                Task { await claim() }
            } label: {
                Label(purchases.isPremium ? "daily.claim.free" : "daily.claim.ad", systemImage: purchases.isPremium ? "gift.fill" : "play.rectangle.fill")
                    .font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.ink)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(KeyCap(fill: GameStyle.reward, radius: 10, depth: 3)).padding(.bottom, 3)
            }
            .buttonStyle(.plain)
            .disabled(!ready || busy)
            .opacity(ready && !busy ? 1 : 0.5)
            .accessibilityIdentifier("daily.claim")
            if !ready { Text("daily.loading").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        if purchases.isPremium {
            rewards.claim()
        } else if await ads.showRewarded() {
            rewards.claim()
        }
        if rewards.justClaimed != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioManager.shared.se(.get)
        }
    }

    // MARK: 先の報酬(7個先まで見える)

    private var upcomingRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("daily.upcoming").font(.footnote.bold()).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(rewards.upcoming.dropFirst().enumerated()), id: \.element) { i, r in
                        VStack(spacing: 4) {
                            RewardSwatch(reward: r, size: 56, locked: true)
                            Text(String(format: L("daily.days.later"), i + 1 + (rewards.canClaim ? 0 : 0)))
                                .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: 集めた報酬(種類ごとに、つけかえる)

    private var collection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("daily.collection").font(.footnote.bold()).foregroundStyle(.secondary)
            ForEach(RewardKind.allCases, id: \.self) { kind in
                let owned = rewards.state.owned(kind)
                if !owned.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LocalizedStringKey(kind.nameKey)).font(.caption.bold())
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { rewards.select(nil, kind: kind) } label: {
                                    Image(systemName: "nosign").font(.title3).frame(width: 48, height: 48)
                                        .background(Color.white.opacity(rewards.selected(kind) == nil ? 0.25 : 0.1), in: PixelRect(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                                ForEach(owned.reversed(), id: \.self) { r in
                                    Button { rewards.select(r, kind: kind) } label: {
                                        RewardSwatch(reward: r, size: 48)
                                            .overlay(PixelRect(cornerRadius: 11).stroke(.white, lineWidth: rewards.selected(kind) == r ? 2.5 : 0))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}


/// ホーム画面の上に出す、今日のごほうびのお知らせ。今日まだ受け取っていないときだけ出る
struct DailyRewardBanner: View {
    @EnvironmentObject private var rewards: RewardStore
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.scenePhase) private var scenePhase
    @State private var busy = false

    var body: some View {
        Group {
            if rewards.canClaim, let next = rewards.upcoming.first {
                let ready = purchases.isPremium || ads.isReady
                HStack(spacing: 12) {
                    RewardSwatch(reward: next, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("daily.title").font(.system(size: 15, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                        Text(RewardArt.name(next)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    Button {
                        Task { await claim() }
                    } label: {
                        Label(purchases.isPremium ? "daily.claim.free" : "daily.claim.ad", systemImage: purchases.isPremium ? "gift.fill" : "play.rectangle.fill")
                            .font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.ink)
                            .lineLimit(2).minimumScaleFactor(0.8).multilineTextAlignment(.center)
                            .padding(.vertical, 8).padding(.horizontal, 12)
                            .background(KeyCap(fill: GameStyle.reward, radius: 10, depth: 3)).padding(.bottom, 3)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
                    .disabled(!ready || busy).opacity(ready && !busy ? 1 : 0.5)
                    .accessibilityIdentifier("home.daily.claim")
                }
                .padding(12)
                .background(GameStyle.panel, in: PixelRect(cornerRadius: 16))
                .overlay(PixelRect(cornerRadius: 16).stroke(GameStyle.yellow.opacity(0.5)))
            }
        }
        .onAppear { rewards.refreshDay() }
        .onChange(of: scenePhase) { if $0 == .active { rewards.refreshDay() } }
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        if purchases.isPremium {
            rewards.claim()
        } else if await ads.showRewarded() {
            rewards.claim()
        }
        if rewards.justClaimed != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioManager.shared.se(.get)
        }
    }
}
