import SwiftUI
import UIKit
import DanmakuCore

/// 画面の下のタブ: あそぶ / ショップ / せってい。アイコンは、ゲームの部品で描いたオリジナル
struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case play, swipe, battle, shop, settings
        var titleKey: String { ["tab.play", "tab.swipe", "tab.battle", "tab.shop", "tab.settings"][rawValue] }
        var id: String { ["play", "swipe", "battle", "shop", "settings"][rawValue] }
    }

    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var rewards: RewardStore
    @EnvironmentObject private var adPatterns: AdPatternStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var swipeConfig: SwipeConfig
    @EnvironmentObject private var battleConfig: BattleConfig
    /// バトルのタブを一度でも開いたか(開くまで、新しい印を出す)
    @AppStorage("battle.seen") private var battleSeen = false
    @ObservedObject private var notice = RewardNoticeService.shared
    @ObservedObject private var updates = UpdateChecker.shared
    @State private var tab: Tab = .play
    /// 一度開いた画面は残しておく(スクロール位置や入力が消えない)
    @State private var opened: Set<Tab> = [.play]

    var body: some View {
        ZStack {
            page(.play) { HomeView() }
            if swipeConfig.enabled { page(.swipe) { SwipeHomeView() } }
            if battleConfig.enabled { page(.battle) { BattleHomeView() } }
            page(.shop) { ShopView() }
            page(.settings) { SettingsView() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                // 広告削除の購入者・同意が取れていないとき・画面確認用の起動では、出さない
                if !purchases.isPremium && ads.canShowBanner {
                    let width = UIScreen.main.bounds.width
                    BannerAdView(unitID: ads.bannerUnitID, width: width)
                        .frame(width: width, height: BannerAdView.adSize(width: width).size.height)
                }
                TabBar(selection: $tab, showSwipe: swipeConfig.enabled, showBattle: battleConfig.enabled, battleBadge: !battleSeen,
                       shopBadge: !purchases.isPremium && (rewards.canClaim || adPatterns.canClaim))
            }
        }
        .onChange(of: tab) { opened.insert($0); if $0 == .battle { battleSeen = true } }
        .fullScreenCover(isPresented: Binding(get: { !notice.pending.isEmpty }, set: { if !$0 { notice.pending = [] } })) {
            RewardNoticeView(items: notice.pending) { notice.pending = [] }
        }
        .task { await notice.check() }
        .task { await updates.refresh() }
        // 古い版: アップデートの案内。必要なら閉じられない画面、おすすめなら「あとで」で閉じられる吹き出し
        .fullScreenCover(isPresented: Binding(get: { updates.required }, set: { _ in })) { UpdateRequiredView() }
        .gameDialog("update.suggest.title", isPresented: Binding(get: { updates.suggested && !updates.required }, set: { if !$0 { updates.later() } }),
                    message: "update.suggest.message") {
            [GameDialogAction(title: "update.open") { updates.openStore() }, GameDialogAction(title: "update.later", role: .cancel) { updates.later() }]
        }
        .onAppear {
            AudioManager.shared.play(.menu)
            // テーマを変えた直後は、設定の画面へ戻す
            if UIThemeStore.shared.consumeReturnToSettings() { tab = .settings; opened.insert(.settings) }
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-open-swipe") { tab = .swipe; opened.insert(.swipe) }
            if args.contains("-open-battle") { tab = .battle; opened.insert(.battle) }
            if args.contains("-open-shop") { tab = .shop; opened.insert(.shop) }
            if args.contains("-open-settings") { tab = .settings; opened.insert(.settings) }
            #endif
        }
    }

    @ViewBuilder private func page<V: View>(_ t: Tab, @ViewBuilder _ content: () -> V) -> some View {
        if opened.contains(t) {
            content()
                .opacity(tab == t ? 1 : 0)
                .allowsHitTesting(tab == t)
                .accessibilityHidden(tab != t)
        }
    }
}

