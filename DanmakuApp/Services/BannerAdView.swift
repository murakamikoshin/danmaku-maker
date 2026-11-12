import GoogleMobileAds
import SwiftUI
import UIKit

/// メニュー画面(あそぶ/ショップ/せってい)の下に出すバナー広告。プレイ中の画面には出さない
struct BannerAdView: UIViewRepresentable {
    let unitID: String
    let width: CGFloat

    /// 画面の幅に合わせた、バナーの大きさ(高さはここで決まる)
    static func adSize(width: CGFloat) -> AdSize {
        currentOrientationAnchoredAdaptiveBanner(width: width)
    }

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: Self.adSize(width: width))
        banner.adUnitID = unitID
        banner.rootViewController = AdsService.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}
}

/// 結果画面の中くらいの広告(レクタングル 300×250)
struct MrecAdView: UIViewRepresentable {
    let unitID: String
    static let size = CGSize(width: 300, height: 250)

    func makeUIView(context: Context) -> BannerView {
        let banner = BannerView(adSize: AdSizeMediumRectangle)
        banner.adUnitID = unitID
        banner.rootViewController = AdsService.topViewController()
        banner.load(Request())
        return banner
    }

    func updateUIView(_ banner: BannerView, context: Context) {}
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
