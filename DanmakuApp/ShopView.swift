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

                    CustomImagesCard().id("customimages")
                    ShotSection().id("shots")
                    PatternShop().id("patterns")
                    ForEach(Theme.paid, id: \.self) { ThemeCard(theme: $0) }
                    ThemeCard(theme: .classic)

                    Button("store.restore") { Task { await purchases.restore() } }
                        .frame(maxWidth: .infinity)
                        .disabled(purchases.isBusy)
                        .accessibilityIdentifier("shop.restore")
                    if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity) }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
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
            Text(purchases.prices[product] ?? "¥\(product.yen)")
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
                .frame(height: 96)
                .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(LocalizedStringKey(shot.nameKey)).font(.system(size: 18, weight: .heavy, design: .rounded))
            Text(LocalizedStringKey(shot.detailKey)).font(.caption).foregroundStyle(.secondary)
                .frame(height: 48, alignment: .topLeading)
            HStack {
                Spacer()
                if cosmetics.ownership.has(shot) {
                    if cosmetics.loadout.shot == shot { EquippedLabel() } else { EquipButton { cosmetics.equip(shot) } }
                } else {
                    PriceButton(product: .shot(shot))
                }
            }
        }
        .padding(12)
        .frame(width: 210)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(cosmetics.loadout.shot == shot ? Color(Palette.bullets[4]).opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1.5))
    }
}

// MARK: テーマ(弾・背景・自機)

private struct ThemeCard: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let theme: Theme

    private var partsYen: Int { ThemePart.allCases.map { Product.part(theme, $0).yen }.reduce(0, +) }
    private var offPercent: Int { theme == .classic ? 0 : Int((1 - Double(Product.set(theme).yen) / Double(partsYen)) * 100 + 0.5) }

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
                HStack(spacing: 6) {
                    Text("¥\(partsYen)").strikethrough().foregroundStyle(.secondary)
                    Text("→").foregroundStyle(.secondary)
                    Text("¥\(Product.set(theme).yen)").foregroundStyle(Color(Palette.gold)).bold()
                }.font(.caption)
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

private struct PatternShop: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore

    private var singlesYen: Int { Pattern.paid.map { Product.pattern($0).yen }.reduce(0, +) }

    var body: some View {
        ShopCard(title: "shop.pattern.title", footer: "shop.pattern.footer") {
            VStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) { ForEach(Pattern.paid, id: \.self) { PatternTile(pattern: $0) } }
                        .padding(.horizontal, 2).padding(.vertical, 2)
                }
                CardBody {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("shop.pattern.pack").font(.system(size: 17, weight: .heavy, design: .rounded))
                            HStack(spacing: 6) {
                                Text("¥\(singlesYen)").strikethrough().foregroundStyle(.secondary)
                                Text("→").foregroundStyle(.secondary)
                                Text("¥\(Product.patternPack.yen)").foregroundStyle(Color(Palette.gold)).bold()
                            }.font(.caption)
                        }
                        Spacer()
                        if cosmetics.ownership.canBuy(.patternPack) { PriceButton(product: .patternPack) }
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
    private static let keys: [Pattern: String] = [
        .homing: "pattern.homing", .flower: "pattern.flower", .star: "pattern.star", .heart: "pattern.heart",
        .beam: "pattern.beam", .cross: "pattern.cross", .accel: "pattern.accel", .bounce: "pattern.bounce",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PatternDemo(pattern: pattern)
                .frame(height: 120)
                .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(LocalizedStringKey(Self.keys[pattern] ?? "")).font(.system(size: 18, weight: .heavy, design: .rounded))
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
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            Canvas { ctx, size in
                engine.advance(to: tl.date, pattern: pattern)
                let sx = size.width / 360
                let sy = size.height / 330
                ctx.scaleBy(x: sx, y: sy)
                let c = engine.source
                ctx.fill(GameBossShape().path(in: CGRect(x: c.x - 18, y: c.y - 18, width: 36, height: 36)), with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                let ship = engine.player
                ctx.fill(GameShipShape().path(in: CGRect(x: ship.x - 9, y: ship.y - 11, width: 18, height: 22)), with: .color(Color(UIColor(hex: 0x5CE1E6))))
                for b in engine.bullets {
                    let r: CGFloat = 8
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)), with: .color(Color(Palette.bullets[b.color % 5])))
                    ctx.fill(Path(ellipseIn: CGRect(x: b.x - 3.5, y: b.y - 3.5, width: 7, height: 7)), with: .color(.white))
                }
            }
        }
    }
}

final class PatternDemoEngine {
    private var sim: Simulation?
    private var t = 0.0
    private var next = 0.0
    private var shot = 0
    private var rng = Mulberry32(seed: 5)
    private var last: Date?
    private(set) var bullets: [Bullet] = []
    private(set) var player = Point(x: 180, y: 290)
    let source = Point(x: 180, y: 50)
    private var emitter: Emitter?
    private var emitterPattern: Pattern?

    func advance(to now: Date, pattern: Pattern) {
        if emitterPattern != pattern {
            var m = Emitter.make(pattern, end: 60)
            m.k = pattern == .heart ? 0 : (pattern == .flower ? 3 : pattern == .star ? 2 : 1)
            emitter = m; emitterPattern = pattern; bullets = []; t = 0; next = 0; shot = 0
        }
        guard let m = emitter else { return }
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        t += dt
        player = Point(x: 180 + sin(t * 0.8) * 100, y: 290)
        while t >= next {
            Emit.emit(m, shot: shot, cx: source.x, cy: source.y, px: player.x, py: player.y, rng: &rng, into: &bullets)
            shot += 1
            next += max(0.05, m.i)
        }
        var w = 0
        for i in 0..<bullets.count {
            var b = bullets[i]
            if b.homeLeft > 0 {
                let want = atan2(player.y - b.y, player.x - b.x), cur = atan2(b.vy, b.vx)
                var d = want - cur
                while d > .pi { d -= 2 * .pi }
                while d < -.pi { d += 2 * .pi }
                let na = cur + min(b.turn * dt, max(-b.turn * dt, d))
                let sp = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                b.vx = cos(na) * sp; b.vy = sin(na) * sp; b.homeLeft -= dt
            }
            if b.accel != 0 {
                let sp = (b.vx * b.vx + b.vy * b.vy).squareRoot()
                if sp < b.maxSpeed { let g = min(1 + b.accel * dt, b.maxSpeed / sp); b.vx *= g; b.vy *= g }
            }
            b.x += b.vx * dt; b.y += b.vy * dt
            if b.bounces > 0 {
                if b.x < 0 { b.x = -b.x; b.vx = -b.vx; b.bounces -= 1 }
                else if b.x > 360 { b.x = 720 - b.x; b.vx = -b.vx; b.bounces -= 1 }
            }
            if b.x < -20 || b.x > 380 || b.y < -20 || b.y > 350 { continue }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
    }
}
