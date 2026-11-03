import SpriteKit
import SwiftUI
import UIKit
import DanmakuCore

/// スワイプ弾幕専用の色と字体（仕様書 6 章）
enum SwipePalette {
    static let background = UIColor(hex: 0x07040F)
    static let text = UIColor(hex: 0xF6F1FF)
    static let dim = UIColor(hex: 0xA597CF)
    static let pink = UIColor(hex: 0xFF4F9A)
    static let cyan = UIColor(hex: 0x3EE8FF)
    static let gold = UIColor(hex: 0xFFD23F)
    static let outline = UIColor(hex: 0x12061F)
    static let bullets: [UIColor] = [0xFF4F9A, 0x3EE8FF, 0xFFD23F, 0xB36BFF, 0x5DFF8F, 0xFF8A3D].map { UIColor(hex: $0) }

    static func bullet(_ colorIndex: Int) -> UIColor { bullets[((colorIndex % bullets.count) + bullets.count) % bullets.count] }

    /// 大きい文字の字体（Dela Gothic One。同梱）。読み込めなければ太いシステム字体
    static func display(_ size: CGFloat) -> UIFont {
        UIFont(name: "DelaGothicOne-Regular", size: size) ?? UIFont.systemFont(ofSize: size, weight: .black)
    }

    /// 点数の書き方（端末の言語が日本語なら日本語の単位、それ以外は英語）
    static var scoreStyle: ScoreFormat.Language { Locale.preferredLanguages.first?.hasPrefix("ja") == true ? .japanese : .english }
}

extension Color {
    init(swipe c: UIColor) { self.init(uiColor: c) }
}

/// 縁取りつきの大きい文字（SwiftUI）
struct OutlinedText: View {
    let text: String
    var size: CGFloat = 28
    var color: Color = Color(uiColor: SwipePalette.text)

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Text(text).font(.custom("DelaGothicOne-Regular", size: size))
                    .foregroundStyle(Color(uiColor: SwipePalette.outline))
                    .offset(x: CGFloat(cos(a)) * size * 0.1, y: CGFloat(sin(a)) * size * 0.1)
            }
            Text(text).font(.custom("DelaGothicOne-Regular", size: size)).foregroundStyle(color)
        }
    }
}
