import SwiftUI
import PhotosUI
import DanmakuCore

/// きせかえ・ショップ。弾の色・背景・自機の見た目と、自機の撃ち方を買って、選ぶ画面
struct ShopView: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var showRemoveAds = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("shop.intro").font(.footnote).foregroundStyle(.secondary)
                    if !purchases.isPremium {
                        Button { showRemoveAds = true } label: { Label("revive.removeads", systemImage: "nosign") }
                            .accessibilityIdentifier("shop.removeads")
                    }
                }
                CustomImagesSection()

                Section {
                    ForEach(ShotType.allCases, id: \.self) { ShotRow(shot: $0) }
                } header: { Text("shop.section.shot") } footer: { Text("shop.shot.footer") }

                ThemeSection(theme: .classic)
                ForEach(Theme.paid, id: \.self) { ThemeSection(theme: $0) }

                Section {
                    Button("store.restore") { Task { await purchases.restore() } }
                        .disabled(purchases.isBusy)
                        .accessibilityIdentifier("shop.restore")
                    if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("shop.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("editor.close") { dismiss() } } }
            .task { await purchases.refresh() }
        }
        .sheet(isPresented: $showRemoveAds) { StoreView() }
        .preferredColorScheme(.dark)
    }
}

private struct PriceButton: View {
    @EnvironmentObject private var purchases: PurchaseService
    let product: Product

    var body: some View {
        let available = purchases.prices[product] != nil
        Button { Task { await purchases.purchase(product) } } label: {
            Text(purchases.prices[product] ?? "¥\(product.yen)")
                .font(.subheadline.bold()).frame(minWidth: 64)
        }
        .buttonStyle(.borderedProminent).tint(Color(Palette.pink))
        .disabled(!available || purchases.isBusy)
        .accessibilityIdentifier("shop.buy.\(product.id)")
    }
}

private struct ShotRow: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let shot: ShotType

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(shot.nameKey)).font(.headline)
                Text(LocalizedStringKey(shot.detailKey)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if cosmetics.ownership.has(shot) {
                if cosmetics.loadout.shot == shot {
                    Label("shop.equipped", systemImage: "checkmark.circle.fill").labelStyle(.titleAndIcon)
                        .font(.footnote).foregroundStyle(Color(Palette.bullets[4]))
                } else {
                    Button("shop.equip") { cosmetics.equip(shot) }.buttonStyle(.bordered)
                }
            } else {
                PriceButton(product: .shot(shot))
            }
        }
    }
}

private struct ThemeSection: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let theme: Theme

    var body: some View {
        Section {
            ForEach(ThemePart.allCases, id: \.self) { PartRow(theme: theme, part: $0) }
            if theme != .classic {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("shop.set").font(.headline)
                        Text("shop.set.detail").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if cosmetics.ownership.canBuy(.set(theme)) {
                        PriceButton(product: .set(theme))
                    } else {
                        Label("shop.owned", systemImage: "checkmark.seal.fill").font(.footnote)
                            .foregroundStyle(Color(Palette.bullets[4]))
                    }
                }
            }
        } header: {
            Text(LocalizedStringKey(theme.nameKey))
        }
    }
}

private struct PartRow: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    let theme: Theme
    let part: ThemePart

    var body: some View {
        HStack(spacing: 12) {
            preview.frame(width: 84, alignment: .leading)
            Text(LocalizedStringKey(part.nameKey))
            Spacer()
            if cosmetics.ownership.has(part, of: theme) {
                if cosmetics.loadout.theme(for: part) == theme {
                    Label("shop.equipped", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(Color(Palette.bullets[4]))
                } else {
                    Button("shop.equip") { cosmetics.equip(theme, for: part) }.buttonStyle(.bordered)
                }
            } else {
                PriceButton(product: .part(theme, part))
            }
        }
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


/// 自分の画像: ボス・弾・自機を、写真アプリから選んだ画像に差し替える(見た目だけ。画像は端末の中にだけ保存する)
private struct CustomImagesSection: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        Section {
            if cosmetics.ownership.hasCustomImages {
                ForEach(CustomSlot.allCases) { CustomSlotRow(slot: $0) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("shop.custom.title").font(.headline)
                    Text("shop.custom.intro").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    PriceButton(product: .customImages)
                }
            }
        } header: {
            Text("shop.custom.title")
        } footer: {
            Text("shop.custom.footer")
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
                Text(LocalizedStringKey(slot.nameKey)).font(.body)
                if failed { Text("shop.custom.failed").font(.caption).foregroundStyle(.red) }
                else if image == nil { Text("shop.custom.empty").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if image != nil {
                Toggle("shop.custom.use", isOn: Binding(get: { cosmetics.isCustomEnabled(slot) },
                                                       set: { cosmetics.setCustomEnabled(slot, $0) }))
                    .labelsHidden()
                Button(role: .destructive) { cosmetics.removeCustomImage(slot) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            PhotosPicker(selection: $item, matching: .images) {
                Text(image == nil ? "shop.custom.pick" : "shop.custom.change").font(.footnote.bold())
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("shop.custom.pick.\(slot.rawValue)")
        }
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
