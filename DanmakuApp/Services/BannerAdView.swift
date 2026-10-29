import GoogleMobileAds
import SwiftUI
import UIKit

/// メニュー画面(あそぶ/ショップ/せってい)の下に出すバナー広告。プレイ中の画面には出さない
struct BannerAdView: UIViewRepresentable {
    let unitID: String
    let width: CGFloat

    /// 画面の幅に合わせた、バナーの大きさ(高さはここで決まる)
    static func adSize(width: CGFloat) -> GADAdSize {
        GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
    }

    func makeUIView(context: Context) -> GADBannerView {
        let banner = GADBannerView(adSize: Self.adSize(width: width))
        banner.adUnitID = unitID
        banner.rootViewController = AdsService.topViewController()
        banner.load(GADRequest())
        return banner
    }

    func updateUIView(_ banner: GADBannerView, context: Context) {}
}
