import SpriteKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Palette {
    static let bullets: [UIColor] = [0xFF6B9D, 0x5CE1E6, 0xFFD166, 0xB28DFF, 0x7CF29C].map { UIColor(hex: $0) }
    static let background = UIColor(hex: 0x0A0818)
    static let star = UIColor(hex: 0x3A3270)
    static let barBack = UIColor(hex: 0x332B62)
    static let pink = UIColor(hex: 0xFF6B9D)
    static let gold = UIColor(hex: 0xFFD23F)
    static let text = UIColor(hex: 0xEFEAFF)
}

/// 画面に出す文字列（String Catalog 経由）
func L(_ key: String) -> String {
    String(localized: String.LocalizationValue(key))
}
