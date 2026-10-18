import SwiftUI

/// 広告削除（買い切り）の購入画面。購入の復元ボタンを置く
struct StoreView: View {
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("store.title").font(.title2.bold())
                VStack(alignment: .leading, spacing: 8) {
                    Label("store.benefit.noads", systemImage: "nosign")
                    Label("store.benefit.revive", systemImage: "arrow.counterclockwise")
                    Label("store.benefit.once", systemImage: "checkmark.seal")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if purchases.isPremium {
                    Text("store.purchased").foregroundStyle(Color(Palette.bullets[4])).font(.headline)
                } else {
                    Button { Task { await purchases.purchase() } } label: {
                        Text(purchases.priceText.map { String(format: L("store.buy"), $0) } ?? L("store.buy.noprice")).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(Color(Palette.pink)).controlSize(.large)
                    .disabled(purchases.isBusy || purchases.priceText == nil)
                    .accessibilityIdentifier("store.buy")
                }
                Button("store.restore") { Task { await purchases.restore() } }
                    .disabled(purchases.isBusy)
                    .accessibilityIdentifier("store.restore")
                if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("editor.close") { dismiss() } } }
            .task { await purchases.refresh() }
        }
        .preferredColorScheme(.dark)
    }
}