private struct TabBar: View {
    @Binding var selection: MainTabView.Tab
    var showSwipe: Bool
    var showBattle: Bool
    /// バトルのタブを、まだ開いていない(アップデートで増えたことを知らせる)
    var battleBadge: Bool
    /// ショップに「広告を見てもらえるごほうび」が残っているとき、赤い点で知らせる
    let shopBadge: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases.filter { (showSwipe || $0 != .swipe) && (showBattle || $0 != .battle) }, id: \.self) { tab in
                let selected = selection == tab
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.5)) { selection = tab }
                } label: {
                    VStack(spacing: 2) {
                        TabIcon(tab: tab, selected: selected)
                            .frame(width: 36, height: 36)
                            .scaleEffect(selected ? 1.08 : 0.94)
                            .overlay(alignment: .topTrailing) {
                                if (tab == .shop && shopBadge) || (tab == .battle && battleBadge) {
                                    Rectangle().fill(GameStyle.pinkColor).frame(width: 9, height: 9)
                                        .overlay(Rectangle().stroke(GameStyle.night, lineWidth: 2))
                                        .offset(x: 2, y: 2)
                                }
                            }
                        Text(LocalizedStringKey(tab.titleKey))
                            .font(.system(size: 11, weight: .black))
                            .lineLimit(1).minimumScaleFactor(0.7)
                            .foregroundStyle(selected ? GameStyle.yellow : GameStyle.dim.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    // 選択中のタブの上に、黄色い目印
                    .overlay(alignment: .top) {
                        if selected { Rectangle().fill(GameStyle.yellow).frame(width: 28, height: 4).offset(y: -8) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(tab.titleKey)))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("tab.\(tab.id)")
            }
        }
        .padding(.top, 8).padding(.bottom, 2)
        .background(
            GameStyle.nightDeep
                .overlay(alignment: .top) { Rectangle().fill(GameStyle.edge).frame(height: 2) }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct TabIcon: View {
    let tab: MainTabView.Tab
    let selected: Bool

    var body: some View {
        icon
            .saturation(selected ? 1 : 0)
            .opacity(selected ? 1 : 0.5)
    }

    @ViewBuilder private var icon: some View {
        switch tab {
        case .play:
            // 自機: シアンの三角と白い芯
            ZStack {
                GameShipShape().fill(GameStyle.cyanColor)
                Circle().fill(Color.white).frame(width: 7, height: 7)
            }
            .frame(width: 26, height: 31)
        case .swipe:
            // 重なったカードと上向きの矢印（縦にスワイプ）
            ZStack {
                PixelRect(cornerRadius: 5).fill(Color(SwipePalette.pink)).frame(width: 20, height: 26).rotationEffect(.degrees(-8)).offset(x: -3)
                PixelRect(cornerRadius: 5).fill(Color(SwipePalette.cyan)).frame(width: 20, height: 26).rotationEffect(.degrees(8)).offset(x: 3)
                Image(systemName: "chevron.up").font(.system(size: 14, weight: .black)).foregroundStyle(.white)
            }
        case .battle:
            // 1 対 1: 上向きのシアンの自機と、下向きのピンクの自機。あいだに黄色の弾
            ZStack {
                GameShipShape().fill(GameStyle.cyanColor).frame(width: 15, height: 18).offset(x: -8, y: 5)
                GameShipShape().fill(GameStyle.pinkColor).frame(width: 15, height: 18).rotationEffect(.degrees(180)).offset(x: 8, y: -5)
                Rectangle().fill(GameStyle.yellow).frame(width: 5, height: 5)
            }
        case .shop:
            // ボス: ピンクの星(中央に穴)
            GameBossShape()
                .fill(GameStyle.pinkColor, style: FillStyle(eoFill: true))
                .frame(width: 32, height: 32)
        case .settings:
            // 弾の輪: 色とりどりの弾が円に並ぶ
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) * Double.pi / 4
                    bulletDot(Palette.bullets[i % Palette.bullets.count], size: 8)
                        .offset(x: CGFloat(cos(a)) * 13, y: CGFloat(sin(a)) * 13)
                }
                bulletDot(Palette.gold, size: 10)
            }
        }
    }

    private func bulletDot(_ color: UIColor, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(Color(color))
            Circle().fill(Color.white).frame(width: size * 0.5, height: size * 0.5)
        }
        .frame(width: size, height: size)
    }
}
