import CoreText
import SpriteKit
import UIKit

/// ボスの段階の名前・必殺技の名前を出す演出(1.4.0)。見た目だけで、計算には関わらない。
///
/// - 必殺技は3種類から、ステージを作る人が選ぶ: 帯のカットイン(ボスの顔つき)/ 一文字ずつ叩き込む / 魔法陣。
///   必殺技でない段階の名前は、顔のない細い金色の帯で出す
/// - 時刻は GameScene から渡す(名前を出し始めてからの秒。0〜1.2)。同じ時刻なら同じ絵になるので、止めても巻き戻っても崩れない
/// - 文字や顔の絵を作るのは、名前を出し始めるときの1回だけ。毎コマは、置き場所・濃さ・大きさを変えるだけ
/// - 帯・魔法陣・顔は弾や自機より下(back)に、名前の文字は上(front)に置く。演出が弾を隠さないようにするため
final class PhaseBanner {
    enum Style: Int { case band = 0, stamp = 1, circle = 2 }

    /// 演出に出すボスの顔
    struct Face {
        let texture: SKTexture
        /// 絵の全体を、画面に出す大きさ
        let size: CGSize
        /// 顔の中心が、絵のどこにあるか(割合。x は左から、y は上から)
        let focus: CGPoint

        /// ドット絵(待機の1コマ目)から、顔のあたりを大きく出す。体の上から 27% あたりを顔とみなす。
        /// 小さい絵(ザコの姿など)は、体の全体が入るようにまん中を出す
        static func pixelArt(_ still: UIImage, texture: SKTexture) -> Face {
            let pw = max(1, still.size.width * still.scale), ph = max(1, still.size.height * still.scale)
            let box = still.cgImage.flatMap { PhaseBanner.opaqueBounds(of: $0) } ?? CGRect(x: 0, y: 0, width: pw, height: ph)
            let zoom = min(8, max(3, 300 / max(1, box.height)))
            let visible = PhaseBanner.bandHeight / zoom
            let fy = box.height <= visible * 1.4 ? box.midY : box.minY + box.height * 0.27
            return Face(texture: texture, size: CGSize(width: pw * zoom, height: ph * zoom), focus: CGPoint(x: box.midX / pw, y: fy / ph))
        }
    }

    /// 演出の長さ(秒)。Simulation が段階の変わり目に取る間(banner)と同じ
    static let length = 1.2
    /// 必殺技の帯の高さ
    fileprivate static let bandHeight: CGFloat = 78

    /// 弾より下に置く部品(帯・魔法陣・顔・光)
    let back = SKNode()
    /// 弾より上に置く部品(名前の文字)
    let front = SKNode()

    private let W: CGFloat, H: CGFloat
    private var key = ""
    private var showing = false
    private var raised = false
    /// 重なる順番(同じ高さに置くと順番が決まらないことがあるので、足した順に少しずつ上へ)
    private var order: CGFloat = 0
    private var update: ((Double) -> Void)?

    init(width: CGFloat, height: CGFloat) {
        W = width; H = height
        back.isHidden = true; front.isHidden = true
    }

    /// 名前を出す。毎コマ呼ぶ。elapsed は、出し始めてからの秒。
    /// raised: 竜王のカットイン(画面のまん中より少し下の帯)と重なるとき。上にずらして出す(出している間は、ずらしたまま)
    func show(_ text: String, special: Bool, style: Style, tag: String, elapsed: Double, raised wantRaised: Bool, face: () -> Face?) {
        let k = "\(style.rawValue)|\(special ? 1 : 0)|\(text)"
        if !showing || k != key {
            key = k; showing = true; raised = false
            order = 0
            back.removeAllChildren(); front.removeAllChildren()
            let col = special ? Palette.pink : Palette.gold
            switch style {
            case .band: update = buildBand(text, special: special, color: col, tag: tag, face: special ? face() : nil)
            case .stamp: update = buildStamp(text, special: special, color: col, tag: tag)
            case .circle: update = buildCircle(text, color: col, tag: tag, face: face())
            }
            back.isHidden = false; front.isHidden = false
        }
        if wantRaised { raised = true }
        let lift: CGFloat = raised ? (style == .circle ? 102 : 74) : 0
        back.position = CGPoint(x: W / 2, y: H / 2 + lift)
        front.position = back.position
        update?(max(0, min(PhaseBanner.length, elapsed)))
    }

