import SwiftUI
import PhotosUI
import DanmakuCore

/// ショップ。動く見本つきのカードを並べた画面で、見た目・撃ち方・自分の画像を買って、選ぶ
struct ShopView: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var purchases: PurchaseService
    @State private var showRemoveAds = false
    @State private var celebrate = false

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    ShopHero()

                    if !purchases.isPremium {
                        Button { showRemoveAds = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "nosign").font(.title2.bold())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("revive.removeads").font(.headline)
                                    Text("store.benefit.revive").font(.caption).opacity(0.9)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.bold())
                            }
                            .foregroundStyle(.white)
                            .padding(16)
                            .background(LinearGradient(colors: [Color(Palette.pink), Color(UIColor(hex: 0x8E5CFF))], startPoint: .leading, endPoint: .trailing),
                                        in: RoundedRectangle(cornerRadius: 18))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shop.removeads")
                    }

                    LifetimeCard().id("lifetime")
                    DailyRewardCard().id("daily")
                    AdPatternCard().id("adpatterns")
                    CustomImagesCard().id("customimages")
                    ShotSection().id("shots")
                    PatternShop().id("patterns")
                    PatternShop(patterns: Pattern.pack2, pack: .patternPack2, title: "shop.pattern2.title", footer: "shop.pattern2.footer",
                                packTitle: "shop.pattern2.pack").id("patterns2")
                    MakerCard().id("maker")
                    RewardShop()
                    ForEach(Theme.paid, id: \.self) { ThemeCard(theme: $0) }
                    ThemeCard(theme: .classic)

                    Button { gameTap(); Task { await purchases.restore() } } label: {
                        Label("store.restore", systemImage: "arrow.clockwise")
                            .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(purchases.isBusy)
                    .accessibilityIdentifier("shop.restore")
                    if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                // 下のタブに隠れないように、タブの高さぶん空ける
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 110)
            }
            .onAppear {
                #if DEBUG
                // 画面確認用: 起動引数 -shop-focus patterns|shots|customimages で、そこまで自動で移動する
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-shop-focus"), args.indices.contains(i + 1) {
                    let target = args[i + 1]
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { proxy.scrollTo(target, anchor: .top) }
                }
                #endif
            }
            }
            .background(Color(Palette.background).ignoresSafeArea())
            .overlay(alignment: .top) { Color(Palette.background).ignoresSafeArea(edges: .top).frame(height: 1) }
            .toolbar(.hidden, for: .navigationBar)
            .task { await purchases.refresh() }
            .overlay {
                if celebrate {
                    ZStack {
                        ConfettiView()
                        Text("shop.got")
                            .font(.system(size: 56, weight: .heavy, design: .rounded))
                            .foregroundStyle(LinearGradient(colors: [Color(Palette.gold), Color(Palette.pink)], startPoint: .top, endPoint: .bottom))
                            .shadow(color: .black.opacity(0.5), radius: 8)
                            .transition(.scale.combined(with: .opacity))
                    }
                    .ignoresSafeArea()
                }
            }
            .onChange(of: purchases.celebration) { product in
                guard product != nil else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                AudioManager.shared.se(.get)
                withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) { celebrate = true }
                Task {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation { celebrate = false }
                    purchases.celebration = nil
                }
            }
        }
        .sheet(isPresented: $showRemoveAds) { StoreView() }
        .preferredColorScheme(.dark)
    }
}

// MARK: 部品

/// 上のバナー: ゲームと同じ渦巻きの弾が、流れ続ける
private struct ShopHero: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            BulletBurstView(theme: .classic)
            LinearGradient(colors: [.clear, Color.black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("SHOP")
                    .font(.system(size: 46, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(Palette.pink)], startPoint: .top, endPoint: .bottom))
                    .shadow(color: Color(Palette.pink).opacity(0.8), radius: 10)
                Text("shop.hero.sub").font(.footnote.bold()).foregroundStyle(.white.opacity(0.9))
            }
            .padding(16)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.18)))
    }
}

/// カードの枠(見出し、中身、補足)
private struct ShopCard<Content: View>: View {
    let title: LocalizedStringKey
    var footer: LocalizedStringKey?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 22, weight: .heavy, design: .rounded)).padding(.horizontal, 4)
            content
            if let footer { Text(footer).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4) }
        }
    }
}

