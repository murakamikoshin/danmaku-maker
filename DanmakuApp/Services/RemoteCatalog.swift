import DanmakuCore
import FirebaseFirestore
import ImageIO
import RevenueCat
import SwiftUI
import UIKit

/// サーバーから配る商品(アプリの更新なしで、ショップに出せるもの)。いまは、ドット絵の自機だけ。
/// 絵や数値のデータだけを受け取る(動きを変えるプログラムは受け取らない)。Firestore の catalog/shop を読んで、端末にも残す。
/// 読めなかったり、壊れていたり、知らない種類だったりしたら、そのぶんは飛ばす(アプリは普通に動く)。
/// 形: { v: 1, items: [{ id: "x_foo", kind: "ship", name: { ja, en, … }, free: true | productId: "com.koshin.danmakumaker.…", frames: [PNG の base64 …], order: [0,1,2,1] }] }
@MainActor
final class RemoteCatalog: ObservableObject {
    static let shared = RemoteCatalog()

    struct Item: Identifiable, Equatable {
        let id: String
        let names: [String: String]
        let free: Bool
        let productId: String?
        let frames: [UIImage]
        var name: String {
            let lang = Locale.preferredLanguages.first ?? "en"
            for k in [lang, String(lang.prefix(2)), "en", "ja"] { if let n = names[k] { return n } }
            return id
        }
    }

    @Published private(set) var items: [Item] = []
    private let defaults = UserDefaults.standard
    private static let cacheKey = "remoteCatalog.v1"
    static let maxItems = 60

    /// 配る自機の ID か(形だけ。中身は catalog にあるか)
    nonisolated static func isRemoteID(_ id: String) -> Bool {
        id.count <= 28 && id.hasPrefix("x_") && id.dropFirst(2).allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" }
    }

    init() {
        if let data = defaults.data(forKey: Self.cacheKey), let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { items = Self.parse(d) }
    }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    /// サーバーの最新を読む(読めなければ、端末に残してあるものをそのまま使う)
    func refresh() async {
        guard Backend.isAvailable else { return }
        guard let snap = try? await Firestore.firestore().document("catalog/shop").getDocument(), let d = snap.data() else { return }
        let parsed = Self.parse(d)
        if let data = try? JSONSerialization.data(withJSONObject: d) { defaults.set(data, forKey: Self.cacheKey) }
        if parsed != items { items = parsed }
        CosmeticsStore.shared.catalogChanged()
    }

    /// 形と大きさを確かめて、使えるものだけ取り出す
    static func parse(_ d: [String: Any]) -> [Item] {
        guard (d["v"] as? NSNumber)?.intValue == 1, let raw = d["items"] as? [[String: Any]] else { return [] }
        var out: [Item] = [], seen = Set<String>()
        for r in raw.prefix(maxItems) {
            guard r["kind"] as? String == "ship", let id = r["id"] as? String, isRemoteID(id), !seen.contains(id),
                  let names = r["name"] as? [String: String], !names.isEmpty,
                  let b64 = r["frames"] as? [String], (3...8).contains(b64.count) else { continue }
            let free = r["free"] as? Bool ?? false
            let product = r["productId"] as? String
            guard free || (product?.hasPrefix(DanmakuCore.Product.idPrefix) ?? false) else { continue }   // 無料か、うちの商品 ID のものだけ
            let imgs = b64.compactMap { s -> UIImage? in
                guard let data = Data(base64Encoded: s), data.count < 20_000, let src = CGImageSourceCreateWithData(data as CFData, nil),
                      let cg = CGImageSourceCreateImageAtIndex(src, 0, nil), cg.width == 32, cg.height == 32 else { return nil }
                return UIImage(cgImage: cg, scale: 1, orientation: .up)
            }
            guard imgs.count == b64.count else { continue }
            let order = (r["order"] as? [NSNumber])?.map(\.intValue) ?? Array(0..<imgs.count)
            guard !order.isEmpty, order.allSatisfy({ imgs.indices.contains($0) }) else { continue }
            seen.insert(id)
            out.append(Item(id: id, names: names.mapValues { String($0.prefix(24)) }, free: free, productId: free ? nil : product, frames: order.map { imgs[$0] }))
        }
        return out
    }
}

// MARK: ショップの「新着」

/// 見た目のタブの先頭に出す、サーバーから配る自機。無料のものは「もらう」、有料のものは「買う」
struct RemoteShopSection: View {
    @ObservedObject private var catalog = RemoteCatalog.shared
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var purchases: PurchaseService
    @State private var prices: [String: String] = [:]

    var body: some View {
        if !catalog.items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("shop.new.title").font(.display(20)).padding(.horizontal, 4)
                ForEach(catalog.items) { item in
                    HStack(spacing: 12) {
                        SkinThumb(id: item.id).frame(width: 56, height: 56)
                            .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 10))
                        Text(item.name).font(.system(size: 15, weight: .heavy)).lineLimit(2)
                        Spacer(minLength: 0)
                        action(item)
                    }
                    .padding(12)
                    .background(GameStyle.panel, in: PixelRect(cornerRadius: 18))
                    .accessibilityIdentifier("shop.new.\(item.id)")
                }
                Text("shop.new.footer").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .task { await loadPrices() }
        }
    }

    @ViewBuilder private func action(_ item: RemoteCatalog.Item) -> some View {
        if cosmetics.ownedSkins.contains(item.id) {
            Label("shop.new.owned", systemImage: "checkmark.circle.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(Palette.gold))
        } else if item.free {
            Button { gameTap(); cosmetics.claimRemoteShip(item.id) } label: { pill(L("shop.new.free")) }.buttonStyle(.plain)
        } else if let pid = item.productId {
            Button { gameTap(); Task { await purchases.buyRemoteShip(item) } } label: { pill(prices[pid] ?? L("shop.new.buy")) }
                .buttonStyle(.plain).disabled(prices[pid] == nil)
        }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.ink)
            .padding(.vertical, 8).padding(.horizontal, 14).background(Color(Palette.bullets[4]), in: PixelRect(cornerRadius: 8))
    }

    private func loadPrices() async {
        for item in catalog.items { if let pid = item.productId, prices[pid] == nil, let p = await purchases.price(of: pid) { prices[pid] = p } }
    }
}