    /// 名前を消す(出していなければ、何もしない)
    func hide() {
        guard showing else { return }
        showing = false
        update = nil
        back.removeAllChildren(); front.removeAllChildren()
        back.isHidden = true; front.isHidden = true
    }

    /// 部品を足す。足した順に、少しずつ上に重ねる
    private func put(_ n: SKNode, in parent: SKNode) {
        order += 0.001
        n.zPosition = order
        parent.addChild(n)
    }

    // MARK: 帯のカットイン

    /// 斜めの帯が開き、右にボスの顔、名前が左から滑り込む。必殺技でなければ、細い金色の帯に名前だけ
    private func buildBand(_ text: String, special: Bool, color: UIColor, tag: String, face: Face?) -> (Double) -> Void {
        let W = self.W, H = self.H
        let BH: CGFloat = special ? PhaseBanner.bandHeight : 46, BW = W + 60
        let tilt: CGFloat = 0.07

        // 画面全体の光と、暗がり(必殺技だけ)。帯と一緒には傾けない
        let flash = SKSpriteNode(color: .white, size: CGSize(width: W, height: H + 220))
        let dim = SKSpriteNode(color: UIColor(red: 5 / 255, green: 3 / 255, blue: 12 / 255, alpha: 1), size: CGSize(width: W, height: H + 220))
        flash.alpha = 0; dim.alpha = 0
        if special { put(dim, in: back); put(flash, in: back) }

        let band = SKNode()
        band.zRotation = tilt
        put(band, in: back)
        put(SKSpriteNode(color: UIColor(red: 6 / 255, green: 3 / 255, blue: 10 / 255, alpha: 0.88), size: CGSize(width: BW, height: BH)), in: band)
        put(SKSpriteNode(texture: PhaseBanner.tintTexture(special: special), size: CGSize(width: BW, height: BH)), in: band)
        // 流れる線
        var lines: [(node: SKSpriteNode, speed: Double, offset: Double)] = []
        for i in 0..<(special ? 16 : 8) {
            let d = Double(i)
            let n = SKSpriteNode(color: i % 3 != 0 ? color : .white, size: CGSize(width: 40 + PhaseBanner.hs(d, 2) * 120, height: 1))
            n.anchorPoint = CGPoint(x: 0, y: 0.5)
            n.alpha = 0.45
            n.position.y = CGFloat((PhaseBanner.hs(d, 1) - 0.5)) * (BH - 2)
            put(n, in: band)
            lines.append((n, 520 + PhaseBanner.hs(d, 3) * 620, PhaseBanner.hs(d, 4) * 500))
        }
        // ボスの顔(帯の高さぶんだけ切り出しておく。帯と一緒に開くので、はみ出さない)
        var faceNode: SKSpriteNode?
        if let f = face {
            let vf = min(1, BH / max(1, f.size.height))
            let top = min(max(0, f.focus.y - vf / 2), 1 - vf)
            let part = SKTexture(rect: CGRect(x: 0, y: 1 - (top + vf), width: 1, height: vf), in: f.texture)
            part.filteringMode = f.texture.filteringMode
            let n = SKSpriteNode(texture: part, size: CGSize(width: f.size.width, height: f.size.height * vf))
            n.anchorPoint = CGPoint(x: min(max(f.focus.x, 0), 1), y: 0.5)
            n.alpha = 0
            put(n, in: band)
            faceNode = n
        }
        // 帯のふち(白い線と、色の細い線)
        for (y, h, c) in [(BH / 2 + 1, 2, UIColor.white), (-BH / 2 - 1, 2, UIColor.white), (BH / 2 + 4.5, 1, color), (-BH / 2 - 4.5, 1, color)] as [(CGFloat, CGFloat, UIColor)] {
            let n = SKSpriteNode(color: c, size: CGSize(width: BW, height: h))
            n.position.y = y
            put(n, in: band)
        }

        // 名前と「必殺技」の札。帯と同じ向きに傾ける
        let words = SKNode()
        words.zRotation = tilt
        put(words, in: front)
        let font = PhaseBanner.fitted(text, base: special ? 30 : 24, room: W - 28)
        let name = PhaseBanner.textSprite(text, font: font, fill: .white, stroke: PhaseBanner.ink, strokeWidth: 6, shadow: color)
        name.node.anchorPoint = CGPoint(x: name.pad / max(1, name.node.size.width), y: 0.5)
        name.node.position.y = special ? -4 : 0
        put(name.node, in: words)
        var plate: SKSpriteNode?
        if special {
            let p = PhaseBanner.plateSprite(tag, maxWidth: W - 40)
            p.anchorPoint = CGPoint(x: 0, y: 0.5)
            put(p, in: words)
            plate = p
        }
        words.isHidden = true

        return { t in
            let open = PhaseBanner.outBack(PhaseBanner.seg(t, 0, 0.14)), close = 1 - PhaseBanner.inCubic(PhaseBanner.seg(t, 1.02, 1.2))
            let e = CGFloat(max(0, open * close))
            band.isHidden = e < 0.01
            band.yScale = max(0.01, e)
            flash.alpha = CGFloat(0.35 * (1 - PhaseBanner.seg(t, 0, 0.16)))
            dim.alpha = 0.3 * min(1, e)
            for l in lines {
                let travel = (t * l.speed + l.offset).truncatingRemainder(dividingBy: Double(W) + 240)
                l.node.position.x = W / 2 + 40 - CGFloat(travel)
            }
            if let n = faceNode {
                let fi = PhaseBanner.outCubic(PhaseBanner.seg(t, 0.05, 0.26))
                n.position.x = W / 2 - 78 + CGFloat((1 - fi) * 170 - t * 10)
                n.alpha = CGFloat(0.95 * fi)
            }
            let si = PhaseBanner.outCubic(PhaseBanner.seg(t, 0.1, 0.3)), so = PhaseBanner.inCubic(PhaseBanner.seg(t, 1.0, 1.2))
            words.isHidden = e <= 0.5
            words.alpha = CGFloat(1 - so)
            let x = -W / 2 + 14 + CGFloat(-(1 - si) * 300 + PhaseBanner.seg(t, 0.3, 1.0) * 8 + so * 320)
            name.node.position.x = x
            if let p = plate {
                p.position = CGPoint(x: x + 2, y: BH * e / 2 + 3)
                p.setScale(CGFloat(max(0.01, PhaseBanner.outBack(PhaseBanner.seg(t, 0.16, 0.3)))))
            }
        }
    }