private struct CardBody<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))
    }
}

private struct CardDivider: View {
    var body: some View { Divider().overlay(Color.white.opacity(0.1)).padding(.leading, 14) }
}

private struct PriceButton: View {
    @EnvironmentObject private var purchases: PurchaseService
    let product: Product

    var body: some View {
        let available = purchases.prices[product] != nil
        Button { Task { await purchases.purchase(product) } } label: {
            // 価格は App Store から届いたもの(その人の国の通貨)だけを出す。届くまでは「…」
            Text(purchases.prices[product] ?? "…")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(minWidth: 70)
                .padding(.vertical, 8).padding(.horizontal, 12)
                .background(LinearGradient(colors: [Color(Palette.pink), Color(UIColor(hex: 0xFF8A5C))], startPoint: .leading, endPoint: .trailing), in: Capsule())
                .shadow(color: Color(Palette.pink).opacity(0.5), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(available && !purchases.isBusy ? 1 : 0.5)
        .disabled(!available || purchases.isBusy)
        .accessibilityIdentifier("shop.buy.\(product.id)")
    }
}

private struct EquippedLabel: View {
    var body: some View {
        Label("shop.equipped", systemImage: "checkmark.circle.fill")
            .font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
    }
}

private struct EquipButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("shop.equip").font(.footnote.bold()).padding(.vertical, 6).padding(.horizontal, 14)
                .background(Color.white.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: 撃ち方

private struct ShotSection: View {
    var body: some View {
        ShopCard(title: "shop.section.shot", footer: "shop.shot.footer") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ShotType.allCases, id: \.self) { ShotTile(shot: $0) }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
            }
        }
    }
}

private struct ShotTile: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let shot: ShotType

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ShotPreviewView(shot: shot)
                .frame(height: 190)
                .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(LocalizedStringKey(shot.nameKey)).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(LocalizedStringKey(shot.detailKey)).font(.caption).foregroundStyle(.secondary)
                .frame(height: 48, alignment: .topLeading)
            HStack {
                Spacer()
                if cosmetics.ownership.has(shot) {
                    Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
                } else {
                    PriceButton(product: .shot(shot))
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1.5))
    }
}

// MARK: テーマ(弾・背景・自機)

/// ステージを投稿した数で、無料で解放される見た目
private struct RewardShop: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        ShopCard(title: "shop.reward.title", footer: "shop.reward.footer") {
            CardBody {
                Text(String(format: L("shop.reward.count"), cosmetics.ownership.posts))
                    .font(.footnote.bold()).foregroundStyle(Color(Palette.gold))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                ForEach(Theme.reward, id: \.self) { t in
                    CardDivider()
                    HStack(spacing: 12) {
                        HStack(spacing: 2) {
                            ForEach(0..<3, id: \.self) { Image(uiImage: SpriteFactory.bulletImages(t)[$0]).resizable().frame(width: 16, height: 16) }
                            Image(uiImage: SpriteFactory.shipImage(t)).resizable().frame(width: 18, height: 21).padding(.leading, 4)
                        }
                        .frame(width: 100, alignment: .leading)
                        Text(LocalizedStringKey(t.nameKey)).font(.body.weight(.semibold))
                        Spacer()
                        if cosmetics.ownership.hasUnlocked(t) {
                            Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
                        } else {
                            let need = (t.unlockPosts ?? 0)
                            VStack(alignment: .trailing, spacing: 2) {
                                Label(String(format: L("shop.reward.need"), max(0, need - cosmetics.ownership.posts)), systemImage: "lock.fill")
                                    .font(.footnote.bold()).foregroundStyle(Color(Palette.gold))
                                Text(String(format: L("shop.reward.condition"), need)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

private struct ThemeCard: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var purchases: PurchaseService
    let theme: Theme

    private var parts: [Product] { ThemePart.allCases.map { Product.part(theme, $0) } }
    private var offPercent: Int { theme == .classic ? 0 : purchases.discountPercent(bundle: .set(theme), singles: parts) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 見本: そのテーマの背景・弾・自機で、実際の弾幕が流れる
            ZStack(alignment: .topLeading) {
                BulletBurstView(theme: theme)
                HStack {
                    Text(LocalizedStringKey(theme.nameKey))
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.7), radius: 5)
                    Spacer()
                    if theme != .classic && cosmetics.ownership.canBuy(.set(theme)) {
                        Text(String(format: L("shop.off"), offPercent))
                            .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .padding(.vertical, 4).padding(.horizontal, 10)
                            .background(Color(Palette.pink), in: Capsule())
                    }
                }
                .padding(14)
            }
            .frame(height: 170)

            VStack(spacing: 0) {
                ForEach(Array(ThemePart.allCases.enumerated()), id: \.element) { idx, part in
                    PartRow(theme: theme, part: part)
                    if idx < ThemePart.allCases.count - 1 || theme != .classic { CardDivider() }
                }
                if theme != .classic { setRow }
            }
            .background(Color.white.opacity(0.07))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.white.opacity(0.12)))
    }

    private var setRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("shop.set").font(.system(size: 17, weight: .heavy, design: .rounded))
                // 単品の合計 → セットの価格(App Store の価格が届いてから出す)
                if let total = purchases.totalText(parts), let price = purchases.prices[.set(theme)] {
                    HStack(spacing: 6) {
                        Text(total).strikethrough().foregroundStyle(.secondary)
                        Text("→").foregroundStyle(.secondary)
                        Text(price).foregroundStyle(Color(Palette.gold)).bold()
                    }.font(.caption)
                }
            }
            Spacer()
            if cosmetics.ownership.canBuy(.set(theme)) { PriceButton(product: .set(theme)) }
            else { Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4])) }
        }
        .padding(14)
        .background(LinearGradient(colors: [Color(Palette.pink).opacity(0.18), Color(Palette.gold).opacity(0.10)], startPoint: .leading, endPoint: .trailing))
    }
}

