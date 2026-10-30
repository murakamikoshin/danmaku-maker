import Foundation
import UIKit
import DanmakuCore

/// 買ったものと、いま選んでいる組み合わせ。端末に保存する（買った記録の本体は App Store / RevenueCat 側）
@MainActor
final class CosmeticsStore: ObservableObject {
    static let shared = CosmeticsStore()

    @Published var loadout: Loadout { didSet { save() } }
    @Published private(set) var ownership: Ownership

    private let defaults: UserDefaults
    private static let loadoutKey = "cosmetics.loadout"
    private static let ownedKey = "cosmetics.owned"
    private static let postedKey = "cosmetics.posted"

    /// 投稿したステージの数(サーバーの記録から数えた、いちばん多い値)。投稿数で解放される見た目に使う
    @Published private(set) var postedCount: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadout = defaults.data(forKey: Self.loadoutKey).flatMap { try? JSONDecoder().decode(Loadout.self, from: $0) } ?? Loadout()
        // 起動直後や電波がないときも使えるよう、前回の購入内容を覚えておく
        let posted = defaults.integer(forKey: Self.postedKey)
        postedCount = posted
        ownership = Ownership(productIDs: defaults.stringArray(forKey: Self.ownedKey) ?? [], posts: posted)
        showStageLook = defaults.object(forKey: "cosmetics.showStageLook") as? Bool ?? true
        effectsOn = defaults.object(forKey: "cosmetics.effectsOn") as? Bool ?? true
        ownership.adPatterns = AdPatternStore.load(defaults).unlocked
        #if DEBUG
        // 画面確認用: 起動引数 -unlock-all で全部持っている状態にする（製品ビルドには入らない）
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-unlock-all") { ownership = Ownership(owned: Set(Product.all), posts: 99) }
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil } }
        if let v = value("-equip-shot").flatMap(ShotType.init(rawValue:)) { loadout.shot = v }
        if let t = value("-equip-theme").flatMap(Theme.init(rawValue:)) { for p in ThemePart.allCases { loadout.set(t, for: p) } }
        #endif
    }

    /// 画像を差し替えたときに画面を更新するための番号
    @Published private(set) var customImageRevision = 0

    /// 選んだ画像を保存する(使うかどうかは、ステージごとに、作る人が決める)
    @discardableResult
    func setCustomImage(_ image: UIImage, for slot: CustomSlot) -> Bool {
        guard ownership.hasCustomImages, CustomImageStore.save(image, for: slot) else { return false }
        customImageRevision += 1
        return true
    }

    func removeCustomImage(_ slot: CustomSlot) {
        CustomImageStore.remove(slot)
        customImageRevision += 1
    }

    /// 警告と撃破の演出(赤い点滅・爆発など)を出すか。点滅が苦手な人のために、遊ぶ人がオフにできる
    @Published var effectsOn: Bool { didSet { defaults.set(effectsOn, forKey: "cosmetics.effectsOn") } }

    /// ステージの見た目を表示するか(見づらいときに、標準に戻せる)。遊ぶ人の設定
    @Published var showStageLook: Bool { didSet { defaults.set(showStageLook, forKey: "cosmetics.showStageLook") } }

    /// 遊ぶときの組み合わせ。見た目(弾・背景・自機)は、ステージを作った人が決めたもの(設定でオフなら標準)。
    /// 撃ち方は、ステージで決まっている(作った人が選ぶ)。じぶんの画像は、自分のステージを遊ぶときだけ
    func forPlay(stage: Stage, isTest: Bool, customs: CustomImageChoice = .none) -> Loadout {
        var l = Loadout()
        if showStageLook {
            l.bullets = stage.lookBullets
            l.background = stage.lookBackground
            l.ship = stage.lookShip
        }
        // 撃ち方はステージで決まっている(作った人が選ぶ)。テストプレイも、遊ぶ人も、同じ
        l.shot = stage.shotType
        if ownership.hasCustomImages {
            l.customBoss = customs.boss && CustomImageStore.exists(.boss)
            l.customBullet = customs.bullet && CustomImageStore.exists(.bullet)
            l.customShip = customs.ship && CustomImageStore.exists(.ship)
        }
        return l
    }

    /// 広告で解放したパターンを反映する(買った商品ではないので、保存は AdPatternStore がする)
    func setAdPatterns(_ patterns: Set<Pattern>) {
        guard ownership.adPatterns != patterns else { return }
        ownership.adPatterns = patterns
    }

    func updateOwnership(productIDs: Set<String>) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-unlock-all") { return }
        #endif
        var next = Ownership(productIDs: productIDs, posts: postedCount)
        next.adPatterns = ownership.adPatterns
        guard next != ownership else { return }
        ownership = next
        defaults.set(next.owned.map(\.id).sorted(), forKey: Self.ownedKey)
    }

    /// サーバーに保存されている投稿数を読み直す(ステージを消して減っても、解放した見た目は残す)
    func refreshPosts(uid: String?) async {
        guard let uid, let n = await StageRepository().publishedCount(uid: uid) else { return }
        setPostedCount(n)
    }

    func setPostedCount(_ n: Int) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-unlock-all") { return }
        #endif
        guard n > postedCount else { return }
        postedCount = n
        defaults.set(n, forKey: Self.postedKey)
        var next = ownership
        next.posts = n
        ownership = next
    }

    func equip(_ shot: ShotType) {
        guard ownership.has(shot) else { return }
        loadout.shot = shot
    }

    private func save() {
        if let d = try? JSONEncoder().encode(loadout) { defaults.set(d, forKey: Self.loadoutKey) }
    }
}