    // MARK: 一文字ずつ

    /// 文字が1つずつ大きく落ちてきて、そろったところで下線と衝撃の輪が走る
    private func buildStamp(_ text: String, special: Bool, color: UIColor, tag: String) -> (Double) -> Void {
        let W = self.W
        let backdrop = SKSpriteNode(texture: PhaseBanner.backdropTexture, size: CGSize(width: W, height: 140))
        backdrop.alpha = 0
        put(backdrop, in: back)

        let font = PhaseBanner.fitted(text, base: special ? 32 : 26, room: W - 28)
        let size = font.pointSize
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let total = (text as NSString).size(withAttributes: attrs).width
        // 一文字ずつの絵。右から書く文字・つながる文字(アラビア文字など)は、分けると形が崩れるので、まとめて1つで出す
        let pieces = PhaseBanner.joinsLetters(text) ? [text] : text.map { String($0) }
        var letters: [(node: SKSpriteNode, index: Int)] = []
        var prefix = ""
        var left = -total / 2
        for (i, ch) in pieces.enumerated() {
            prefix += ch
            let right = -total / 2 + (prefix as NSString).size(withAttributes: attrs).width
            defer { left = right }
            guard !ch.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let s = PhaseBanner.textSprite(ch, font: font, fill: .white, stroke: PhaseBanner.ink, strokeWidth: 6, shadow: color)
            s.node.position.x = (left + right) / 2
            s.node.isHidden = true
            put(s.node, in: front)
            letters.append((s.node, i))
        }
        let lineY = -size * 0.62
        let under = SKSpriteNode(color: color, size: CGSize(width: total + 16, height: 3))
        under.position.y = lineY - 1.5
        let under2 = SKSpriteNode(color: .white, size: CGSize(width: total + 16, height: 1))
        under2.position.y = lineY - 4.5
        put(under, in: front); put(under2, in: front)
        var ring: SKShapeNode?
        var tagNode: SKSpriteNode?
        if special {
            let r = SKShapeNode(ellipseOf: CGSize(width: 80, height: 28))
            r.strokeColor = color; r.fillColor = .clear; r.lineWidth = 1
            r.isHidden = true
            put(r, in: front)
            ring = r
            let tf = PhaseBanner.fitted(tag, base: 16, room: W - 40)
            let ts = PhaseBanner.textSprite(tag, font: tf, fill: Palette.pink, stroke: PhaseBanner.ink, strokeWidth: 4, shadow: nil)
            ts.node.position.y = size * 0.62 + 14
            put(ts.node, in: front)
            tagNode = ts.node
        }
        let count = Double(pieces.count)
        let step = min(0.05, 0.36 / max(1, count)), land = 0.1 + step * count + 0.1

        return { t in
            let fade = 1 - PhaseBanner.seg(t, 1.0, 1.2)
            backdrop.alpha = CGFloat(min(PhaseBanner.seg(t, 0, 0.1), fade))
            let lift = CGFloat(PhaseBanner.seg(t, 1.0, 1.2) * 10)
            for l in letters {
                let start = 0.06 + Double(l.index) * step
                let p = PhaseBanner.seg(t, start, start + 0.12)
                l.node.isHidden = p <= 0
                l.node.setScale(CGFloat(1 + (1 - PhaseBanner.outCubic(p)) * 1.8))
                l.node.alpha = CGFloat(min(p * 2, 1) * fade)
                l.node.position.y = lift
            }
            let u = CGFloat(max(0.001, PhaseBanner.outCubic(PhaseBanner.seg(t, land - 0.08, land + 0.12))))
            under.xScale = u; under2.xScale = u
            under.alpha = CGFloat(fade); under2.alpha = CGFloat(fade)
            if let r = ring {
                let k = PhaseBanner.seg(t, land - 0.05, land + 0.3)
                r.isHidden = k <= 0 || k >= 1
                r.xScale = CGFloat((40 + k * 190) / 40); r.yScale = CGFloat((14 + k * 60) / 14)
                r.alpha = CGFloat((1 - k) * 0.8)
            }
            tagNode?.alpha = CGFloat(fade * PhaseBanner.seg(t, 0.02, 0.12))
        }
    }

