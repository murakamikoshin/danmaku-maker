import Foundation
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

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadout = defaults.data(forKey: Self.loadoutKey).flatMap { try? JSONDecoder().decode(Loadout.self, from: $0) } ?? Loadout()
        // 起動直後や電波がないときも使えるよう、前回の購入内容を覚えておく
        ownership = Ownership(productIDs: defaults.stringArray(forKey: Self.ownedKey) ?? [])
        #if DEBUG
        // 画面確認用: 起動引数 -unlock-all で全部持っている状態にする（製品ビルドには入らない）
        if ProcessInfo.processInfo.arguments.contains("-unlock-all") { ownership = Ownership(owned: Set(Product.all)) }
        #endif
    }

    /// 持っていないものを標準に戻した、実際に遊ぶときの組み合わせ
    var effective: Loadout { loadout.effective(ownership) }

    /// 投稿前のテストプレイは、誰でもクリアできる標準の撃ち方に固定する
    func forPlay(isTest: Bool) -> Loadout {
        var l = effective
        if isTest { l.shot = .standard }
        return l
    }

    func updateOwnership(productIDs: Set<String>) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-unlock-all") { return }
        #endif
        let next = Ownership(productIDs: productIDs)
        guard next != ownership else { return }
        ownership = next
        defaults.set(next.owned.map(\.id).sorted(), forKey: Self.ownedKey)
    }

    func equip(_ theme: Theme, for part: ThemePart) {
        guard ownership.has(part, of: theme) else { return }
        loadout.set(theme, for: part)
    }

    func equip(_ shot: ShotType) {
        guard ownership.has(shot) else { return }
        loadout.shot = shot
    }

    private func save() {
        if let d = try? JSONEncoder().encode(loadout) { defaults.set(d, forKey: Self.loadoutKey) }
    }
}
