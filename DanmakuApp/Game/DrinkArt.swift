import SwiftUI
import UIKit

/// 虹色の回復ドリンクのドット絵(32×32、1枚。art/rewards/drink_rainbow)。拡大は最近傍補間。見た目だけ
enum DrinkArt {
    private static var cache: UIImage??

    static func image() -> UIImage? {
        if let c = cache { return c }
        let img = Bundle.main.url(forResource: "drink_rainbow", withExtension: "png", subdirectory: "rewards/drink_rainbow")
            .flatMap { UIImage(contentsOfFile: $0.path) }
        cache = .some(img)
        return img
    }
}

/// 回復ドリンクの絵。絵が見つからないときは、しずくのアイコン
struct DrinkArtView: View {
    var size: CGFloat = 20
    var body: some View {
        Group {
            if let img = DrinkArt.image() {
                Image(uiImage: img).resizable().interpolation(.none).frame(width: size, height: size)
            } else {
                Image(systemName: "drop.fill").font(.system(size: size * 0.8, weight: .bold))
            }
        }
        .accessibilityHidden(true)
    }
}
