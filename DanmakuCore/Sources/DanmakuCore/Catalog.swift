/// 見た目のテーマ。classic は最初から使える
public enum Theme: String, CaseIterable, Codable, Sendable {
    case classic, sakura, ocean, aurora

    /// 有料のテーマ（classic 以外）
    public static var paid: [Theme] { allCases.filter { $0 != .classic } }
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

    public static let idPrefix = "com.koshin.danmakumaker."

    public var id: String {
        switch self {
        case .part(let t, let p): return Product.idPrefix + "\(t.rawValue).\(p.rawValue)"
        case .set(let t): return Product.idPrefix + "\(t.rawValue).set"
        case .shot(let s): return Product.idPrefix + "shot.\(s.rawValue)"
        }
    }

    public init?(id: String) {
        guard id.hasPrefix(Product.idPrefix) else { return nil }
        let rest = id.dropFirst(Product.idPrefix.count).split(separator: ".").map(String.init)
        if rest.count == 2, rest[0] == "shot", let s = ShotType(rawValue: rest[1]), s != .standard {
            self = .shot(s); return
        }
        guard rest.count == 2, let t = Theme(rawValue: rest[0]), t != .classic else { return nil }
        if rest[1] == "set" { self = .set(t); return }
        if let p = ThemePart(rawValue: rest[1]) { self = .part(t, p); return }
        return nil
    }

    /// 購入前に画面に出す目安の価格（円）。実際の表示は App Store の価格を使う
    public var yen: Int {
        switch self {
        case .part: return 120
        case .set: return 250
        case .shot: return 300
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
        return list
    }
}

/// 購入済みの商品から、何が使えるかを決める
public struct Ownership: Equatable, Sendable {
    public private(set) var owned: Set<Product>

    public init(owned: Set<Product> = []) { self.owned = owned }

    /// RevenueCat などから得た、購入済みの商品 ID の一覧から作る
    public init(productIDs: some Sequence<String>) {
        owned = Set(productIDs.compactMap(Product.init(id:)))
    }

    public func has(_ part: ThemePart, of theme: Theme) -> Bool {
        theme == .classic || owned.contains(.part(theme, part)) || owned.contains(.set(theme))
    }

    public func has(_ shot: ShotType) -> Bool {
        shot == .standard || owned.contains(.shot(shot))
    }

    /// その商品を買う意味があるか（すでに全部使えるなら false）
    public func canBuy(_ product: Product) -> Bool {
        switch product {
        case .part(let t, let p): return !has(p, of: t)
        case .set(let t): return !ThemePart.allCases.allSatisfy { has($0, of: t) }
        case .shot(let s): return !has(s)
        }
    }
}

/// いま選んでいる組み合わせ。持っていないものを指していたら、標準に戻して使う
public struct Loadout: Equatable, Codable, Sendable {
    public var bullets: Theme = .classic
    public var background: Theme = .classic
    public var ship: Theme = .classic
    public var shot: ShotType = .standard

    public init() {}

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
        return l
    }
}
