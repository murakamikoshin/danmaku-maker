import GoogleMobileAds
import SwiftUI
import UIKit

/// 世界のステージ一覧に混ぜる、ネイティブ広告(一覧の行になじむ形の広告)。一覧の N 行ごとに1枠出す。
/// 1つの広告は1つの枠にだけ出す(使い回すと、2回目からは表示として数えられず、前の枠のタップの計測も外れる)。
/// スクロールに合わせて、少し先の枠の分だけ読んでおく(読んだのに見せない広告が増えないように)。
/// 読めていない枠は出さない。広告削除の購入者・SDK を始められていないときは出さない
@MainActor
final class NativeAdStore: NSObject, ObservableObject {
    static let shared = NativeAdStore()

    /// 一覧の何行ごとに1枠入れるか
    static let every = 8
    /// 手元に置いておく、まだ枠に入れていない広告の本数(一覧を開いてすぐの枠に間に合わせるため)
    private static let spare = 2
    /// 今いる位置から何枠先まで、広告を入れておくか
    private static let ahead = 2
    /// 1回の起動で使う広告の上限(メモリを使いすぎないように)。これより先の枠は出さない
    static let maxSlots = 30
    /// 枠に入れる前の広告の有効時間(Google の決まりは1時間。少し手前で捨てる)
    private static let lifetime: TimeInterval = 55 * 60

    /// 枠番号(0, 1, 2, ...)→ その枠の広告
    @Published private(set) var assigned: [Int: NativeAd] = [:]
    /// 読んだが、まだ枠に入れていない広告(読んだ時刻つき)
    private var spares: [(ad: NativeAd, at: Date)] = []
    /// 一覧で映った行のうち、いちばん下の行番号
    private var lowestRow = -1
    private var loader: AdLoader?
    private var loading = false
    private var failures = 0
    private var retryTask: Task<Void, Never>?

    /// Info.plist 経由(ビルド設定 ADMOB_NATIVE_UNIT_ID。開発中は Google のテスト広告 ID)。空なら読まない
    private var unitID: String? { AdsService.optionalUnit("ADMOB_NATIVE_UNIT_ID") }

    /// 枠 slot を置く、直前の行番号(この行のすぐ下に出す)
    static func row(ofSlot slot: Int) -> Int { (slot + 1) * every - 1 }
    /// 行 row のすぐ下に枠があれば、その枠番号
    static func slot(afterRow row: Int) -> Int? {
        let s = (row + 1) / every - 1
        return (row + 1) % every == 0 && s < maxSlots ? s : nil
    }

    /// 一覧の枠に出す広告。まだ入っていなければ nil(枠ごと出さない)
    func ad(slot: Int) -> NativeAd? { assigned[slot] }

    /// 一覧を開いたとき。手元の広告を用意しておく(何度呼んでもよい)
    func prepare() { fill() }

    /// 一覧の行が映ったとき。そこから少し先までの枠に、広告を入れる
    func rowAppeared(_ row: Int) {
        if row > lowestRow { lowestRow = row }
        fill()
    }

    /// 一覧を読み直したとき(並び順・絞り込み・検索・引っぱって更新)。枠の広告を外して、上からやり直す
    func reset() {
        assigned = [:]
        lowestRow = -1
        fill()
    }

    /// 広告を入れたい枠(まだ入っていないもの)を、上から順に
    private func wantedSlots() -> [Int] {
        // 今いちばん下に映っている行の1枠上(まだ画面の中にあるかもしれない枠)から、ahead 枠先まで
        let first = max(0, (lowestRow + 1) / Self.every - 1)
        let last = min(Self.maxSlots - 1, (max(lowestRow, 0) + 1) / Self.every + Self.ahead - 1)
        guard first <= last else { return [] }
        return (first...last).filter { assigned[$0] == nil }
    }

    /// 手元の広告を枠に入れ、足りない分を読む
    private func fill() {
        let now = Date()
        spares.removeAll { now.timeIntervalSince($0.at) >= Self.lifetime }
        if lowestRow >= 0 {
            var next = assigned
            for slot in wantedSlots() {
                guard !spares.isEmpty else { break }
                next[slot] = spares.removeFirst().ad
            }
            if next.count != assigned.count { assigned = next }
        }
        let need = (lowestRow >= 0 ? wantedSlots().count : 0) + Self.spare
        guard let unitID, !loading, retryTask == nil, spares.count < need, assigned.count + spares.count < Self.maxSlots else { return }
        loading = true
        let l = AdLoader(adUnitID: unitID, rootViewController: AdsService.topViewController(), adTypes: [.native], options: nil)
        l.delegate = self
        loader = l
        l.load(Request())
    }

    private func received(_ ad: NativeAd) {
        loading = false
        failures = 0
        spares.append((ad, Date()))
        fill()
    }

    /// 読めなかったら、少し待ってからやり直す(15秒・30秒・60秒…最大5分)。在庫がないときに何度も頼まないように
    private func failed() {
        loading = false
        failures += 1
        let wait = min(300.0, 15.0 * pow(2.0, Double(failures - 1)))
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.retryTask = nil
            self.fill()
        }
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