private struct PartRow: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let theme: Theme
    let part: ThemePart

    var body: some View {
        HStack(spacing: 12) {
            preview.frame(width: 84, alignment: .leading)
            Text(LocalizedStringKey(part.nameKey)).font(.body.weight(.semibold))
            Spacer()
            if cosmetics.ownership.has(part, of: theme) {
                Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
            } else {
                PriceButton(product: .part(theme, part))
            }
        }
        .padding(14)
    }

    @ViewBuilder private var preview: some View {
        let skin = Skin.of(theme)
        switch part {
        case .bullets:
            HStack(spacing: 2) {
                ForEach(0..<4, id: \.self) { Image(uiImage: SpriteFactory.bulletImages(theme)[$0]).resizable().frame(width: 16, height: 16) }
            }
        case .background:
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(Color(skin.background))
                HStack(spacing: 7) {
                    ForEach(0..<5, id: \.self) { i in
                        Circle().fill(Color(skin.star)).frame(width: i % 2 == 0 ? 3 : 2, height: i % 2 == 0 ? 3 : 2)
                            .offset(y: CGFloat((i * 7) % 11) - 5)
                    }
                }
            }
            .frame(width: 44, height: 28)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.2)))
        case .ship:
            Image(uiImage: SpriteFactory.shipImage(theme)).resizable().frame(width: 20, height: 24)
        }
    }
}

// MARK: じぶんの画像

/// ボス・弾・自機を、写真アプリから選んだ画像に差し替える(見た目だけ。画像は端末の中にだけ保存する)
private struct CustomImagesCard: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        ShopCard(title: "shop.custom.title", footer: "shop.custom.footer") {
            CardBody {
                if cosmetics.ownership.hasCustomImages {
                    ForEach(Array(CustomSlot.allCases.enumerated()), id: \.element) { idx, slot in
                        CustomSlotRow(slot: slot)
                        if idx < CustomSlot.allCases.count - 1 { CardDivider() }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("shop.custom.intro").font(.footnote).foregroundStyle(.secondary)
                        HStack(spacing: 16) {
                            ForEach(CustomSlot.allCases) { slot in
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle().fill(Color.white.opacity(0.1))
                                        Circle().strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])).foregroundStyle(Color.white.opacity(0.35))
                                        Image(systemName: "sparkles").foregroundStyle(Color(Palette.gold))
                                    }.frame(width: 46, height: 46)
                                    Text(LocalizedStringKey(slot.nameKey)).font(.caption2.bold()).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            PriceButton(product: .customImages)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}

private struct CustomSlotRow: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let slot: CustomSlot
    @State private var item: PhotosPickerItem?
    @State private var failed = false

