/// 見た目のテーマ。classic は最初から使える
public enum Theme: String, CaseIterable, Codable, Sendable {
    case classic, sakura, ocean, aurora
    /// ステージを投稿した数で解放される、無料のテーマ(買うことはできない)
    case gold, neon, rainbow

    /// 有料のテーマ（買って手に入れる）
    public static var paid: [Theme] { [.sakura, .ocean, .aurora] }
    /// 投稿数で解放されるテーマ
    public static var reward: [Theme] { [.gold, .neon, .rainbow] }

    /// 解放に必要な、投稿したステージの数(投稿で解放されるテーマだけ)
    public var unlockPosts: Int? {
        switch self {
        case .gold: return 1
        case .neon: return 3
        case .rainbow: return 10
        default: return nil
        }
    }
}

/// テーマの中で、別々に買える部品
public enum ThemePart: String, CaseIterable, Codable, Sendable {
    case bullets, background, ship
}

/// 購入できる商品（App Store Connect の商品 ID と1対1）
public enum Product: Hashable, Sendable {
    case part(Theme, ThemePart)
    /// テーマの3部品をまとめたセット（単品で買うよりお得）
    case set(Theme)
    case shot(ShotType)
    /// ボス・弾・自機を、自分で選んだ画像に差し替える(見た目だけ。画像は端末の中にだけ置く)
    case customImages
    /// 弾のパターンを、ステージ作りで使える(遊ぶのは誰でもできる)
    case pattern(Pattern)
    /// 買えるパターンの全部入り(単品で全部買うよりお得)
    case patternPack
    /// 弾幕パターン作成モード(弾の出る位置と軌道を線で描いて、自分だけの弾幕を作る)
    case patternMaker
    /// 永久買い切りパック: いまある課金コンテンツと広告削除を全部、これから増える課金コンテンツも全部、一度の購入で使える
    case lifetime

    public static let idPrefix = "com.koshin.danmakumaker."

    public var id: String {
        switch self {
        case .part(let t, let p): return Product.idPrefix + "\(t.rawValue).\(p.rawValue)"
        case .set(let t): return Product.idPrefix + "\(t.rawValue).set"
        case .shot(let s): return Product.idPrefix + "shot.\(s.rawValue)"
        case .customImages: return Product.idPrefix + "customimages"
        case .pattern(let p): return Product.idPrefix + (p == .homing ? "homing" : "pattern.\(p.rawValue)")
        case .patternPack: return Product.idPrefix + "patternpack"
        case .patternMaker: return Product.idPrefix + "patternmaker"
        case .lifetime: return Product.idPrefix + "lifetime"
        }
    }

    public init?(id: String) {
        guard id.hasPrefix(Product.idPrefix) else { return nil }
        if id == Product.idPrefix + "customimages" { self = .customImages; return }
        if id == Product.idPrefix + "homing" { self = .pattern(.homing); return }
        if id == Product.idPrefix + "patternpack" { self = .patternPack; return }
        if id == Product.idPrefix + "patternmaker" { self = .patternMaker; return }
        if id == Product.idPrefix + "lifetime" { self = .lifetime; return }
        if id.hasPrefix(Product.idPrefix + "pattern."), let p = Pattern(rawValue: String(id.dropFirst((Product.idPrefix + "pattern.").count))), p.isPaid, p != .homing {
            self = .pattern(p); return
        }
        let rest = id.dropFirst(Product.idPrefix.count).split(separator: ".").map(String.init)
        if rest.count == 2, rest[0] == "shot", let s = ShotType(rawValue: rest[1]), s != .standard {
            self = .shot(s); return
        }
        guard rest.count == 2, let t = Theme(rawValue: rest[0]), Theme.paid.contains(t) else { return nil }
        if rest[1] == "set" { self = .set(t); return }
        if let p = ThemePart(rawValue: rest[1]) { self = .part(t, p); return }
        return nil
    }

    /// 購入前に画面に出す目安の価格（円）。実際の表示は App Store の価格を使う
    public var yen: Int {
        switch self {
        case .part: return 100
        case .set: return 200
        case .shot: return 300
        case .customImages: return 500
        case .pattern(let p): return p == .homing ? 300 : 100
        case .patternPack: return 600
        case .patternMaker: return 1000
        case .lifetime: return 3000
        }
    }

    /// 全商品（広告削除は含まない）
    public static var all: [Product] {
        var list: [Product] = []
        for t in Theme.paid {
            for p in ThemePart.allCases { list.append(.part(t, p)) }
            list.append(.set(t))
        }
        for s in ShotType.allCases where s != .standard { list.append(.shot(s)) }
        list.append(.customImages)
        for p in Pattern.paid { list.append(.pattern(p)) }
        list.append(.patternPack)
        list.append(.patternMaker)
        list.append(.lifetime)
        return list
    }
}

