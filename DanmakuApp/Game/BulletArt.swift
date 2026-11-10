import SpriteKit
import SwiftUI
import UIKit
import DanmakuCore

/// ボス専用の弾のドット絵(狐火・御札・ミサイルなど)。絵のデータは BulletArtData(art/bosses/patterns/engine.js から生成)。
/// 拡大は必ず最近傍補間。上向きの絵で、進む向きへ回して描く弾は BulletLook.isOriented
enum BulletArt {
    private static var cache: [UInt8: UIImage] = [:]
    private static var texCache: [UInt8: SKTexture] = [:]

    static func color(_ hex: String) -> UIColor {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        return UIColor(red: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
    }

    /// 1ドット = 1論理px の絵
    static func image(look: UInt8) -> UIImage? {
        guard let kind = BulletLook.kind(of: look) else { return nil }
        if let c = cache[look] { return c }
        let map = BulletArtData.maps[kind.rawValue]
        let pal = BulletArtData.palettes[kind.rawValue][BulletLook.isAwakened(look) ? 1 : 0]
        let h = map.count, w = map[0].count
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { r in
            for (j, row) in map.enumerated() {
                for (i, ch) in row.enumerated() {
                    guard let hex = pal[ch] else { continue }
                    color(hex).setFill()
                    r.cgContext.fill(CGRect(x: i, y: j, width: 1, height: 1))
                }
            }
        }
        cache[look] = img
        return img
    }

    static func texture(look: UInt8) -> SKTexture? {
        if let t = texCache[look] { return t }
        guard let img = image(look: look) else { return nil }
        let t = SKTexture(image: img)
        t.filteringMode = .nearest
        texCache[look] = t
        return t
    }

    /// 画面に描く大きさ。膨らむ泡は、当たる広さに合わせて大きくする
    static func drawSize(_ b: Bullet) -> CGSize {
        if (BulletLook.kind(of: b.look) == .bubble || BulletLook.kind(of: b.look) == .jelly) && b.radius > 0 {
            let d = CGFloat(b.radius + 3) * 2
            return CGSize(width: d, height: d)
        }
        return texture(look: b.look)?.size() ?? .zero
    }

    /// 進む向きへ回す角度(絵は上向き)。回さない弾は 0
    static func rotation(_ b: Bullet) -> CGFloat {
        guard let k = BulletLook.kind(of: b.look), BulletLook.isOriented(k) else { return 0 }
        // 動かない鎖などは、決めた向き(u1)へ。ほかは進む向きへ
        if b.script == Bullet.holdScript && b.vx == 0 && b.vy == 0 { return CGFloat(b.u1) + .pi / 2 }
        return CGFloat(atan2(b.vy, b.vx)) + .pi / 2
    }
}