    var body: some View {
        // 画像が変わったら見た目を更新するため、番号を読む
        let _ = cosmetics.customImageRevision
        let image = CustomImageStore.load(slot)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.white.opacity(0.08))
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().clipShape(Circle())
                } else {
                    Image(systemName: "photo").foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(slot.nameKey)).font(.body.weight(.semibold))
                if failed { Text("shop.custom.failed").font(.caption).foregroundStyle(.red) }
                else if image == nil { Text("shop.custom.empty").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if image != nil {
                Button(role: .destructive) { cosmetics.removeCustomImage(slot) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            PhotosPicker(selection: $item, matching: .images) {
                Text(image == nil ? "shop.custom.pick" : "shop.custom.change").font(.footnote.bold())
                    .padding(.vertical, 6).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.14), in: Capsule())
            }
            .accessibilityIdentifier("shop.custom.pick.\(slot.rawValue)")
        }
        .padding(14)
        .onChange(of: item) { newItem in
            guard let newItem else { return }
            Task {
                let data = try? await newItem.loadTransferable(type: Data.self)
                await MainActor.run {
                    if let data, let ui = UIImage(data: data), cosmetics.setCustomImage(ui, for: slot) { failed = false }
                    else { failed = true }
                    item = nil
                }
            }
        }
    }
}


// MARK: 弾幕(ステージ作りで使える新しい弾のパターン)

/// 永久買い切りパック: いまある課金コンテンツ・広告削除・これから増える課金コンテンツが、全部使える
private struct LifetimeCard: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    private let items = ["lifetime.item.1", "lifetime.item.2", "lifetime.item.3", "lifetime.item.4"]

    var body: some View {
        ShopCard(title: "lifetime.title", footer: "lifetime.footer") {
            CardBody {
                VStack(alignment: .leading, spacing: 10) {
                    Text("lifetime.tagline").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
                    ForEach(items, id: \.self) { k in
                        Label(LocalizedStringKey(k), systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color(Palette.text))
                    }
                    HStack {
                        Spacer()
                        if cosmetics.ownership.canBuy(.lifetime) { PriceButton(product: .lifetime) }
                        else { Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4])) }
                    }
                }
                .padding(14)
                .background(LinearGradient(colors: [Color(Palette.pink).opacity(0.22), Color(Palette.gold).opacity(0.12)], startPoint: .leading, endPoint: .trailing))
            }
        }
        .accessibilityIdentifier("shop.lifetime")
    }
}

/// 弾幕作成モード(有料)の販売カード。どう作るかを、動く見本で見せる(線を描く → 弾がその線の上を進む)
private struct MakerCard: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showMaker = false

    var body: some View {
        ShopCard(title: "maker.title", footer: "maker.footer") {
            CardBody {
                VStack(alignment: .leading, spacing: 12) {
                    Text("maker.tagline").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
                    MakerDemo()
                        .aspectRatio(PatternDemoEngine.fieldWidth / PatternDemoEngine.fieldHeight, contentMode: .fit)
                        .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("maker.how").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        if cosmetics.ownership.hasPatternMaker {
                            Button { gameTap(); showMaker = true } label: {
                                Label("maker.open", systemImage: "pencil.and.scribble").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                                    .padding(.vertical, 8).padding(.horizontal, 14)
                                    .background(LinearGradient(colors: [Color(Palette.pink), Color(UIColor(hex: 0xFF8A5C))], startPoint: .leading, endPoint: .trailing), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("maker.open")
                        } else {
                            PriceButton(product: .patternMaker)
                        }
                    }
                }
                .padding(14)
            }
        }
        .fullScreenCover(isPresented: $showMaker) { PatternMakerView() }
    }
}

/// 販売画面の見本: 指で線を描く → 弾がその線の上を、描いた速さで進む(ゲームと同じ計算)
private struct MakerDemo: View {
    /// 見本の線: 左右に揺れながら下へ進む(0.1秒ごとの点)
    static let path: [Double] = PathData.sanitized((0..<40).flatMap { i -> [Double] in [60 * sin(Double(i) * 0.35), Double(i) * 6.5] }) ?? []
    static let drawSeconds = 4.0, cycle = 9.0
    @State private var engine = PatternDemoEngine(source: Point(x: 180, y: 40), player: Point(x: 180, y: 290), sweepPlayer: false)