    // MARK: 魔法陣

    /// 回る魔法陣の中にボスの顔。名前は右から流れてきて、右上へ抜けて消える
    private func buildCircle(_ text: String, color: UIColor, tag: String, face: Face?) -> (Double) -> Void {
        let W = self.W, H = self.H
        let R: CGFloat = 62
        let circle = SKNode()
        circle.position.y = 18
        put(circle, in: back)
        let disc = SKShapeNode(circleOfRadius: R)
        disc.fillColor = UIColor(red: 5 / 255, green: 3 / 255, blue: 12 / 255, alpha: 0.6)
        disc.strokeColor = color; disc.lineWidth = 2
        put(disc, in: circle)
        if let f = face {
            // 顔は丸く切り抜く
            let crop = SKCropNode()
            crop.maskNode = SKSpriteNode(texture: PhaseBanner.discTexture, size: CGSize(width: (R - 6) * 2, height: (R - 6) * 2))
            let n = SKSpriteNode(texture: f.texture, size: f.size)
            n.anchorPoint = CGPoint(x: min(max(f.focus.x, 0), 1), y: 1 - min(max(f.focus.y, 0), 1))
            n.position.y = -4
            put(n, in: crop)
            put(crop, in: circle)
        }
        let spin = SKNode()
        put(spin, in: circle)
        let outer = CGRect(x: -(R + 8), y: -(R + 8), width: (R + 8) * 2, height: (R + 8) * 2)
        let dashed = SKShapeNode(path: CGPath(ellipseIn: outer, transform: nil).copy(dashingWithPhase: 0, lengths: [6, 5]))
        dashed.strokeColor = color; dashed.fillColor = .clear; dashed.lineWidth = 1
        put(dashed, in: spin)
        for k in 0..<2 {
            let path = CGMutablePath()
            for i in 0..<3 {
                let a = CGFloat(k) * .pi / 3 + CGFloat(i) * .pi * 2 / 3
                let p = CGPoint(x: cos(a) * (R + 8), y: sin(a) * (R + 8))
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            path.closeSubpath()
            let tri = SKShapeNode(path: path)
            tri.strokeColor = UIColor.white.withAlphaComponent(0.7); tri.fillColor = .clear; tri.lineWidth = 1
            put(tri, in: spin)
        }

        let font = PhaseBanner.fitted(text, base: 28, room: W - 28)
        let size = font.pointSize
        let tw = (text as NSString).size(withAttributes: [.font: font]).width
        let name = PhaseBanner.textSprite(text, font: font, fill: .white, stroke: PhaseBanner.ink, strokeWidth: 6, shadow: color)
        put(name.node, in: front)
        let under = SKSpriteNode(color: color, size: CGSize(width: tw + 12, height: 2))
        under.anchorPoint = CGPoint(x: 0, y: 0.5)
        put(under, in: front)
        let tf = PhaseBanner.fitted(tag, base: 16, room: W - 40)
        let ts = PhaseBanner.textSprite(tag, font: tf, fill: Palette.pink, stroke: PhaseBanner.ink, strokeWidth: 4, shadow: nil)
        ts.node.anchorPoint = CGPoint(x: ts.pad / max(1, ts.node.size.width), y: 0.5)
        put(ts.node, in: front)
        // 名前の置き場所(front のまん中から見て): 魔法陣の下。消えるときは、画面の右上へ
        let homeY: CGFloat = 18 - 86

        let front = self.front
        return { t in
            let inn = PhaseBanner.outCubic(PhaseBanner.seg(t, 0, 0.22)), out = PhaseBanner.inCubic(PhaseBanner.seg(t, 0.98, 1.2))
            circle.alpha = CGFloat(inn * (1 - out))
            circle.setScale(CGFloat((0.5 + 0.5 * inn) * (1 + out * 0.5)))
            spin.zRotation = CGFloat(-t * 2.2)
            let si = PhaseBanner.outCubic(PhaseBanner.seg(t, 0.08, 0.3))
            let exitX = W / 2 - 14 - tw / 2, exitY = (H - 40) - front.position.y
            let x = CGFloat((1 - si) * 320) + CGFloat(out) * exitX
            let y = homeY + CGFloat(out) * (exitY - homeY)
            let a = CGFloat(min(si * 1.5, 1) * (1 - out))
            name.node.position = CGPoint(x: x, y: y); name.node.alpha = a
            under.position = CGPoint(x: x - tw / 2 - 6, y: y - size * 0.6 - 1)
            under.xScale = CGFloat(max(0.001, si)); under.alpha = a
            ts.node.position = CGPoint(x: x - tw / 2, y: y + size * 0.6 + 11); ts.node.alpha = a
        }
    }

    // MARK: 文字の絵

    /// 文字のふち取りの色
    private static let ink = UIColor(red: 10 / 255, green: 6 / 255, blue: 18 / 255, alpha: 1)

    /// 見出しの字体。Dela Gothic One に無い字(韓国語・一部の中国語・絵文字など)が1つでも入っていたら、
    /// 字体が混ざって見えないように、名前の全体を端末の太字で出す
    private static func font(for text: String, size: CGFloat) -> UIFont {
        if let dela = UIFont(name: "DelaGothicOne-Regular", size: size) {
            let chars = Array(text.utf16)
            if chars.isEmpty { return dela }
            var glyphs = [CGGlyph](repeating: 0, count: chars.count)
            let ct = CTFontCreateWithName(dela.fontName as CFString, size, nil)
            if CTFontGetGlyphsForCharacters(ct, chars, &glyphs, chars.count) { return dela }
        }
        return UIFont.systemFont(ofSize: size, weight: .black)
    }

    /// room の幅に収まる大きさの字体(長い名前は小さくする)
    private static func fitted(_ text: String, base: CGFloat, room: CGFloat) -> UIFont {
        let f = font(for: text, size: base)
        let w = (text as NSString).size(withAttributes: [.font: f]).width
        guard w > room else { return f }
        return f.withSize(max(8, floor(base * room / w * 10) / 10))
    }

    /// 文字を1枚の絵にする: 色の影 → ふち取り → 中の色、の順に重ねる。pad は、絵のふちから文字までの余白
    private static func textSprite(_ text: String, font: UIFont, fill: UIColor, stroke: UIColor, strokeWidth: CGFloat, shadow: UIColor?) -> (node: SKSpriteNode, pad: CGFloat) {
        let ns = text as NSString
        let ts = ns.size(withAttributes: [.font: font])
        let pad = ceil(strokeWidth / 2) + 5
        let size = CGSize(width: ceil(ts.width) + pad * 2, height: ceil(ts.height) + pad * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let outline = strokeWidth / max(1, font.pointSize) * 100
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.setLineJoin(.round)
            let p = CGPoint(x: pad, y: pad)
            if let shadow {
                let q = CGPoint(x: p.x + 2.5, y: p.y + 3)
                ns.draw(at: q, withAttributes: [.font: font, .strokeColor: shadow, .strokeWidth: outline])
                ns.draw(at: q, withAttributes: [.font: font, .foregroundColor: shadow])
            }
            ns.draw(at: p, withAttributes: [.font: font, .strokeColor: stroke, .strokeWidth: outline])
            ns.draw(at: p, withAttributes: [.font: font, .foregroundColor: fill])
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return (SKSpriteNode(texture: tex, size: size), pad)
    }

    /// 「必殺技」の札(ピンクの斜めの板に、濃い色の文字)
    private static func plateSprite(_ text: String, maxWidth: CGFloat) -> SKSpriteNode {
        let font = fitted(text, base: 16, room: maxWidth - 31)
        let ns = text as NSString
        let ts = ns.size(withAttributes: [.font: font])
        let h: CGFloat = 26, skew: CGFloat = 7
        let size = CGSize(width: ceil(ts.width) + 24 + skew, height: h)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let c = ctx.cgContext
            c.setFillColor(Palette.pink.cgColor)
            c.move(to: CGPoint(x: skew, y: 0)); c.addLine(to: CGPoint(x: size.width, y: 0))
            c.addLine(to: CGPoint(x: size.width - skew, y: h)); c.addLine(to: CGPoint(x: 0, y: h))
            c.closePath(); c.fillPath()
            ns.draw(at: CGPoint(x: (size.width - ts.width) / 2, y: (h - ts.height) / 2),
                    withAttributes: [.font: font, .foregroundColor: UIColor(red: 26 / 255, green: 6 / 255, blue: 18 / 255, alpha: 1)])
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return SKSpriteNode(texture: tex, size: size)
    }

    /// 一文字ずつに分けると形が崩れる文字(右から書く文字・つながる文字)が入っているか
    private static func joinsLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { s in
            let v = s.value
            return (0x0590...0x08FF).contains(v) || (0x0900...0x0DFF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
        }
    }

    // MARK: 使い回す絵(最初に使うときに1回だけ作る)

    private static func gradientTexture(size: CGSize, colors: [UIColor], horizontal: Bool) -> SKTexture {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let cg = colors.map { $0.cgColor } as CFArray
            guard let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cg, locations: nil) else { return }
            let end = horizontal ? CGPoint(x: size.width, y: 0) : CGPoint(x: 0, y: size.height)
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: end, options: [])
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }

