import GoogleMobileAds
import SwiftUI
import UIKit

/// 世界のステージ一覧に混ぜる、ネイティブ広告(一覧の行になじむ形の広告)。
/// 何本か先に読んでおき、一覧の N 行ごとに1枠出す。広告削除の購入者・SDK を始められていないときは出さない
@MainActor
final class NativeAdStore: NSObject, ObservableObject {
    static let shared = NativeAdStore()

    /// 一覧の何行ごとに1枠入れるか
    static let every = 8
    /// 先に読んでおく本数(枠が多くても、この本数を順に使い回す)
    private static let poolSize = 3
    /// 読んだ広告の有効時間(Google の決まりは1時間。少し手前で捨てる)
    private static let lifetime: TimeInterval = 55 * 60

    @Published private(set) var ads: [NativeAd] = []
    private var loadedAt: [ObjectIdentifier: Date] = [:]
    private var loader: AdLoader?
    private var loading = false
    private var failures = 0

    /// Info.plist 経由(ビルド設定 ADMOB_NATIVE_UNIT_ID。開発中は Google のテスト広告 ID)。空なら読まない
    private var unitID: String? { AdsService.optionalUnit("ADMOB_NATIVE_UNIT_ID") }

    /// 一覧の枠番号(0, 1, 2, ...)に出す広告。読めていなければ nil(枠ごと出さない)
    func ad(slot: Int) -> NativeAd? {
        guard !ads.isEmpty else { return nil }
        return ads[slot % ads.count]
    }

    /// 足りない分を読む(何度呼んでもよい)
    func fill() {
        let now = Date()
        let fresh = ads.filter { now.timeIntervalSince(loadedAt[ObjectIdentifier($0)] ?? .distantPast) < Self.lifetime }
        if fresh.count != ads.count { ads = fresh }
        guard let unitID, !loading, ads.count < Self.poolSize, failures < 3 else { return }
        loading = true
        let l = AdLoader(adUnitID: unitID, rootViewController: AdsService.topViewController(), adTypes: [.native], options: nil)
        l.delegate = self
        loader = l
        l.load(Request())
    }

    private func received(_ ad: NativeAd) {
        loading = false
        failures = 0
        loadedAt[ObjectIdentifier(ad)] = Date()
        ads.append(ad)
        fill()
    }

    private func failed() {
        loading = false
        failures += 1
    }
}

extension NativeAdStore: NativeAdLoaderDelegate {
    nonisolated func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        Task { @MainActor in self.received(nativeAd) }
    }
    nonisolated func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        Task { @MainActor in self.failed() }
    }
}

/// 一覧の1枠。ステージの行と同じくらいの大きさのパネルに、画像・見出し・本文・ボタンを並べる。
/// 「広告」の印を必ず付ける(ステージと見間違えないように)
struct NativeAdRow: View {
    let ad: NativeAd
    static let height: CGFloat = 132

    var body: some View {
        NativeAdPanel(ad: ad)
            .frame(height: Self.height)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("home.world.nativead")
    }
}

private struct NativeAdPanel: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let v = NativeAdView()
        v.backgroundColor = UIColor(GameStyle.panel)
        v.layer.cornerRadius = 14
        v.layer.borderWidth = 2
        v.layer.borderColor = UIColor(GameStyle.edge).cgColor
        v.clipsToBounds = true

        let media = MediaView()
        media.contentMode = .scaleAspectFill
        media.clipsToBounds = true
        media.layer.cornerRadius = 10

        let badge = PaddedLabel()
        badge.text = L("ad.badge")
        badge.font = .systemFont(ofSize: 10, weight: .heavy)
        badge.textColor = UIColor(GameStyle.ink)
        badge.backgroundColor = UIColor(GameStyle.yellow)
        badge.layer.cornerRadius = 4
        badge.clipsToBounds = true
        badge.setContentHuggingPriority(.required, for: .horizontal)

        let advertiser = UILabel()
        advertiser.font = .systemFont(ofSize: 11, weight: .semibold)
        advertiser.textColor = UIColor.white.withAlphaComponent(0.6)

        let headline = UILabel()
        headline.font = .systemFont(ofSize: 15, weight: .heavy)
        headline.textColor = UIColor(GameStyle.text)
        headline.numberOfLines = 2

        let body = UILabel()
        body.font = .systemFont(ofSize: 12, weight: .regular)
        body.textColor = UIColor.white.withAlphaComponent(0.7)
        body.numberOfLines = 2

        let cta = UIButton(type: .system)
        cta.titleLabel?.font = .systemFont(ofSize: 13, weight: .heavy)
        cta.setTitleColor(UIColor(GameStyle.ink), for: .normal)
        cta.backgroundColor = UIColor(GameStyle.cyanColor)
        cta.layer.cornerRadius = 8
        cta.contentEdgeInsets = UIEdgeInsets(top: 5, left: 12, bottom: 5, right: 12)
        // ボタンの押下は SDK が受け取る(自分で反応させない)
        cta.isUserInteractionEnabled = false

        let top = UIStackView(arrangedSubviews: [badge, advertiser])
        top.spacing = 6
        top.alignment = .center
        let ctaRow = UIStackView(arrangedSubviews: [UIView(), cta])
        let column = UIStackView(arrangedSubviews: [top, headline, body, UIView(), ctaRow])
        column.axis = .vertical
        column.spacing = 3

        for s in [media, column] as [UIView] { s.translatesAutoresizingMaskIntoConstraints = false; v.addSubview(s) }
        NSLayoutConstraint.activate([
            media.leadingAnchor.constraint(equalTo: v.leadingAnchor, constant: 10),
            media.centerYAnchor.constraint(equalTo: v.centerYAnchor),
            media.widthAnchor.constraint(equalToConstant: 112),
            media.heightAnchor.constraint(equalToConstant: 112),
            column.leadingAnchor.constraint(equalTo: media.trailingAnchor, constant: 10),
            column.trailingAnchor.constraint(equalTo: v.trailingAnchor, constant: -10),
            column.topAnchor.constraint(equalTo: v.topAnchor, constant: 10),
            column.bottomAnchor.constraint(equalTo: v.bottomAnchor, constant: -10),
        ])

        v.mediaView = media
        v.headlineView = headline
        v.bodyView = body
        v.advertiserView = advertiser
        v.callToActionView = cta
        apply(ad, to: v)
        return v
    }

    func updateUIView(_ v: NativeAdView, context: Context) {
        if v.nativeAd !== ad { apply(ad, to: v) }
    }

    private func apply(_ ad: NativeAd, to v: NativeAdView) {
        (v.headlineView as? UILabel)?.text = ad.headline
        (v.bodyView as? UILabel)?.text = ad.body
        v.bodyView?.isHidden = ad.body == nil
        (v.advertiserView as? UILabel)?.text = ad.advertiser
        (v.callToActionView as? UIButton)?.setTitle(ad.callToAction, for: .normal)
        v.callToActionView?.isHidden = ad.callToAction == nil
        v.mediaView?.mediaContent = ad.mediaContent
        // 最後に入れる(ここで SDK が表示とクリックの計測を始める)
        v.nativeAd = ad
    }
}

/// 「広告」の印(文字の周りに少し余白を付けたラベル)
private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: UIEdgeInsets(top: 1, left: 5, bottom: 1, right: 5))) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + 10, height: s.height + 2)
    }
}
