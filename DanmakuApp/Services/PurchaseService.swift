import Foundation
import RevenueCat

/// 広告削除の買い切り（非消耗型）。購入者は復活が無料・無制限になり、広告は一切出ない。
@MainActor
final class PurchaseService: NSObject, ObservableObject {
    static let entitlementID = "no_ads"

    @Published private(set) var isPremium = false
    @Published private(set) var priceText: String?
    @Published private(set) var isBusy = false
    @Published var message: String?

    private var package: Package?
    private(set) var isConfigured = false

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
    }

    func purchase() async {
        guard let package else { message = L("store.unavailable"); return }
        isBusy = true; defer { isBusy = false }
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled { apply(result.customerInfo) }
        } catch {
            message = L("store.failed")
        }
    }

    func restore() async {
        guard isConfigured else { message = L("store.unavailable"); return }
        isBusy = true; defer { isBusy = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            apply(info)
            message = L(isPremium ? "store.restored" : "store.nothing.to.restore")
        } catch {
            message = L("store.failed")
        }
    }

    fileprivate func apply(_ info: CustomerInfo) {
        isPremium = info.entitlements[Self.entitlementID]?.isActive == true
    }
}

extension PurchaseService: PurchasesDelegate {
    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in self.apply(customerInfo) }
    }
}
