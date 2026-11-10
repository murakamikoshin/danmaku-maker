import SwiftUI
import UIKit

/// ボスのチケットのドット絵(レアチケット。64×28、8コマで虹色が流れる)。拡大は最近傍補間。見た目だけ
enum TicketArt {
    static let frameCount = 8
    static let frameSeconds = 0.1
    private static var cache: [UIImage]?

    static func frames() -> [UIImage] {
        if let c = cache { return c }
        let list = (0..<frameCount).compactMap { n -> UIImage? in
            guard let url = Bundle.main.url(forResource: "ticket_rainbow_\(n)", withExtension: "png", subdirectory: "rewards/ticket_rainbow") else { return nil }
            return UIImage(contentsOfFile: url.path)
        }
        cache = list.count == frameCount ? list : []
        return cache ?? []
    }
}

/// 動くチケット。高さ(ポイント)を決めると、64:28 の比で幅が決まる。絵が見つからないときは、いつもの🎫のアイコン
struct TicketArtView: View {
    var height: CGFloat = 16
    var body: some View {
        let frames = TicketArt.frames()
        if frames.isEmpty {
            Image(systemName: "ticket.fill").font(.system(size: height * 0.8, weight: .bold))
        } else {
            TimelineView(.periodic(from: .now, by: TicketArt.frameSeconds)) { tl in
                let i = Int(tl.date.timeIntervalSinceReferenceDate / TicketArt.frameSeconds) % TicketArt.frameCount
                Image(uiImage: frames[i]).resizable().interpolation(.none)
                    .frame(width: height * 64 / 28, height: height)
            }
            .accessibilityHidden(true)
        }
    }
}
