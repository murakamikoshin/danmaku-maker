import SpriteKit

/// 試作と同じ見た目の弾・自機・ボスを、起動時に1回だけ絵にしてテクスチャにする
enum SpriteFactory {
    private static func texture(size: CGSize, _ draw: (CGContext) -> Void) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { draw($0.cgContext) }
        let t = SKTexture(image: image)
        t.filteringMode = .linear
        return t
    }

    /// 色つきの円（半径6）＋白い芯（半径3）
    static let bullets: [SKTexture] = Palette.bullets.map { color in
        texture(size: CGSize(width: 12, height: 12)) { c in
            c.setFillColor(color.cgColor)
            c.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
            c.setFillColor(UIColor.white.cgColor)
            c.fillEllipse(in: CGRect(x: 3, y: 3, width: 6, height: 6))
        }
    }

    static let ship: SKTexture = texture(size: CGSize(width: 20, height: 24)) { c in
        // 試作の drawShip（中心 (10,12)）
        c.setFillColor(UIColor(hex: 0x5CE1E6).cgColor)
        c.move(to: CGPoint(x: 10, y: 1))
        c.addLine(to: CGPoint(x: 18, y: 20))
        c.addLine(to: CGPoint(x: 10, y: 16))
        c.addLine(to: CGPoint(x: 2, y: 20))
        c.closePath()
        c.fillPath()
        c.setFillColor(UIColor.white.cgColor)
        c.fillEllipse(in: CGRect(x: 7.5, y: 9.5, width: 5, height: 5))
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
