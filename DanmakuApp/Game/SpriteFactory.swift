import SpriteKit
import DanmakuCore
/// 試作と同じ見た目の弾・自機・ボスを、起動時に1回だけ絵にしてテクスチャにする
enum SpriteFactory {
    private static func texture(size: CGSize, _ draw: (CGContext) -> Void) -> SKTexture {
        texture(image(size: size, draw))
    }

    private static var bulletCache: [Theme: [UIImage]] = [:]
    private static var shipCache: [Theme: UIImage] = [:]
    private static var bulletTextureCache: [Theme: [SKTexture]] = [:]
    private static var shipTextureCache: [Theme: SKTexture] = [:]

    private static func image(size: CGSize, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
    }

    private static func texture(_ image: UIImage) -> SKTexture {
        let t = SKTexture(image: image)
        t.filteringMode = .linear
        return t
    }

    /// 弾の絵（12×12）。形はテーマごとに違うが、大きさは同じ
    static func bulletImages(_ theme: Theme) -> [UIImage] {
        if let c = bulletCache[theme] { return c }
        let skin = Skin.of(theme)
        let list = skin.bulletColors.map { color in
            image(size: CGSize(width: 12, height: 12)) { c in
                c.setFillColor(color.cgColor)
                switch skin.bulletShape {
                case .circle:
                    c.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
                case .petal:
                    for i in 0..<5 {
                        let a = Double(i) * 2 * Double.pi / 5
                        c.fillEllipse(in: CGRect(x: 6 + cos(a) * 2.8 - 2.6, y: 6 + sin(a) * 2.8 - 2.6, width: 5.2, height: 5.2))
                    }
                case .bubble:
                    c.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
                    c.setBlendMode(.clear)
                    c.fillEllipse(in: CGRect(x: 2.4, y: 2.4, width: 7.2, height: 7.2))
                    c.setBlendMode(.normal)
                    c.setFillColor(color.cgColor)
                    c.fillEllipse(in: CGRect(x: 4.4, y: 4.4, width: 3.2, height: 3.2))
                case .diamond:
                    c.move(to: CGPoint(x: 6, y: 0)); c.addLine(to: CGPoint(x: 12, y: 6))
                    c.addLine(to: CGPoint(x: 6, y: 12)); c.addLine(to: CGPoint(x: 0, y: 6))
                    c.closePath(); c.fillPath()
                }
                if skin.bulletShape != .bubble {
                    c.setFillColor(UIColor.white.cgColor)
                    c.fillEllipse(in: CGRect(x: 3, y: 3, width: 6, height: 6))
                }
            }
        }
        bulletCache[theme] = list
        return list
    }

    static func bullets(_ theme: Theme) -> [SKTexture] {
        if let c = bulletTextureCache[theme] { return c }
        let list = bulletImages(theme).map(texture)
        bulletTextureCache[theme] = list
        return list
    }

    /// 自機の絵（20×24）。当たり判定は中心の白い点で、形が違っても変わらない
    static func shipImage(_ theme: Theme) -> UIImage {
        if let c = shipCache[theme] { return c }
        let skin = Skin.of(theme)
        let img = image(size: CGSize(width: 20, height: 24)) { c in
            c.setFillColor(skin.shipColor.cgColor)
            func poly(_ pts: [(Double, Double)]) {
                for (i, p) in pts.enumerated() {
                    let q = CGPoint(x: p.0, y: p.1)
                    i == 0 ? c.move(to: q) : c.addLine(to: q)
                }
                c.closePath(); c.fillPath()
            }
            switch skin.shipShape {
            case .arrow: poly([(10, 1), (18, 20), (10, 16), (2, 20)])
            case .wings: poly([(10, 2), (13, 12), (19, 8), (17, 21), (10, 17), (3, 21), (1, 8), (7, 12)])
            case .manta: poly([(10, 1), (14, 9), (20, 14), (13, 17), (10, 23), (7, 17), (0, 14), (6, 9)])
            case .star: poly([(10, 0), (13, 8), (20, 10), (14, 14), (16, 22), (10, 17), (4, 22), (6, 14), (0, 10), (7, 8)])
            }
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: 7.5, y: 9.5, width: 5, height: 5))
        }
        shipCache[theme] = img
        return img
    }

    static func ship(_ theme: Theme) -> SKTexture {
        if let c = shipTextureCache[theme] { return c }
        let t = texture(shipImage(theme))
        shipTextureCache[theme] = t
        return t
    }

    /// 自分の画像から作る絵。ゲーム内の大きさ(ポイント)に合わせる。
    /// 自機は、当たる場所が分かるように中心に白い点を重ねる。ボスは被弾したとき白くひらめく
    static func custom(_ slot: CustomSlot, flash: Bool = false) -> SKTexture? {
        guard let src = CustomImageStore.load(slot) else { return nil }
        let size = slot.pointSize
        let img = image(size: size) { c in
            let rect = CGRect(origin: .zero, size: size)
            UIImage(cgImage: src.cgImage!, scale: 1, orientation: .up).draw(in: rect)
            if flash {
                c.setBlendMode(.sourceAtop)
                c.setFillColor(UIColor.white.withAlphaComponent(0.7).cgColor)
                c.fill(rect)
                c.setBlendMode(.normal)
            }
            if slot == .ship {
                c.setFillColor(UIColor.black.withAlphaComponent(0.45).cgColor)
                c.fillEllipse(in: CGRect(x: size.width / 2 - 3.6, y: size.height / 2 - 3.6, width: 7.2, height: 7.2))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: size.width / 2 - 2.5, y: size.height / 2 - 2.5, width: 5, height: 5))
            }
        }
        return texture(img)
    }

    static func boss(flash: Bool) -> SKTexture {
        texture(size: CGSize(width: 48, height: 48)) { c in
            c.setFillColor((flash ? UIColor.white : Palette.pink).cgColor)
            for i in 0..<12 {
                let a = Double(i) * Double.pi / 6
                let r: Double = i % 2 == 1 ? 14 : 22
                let p = CGPoint(x: 24 + cos(a) * r, y: 24 + sin(a) * r)
                i == 0 ? c.move(to: p) : c.addLine(to: p)
            }
            c.closePath()
            c.fillPath()
            c.setFillColor(Palette.background.cgColor)
            c.fillEllipse(in: CGRect(x: 17, y: 17, width: 14, height: 14))
        }
    }
}
