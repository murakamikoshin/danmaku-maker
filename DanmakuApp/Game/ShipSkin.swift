import SpriteKit
import UIKit

/// ドット絵の自機(art/rewards)。招待のごほうびなどで手に入れて、じぶんで選んで使う。見た目だけで、当たり判定は標準の自機と同じ。
/// 絵は 32×32 の透過 PNG(機首が上)。通常機は 3 コマ(0→1→2→1 でループ)、特別機は 4 コマ(0→1→2→3)
enum ShipSkin {
    static let models = ["ace", "bastion", "gemini", "lancer", "phantom", "wasp"]
    static let colors = ["crimson", "emerald", "gold", "shadow", "snow", "steel"]
    static let original = "original_steel"
    static let special = "seraph_special"
    /// 全部の ID(サーバーの INVITER_SHIPS などと同じ名前)
    static let all: [String] = [original] + models.flatMap { m in colors.map { "\(m)_\($0)" } } + [special]

    static func isValid(_ id: String) -> Bool { all.contains(id) || RemoteCatalog.isRemoteID(id) }

    /// 画面に出す名前。例「エース 鋼」。オリジナル・特別機は、機種名だけ
    static func name(_ id: String) -> String {
        if RemoteCatalog.isRemoteID(id) { return compatAssumeMainActor { RemoteCatalog.shared.item(id)?.name ?? id } }
        if id == original { return L("ship.original") }
        if id == special { return L("ship.special") }
        let parts = id.split(separator: "_").map(String.init)
        guard parts.count == 2 else { return id }
        return "\(L("ship.model.\(parts[0])")) \(L("ship.color.\(parts[1])"))"
    }

    /// 再生する順のコマ(ループ)。見つからなければ空
    static func frames(_ id: String) -> [UIImage] {
        if let c = cache[id] { return c }
        if RemoteCatalog.isRemoteID(id) { return compatAssumeMainActor { RemoteCatalog.shared.item(id)?.frames ?? [] } }
        guard isValid(id) else { return [] }
        let count = id == special ? 4 : 3
        let files = (0..<count).compactMap { n -> UIImage? in
            guard let url = Bundle.main.url(forResource: "\(id)_\(n)", withExtension: "png", subdirectory: "rewards/\(id)"),
                  let img = UIImage(contentsOfFile: url.path) else { return nil }
            return img
        }
        guard files.count == count else { return [] }
        let order = id == special ? [0, 1, 2, 3] : [0, 1, 2, 1]
        let list = order.map { files[$0] }
        cache[id] = list
        return list
    }

    /// ゲーム内の表示の大きさ(ポイント)。32px を 3 倍(96px)で、ドットをくっきり出す
    static let pointSize: CGFloat = 32

    /// ゲームで使うテクスチャ。当たり判定の白い点を、中心に重ねる(標準の自機と同じ)
    static func textures(_ id: String) -> [SKTexture] {
        if let c = textureCache[id] { return c }
        let list = frames(id).map { src -> SKTexture in
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3; format.opaque = false
            let img = UIGraphicsImageRenderer(size: CGSize(width: pointSize, height: pointSize), format: format).image { r in
                let c = r.cgContext
                c.interpolationQuality = .none
                src.draw(in: CGRect(x: 0, y: 0, width: pointSize, height: pointSize))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: pointSize / 2 - 2.5, y: pointSize / 2 - 2.5, width: 5, height: 5))
            }
            let t = SKTexture(image: img)
            t.filteringMode = .nearest
            return t
        }
        textureCache[id] = list
        return list
    }

    private static var cache: [String: [UIImage]] = [:]
    private static var textureCache: [String: [SKTexture]] = [:]
}
