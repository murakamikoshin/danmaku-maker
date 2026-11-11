import SwiftUI

/// 広告削除(買い切り)の購入画面。購入の復元ボタンを置く
struct StoreView: View {
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "store.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
            } trailing: { Color.clear.frame(width: 38, height: 38) }
            ScrollView {
                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(GameStyle.pinkColor.opacity(0.18)).frame(width: 110, height: 110)
                        Image(systemName: "nosign").font(.system(size: 52, weight: .heavy)).foregroundStyle(GameStyle.accent)
                    }
                    .padding(.top, 8)
                    VStack(alignment: .leading, spacing: 10) {
                        benefit("store.benefit.noads", "nosign")
                        benefit("store.benefit.revive", "arrow.counterclockwise")
                        benefit("store.benefit.once", "checkmark.seal")
                    }
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameStyle.panel, in: PixelRect(cornerRadius: 18))
                    .overlay(PixelRect(cornerRadius: 18).stroke(GameStyle.edge))
                    if purchases.isPremium {
                        Label("store.purchased", systemImage: "checkmark.seal.fill").font(.display(15))
                            .foregroundStyle(Color(Palette.bullets[4]))
                    } else {
                        GameActionButton(title: purchases.priceText.map { LocalizedStringKey(String(format: L("store.buy"), $0)) } ?? "store.buy.noprice",
                                         systemImage: "cart.fill", fill: GameStyle.accent,
                                         enabled: !purchases.isBusy && purchases.priceText != nil) { Task { await purchases.purchase() } }
                            .accessibilityIdentifier("store.buy")
                    }
                    Button { gameTap(); Task { await purchases.restore() } } label: {
                        Text("store.restore").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 14))
                    }
                    .buttonStyle(BounceButtonStyle()).disabled(purchases.isBusy)
                    .accessibilityIdentifier("store.restore")
                    if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(20)
            }
        }
        .background(GameStyle.night.ignoresSafeArea())
        .task { await purchases.refresh() }
        .preferredColorScheme(.dark)
    }

    private func benefit(_ key: LocalizedStringKey, _ symbol: String) -> some View {
        Label { Text(key).font(.system(size: 15, weight: .semibold)).foregroundStyle(GameStyle.text) }
            icon: { Image(systemName: symbol).foregroundStyle(GameStyle.yellow).frame(width: 24) }
    }
}