    var body: some View {
        let images = SpriteFactory.bulletImages(.classic)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                let s = size.width / CGFloat(PatternDemoEngine.fieldWidth)
                let now = tl.date.timeIntervalSinceReferenceDate
                let t = now.truncatingRemainder(dividingBy: Self.cycle)
                let origin = CGPoint(x: 180, y: 40)
                let n = Self.path.count / 2
                let drawing = t < Self.drawSeconds
                let shown = drawing ? max(2, Int(Double(n) * t / Self.drawSeconds)) : n
                func pt(_ i: Int) -> CGPoint { CGPoint(x: (origin.x + Self.path[2 * i]) * s, y: (origin.y + Self.path[2 * i + 1]) * s) }
                var line = Path()
                line.move(to: pt(0))
                for i in 1..<shown { line.addLine(to: pt(i)) }
                ctx.stroke(line, with: .color(Color(Palette.gold).opacity(drawing ? 0.9 : 0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: drawing ? [] : [4, 4]))
                // 発射位置
                let bossSide = 38 * s
                ctx.fill(GameBossShape().path(in: CGRect(x: origin.x * s - bossSide / 2, y: origin.y * s - bossSide / 2, width: bossSide, height: bossSide)),
                         with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                if drawing {
                    // 線を描いている指
                    let f = pt(shown - 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: f.x - 9, y: f.y - 9, width: 18, height: 18)), with: .color(.white.opacity(0.85)))
                } else {
                    var m = Emitter(t: .custom, x: 0.5, y: 0.2, s: 0, e: 60, i: 0.9, c: 5, v: 2, r: 0, k: 1, path: Self.path)
                    m.a = 0
                    engine.advance(to: tl.date, emitters: [m], key: Int(floor(now / Self.cycle)))
                    let bs = 12 * s
                    for b in engine.bullets { ctx.draw(Image(uiImage: images[b.color % images.count]), in: CGRect(x: b.x * s - bs / 2, y: b.y * s - bs / 2, width: bs, height: bs)) }
                }
            }
            .overlay(alignment: .topLeading) {
                Text(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: Self.cycle) < Self.drawSeconds ? "maker.demo.step1" : "maker.demo.step2")
                    .font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.vertical, 3).padding(.horizontal, 8).background(Color.black.opacity(0.5), in: Capsule()).padding(8)
            }
        }
    }
}

/// 広告を見て1日1つ解放する30パターン(広告削除・永久買い切りパックの購入者は、広告なしで)
private struct AdPatternCard: View {
    @EnvironmentObject private var adPatterns: AdPatternStore
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var busy = false

