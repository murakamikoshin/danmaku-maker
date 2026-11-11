import SwiftUI
import UIKit
import DanmakuCore

/// 画面の下のタブ: あそぶ / ショップ / せってい。アイコンは、ゲームの部品で描いたオリジナル
struct MainTabView: View {
    enum Tab: Int, CaseIterable {
        case play, swipe, shop, settings
        var titleKey: String { ["tab.play", "tab.swipe", "tab.shop", "tab.settings"][rawValue] }
        var id: String { ["play", "swipe", "shop", "settings"][rawValue] }
    }

    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var rewards: RewardStore
    @EnvironmentObject private var adPatterns: AdPatternStore
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var swipeConfig: SwipeConfig
    @ObservedObject private var notice = RewardNoticeService.shared
    @State private var tab: Tab = .play
    /// 一度開いた画面は残しておく(スクロール位置や入力が消えない)
    @State private var opened: Set<Tab> = [.play]

    var body: some View {
        ZStack {
            page(.play) { HomeView() }
            if swipeConfig.enabled { page(.swipe) { SwipeHomeView() } }
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
                TabBar(selection: $tab, showSwipe: swipeConfig.enabled, shopBadge: !purchases.isPremium && (rewards.canClaim || adPatterns.canClaim))
            }
        }
        .onChange(of: tab) { opened.insert($0) }
        .fullScreenCover(isPresented: Binding(get: { !notice.pending.isEmpty }, set: { if !$0 { notice.pending = [] } })) {
            RewardNoticeView(items: notice.pending) { notice.pending = [] }
        }
        .task { await notice.check() }
        .onAppear {
            AudioManager.shared.play(.menu)
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-open-swipe") { tab = .swipe; opened.insert(.swipe) }
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
    /// ショップに「広告を見てもらえるごほうび」が残っているとき、赤い点で知らせる
    let shopBadge: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(MainTabView.Tab.allCases.filter { showSwipe || $0 != .swipe }, id: \.self) { tab in
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
                                if tab == .shop && shopBadge {
                                    Rectangle().fill(Color(Palette.pink)).frame(width: 9, height: 9)
                                        .overlay(Rectangle().stroke(Color(Palette.background), lineWidth: 2))
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
            Color(UIColor(hex: 0x0D0B1F))
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
                GameShipShape().fill(Color(UIColor(hex: 0x5CE1E6)))
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
        case .shop:
            // ボス: ピンクの星(中央に穴)
            GameBossShape()
                .fill(Color(Palette.pink), style: FillStyle(eoFill: true))
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