    /// 帯にかける色(必殺技: ピンク → 紫、ふつう: 金色が右へ薄くなる)
    private static let specialTint = gradientTexture(size: CGSize(width: 64, height: 4), colors: [
        UIColor(red: 1, green: 60 / 255, blue: 130 / 255, alpha: 0.55), UIColor(red: 120 / 255, green: 40 / 255, blue: 220 / 255, alpha: 0.35)], horizontal: true)
    private static let normalTint = gradientTexture(size: CGSize(width: 64, height: 4), colors: [
        UIColor(red: 1, green: 200 / 255, blue: 40 / 255, alpha: 0.30), UIColor(red: 1, green: 200 / 255, blue: 40 / 255, alpha: 0.05)], horizontal: true)
    private static func tintTexture(special: Bool) -> SKTexture { special ? specialTint : normalTint }

    /// 一文字ずつの演出の、文字の後ろの暗がり(上下が透ける)
    private static let backdropTexture = gradientTexture(size: CGSize(width: 4, height: 64), colors: [
        UIColor(red: 5 / 255, green: 3 / 255, blue: 12 / 255, alpha: 0), UIColor(red: 5 / 255, green: 3 / 255, blue: 12 / 255, alpha: 0.75),
        UIColor(red: 5 / 255, green: 3 / 255, blue: 12 / 255, alpha: 0)], horizontal: false)

