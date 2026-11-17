import SpriteKit
import UIKit
import DanmakuCore

/// 竜王のドット絵。ほかのボスと作り方が違う(art/bosses/dragon/README.txt):
/// - 絵は「色の番号の絵」(dragonsheet_<動き>.png。赤の値 ÷ 10 = 色の番号、透明 = 0)を 1 行 8 コマで並べたもの
/// - 姿(0 通常・1 蒼炎・2 紫電・3 白金)ごとの色の表(dragon_forms.json)で塗ってから使う
/// - 1 コマ 240×200、25 コマ/秒。画面には 2 倍(480×400 の論理px)で描く(試射場と同じ)
/// 全部塗ると重いので、使う動きだけ、使うときに塗って覚える(姿が変わったら、前の姿の絵は捨てる)
enum DragonArt {
    struct Meta: Decodable {
        let frame_ms: Int
        let w: Int
        let h: Int
        let cols: Int
        let anims: [String: Int]
        let label_step: Int
    }
    private struct Forms: Decodable {
        struct Form: Decodable { let id: String; let name: String; let colors: [String: [Int]] }
        let forms: [Form]
    }

    static let meta: Meta? = {
        guard let u = Bundle.main.url(forResource: "dragon_anim", withExtension: "json"), let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONDecoder().decode(Meta.self, from: d)
    }()
    /// 姿ごとの色の表(番号 → RGBA)
    private static let palettes: [[UInt32]] = {
        guard let u = Bundle.main.url(forResource: "dragon_forms", withExtension: "json"), let d = try? Data(contentsOf: u),
              let f = try? JSONDecoder().decode(Forms.self, from: d) else { return [] }
        return f.forms.map { form in
            var p = [UInt32](repeating: 0, count: 256)
            for (k, c) in form.colors {
                guard let i = Int(k), i < 256, c.count >= 3 else { continue }
                // RGBA(メモリの並び R, G, B, A)。透明でないので、そのまま(乗算済みと同じ)
                p[i] = UInt32(c[0]) | UInt32(c[1]) << 8 | UInt32(c[2]) << 16 | 0xFF00_0000
            }
            return p
        }
    }()

    /// 1 コマの長さ(秒)
    static var frameSeconds: Double { Double(meta?.frame_ms ?? 40) / 1000 }
    /// 画面での 1 コマの大きさ(論理px。絵の 2 倍)
    static var drawSize: CGSize { CGSize(width: (meta?.w ?? 240) * 2, height: (meta?.h ?? 200) * 2) }
    static func frameCount(_ anim: String) -> Int { meta?.anims[anim] ?? 0 }

    // MARK: 塗った絵

