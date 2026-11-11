import FirebaseFirestore
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
    private static let freeBossesKey = "cosmetics.freeBosses"
    private static let bossTicketsKey = "cosmetics.bossTickets"
    private static let ticketGrantedKey = "cosmetics.ticketGranted"
    private static let skinsOwnedKey = "cosmetics.shipSkinsOwned"
    private static let skinKey = "cosmetics.shipSkin"

    /// 招待などで手に入れたドット絵の自機(サーバーの記録。端末にも覚えておく)と、いま使っているもの(nil=標準の自機)
    @Published private(set) var ownedSkins: [String] = []
    @Published private(set) var shipSkin: String?

    /// ボスの無料チケット(初めて公開すると1枚もらえる。サーバーの記録)の残り枚数と、もうもらったか
    @Published private(set) var bossTickets = 0
    @Published private(set) var ticketGranted = false

    /// 無料チケットでボスをもらえるか。チケットが残っているか、まだ一度も公開しておらず、初めての公開のために1体もらえるとき
    var canClaimBossTicket: Bool { bossTickets > 0 || (!ticketGranted && postedCount == 0) }

    /// 無料でボスと交換できる回数(チケットの枚数に、初めての公開のための 1 体を足したもの)
    var availableBossClaims: Int { bossTickets + ((!ticketGranted && postedCount == 0) ? 1 : 0) }

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
        ownership.freeBosses = Set((defaults.stringArray(forKey: Self.freeBossesKey) ?? []).compactMap { k in BossCharacter.allCases.first { $0.productKey == k } })
        ownedSkins = (defaults.stringArray(forKey: Self.skinsOwnedKey) ?? []).filter(ShipSkin.isValid)
        shipSkin = defaults.string(forKey: Self.skinKey).flatMap { ShipSkin.isValid($0) ? $0 : nil }
        bossTickets = defaults.integer(forKey: Self.bossTicketsKey)
        ticketGranted = defaults.bool(forKey: Self.ticketGrantedKey)
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
        // ドット絵の自機: 作者がステージに選んだものがあれば、遊ぶ全員にそれを出す(持っていなくても見える)。
        // 無ければ、遊ぶ人が自分で選んだもの(持っているものだけ)。見た目だけで、当たり判定は同じ
        if showStageLook, let s = stage.shipSkin, ShipSkin.isValid(s) {
            l.shipSkin = s
        } else {
            l.shipSkin = shipSkin.flatMap { ownedSkins.contains($0) ? $0 : nil }
        }
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
        next.freeBosses = ownership.freeBosses
        guard next != ownership else { return }
        ownership = next
        defaults.set(next.owned.map(\.id).sorted(), forKey: Self.ownedKey)
    }

    /// サーバーに保存されている投稿数を読み直す(ステージを消して減っても、解放した見た目は残す)
    func refreshPosts(uid: String?) async {
        guard let uid, let n = await StageRepository().publishedCount(uid: uid) else { return }
        setPostedCount(n)
    }

    /// サーバーに保存されている無料チケットの状態を読み直す(もらったボスは、ずっと残る)
    func refreshBossTickets(uid: String?) async {
        guard let uid, Backend.isAvailable, let d = try? await Firestore.firestore().document("users/\(uid)").getDocument().data() else { return }
        applyTickets(free: d["freeBosses"] as? [String] ?? [], tickets: (d["bossTickets"] as? NSNumber)?.intValue ?? 0, granted: d["ticketGranted"] as? Bool ?? false)
    }

    /// 無料チケットで、ボスを1体もらう。成功したら true
    @discardableResult
    func claimBossTicket(_ boss: BossCharacter) async -> Bool {
        guard Backend.isAvailable,
              let r = try? await Backend.functions.httpsCallable("claimBossTicket").call(["boss": boss.productKey]),
              let d = r.data as? [String: Any] else { return false }
        applyTickets(free: d["freeBosses"] as? [String] ?? [], tickets: (d["bossTickets"] as? NSNumber)?.intValue ?? 0, granted: true)
        return true
    }

    private func applyTickets(free: [String], tickets: Int, granted: Bool) {
        let bosses = Set(free.compactMap { k in BossCharacter.allCases.first { $0.productKey == k } })
        var next = ownership
        next.freeBosses = ownership.freeBosses.union(bosses)
        if next != ownership { ownership = next }
        bossTickets = tickets
        ticketGranted = granted || ticketGranted
        defaults.set(next.freeBosses.map(\.productKey).sorted(), forKey: Self.freeBossesKey)
        defaults.set(tickets, forKey: Self.bossTicketsKey)
        defaults.set(ticketGranted, forKey: Self.ticketGrantedKey)
    }

    /// サーバーの記録から、持っているドット絵の自機を更新する(増えるだけ。使っているものが消えたら標準に戻す)
    func setOwnedSkins(_ ids: [String]) {
        let next = Array(Set(ownedSkins).union(ids.filter(ShipSkin.isValid))).sorted { (ShipSkin.all.firstIndex(of: $0) ?? 999) < (ShipSkin.all.firstIndex(of: $1) ?? 999) }
        guard next != ownedSkins else { return }
        ownedSkins = next
        defaults.set(next, forKey: Self.skinsOwnedKey)
    }

    /// サーバーから配る自機(無料)をもらう
    func claimRemoteShip(_ id: String) {
        guard let item = RemoteCatalog.shared.item(id), item.free else { return }
        setOwnedSkins([id])
    }

    /// 買った商品の ID から、サーバーから配る自機の所持を合わせる(購入・復元のとき)
    func updateRemoteOwnership(productIDs: Set<String>) {
        let ids = RemoteCatalog.shared.items.compactMap { i in i.productId.flatMap { productIDs.contains($0) ? i.id : nil } }
        if !ids.isEmpty { setOwnedSkins(ids) }
    }

    /// 配る自機の一覧が更新されたとき: 外れた(消された)自機を使っていたら、標準に戻す
    func catalogChanged() {
        if let s = shipSkin, RemoteCatalog.isRemoteID(s), RemoteCatalog.shared.item(s) == nil { selectSkin(nil) }
    }

    /// 使うドット絵の自機を選ぶ(nil で標準の自機)。持っているものだけ
    func selectSkin(_ id: String?) {
        if let id, !ownedSkins.contains(id) { return }
        shipSkin = id
        if let id { defaults.set(id, forKey: Self.skinKey) } else { defaults.removeObject(forKey: Self.skinKey) }
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