    /// 丸く切り抜くための、白い円
    private static let discTexture: SKTexture = {
        let size = CGSize(width: 64, height: 64)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = false
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
        }
        let tex = SKTexture(image: image)
        tex.filteringMode = .linear
        return tex
    }()

    // MARK: 絵の中で、体が描かれている範囲

    /// 透明でない部分を囲む四角(左上が原点、ピクセル)。まわりに散った小さな点(きらめきなど)は数えない
    fileprivate static func opaqueBounds(of cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0, w * h <= 1_000_000 else { return nil }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let c = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            c.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else { return nil }
        var rows = [Int](repeating: 0, count: h), cols = [Int](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w where px[(y * w + x) * 4 + 3] > 40 { rows[y] += 1; cols[x] += 1 }
        }
        guard let y0 = rows.firstIndex(where: { $0 >= 3 }), let y1 = rows.lastIndex(where: { $0 >= 3 }),
              let x0 = cols.firstIndex(where: { $0 >= 3 }), let x1 = cols.lastIndex(where: { $0 >= 3 }) else { return nil }
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }

    // MARK: 動きの式

    /// t が a〜b のどこにあるか(0〜1)
    private static func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
    private static func outCubic(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    private static func inCubic(_ x: Double) -> Double { x * x * x }
    /// 少し行きすぎてから戻る
    private static func outBack(_ x: Double) -> Double { 1 + 2.2 * pow(x - 1, 3) + 1.2 * pow(x - 1, 2) }
    /// いつも同じ値になる乱数(0〜1)
    private static func hs(_ i: Double, _ k: Double) -> Double {
        let s = sin(i * 127.1 + k * 311.7) * 43758.5453
        return s - floor(s)
    }
}
