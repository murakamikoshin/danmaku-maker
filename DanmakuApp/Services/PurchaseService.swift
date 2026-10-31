import Foundation
import RevenueCat
import DanmakuCore

/// 課金の窓口。広告削除（買い切り）と、見た目・撃ち方の買い切り商品を扱う。
/// 広告削除の購入者は復活が無料・無制限になり、広告は一切出ない。
@MainActor
final class PurchaseService: NSObject, ObservableObject {
    static let entitlementID = "no_ads"
    static let removeAdsID = Product.idPrefix + "removeads"

    @Published private(set) var isPremium = false
    @Published private(set) var priceText: String?
    @Published private(set) var isBusy = false
    @Published var message: String?
    /// 買えたばかりの商品(ショップの紙吹雪に使う。画面側が消す)
    @Published var celebration: Product?
    /// 商品ごとの価格表示（App Store から取得できたものだけ）
    @Published private(set) var prices: [Product: String] = [:]
    /// 商品ごとの価格の数字と、表示の書式(App Store の国の通貨)。合計や割引率の計算に使う
    @Published private(set) var amounts: [Product: Decimal] = [:]
    private var priceFormatter: NumberFormatter?

    private var package: Package?
    private var storeProducts: [Product: StoreProduct] = [:]
    private(set) var isConfigured = false
    private let cosmetics = CosmeticsStore.shared

    /// RevenueCat の公開 API キー（ビルド設定 REVENUECAT_API_KEY）。空なら課金機能は無効
    func start() {
        guard !isConfigured else { return }
        let key = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
        guard !key.isEmpty, !key.hasPrefix("$(") else { return }
        Purchases.configure(withAPIKey: key)
        Purchases.shared.delegate = self
        isConfigured = true
    }

    func refresh() async {
        guard isConfigured else { return }
        if let info = try? await Purchases.shared.customerInfo() { apply(info) }
        if let offering = try? await Purchases.shared.offerings().current {
            package = offering.lifetime ?? offering.availablePackages.first
            priceText = package?.storeProduct.localizedPriceString
        }
        let ids = Product.all.map(\.id) + [Self.removeAdsID]
        let fetched = await Purchases.shared.products(ids)
        for sp in fetched {
            if sp.productIdentifier == Self.removeAdsID {
                if priceText == nil { priceText = sp.localizedPriceString }
            } else if let p = Product(id: sp.productIdentifier) {
                storeProducts[p] = sp
                prices[p] = sp.localizedPriceString
                amounts[p] = sp.price
                if priceFormatter == nil { priceFormatter = sp.priceFormatter }
            }
        }
    }

    /// 広告削除を買う
    func purchase() async {
        guard let package else { message = L("store.unavailable"); return }
        await run { try await Purchases.shared.purchase(package: package) }
    }

    /// 見た目・撃ち方の商品を買う。買えたら、そのまま装備する
    func purchase(_ product: Product) async {
        guard let sp = storeProducts[product] else { message = L("store.unavailable"); return }
        await run { try await Purchases.shared.purchase(product: sp) }
        autoEquip(product)
        if !cosmetics.ownership.canBuy(product) { celebration = product }
    }

    private func run(_ buy: () async throws -> PurchaseResultData) async {
        isBusy = true; defer { isBusy = false }
        do {
            let result = try await buy()
            if !result.userCancelled { apply(result.customerInfo) }
        } catch {
            message = L("store.failed")
        }
    }

    private func autoEquip(_ product: Product) {
        switch product {
        case .part, .set: break   // 見た目は、ステージ作りで選ぶ(装備はない)
        case .shot(let s): cosmetics.equip(s)
        case .customImages: break   // 画像を選んだときに使う設定になる
        case .pattern, .patternPack, .patternPack2, .patternMaker, .lifetime: break   // ステージ作りで、そのパターンや作成モードが使えるようになる
        }
    }

    func restore() async {
        guard isConfigured else { message = L("store.unavailable"); return }
        isBusy = true; defer { isBusy = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            message = L(isPremium || !cosmetics.ownership.owned.isEmpty ? "store.restored" : "store.nothing.to.restore")
        } catch {
            message = L("store.failed")
        }
    }

    fileprivate func apply(_ info: CustomerInfo) {
        let ids = info.allPurchasedProductIdentifiers
        // 永久買い切りパックは、広告削除も含む
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true || ids.contains(Self.removeAdsID) || ids.contains(Product.lifetime.id)
        cosmetics.updateOwnership(productIDs: ids)
    }
}

extension PurchaseService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.apply(customerInfo) }
    }
}

extension PurchaseService {
    /// 商品をまとめて買ったときの合計(App Store の通貨で)。どれか1つでも価格が取れていなければ nil
    func totalText(_ products: [Product]) -> String? {
        var sum: Decimal = 0
        for p in products {
            guard let a = amounts[p] else { return nil }
            sum += a
        }
        return priceFormatter?.string(from: sum as NSDecimalNumber)
    }

    /// まとめ売りの割引率(%)。App Store の価格が取れていなければ、目安の価格(円)で計算する
    func discountPercent(bundle: Product, singles: [Product]) -> Int {
        let total = singles.compactMap { amounts[$0] }.reduce(Decimal(0), +)
        if let b = amounts[bundle], singles.allSatisfy({ amounts[$0] != nil }), total > 0 {
            let ratio = NSDecimalNumber(decimal: b / total).doubleValue
            return Int((1 - ratio) * 100 + 0.5)
        }
        let yen = singles.map(\.yen).reduce(0, +)
        return yen > 0 ? Int((1 - Double(bundle.yen) / Double(yen)) * 100 + 0.5) : 0
    }
}