    private var all: Bool { cosmetics.ownership.hasLifetime }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("shop.adpattern.title").font(.system(size: 22, weight: .heavy, design: .rounded))
                Spacer()
                Text(String(format: L("shop.adpattern.progress"), all ? Pattern.ad.count : adPatterns.state.claimed, Pattern.ad.count))
                    .font(.footnote.bold()).foregroundStyle(Color(Palette.gold))
            }
            .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 14) {
                if let next = adPatterns.state.next, !all {
                    HStack(spacing: 14) {
                        PatternDemo(pattern: next)
                            .aspectRatio(PatternDemoEngine.fieldWidth / PatternDemoEngine.fieldHeight, contentMode: .fit)
                            .frame(width: 150)
                            .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 8) {
                            Text("shop.adpattern.next").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(L("pattern.\(next.rawValue)")).font(.system(size: 18, weight: .heavy, design: .rounded))
                            claimButton
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Label(all ? "shop.adpattern.lifetime" : "shop.adpattern.complete", systemImage: "crown.fill")
                        .font(.headline).foregroundStyle(Color(Palette.gold))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Pattern.ad, id: \.self) { p in
                            let open = cosmetics.ownership.has(p)
                            VStack(spacing: 4) {
                                PatternDemo(pattern: p)
                                    .aspectRatio(PatternDemoEngine.fieldWidth / PatternDemoEngine.fieldHeight, contentMode: .fit)
                                    .frame(width: 92)
                                    .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .opacity(open ? 1 : 0.4)
                                    .overlay { if !open { Image(systemName: "lock.fill").foregroundStyle(Color(Palette.gold)) } }
                                Text(L("pattern.\(p.rawValue)")).font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(open ? Color(Palette.text) : .secondary).lineLimit(1).minimumScaleFactor(0.7)
                            }
                            .frame(width: 92)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08)))

            Text(purchases.isPremium ? "shop.adpattern.footer.premium" : "shop.adpattern.footer")
                .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
        .onAppear { adPatterns.refreshDay() }
        .onChange(of: scenePhase) { if $0 == .active { adPatterns.refreshDay() } }
        .accessibilityIdentifier("adpatterns.card")
    }

    @ViewBuilder private var claimButton: some View {
        if !adPatterns.canClaim {
            Label("shop.adpattern.claimed", systemImage: "checkmark.circle.fill")
                .font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
        } else {
            let ready = purchases.isPremium || ads.isReady
            Button { Task { await claim() } } label: {
                Label(purchases.isPremium ? "shop.adpattern.claim.free" : "shop.adpattern.claim.ad", systemImage: purchases.isPremium ? "gift.fill" : "play.rectangle.fill")
                    .font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .padding(.vertical, 8).padding(.horizontal, 14)
                    .background(LinearGradient(colors: [Color(Palette.pink), Color(UIColor(hex: 0xFF8A5C))], startPoint: .leading, endPoint: .trailing), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!ready || busy)
            .opacity(ready && !busy ? 1 : 0.5)
            .accessibilityIdentifier("adpatterns.claim")
            if !ready { Text("daily.loading").font(.caption2).foregroundStyle(.secondary) }
        }
    }

    private func claim() async {
        busy = true
        defer { busy = false }
        if purchases.isPremium {
            adPatterns.claim()
        } else if await ads.showRewarded() {
            adPatterns.claim()
        }
        if adPatterns.justUnlocked != nil {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            AudioManager.shared.se(.get)
        }
    }
}

/// 買えるパターンのカード(バラと全部入り)。弾幕パック1とパック2で同じ形
private struct PatternShop: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var purchases: PurchaseService
    var patterns: [Pattern] = Pattern.paid
    var pack: Product = .patternPack
    var title: LocalizedStringKey = "shop.pattern.title"
    var footer: LocalizedStringKey = "shop.pattern.footer"
    var packTitle: LocalizedStringKey = "shop.pattern.pack"

    private var singles: [Product] { patterns.map { Product.pattern($0) } }

    var body: some View {
        ShopCard(title: title, footer: footer) {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(patterns, id: \.self) { PatternTile(pattern: $0) } }
                        .padding(.horizontal, 2).padding(.vertical, 2)
                }
                CardBody {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(packTitle).font(.system(size: 17, weight: .heavy, design: .rounded))
                            if let total = purchases.totalText(singles), let price = purchases.prices[pack] {
                                HStack(spacing: 6) {
                                    Text(total).strikethrough().foregroundStyle(.secondary)
                                    Text("→").foregroundStyle(.secondary)
                                    Text(price).foregroundStyle(Color(Palette.gold)).bold()
                                }.font(.caption)
                            }
                        }
                        Spacer()
                        if cosmetics.ownership.canBuy(pack) { PriceButton(product: pack) }
                        else { Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4])) }
                    }
                    .padding(14)
                    .background(LinearGradient(colors: [Color(Palette.pink).opacity(0.18), Color(Palette.gold).opacity(0.10)], startPoint: .leading, endPoint: .trailing))
                }
            }
        }
    }
}

private struct PatternTile: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let pattern: Pattern

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PatternDemo(pattern: pattern)
                .aspectRatio(PatternDemoEngine.fieldWidth / PatternDemoEngine.fieldHeight, contentMode: .fit)
                .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(L("pattern.\(pattern.rawValue)")).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(L("shop.pattern.\(pattern.rawValue)")).font(.caption).foregroundStyle(.secondary)
                .frame(height: 44, alignment: .topLeading)
            HStack {
                Spacer()
                if cosmetics.ownership.has(pattern) {
                    Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote.bold()).foregroundStyle(Color(Palette.bullets[4]))
                } else {
                    PriceButton(product: .pattern(pattern))
                }
            }
        }
        .padding(12)
        .frame(width: 200)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.white.opacity(0.08), lineWidth: 1.5))
    }
}