    /// 色の番号の絵(読み込みは 1 回だけ)。[番号]・幅・高さ
    private static var labels: [String: (px: [UInt8], w: Int, h: Int)] = [:]
    private static func labelSheet(_ anim: String) -> (px: [UInt8], w: Int, h: Int)? {
        if let l = labels[anim] { return l }
        guard let u = Bundle.main.url(forResource: "dragonsheet_" + anim, withExtension: "png"),
              let img = UIImage(contentsOfFile: u.path)?.cgImage else { return nil }
        let w = img.width, h = img.height
        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        let ok = rgba.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        let step = Double(meta?.label_step ?? 10)
        var px = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) where rgba[i * 4 + 3] > 0 {
            px[i] = UInt8(min(255, (Double(rgba[i * 4]) / step).rounded()))
        }
        let l = (px, w, h)
        labels[anim] = l
        return l
    }

    /// 姿 form で塗った動き anim の絵(並べたまま)
    static func coloredSheet(_ anim: String, form: Int) -> CGImage? {
        guard let l = labelSheet(anim), !palettes.isEmpty else { return nil }
        let pal = palettes[min(max(form, 0), palettes.count - 1)]
        var out = [UInt32](repeating: 0, count: l.w * l.h)
        for i in 0..<out.count where l.px[i] != 0 { out[i] = pal[Int(l.px[i])] }
        let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let prov = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: l.w, height: l.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: l.w * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 1 コマずつの絵(CGImage)。ショップ・エディタの見本用
    static func frames(_ anim: String, form: Int) -> [CGImage] {
        guard let m = meta, let sheet = coloredSheet(anim, form: form) else { return [] }
        return (0..<frameCount(anim)).compactMap { k in
            sheet.cropping(to: CGRect(x: (k % m.cols) * m.w, y: (k / m.cols) * m.h, width: m.w, height: m.h))
        }
    }

    // MARK: ゲームで使う絵(SKTexture)

    /// 塗ったコマ。キーは「姿:動き」。姿が変わったら、前の姿の待機以外の絵は捨てる(メモリを食うので)
    private static var texCache: [String: [SKTexture]] = [:]
    static func textures(_ anim: String, form: Int) -> [SKTexture] {
        let key = "\(form):\(anim)"
        if let t = texCache[key] { return t }
        guard let m = meta, let sheet = coloredSheet(anim, form: form) else { return [] }
        let all = SKTexture(cgImage: sheet)
        all.filteringMode = .nearest
        let W = CGFloat(sheet.width), H = CGFloat(sheet.height)
        let n = frameCount(anim)
        let list: [SKTexture] = (0..<n).map { k in
            // SKTexture の rect は 0〜1 で、原点は左下
            let x = CGFloat((k % m.cols) * m.w), yTop = CGFloat((k / m.cols) * m.h)
            let r = CGRect(x: x / W, y: (H - yTop - CGFloat(m.h)) / H, width: CGFloat(m.w) / W, height: CGFloat(m.h) / H)
            let t = SKTexture(rect: r, in: all)
            t.filteringMode = .nearest
            return t
        }
        texCache[key] = list
        return list
    }
    /// もう塗ってあるか
    static func isLoaded(_ anim: String, form: Int) -> Bool { texCache["\(form):\(anim)"] != nil }
    /// 使う動きを先に塗っておく(技の途中で塗ると、一瞬止まるので)
    static func preload(_ anims: [String], form: Int) {
        for a in anims { _ = textures(a, form: form) }
    }
    /// 姿 form 以外の、待機でない絵を捨てる(待機の絵は、姿が変わる瞬間に止まらないよう残す)
    static func keepMoves(of form: Int) {
        texCache = texCache.filter { $0.key.hasPrefix("\(form):") || $0.key.hasSuffix(":idle") }
    }
    /// ゲームが終わったら捨てる(色の番号の絵も)
    static func purge() { texCache.removeAll(); labels.removeAll(); faceCache.removeAll() }

    /// カットインに出す顔(待機の1コマ目の顔のあたり)。小さい所だけ塗る(大きな絵全体を持たない)
    private static var faceCache: [Int: CGImage] = [:]
    static func face(form: Int) -> CGImage? {
        if let f = faceCache[form] { return f }
        guard let l = labelSheet("idle"), !palettes.isEmpty else { return nil }
        let pal = palettes[min(max(form, 0), palettes.count - 1)]
        let x0 = 84, y0 = 40, w = 88, h = 44
        guard x0 + w <= l.w, y0 + h <= l.h else { return nil }
        var out = [UInt32](repeating: 0, count: w * h)
        for y in 0..<h { for x in 0..<w {
            let v = l.px[(y0 + y) * l.w + x0 + x]
            if v != 0 { out[y * w + x] = pal[Int(v)] }
        } }
        let data = out.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let prov = CGDataProvider(data: data as CFData),
              let img = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        faceCache[form] = img
        return img
    }

    /// 弾が当たったときに白く光らせる(形はそのまま)
    static let flashShader = SKShader(source: """
    void main() {
        vec4 c = texture2D(u_texture, v_tex_coord);
        gl_FragColor = vec4(c.a, c.a, c.a, c.a);
    }
    """)

    // MARK: 技ごとの動き(試射場 spec.py の anim / windup)

    /// 技中の動き
    static func attackAnim(_ m: DragonMove) -> String {
        switch m {
        case .breath: return "breath"
        case .raid: return "dive"
        case .gale: return "gale"
        case .inhale: return "inhale"
        case .glide: return "glide"
        case .roar: return "roar"
        case .quake: return "slam"
        case .tail: return "tail"
        case .rampage: return "cyclone"
        case .end: return "wrath"
        }
    }
    /// 構えの動き(星喰いはブレス、灼熱の滑空は急降下の構え)
    static func windupAnim(_ m: DragonMove) -> String {
        switch m {
        case .inhale: return "breath"
        case .glide: return "dive"
        default: return attackAnim(m)
        }
    }
    /// エディタの見本の絵で、技を始めてから何フレーム(60Hz)進めたところを描くか(弾・範囲攻撃がよく見えるところ)
    static func iconFrames(_ m: DragonMove) -> Int {
        switch m {
        case .breath: return 30 + 70
        case .raid: return 30 + 60
        case .gale: return 30 + 80
        case .inhale: return 30 + 150
        case .glide: return 30 + 60
        case .roar: return 30 + 50
        case .quake: return 30 + 60
        case .tail: return 30 + 50
        case .rampage: return 30 + 90
        case .end: return 30 + 60
        }
    }

    /// 技 m で使う動きの名前(先に塗る用)
    static func anims(for m: DragonMove) -> [String] {
        var a = [windupAnim(m) + "_windup", attackAnim(m) + "_attack", attackAnim(m) + "_recover"]
        if m == .glide { a += ["side_fly_l", "side_fly_r"] }
        return a
    }

    /// いまの状態で出す絵の(動き, コマ番号)。試射場の bossFrame と同じ: 25 コマ/秒、待機・技中・横向きはループ、構え・硬直は最後のコマで止まる
    static func frame(for d: DragonState, waveFrames: Int) -> (anim: String, index: Int) {
        // 待機(技を待っている間)は時刻で、休み(硬直のあと)・技の各段階は、その段階の始まりから数える
        let i = Int(Double(d.stage == .idle ? waveFrames : d.stageFrames) / (7.0 * Double(meta?.frame_ms ?? 40) / 120.0))
        func loop(_ a: String) -> (String, Int) { (a, i % max(1, frameCount(a))) }
        func once(_ a: String) -> (String, Int) { (a, min(i, max(1, frameCount(a)) - 1)) }
        if d.pose != 0 { return loop(d.pose > 0 ? "side_fly_r" : "side_fly_l") }
        guard let m = d.move else { return loop("idle") }
        switch d.stage {
        case .windup: return once(windupAnim(m) + "_windup")
        case .attack: return loop(attackAnim(m) + "_attack")
        case .recover: return once(attackAnim(m) + "_recover")
        case .idle, .rest: return loop("idle")
        }
    }
}
