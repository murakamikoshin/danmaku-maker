import UIKit

/// 自分で選んだ画像を置く場所の種類。見た目だけを差し替える(当たり判定は変わらない)
enum CustomSlot: String, CaseIterable, Identifiable {
    case boss, bullet, ship
    var id: String { rawValue }

    /// ゲーム画面での大きさ(ポイント)。標準の絵と同じにして、見た目の大きさで有利・不利が出ないようにする
    var pointSize: CGSize {
        switch self {
        case .boss: return CGSize(width: 48, height: 48)
        case .bullet: return CGSize(width: 12, height: 12)
        case .ship: return CGSize(width: 24, height: 24)
        }
    }
    var nameKey: String { "custom.slot.\(rawValue)" }
}

/// 画像は端末の中(Application Support)にだけ保存する。サーバーには送らない
enum CustomImageStore {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CustomImages", isDirectory: true)
    }

    private static func url(_ slot: CustomSlot) -> URL { directory.appendingPathComponent("\(slot.rawValue).png") }

    static func exists(_ slot: CustomSlot) -> Bool { FileManager.default.fileExists(atPath: url(slot).path) }

    static func load(_ slot: CustomSlot) -> UIImage? { UIImage(contentsOfFile: url(slot).path) }

    /// 中央を正方形に切り出し、256px に縮め、丸く切り抜いて保存する
    @discardableResult
    static func save(_ image: UIImage, for slot: CustomSlot) -> Bool {
        let side = min(image.size.width, image.size.height) * image.scale
        guard side > 0, let cg = image.cgImage else { return false }
        let crop = CGRect(x: (CGFloat(cg.width) - side) / 2, y: (CGFloat(cg.height) - side) / 2, width: side, height: side)
        guard let cropped = cg.cropping(to: crop) else { return false }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let size = CGSize(width: 256, height: 256)
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
            UIImage(cgImage: cropped, scale: 1, orientation: image.imageOrientation)
                .draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.pngData() else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(slot), options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    static func remove(_ slot: CustomSlot) { try? FileManager.default.removeItem(at: url(slot)) }
}
