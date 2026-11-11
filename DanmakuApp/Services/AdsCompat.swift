import GoogleMobileAds
import UIKit

// 広告 SDK(Google Mobile Ads)の新旧の書き方の違いを、ここで吸収する。
// - 提出用のビルド(GitHub Actions の Xcode 26)は SDK 13 を使う。メディエーション(AppLovin・Unity Ads)の部品が SDK 12 以上を要るため。
// - この Mac の Xcode 15.2 では SDK 13 がビルドできないので、tools/build_shots_app.sh が SDK 11.2.0 に差し替えて
//   メディエーションの部品を外す。そのときだけ、下の「SDK 12 の名前 → SDK 11 の名前」の置き換えが効く。
// アプリのコードは SDK 12 以降の名前(MobileAds・RewardedAd・BannerView など)で書く。
#if !compiler(>=6.0)
typealias MobileAds = GADMobileAds
typealias Request = GADRequest
typealias RewardedAd = GADRewardedAd
typealias InterstitialAd = GADInterstitialAd
typealias FullScreenContentDelegate = GADFullScreenContentDelegate
typealias FullScreenPresentingAd = GADFullScreenPresentingAd
typealias BannerView = GADBannerView
typealias AdSize = GADAdSize

extension GADMobileAds {
    static var shared: GADMobileAds { sharedInstance() }
}

extension GADRewardedAd {
    static func load(with adUnitID: String, request: GADRequest?, completionHandler: @escaping (GADRewardedAd?, Error?) -> Void) {
        load(withAdUnitID: adUnitID, request: request, completionHandler: completionHandler)
    }
    func present(from viewController: UIViewController?, userDidEarnRewardHandler: @escaping () -> Void) {
        present(fromRootViewController: viewController, userDidEarnRewardHandler: userDidEarnRewardHandler)
    }
}

extension GADInterstitialAd {
    static func load(with adUnitID: String, request: GADRequest?, completionHandler: @escaping (GADInterstitialAd?, Error?) -> Void) {
        load(withAdUnitID: adUnitID, request: request, completionHandler: completionHandler)
    }
    func present(from viewController: UIViewController?) {
        present(fromRootViewController: viewController)
    }
}

func currentOrientationAnchoredAdaptiveBanner(width: CGFloat) -> GADAdSize {
    GADCurrentOrientationAnchoredAdaptiveBannerAdSizeWithWidth(width)
}
#endif
