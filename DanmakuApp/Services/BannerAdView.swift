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

/// 全画面のゲーム画面に付ける。表示している間は、メニューの下のバナーを外す
private struct HidesBannerWhileShown: ViewModifier {
    @EnvironmentObject private var ads: AdsService
    func body(content: Content) -> some View {
        content
            .onAppear { ads.coverAppeared() }
            .onDisappear { ads.coverDisappeared() }
    }
}

extension View {
    func hidesBannerWhileShown() -> some View { modifier(HidesBannerWhileShown()) }
}
