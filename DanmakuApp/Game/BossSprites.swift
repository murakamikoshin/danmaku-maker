import SpriteKit
import UIKit
import DanmakuCore

/// 専用の絵を持つボス(ドット絵)の、待機アニメ。横に8コマ並んだ画像を切り分けて使う。
/// 見た目だけで、計算には関わらない(位置と当たり判定は DanmakuCore.BossCharacter)。拡大は必ず最近傍補間
enum BossSprites {
    struct Art {
        /// 待機の8コマ
        let frames: [SKTexture]
        /// 弾が当たったときの白い姿(同じ形)
        let flashFrames: [SKTexture]
        /// 1コマ目の絵(エディタの選択肢・プレビュー用)
        let still: UIImage
        /// 画面に出す大きさ(元の絵の2倍)
        let size: CGSize
        /// 構え・技中・硬直の絵(あるものだけ)。通常の姿と覚醒した姿で別。flash は、弾が当たったときの白い姿
        var actions: [Action: (frames: [SKTexture], flash: [SKTexture])] = [:]
    }

    /// 技の前後の動き: 構え → 技中(ループ)→ 硬直 → 待機。見た目だけ
    enum Action: String, CaseIterable { case windup, attack, recover }

    /// 構え(4コマ)と硬直(2コマ)の1コマの長さ(秒)。README の再生の目安(0.12秒)
    static let actionFrameDuration = 0.12

    /// 元の絵を、画面で何倍に拡大するか
    static let scale: CGFloat = 2
    /// 1コマの長さ(秒)。60fps で7フレームごと
    static let frameDuration = 7.0 / 60.0
    static let frameCount = 8

    private static var cache: [String: Art] = [:]

    /// 通常の姿と、覚醒した姿の絵。覚醒の絵がないボスは awakened が nil
    static func art(_ c: BossCharacter, awakened: Bool) -> Art? {
        let name = awakened ? c.awakenedSheet : c.sheet
        guard let name else { return nil }
        if let a = cache[name] { return a }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage else { return nil }
        let fw = cg.width / frameCount, fh = cg.height
        var frames: [SKTexture] = [], flashes: [SKTexture] = []
        var first: UIImage?
        for i in 0..<frameCount {
            guard let part = cg.cropping(to: CGRect(x: i * fw, y: 0, width: fw, height: fh)) else { return nil }
            let ui = UIImage(cgImage: part, scale: 1, orientation: .up)
            if first == nil { first = ui }
            frames.append(texture(ui))
            flashes.append(texture(whiteSilhouette(of: ui)))
        }
        var art = Art(frames: frames, flashFrames: flashes, still: first!, size: CGSize(width: CGFloat(fw) * scale, height: CGFloat(fh) * scale))
        // 構え・技中・硬直の絵(<ボス>_<状態>[_awakened]_sheet.png。1コマの幅は待機と同じ)
        let base = name.replacingOccurrences(of: "_awakened_idle_sheet", with: "").replacingOccurrences(of: "_idle_sheet", with: "")
        for action in Action.allCases {
            let file = "\(base)_\(action.rawValue)" + (awakened ? "_awakened" : "") + "_sheet"
            guard let u = Bundle.main.url(forResource: file, withExtension: "png"), let img = UIImage(contentsOfFile: u.path), let c = img.cgImage else { continue }
            let n = c.width / fw
            var fs: [SKTexture] = [], fl: [SKTexture] = []
            for i in 0..<n {
                guard let part = c.cropping(to: CGRect(x: i * fw, y: 0, width: fw, height: c.height)) else { continue }
                let ui = UIImage(cgImage: part, scale: 1, orientation: .up)
                fs.append(texture(ui)); fl.append(texture(whiteSilhouette(of: ui)))
            }
            if n > 0 && fs.count == n { art.actions[action] = (fs, fl) }
        }
        cache[name] = art
        return art
    }

    /// 時刻(ステージの経過秒)に合わせたコマの番号。ループする
    static func frameIndex(at t: Double) -> Int {
        Int(max(0, t) / frameDuration) % frameCount
    }

    private static func texture(_ image: UIImage) -> SKTexture {
        let t = SKTexture(image: image)
        t.filteringMode = .nearest
        return t
    }

    /// 絵の形のまま、真っ白に塗った絵
    private static func whiteSilhouette(of image: UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        return UIGraphicsImageRenderer(size: image.size, format: format).image { ctx in
            image.draw(at: .zero)
            ctx.cgContext.setBlendMode(.sourceAtop)
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: image.size))
        }
    }
}

extension BossCharacter {
    /// 画像ファイル名(拡張子なし)
    var sheet: String? {
        switch self {
        case .fallenAngel: return "fallen_angel_idle_sheet"
        case .kitsune: return "kitsune_idle_sheet"
        case .iceQueen: return "ice_idle_sheet"
        case .reaper: return "reaper_idle_sheet"
        case .witch: return "witch_idle_sheet"
        case .mech: return "mech_idle_sheet"
        case .puni: return "puni_idle_sheet"
        }
    }
    /// 覚醒した姿の画像ファイル名。nil は、姿を変えない
    var awakenedSheet: String? {
        switch self {
        case .fallenAngel: return "fallen_angel_awakened_idle_sheet"
        case .kitsune: return "kitsune_awakened_idle_sheet"
        case .iceQueen: return "ice_awakened_idle_sheet"
        case .reaper: return "reaper_awakened_idle_sheet"
        case .witch: return "witch_awakened_idle_sheet"
        case .mech: return "mech_awakened_idle_sheet"
        case .puni: return "puni_awakened_idle_sheet"
        }
    }
}