/// 購入済みの商品から、何が使えるかを決める
public struct Ownership: Equatable, Sendable {
    public private(set) var owned: Set<Product>
    /// 投稿したステージの数(投稿で解放されるテーマの判定に使う。サーバーの記録で数える)
    public var posts: Int

    /// 広告を見て解放した、無料のパターン(買う商品ではない)
    public var adPatterns: Set<Pattern> = []

    public init(owned: Set<Product> = [], posts: Int = 0) { self.owned = owned; self.posts = posts }

    /// RevenueCat などから得た、購入済みの商品 ID の一覧から作る
    public init(productIDs: some Sequence<String>, posts: Int = 0) {
        owned = Set(productIDs.compactMap(Product.init(id:)))
        self.posts = posts
    }

    /// 永久買い切りパックを持っているか(持っていれば、課金コンテンツは全部使える)
    public var hasLifetime: Bool { owned.contains(.lifetime) }

    /// 投稿数で解放されるテーマを、もう使えるか
    public func hasUnlocked(_ theme: Theme) -> Bool {
        guard let need = theme.unlockPosts else { return false }
        return posts >= need
    }

    public func has(_ part: ThemePart, of theme: Theme) -> Bool {
        if theme == .classic { return true }
        if theme.unlockPosts != nil { return hasUnlocked(theme) }
        return hasLifetime || owned.contains(.part(theme, part)) || owned.contains(.set(theme))
    }

    public func has(_ shot: ShotType) -> Bool {
        shot == .standard || hasLifetime || owned.contains(.shot(shot))
    }

    /// そのパターンをステージ作りで使えるか(無料のパターンは、いつでも使える)
    public func has(_ pattern: Pattern) -> Bool {
        if pattern.isAd { return hasLifetime || adPatterns.contains(pattern) }
        return !pattern.isPaid || hasLifetime || owned.contains(.pattern(pattern)) || owned.contains(.patternPack)
    }

    /// 弾幕パターン作成モードを使えるか
    public var hasPatternMaker: Bool { hasLifetime || owned.contains(.patternMaker) }

    /// 自分の画像を使う権利があるか
    public var hasCustomImages: Bool { hasLifetime || owned.contains(.customImages) }

    /// その商品を買う意味があるか（すでに全部使えるなら false）
    public func canBuy(_ product: Product) -> Bool {
        switch product {
        case .part(let t, let p): return !has(p, of: t)
        case .set(let t): return !ThemePart.allCases.allSatisfy { has($0, of: t) }
        case .shot(let s): return !has(s)
        case .customImages: return !hasCustomImages
        case .pattern(let p): return !has(p)
        case .patternPack: return !Pattern.paid.allSatisfy { has($0) }
        case .patternMaker: return !hasPatternMaker
        case .lifetime: return !hasLifetime
        }
    }
}

/// いま選んでいる組み合わせ。持っていないものを指していたら、標準に戻して使う
public struct Loadout: Equatable, Codable, Sendable {
    public var bullets: Theme = .classic
    public var background: Theme = .classic
    public var ship: Theme = .classic
    public var shot: ShotType = .standard
    /// 自分の画像を使うか(権利があり、画像が登録されているものだけ実際に使われる)
    public var customBoss = false
    public var customBullet = false
    public var customShip = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case bullets, background, ship, shot, customBoss, customBullet, customShip
    }

    /// 古い保存データ(自分の画像の項目がない)も読めるようにする
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bullets = try c.decodeIfPresent(Theme.self, forKey: .bullets) ?? .classic
        background = try c.decodeIfPresent(Theme.self, forKey: .background) ?? .classic
        ship = try c.decodeIfPresent(Theme.self, forKey: .ship) ?? .classic
        shot = try c.decodeIfPresent(ShotType.self, forKey: .shot) ?? .standard
        customBoss = try c.decodeIfPresent(Bool.self, forKey: .customBoss) ?? false
        customBullet = try c.decodeIfPresent(Bool.self, forKey: .customBullet) ?? false
        customShip = try c.decodeIfPresent(Bool.self, forKey: .customShip) ?? false
    }

    public func theme(for part: ThemePart) -> Theme {
        switch part {
        case .bullets: return bullets
        case .background: return background
        case .ship: return ship
        }
    }

    public mutating func set(_ theme: Theme, for part: ThemePart) {
        switch part {
        case .bullets: bullets = theme
        case .background: background = theme
        case .ship: ship = theme
        }
    }

    /// 持っていないものを標準に置き換えた、実際に使う組み合わせ
    public func effective(_ own: Ownership) -> Loadout {
        var l = self
        for p in ThemePart.allCases where !own.has(p, of: theme(for: p)) { l.set(.classic, for: p) }
        if !own.has(shot) { l.shot = .standard }
        if !own.hasCustomImages { l.customBoss = false; l.customBullet = false; l.customShip = false }
        return l
    }
}