/// そのパターンを、実際のゲームと同じ計算で動かして見せる(DanmakuCore の emit をそのまま使う)
private struct PatternDemo: View {
    let pattern: Pattern
    @State private var engine = PatternDemoEngine()

    var body: some View {
        let images = SpriteFactory.bulletImages(.classic)
        let boomerangs = SpriteFactory.boomerangImages(.classic)
        let ship = SpriteFactory.shipImage(.classic)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                engine.advance(to: tl.date, pattern: pattern)
                // 縦横同じ倍率で描く(実際の画面の一部。幅 360 を枠いっぱいに使う)
                let s = size.width / CGFloat(PatternDemoEngine.fieldWidth)
                // 弾・自機・ボスは、ゲームと同じ大きさ(弾 12×12、自機 20×24、ボス = 中サイズの 48)
                let c = engine.source
                let bossSide = EnemyArt.bossPoints(size: 1) * s
                ctx.fill(GameBossShape().path(in: CGRect(x: c.x * s - bossSide / 2, y: c.y * s - bossSide / 2, width: bossSide, height: bossSide)),
                         with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                let p = engine.player
                ctx.draw(Image(uiImage: ship), in: CGRect(x: p.x * s - 10 * s, y: p.y * s - 12 * s, width: 20 * s, height: 24 * s))
                for b in engine.bullets {
                    ctx.drawBullet(b, images: images, boomerangs: boomerangs, colors: Skin.of(.classic).bulletColors, scale: s,
                                   time: tl.date.timeIntervalSinceReferenceDate)
                }
            }
        }
    }
}

/// ショップの見本用に、ゲーム本体と同じ計算(Emit.emit と Bullet.advance)で弾を動かす。複数の発射台も扱える
final class PatternDemoEngine {
    /// 見せる範囲(論理px)。実際の画面は 360×540 で、その上の 360×fieldHeight を縦横同じ倍率で見せる
    static let fieldWidth = 360.0
    static let fieldHeight = 330.0

    private var t = 0.0
    private var next: [Double] = []
    private var shot: [Int] = []
    private var rng = Mulberry32(seed: 5)
    private var last: Date?
    private(set) var bullets: [Bullet] = []
    private(set) var player: Point
    var source: Point
    private var emitters: [Emitter] = []
    private var key: AnyHashable?
    private let sweepPlayer: Bool

    /// source: 発射位置、player: 自機の位置、sweepPlayer: 自機を左右に動かす(狙う弾を見せるため)
    init(source: Point = Point(x: 180, y: 50), player: Point = Point(x: 180, y: 290), sweepPlayer: Bool = true) {
        self.source = source
        self.player = player
        self.sweepPlayer = sweepPlayer
    }

    func advance(to now: Date, pattern: Pattern) {
        var m = Emitter.make(pattern, end: 60)
        m.k = pattern == .heart ? 0 : (pattern == .flower ? 3 : pattern == .star ? 2 : 1)
        advance(to: now, emitters: [m], key: pattern)
    }

    func advance(to now: Date, emitters list: [Emitter], key: AnyHashable) {
        if self.key != key {
            emitters = list; self.key = key; bullets = []; t = 0
            next = Array(repeating: 0, count: list.count); shot = Array(repeating: 0, count: list.count)
        }
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        t += dt
        if sweepPlayer { player = Point(x: 180 + sin(t * 0.8) * 100, y: player.y) }
        for (n, m) in emitters.enumerated() {
            while t >= next[n] {
                Emit.emit(m, shot: shot[n], cx: source.x, cy: source.y, px: player.x, py: player.y, rng: &rng, into: &bullets)
                shot[n] += 1
                next[n] += max(0.05, m.i)
            }
        }
        var w = 0
        var born: [Bullet] = []
        for i in 0..<bullets.count {
            var b = bullets[i]
            // ゲーム本体と同じ動き(止まる・分裂・追尾・加速・反射)
            let motion = b.advance(dt: dt, width: DanmakuConfig.width, playerX: player.x, playerY: player.y)
            if motion == .burst {
                born.append(contentsOf: b.fragments())
                continue
            }
            if motion == .gone { continue }   // 撃ち終わったチャージビーム
            if b.x < -20 || b.x > DanmakuConfig.width + 20 || b.y < -20 || b.y > Self.fieldHeight + 20 { continue }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        bullets.append(contentsOf: born)
    }
}
