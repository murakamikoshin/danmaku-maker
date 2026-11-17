import SpriteKit
import UIKit
import DanmakuCore

/// 竜王の場面の演出(見た目だけで、計算には関わらない)。試射場(art/bosses/patterns/template.html の「ドラゴンの攻撃の演出」と
/// engine.js の step の見た目の部分)の移植。数値・色・形は試射場と同じにする(Koshin の決まり: 見本と実際を同じに)。
/// - 炎は「熱の地図」: 燃えている物が熱を置く → 熱は毎コマ少し冷めながら上へのぼる → 熱さに応じた7段の色で塗る
/// - くっきり描く物(範囲攻撃の予告・炎の柱の芯・爆発の閃光・尻尾・鎖・弾)は、論理px 1 = 1 ドットの絵に描いて、最近傍で拡大する
/// 試射場は 60 コマ/秒で進むので、こちらも 60Hz(シミュレーションの 2 ステップ)ごとに 1 コマ進める
final class DragonLayer {
    static let W = Int(DanmakuConfig.width), H = Int(DanmakuConfig.height)
    private static let Wd = Double(W), Hd = Double(H)

    // MARK: 色(試射場と同じ)

    /// 姿ごと: 濃い・中・明るい・白
    static let FXC: [[String]] = [["#7a1408", "#f0541e", "#ffb428", "#fff4c8"], ["#0a2a6a", "#1e78f0", "#5ad2ff", "#f0fcff"],
                                  ["#3c0a50", "#aa28a0", "#ff5adc", "#ffe6fa"], ["#a06414", "#ffc83c", "#fff0aa", "#ffffff"]]
    /// 炎の色(冷たい → 熱い)の7段
    private static let RAMP: [[String]] = [["#2e0e12", "#7a1408", "#d23a12", "#f0741e", "#ffb428", "#ffe07a", "#fff8dc"],
                                           ["#0e1634", "#0a2a6a", "#1450c8", "#1e8cf0", "#5ad2ff", "#b4f0ff", "#f4feff"],
                                           ["#220c30", "#3c0a50", "#7a1a8c", "#c832b4", "#ff5adc", "#ffb4f4", "#fff0fc"],
                                           ["#402808", "#8c5010", "#d28c1e", "#ffb428", "#ffd250", "#ffec96", "#fffbe6"]]
    /// 背景: 空の上・下・足元の明かり・雲の色
    private static let BGC: [(String, String, String, [UInt8])] = [("#12040a", "#3a0a0c", "#ff5a1e", [120, 30, 24]), ("#03081c", "#0a2048", "#3ca0ff", [30, 70, 150]),
                                                                  ("#0a0316", "#2a0a44", "#e650e6", [96, 36, 130]), ("#05051a", "#1c1638", "#ffdc78", [70, 62, 120])]

    private static var colorCache: [String: CGColor] = [:]
    static func col(_ hex: String) -> CGColor {
        if let c = colorCache[hex] { return c }
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0
        let c = CGColor(srgbRed: CGFloat((v >> 16) & 255) / 255, green: CGFloat((v >> 8) & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
        colorCache[hex] = c
        return c
    }
    private static let white = col("#ffffff"), black = col("#000000")

    /// 試射場の hs(i, s): 決まった値を返す乱数
    @inline(__always) static func hs(_ i: Double, _ s: Double) -> Double {
        let v = sin(i * 127.1 + s * 311.7) * 43758.5453
        return v - floor(v)
    }

    // MARK: 状態(見た目だけ)

    private struct Spark { var x, y, vx, vy: Double; var t = 0.0; var life: Double; var s: Double; var g: Double; var k: Int; var drag: Double }
    private struct Flash { var x, y, r: Double; var t = 0; var life: Int; var slash = 0; var ring = false }
    private var fx: [Spark] = []
    private var flashes: [Flash] = []
    private(set) var shake = 0.0
    private(set) var punch = 0.0
    private var heat = 0
    /// 見た目用の乱数(計算の乱数とは別)
    private var seed: UInt32 = 0x9E37_79B9
    private func rand() -> Double {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Double(seed >> 8) / Double(1 << 24)
    }
    /// 60Hz の時計(背景・点滅に使う)
    private var T = 0
    private var lastTick = -1
    /// 当たり始めを出した範囲攻撃(id)
    private var started: Set<Int> = []
    private var lastLife = -1
    private var lastForm = -1
    private var formCutT = -1
    private var formCut = 0
    /// カットインに出す段階の番号(姿の番号とは別。作者は段階ごとに好きな姿を選べる)
    private var formPhase = 1
    private var prevBoss = CGPoint(x: 180, y: 128)
    private var bSpd = 0.0

    // MARK: 絵を置く部品

    let root = SKNode()
    private let bgNode = SKSpriteNode()
    private let backNode = SKSpriteNode()
    let fireNode = SKSpriteNode()
    private let glow1 = SKSpriteNode(), glow2 = SKSpriteNode()
    private let haloNode = SKSpriteNode()
    private let frontNode = SKSpriteNode()
    private let sparkNode = SKSpriteNode()
    private let overNode = SKSpriteNode()

    private let bgC: CGContext, backC: CGContext, haloC: CGContext, frontC: CGContext, sparkC: CGContext, overC: CGContext
    /// 熱の地図: 置く熱(グレーの絵)と、のぼる熱
    private let heatC: CGContext
    private var HEAT: [UInt8]
    private var fireBuf: [UInt32]
    private var hLive = 0
    private var fireOn = false
    private var rI = 0
    private let RND: [UInt8]
    private let NOISE: [UInt8]
    private let LUT: [[UInt32]]
    private let BAY = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5].map { Int((Double($0) - 7.5) * 1.5) }
    private var clouds: [Int: CGImage] = [:]
    private var glowImgs: [String: CGImage] = [:]
    private var bulletSprites: [String: CGImage] = [:]
    private let stars: [(Double, Double, Int)]

    init() {
        func ctx(gray: Bool = false) -> CGContext {
            let c = CGContext(data: nil, width: DragonLayer.W, height: DragonLayer.H, bitsPerComponent: 8, bytesPerRow: gray ? DragonLayer.W : DragonLayer.W * 4,
                              space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
            // 試射場と同じ、左上が原点・下向きが +y
            c.translateBy(x: 0, y: CGFloat(DragonLayer.H)); c.scaleBy(x: 1, y: -1)
            return c
        }
        bgC = ctx(); backC = ctx(); haloC = ctx(); frontC = ctx(); sparkC = ctx(); overC = ctx(); heatC = ctx(gray: true)
        HEAT = [UInt8](repeating: 0, count: DragonLayer.W * DragonLayer.H)
        fireBuf = [UInt32](repeating: 0, count: DragonLayer.W * DragonLayer.H)
        var s: UInt32 = 12345
        func r() -> Double { s = s &* 1_664_525 &+ 1_013_904_223; return Double(s >> 8) / Double(1 << 24) }
        RND = (0..<8192).map { _ in UInt8(r() * 256) }
        // くり返せる雲の模様(128×128)
        let n = 128
        let oct: [(Int, Double, [Double])] = [(4, 0.42), (8, 0.3), (16, 0.18), (32, 0.1)].map { ($0.0, $0.1, (0..<($0.0 * $0.0)).map { _ in r() }) }
        var noise = [UInt8](repeating: 0, count: n * n)
        for y in 0..<n { for x in 0..<n {
            var v = 0.0
            for (sz, w, a) in oct {
                let u = Double(x) / Double(n) * Double(sz), t = Double(y) / Double(n) * Double(sz)
                let x0 = Int(u), y0 = Int(t), tx = u - Double(x0), ty = t - Double(y0)
                let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty), x1 = (x0 + 1) % sz, y1 = (y0 + 1) % sz
                v += w * ((a[y0 * sz + x0] * (1 - sx) + a[y0 * sz + x1] * sx) * (1 - sy) + (a[y1 * sz + x0] * (1 - sx) + a[y1 * sz + x1] * sx) * sy)
            }
            noise[y * n + x] = UInt8(max(0, min(255, (v - 0.22) / 0.56 * 255)))
        } }
        NOISE = noise
        // 熱 → 色の表(姿ごと)。乗算済みの RGBA
        LUT = DragonLayer.RAMP.map { ramp in
            let th = [22, 54, 90, 126, 162, 198, 232]
            return (0..<320).map { i -> UInt32 in
                let h = i - 24
                var k = -1
                for j in 0..<7 where h >= th[j] { k = j }
                guard k >= 0 else { return 0 }
                let v = UInt32(ramp[k].dropFirst(), radix: 16) ?? 0
                let a: UInt32 = k == 0 ? 150 : k == 1 ? 225 : 255
                let R = ((v >> 16) & 255) * a / 255, G = ((v >> 8) & 255) * a / 255, B = (v & 255) * a / 255
                return R | G << 8 | B << 16 | a << 24
            }
        }
        stars = (0..<60).map { _ in (r() * DragonLayer.Wd, r() * DragonLayer.Hd, r() < 0.2 ? 2 : 1) }

        let size = CGSize(width: DragonLayer.W, height: DragonLayer.H), mid = CGPoint(x: DragonLayer.W / 2, y: DragonLayer.H / 2)
        for (n, z) in [(bgNode, -1.0), (backNode, 1.7), (haloNode, 2.45), (frontNode, 2.5), (sparkNode, 2.55), (overNode, 6.0)] as [(SKSpriteNode, CGFloat)] {
            n.size = size; n.position = mid; n.zPosition = z
            root.addChild(n)
        }
        for (n, a) in [(glow1, 0.4), (glow2, 0.5)] as [(SKSpriteNode, CGFloat)] {
            n.size = size; n.position = mid; n.blendMode = .add; n.alpha = a
            root.addChild(n)
        }
        fireNode.size = size; fireNode.position = mid
        root.addChild(fireNode)
        haloNode.blendMode = .add
        sparkNode.blendMode = .add
    }

    /// 竜王の場面に入ったとき、前の場面の演出(火花・ゆれ・カットイン)を持ち越さない
    func resetScene() {
        fx.removeAll(); flashes.removeAll(); started.removeAll()
        shake = 0; punch = 0; heat = 0
        lastTick = -1; lastLife = -1; lastForm = -1; formCutT = -1
    }

    // MARK: 進める(60Hz)

    /// シミュレーションを進めたあとに呼ぶ。60Hz のコマの数だけ、見た目を進める
    func advance(_ sim: Simulation) {
        let tick60 = sim.tick / 2
        if lastTick < 0 { lastTick = tick60 }
        let n = min(4, tick60 - lastTick)
        lastTick = tick60
        guard n > 0 else { return }
        for _ in 0..<n { step(sim) }
        fireTick(sim)
    }

    /// 被弾・姿の変化・範囲攻撃の当たり始めなど、出来事に合わせた演出(試射場の step の見た目の部分)
    private func step(_ sim: Simulation) {
        T += 1
        let d = sim.dragon, lv = sim.dragonForm
        let bp = sim.bossPosition, B = CGPoint(x: bp.x, y: bp.y)
        // 姿が変わった(段階が変わった): カットインと、光の輪
        if lastForm < 0 { lastForm = lv }
        if lv != lastForm {
            lastForm = lv; formCut = lv; formPhase = sim.phase; formCutT = 0
            heat = max(heat, 18); addShake(12); punch = 1
            spark(B.x, B.y, 90, 9, life: 40, s: 3)
            flashes.append(Flash(x: B.x, y: B.y, r: 300, life: 36, ring: true))
        }
        if formCutT >= 0 { formCutT += 1; if formCutT >= 64 { formCutT = -1 } }
        // 被弾
        if lastLife < 0 { lastLife = sim.lifeLeft }
        if sim.lifeLeft < lastLife {
            spark(sim.player.x, sim.player.y, 20, 4, life: 20, s: 2); addShake(5)
            if sim.lifeLeft == 0 && lastLife > 1 { heat = 30 }      // 即死
        }
        lastLife = sim.lifeLeft
        // 大きい弾は火花の尾を引く
        for b in sim.bullets where b.isDragon && !b.isHiddenBody {
            guard let k = BulletLook.kind(of: b.look), k != .ember, k != .pshot else { continue }
            let t = Int(b.age * 60)
            if k == .tornado {
                spark(b.x + (rand() - 0.5) * 50, b.y + 20, 1, 2.4, a: -.pi / 2, spread: 0.8, life: 30, s: 2)
                if t % 3 == 0 { spark(b.x, b.y + 24, 1, 1, life: 40, k: 2, g: -0.04, jit: 40) }
            } else if t % 2 == 0 {
                let sun = k == .sun
                spark(b.x, b.y, sun ? 3 : 1, sun ? 2 : 0.7, life: sun ? 26 : 16, s: sun ? 3 : 2, jit: b.radius)
            }
        }
        for z in d.zones {
            // 炎の柱: ふちから火花が散り、口元と画面の下で炎がはじける
            if z.shape == .beam && z.active {
                let ux = cos(z.a), uy = sin(z.a)
                for _ in 0..<4 {
                    let dd = rand() * 640, sd: Double = rand() < 0.5 ? 1 : -1
                    spark(z.x + ux * dd - uy * sd * z.w * 0.5, z.y + uy * dd + ux * sd * z.w * 0.5, 1, 2.2, a: z.a + sd * 1.1, spread: 0.9, life: 22, s: 2)
                }
                spark(z.x, z.y, 2, 3.5, a: z.a, spread: 2.2, life: 16, s: 3)
                if uy > 0.2 {
                    let dd = (DragonLayer.Hd - z.y) / uy
                    spark(z.x + ux * dd, DragonLayer.Hd - 4, 3, 4, a: -.pi / 2, spread: 2.4, life: 26, s: 3, g: 0.12)
                    if z.t % 4 == 0 { spark(z.x + ux * dd, DragonLayer.Hd - 6, 1, 1.5, a: -.pi / 2, life: 44, s: 6, k: 1, jit: z.w) }
                }
                if z.t % 6 == 0 { addShake(2) }
            }
            if z.active && !started.contains(z.id) {
                // 当たり始めの瞬間
                started.insert(z.id)
                switch (z.shape, z.style) {
                case (.beam, _): addShake(8)
                case (.circle, .boom): boom(z.x, z.y, z.r)
                case (.circle, .claw):
                    addShake(7); spark(z.x, z.y, 30, 6, life: 20, s: 3)
                    flashes.append(Flash(x: z.x, y: z.y, r: z.r, life: 14, slash: z.x > B.x ? 1 : -1))
                case (.circle, .pillar): spark(z.x, z.y, 8, 5, a: -.pi / 2, spread: 1.2, life: 30, s: 3, g: 0.1); addShake(5)
                case (.rect, _): addShake(9)
                case (.safe, _):
                    addShake(18)
                    for _ in 0..<120 { spark(rand() * DragonLayer.Wd, rand() * DragonLayer.Hd, 1, 5, life: 40, s: 3) }
                default: break
                }
            }
            if z.shape == .ring {
                for _ in 0..<3 {
                    let a = z.gapA + z.gapW + rand() * (2 * .pi - 2 * z.gapW)
                    spark(z.x + cos(a) * z.r, z.y + sin(a) * z.r, 1, 1.5, a: a, spread: 0.8, life: 18, s: 2)
                }
            }
            if z.shape == .safe && !z.active {
                let k = Double(z.t) / Double(max(1, z.warn))
                for _ in 0..<Int(2 + k * 5) { spark(rand() * DragonLayer.Wd, DragonLayer.Hd + 4, 1, 3 + 3 * k, a: -.pi / 2, spread: 0.5, life: 60, s: 2, k: 2, g: -0.05) }
                if k > 0.6 { addShake(2) }
            }
            if z.active {
                if z.style == .pillar && z.t % 2 == 0 { spark(z.x, z.y + z.r * 0.5, 1, 4.5, a: -.pi / 2, spread: 0.7, life: 26, s: 3) }
                if z.fly != 0 {
                    let f = Double(z.fly)
                    for _ in 0..<5 { spark(B.x - f * (40 + rand() * 160), z.y + rand() * z.h, 1, 4, a: z.fly > 0 ? .pi : 0, spread: 1, life: 26, s: 3) }
                }
                if z.sweep != 0 {
                    let x = Simulation.tailTip(z)
                    for _ in 0..<6 { spark(x, z.y + rand() * z.h, 1, 5, a: z.sweep > 0 ? .pi : 0, spread: 1.2, life: 22, s: 3) }
                }
            }
        }
        started = started.filter { id in d.zones.contains { $0.id == id } }
        // 風の筋・吸い込みの筋
        if d.wind.x != 0 {
            for _ in 0..<3 { spark(d.wind.x > 0 ? -10 : DragonLayer.Wd + 10, 180 + rand() * 360, 1, 9, a: d.wind.x > 0 ? 0.08 : .pi - 0.08, spread: 0.05, life: 50, s: 2, k: 3, drag: 1) }
        }
        if d.pull != 0 && d.pullForce > 0, let o = sim.dragonPullTarget(), o.y < 200 {
            for _ in 0..<2 {
                let a = rand() * .pi, dd = 180 + rand() * 260, x = o.x + cos(a) * dd, y = o.y + sin(a) * dd
                spark(x, y, 1, 7, a: atan2(o.y - y, o.x - x), spread: 0.1, life: 30, s: 2, k: 3, drag: 1.02)
            }
        }
        for i in fx.indices {
            fx[i].t += 1; fx[i].x += fx[i].vx; fx[i].y += fx[i].vy; fx[i].vy += fx[i].g; fx[i].vx *= fx[i].drag; fx[i].vy *= fx[i].drag
        }
        fx.removeAll { $0.t >= $0.life }
        for i in flashes.indices { flashes[i].t += 1 }
        flashes.removeAll { $0.t >= $0.life }
        if shake > 0 { shake *= 0.86 }
        if punch > 0.02 { punch *= 0.78 } else { punch = 0 }
        bSpd = hypot(B.x - prevBoss.x, B.y - prevBoss.y); prevBoss = B
    }

    private func addShake(_ n: Double) { shake = max(shake, n) }

    private func spark(_ x: Double, _ y: Double, _ n: Int, _ sp: Double, a: Double? = nil, spread: Double = 0.6, life: Double = 24, s: Double = 2,
                       k: Int = 0, g: Double = 0, jit: Double = 0, drag: Double = 0.95) {
        for _ in 0..<n where fx.count < 900 {
            let an = a.map { $0 + (rand() - 0.5) * spread } ?? rand() * 2 * .pi
            let v = sp * (0.3 + rand() * 0.9)
            fx.append(Spark(x: x + (rand() - 0.5) * jit, y: y + (rand() - 0.5) * jit, vx: cos(an) * v, vy: sin(an) * v,
                            life: life * (0.6 + rand() * 0.8), s: s, g: g, k: k, drag: drag))
        }
    }

    /// 大爆発: 火花・破片・煙・画面のゆれ・光の輪
    private func boom(_ x: Double, _ y: Double, _ r: Double) {
        addShake(min(16, 4 + r / 12))
        spark(x, y, min(90, Int(r * 0.6)), r / 8, life: 36, s: 3, g: 0.04)
        spark(x, y, 26, r / 14, life: 60, s: 5, k: 1, g: -0.03, jit: r * 0.8)
        spark(x, y, 30, r / 20, life: 70, s: 2, k: 2, g: -0.02, jit: r)
        flashes.append(Flash(x: x, y: y, r: r, life: 30))
        if r >= 60 { punch = max(punch, min(1.4, r / 120)); if r >= 100 { heat = max(heat, 12) } }
    }

    // MARK: 熱の地図

    private func hDisc(_ x: Double, _ y: Double, _ r: Double, _ h: Double) {
        guard r > 0.3 else { return }
        heatC.setFillColor(gray: CGFloat(min(255, h)) / 255, alpha: 1)
        heatC.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }
    private func hEll(_ x: Double, _ y: Double, _ rx: Double, _ ry: Double, _ h: Double) {
        heatC.setFillColor(gray: CGFloat(min(255, h)) / 255, alpha: 1)
        heatC.fillEllipse(in: CGRect(x: x - rx, y: y - ry, width: rx * 2, height: ry * 2))
    }

    /// 炎の柱の形: ふちが波打つ。口元は細く、先へ行くほど太い
    private static func beamPoly(_ c: CGContext, _ z: DragonZone, wd: Double, amp: Double, sp: Double, ph: Double) {
        let ux = cos(z.a), uy = sin(z.a)
        let k = min(1, Double(z.t - z.warn) / 8, Double(z.warn + z.dur - z.t) / 8)
        let n = 44, len = 760.0, t = Double(z.t)
        let p = CGMutablePath()
        var first = true
        for side in [1.0, -1.0] {
            for i in 0...n {
                let j = side > 0 ? i : n - i, d = Double(j) / Double(n) * len, flare = 0.35 + 0.65 * min(1, d / 70)
                let w = z.w * 0.5 * wd * k * flare * (1 + amp * sin(d * 0.07 - t * sp + ph + side) + amp * 0.6 * sin(d * 0.19 + t * sp * 1.7 - side * 2))
                let pt = CGPoint(x: z.x + ux * d - uy * side * w, y: z.y + uy * d + ux * side * w)
                if first { p.move(to: pt); first = false } else { p.addLine(to: pt) }
            }
        }
        p.closeSubpath()
        c.addPath(p); c.fillPath()
    }

    /// 先のとがった弓なりの刃(爪の跡)。k = どこまで伸びたか
    private static func blade(_ c: CGContext, _ g: [Double], _ w: Double, _ k: Double) {
        let (x0, y0, qx, qy, x1, y1) = (g[0], g[1], g[2], g[3], g[4], g[5])
        let n = 14
        var L: [CGPoint] = [], R: [CGPoint] = []
        for i in 0...n {
            let s = Double(i) / Double(n) * k, a = 1 - s
            let x = a * a * x0 + 2 * a * s * qx + s * s * x1, y = a * a * y0 + 2 * a * s * qy + s * s * y1
            let dx = 2 * a * (qx - x0) + 2 * s * (x1 - qx), dy = 2 * a * (qy - y0) + 2 * s * (y1 - qy)
            let l = max(1e-9, hypot(dx, dy)), hw = w * pow(sin(Double.pi * Double(i) / Double(n)), 0.7)
            L.append(CGPoint(x: x - dy / l * hw, y: y + dx / l * hw)); R.append(CGPoint(x: x + dy / l * hw, y: y - dx / l * hw))
        }
        let p = CGMutablePath()
        p.addLines(between: L + R.reversed()); p.closeSubpath()
        c.addPath(p); c.fillPath()
    }
    private static func slashGeo(_ f: Flash) -> [[Double]] {
        let s = Double(f.slash)
        return [-18.0, 0, 18].map { off in [f.x + s * f.r * 0.75 + off, f.y - f.r * 0.95, f.x + off - s * 30, f.y - 14, f.x - s * f.r * 0.85 + off, f.y + f.r * 0.95] }
    }
    /// 竜巻の輪切り(下が細く、上が広い。うねって、軸もゆっくり曲がる)
    private static func torGeo(_ b: Bullet, _ j: Int) -> (Double, Double, Double) {
        let t = b.age * 60, jd = Double(j)
        return (b.x + sin(t * 0.22 + jd * 0.6) * (1 + jd * 1.1) + sin(t * 0.045 + b.u2) * jd * jd * 0.12, b.y + 34 - jd * 7, 4 + jd * jd * 0.16 + jd * 0.9)
    }

    /// 熱を置く(このコマで燃えている物ぜんぶ)
    private func fireEmit(_ sim: Simulation) -> Bool {
        let c = heatC
        c.saveGState()
        c.setBlendMode(.normal); c.setFillColor(gray: 0, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: DragonLayer.W, height: DragonLayer.H))
        c.setBlendMode(.plusLighter)
        var dirty = false
        let d = sim.dragon, B = sim.bossPosition
        for z in d.zones where z.shape == .beam {
            dirty = true
            if !z.active { hDisc(z.x, z.y, 3 + 10 * Double(z.t) / Double(max(1, z.warn)) + Double(z.t % 3), 255) }
            else {
                c.setFillColor(gray: 1, alpha: 1); DragonLayer.beamPoly(c, z, wd: 1.0, amp: 0.16, sp: 0.6, ph: 0)
                hDisc(z.x, z.y, z.w * 0.5, 255)
                let uy = sin(z.a)
                if uy > 0.2 { let dd = (DragonLayer.Hd - z.y) / uy; hDisc(z.x + cos(z.a) * dd, DragonLayer.Hd - 6, z.w * 0.62, 255) }
            }
        }
        for f in flashes {
            if f.slash != 0 {
                if f.t < 9 { c.setFillColor(gray: 230.0 / 255, alpha: 1); for g in DragonLayer.slashGeo(f) { DragonLayer.blade(c, g, 5, min(1, Double(f.t) / 4)) }; dirty = true }
                continue
            }
            if f.ring { continue }
            dirty = true
            if f.t < 13 {
                let R0 = f.r * (0.45 + 0.5 * min(1, Double(f.t) / 7))
                hDisc(f.x, f.y, R0 * 0.78, 255)
                for i in 0..<7 { let a = Double(i) * 0.9 + f.r; hDisc(f.x + cos(a) * R0 * 0.56, f.y + sin(a) * R0 * 0.56, R0 * 0.4, 255) }
            } else if f.t < 22 {
                for i in 0..<5 { let a = Double(i) * 1.3 + f.r; hDisc(f.x + cos(a) * f.r * 0.45, f.y + sin(a) * f.r * 0.45, f.r * 0.22, 190) }
            }
        }
        for m in d.marks where m.kind == .crack {
            // 地割れの予告: ひびがくすぶる
            c.setStrokeColor(gray: (90 + 60 * Double(m.t) / Double(max(1, m.life))) / 255, alpha: 1); c.setLineWidth(2)
            let n = min(m.pts.count, 2 + m.t / 3)
            if n >= 2 { c.addLines(between: m.pts.prefix(n).map { CGPoint(x: $0.x, y: $0.y) }); c.strokePath(); dirty = true }
        }
        for z in d.zones {
            let on = z.active, k = min(1, Double(z.t) / Double(max(1, z.warn)))
            if z.shape == .circle && z.style == .pillar && on {
                let f = min(1, Double(z.t - z.warn) / 6, Double(z.warn + z.dur - z.t) / 10)
                for _ in 0..<4 { hDisc(z.x + (rand() - 0.5) * z.r * 1.5 * f, z.y + z.r * (0.25 + 0.6 * rand()), (3 + rand() * 6) * f, 255) }
                hEll(z.x, z.y + z.r * 0.75, z.r * 0.8 * f, 3, 255); dirty = true
            } else if z.shape == .safe {
                c.setFillColor(gray: 1, alpha: 1); dirty = true
                if on { c.fill(CGRect(x: 0, y: 0, width: DragonLayer.W, height: DragonLayer.H)) }
                else {
                    // 予告: 足元から火の手が上がり、広がっていく
                    c.fill(CGRect(x: 0, y: DragonLayer.Hd - 5, width: DragonLayer.Wd, height: 5))
                    for _ in 0..<Int(3 + 16 * k) { hDisc(rand() * DragonLayer.Wd, DragonLayer.Hd - rand() * rand() * (60 + k * DragonLayer.Hd * 0.75), 4 + rand() * (5 + 9 * k), 90 + 105 * k * rand()) }
                }
            } else if z.shape == .rect && on && z.fly != 0 {
                let f = Double(z.fly), cy = z.y + z.h / 2
                for i in 0..<6 { let di = Double(i); hDisc(B.x - f * (80 + di * 34), cy + sin(Double(z.t) * 0.9 + di) * z.h * 0.14, z.h * 0.3 * (1 - di * 0.12), i < 2 ? 235 : 190) }
                dirty = true
            } else if z.shape == .rect && on && z.sweep != 0 {
                // 尻尾が通った跡が燃える
                let x = Simulation.tailTip(z), s = Double(z.sweep)
                for i in 0..<6 { let di = Double(i); hEll(x - s * (40 + di * 62), z.y + z.h * 0.5 + sin(di * 2 + Double(z.t) * 0.6) * z.h * 0.22, 34 - di * 2, z.h * 0.07, 175 - di * 8) }
                dirty = true
            }
        }
        for b in sim.bullets where b.isDragon && !b.isHiddenBody {
            guard let k = BulletLook.kind(of: b.look) else { continue }
            dirty = true
            switch k {
            case .flame:
                let pyre = DragonLayer.isPyre(b)
                hDisc(b.x, b.y, pyre ? b.radius * (0.9 + 0.25 * rand()) : b.radius * 0.9, pyre ? 255 : 215)
            case .sun: hDisc(b.x, b.y, b.radius * 1.15, 255)
            case .rock: hDisc(b.x, b.y, b.radius * 0.55, 150)
            case .ember: hDisc(b.x, b.y, 2, 170)
            case .slash: hDisc(b.x, b.y, b.radius * 0.45, 120)
            case .tornado:
                // 渦に沿って回る炎のかたまり。手前(下側)ほど明るい。芯は細く
                let t = b.age * 60, life = b.fuse * 60, g = min(1, t / 20, (life - t) / 20), ti = Int(t)
                for j in 0..<14 {
                    let (cx, cy, w) = DragonLayer.torGeo(b, j)
                    hEll(cx, cy, w * g * 0.4, 3, j < 2 ? 255 : 200)
                    for kk in 0..<3 {
                        let ph = t * 0.33 + Double(j) * 0.85 + Double(kk) * 2 * .pi / 3 + DragonLayer.hs(Double(j), Double(kk)) * 0.8
                        if DragonLayer.hs(Double(j * 3 + kk), Double(ti >> 2) + b.u2) < 0.18 { continue }
                        hDisc(cx + cos(ph) * w * g * 0.85, cy + sin(ph) * 2.5, (2.5 + Double(j) * 0.4) * g * (0.7 + 0.6 * DragonLayer.hs(Double(kk), Double(j + (ti >> 3)))), 150 + 95 * max(0, sin(ph)))
                    }
                }
                for i in 0..<5 {      // 足元の巻き上げ
                    let ph = t * 0.2 + Double(i) * 1.3
                    hDisc(b.x + cos(ph) * (26 + 8 * DragonLayer.hs(Double(i), Double(ti >> 3))) * g, b.y + 36 + sin(ph) * 5, (4 + 3 * DragonLayer.hs(Double(i), 2)) * g, 140)
                }
            default: break
            }
        }
        for q in fx where q.k == 1 { let u = q.t / q.life; hDisc(q.x, q.y, q.s * (0.8 + u), 80 * (1 - u)); dirty = true }
        // 体当たりで飛ぶ本体は、炎の尾を引く
        if bSpd > 2.4 && d.pose == 0 && sim.bullets.contains(where: { $0.isHiddenBody }) { hDisc(B.x, B.y + 14, 34, 115); dirty = true }
        c.restoreGState()
        return dirty
    }

    static func isPyre(_ b: Bullet) -> Bool {
        BulletLook.kind(of: b.look) == .flame && b.script == Bullet.dragonPlainScript && b.vy < 0 && b.vy > -20 && abs(b.vx) < 0.5
    }

    /// 熱を進めて、色を塗る(進行 1 コマにつき 1 回)
    private func fireTick(_ sim: Simulation) {
        let dirty = fireEmit(sim)
        if !dirty && hLive == 0 { fireOn = false; return }
        fireOn = true
        let W = DragonLayer.W, H = DragonLayer.H
        let wx = sim.dragon.wind.x > 0 ? 1 : sim.dragon.wind.x < 0 ? -1 : 0, cool = 10
        let lut = LUT[min(max(sim.dragonForm, 0), 3)]
        let src: UnsafeMutablePointer<UInt8>? = dirty ? heatC.data?.assumingMemoryBound(to: UInt8.self) : nil
        // 熱の地図の行は、上が 0(heatC は上下を返して描いているので、メモリの行も上から)
        let T = sim.tick / 2
        HEAT.withUnsafeMutableBufferPointer { hp in
            fireBuf.withUnsafeMutableBufferPointer { fp in
                let h = hp.baseAddress!, f = fp.baseAddress!
                for y in 1..<H {
                    let row = y * W, up = row - W
                    for x in 0..<W {
                        let v0 = Int(h[row + x])
                        if v0 == 0 { h[up + x] = 0; continue }
                        rI = (rI + 1) & 8191
                        let r = Int(RND[rI])
                        var dx = x + (r % 3) - 1 + ((r & 8) != 0 ? wx * 2 : 0)
                        if dx < 0 { dx = 0 } else if dx >= W { dx = W - 1 }
                        let v = v0 - ((r >> 4) * cool >> 4)
                        h[up + dx] = UInt8(max(0, v))
                    }
                }
                for x in 0..<W { h[(H - 1) * W + x] = 0 }
                if let s = src {
                    let ox = (T * 2) & 127, oy = (-T * 5) & 127
                    // heatC の bytesPerRow は W(グレー 1 バイト)。CGContext のメモリは上の行から
                    for y in 0..<H {
                        for x in 0..<W {
                            let i = y * W + x, sv = Int(s[i])
                            if sv < 8 { continue }
                            let v = sv * (140 + (Int(NOISE[((x + ox) & 127) + (((y + oy) & 127) << 7)]) * 116 >> 8)) >> 8
                            if sv >= 200 || v > Int(h[i]) { h[i] = UInt8(min(255, v)) }
                        }
                    }
                }
                // 安全な輪の中は燃えない
                for z in sim.dragon.zones where z.shape == .safe {
                    for c in z.safe {
                        let r = c.r + 2
                        for y in max(0, Int(c.y - r))..<min(H, Int(c.y + r) + 1) {
                            let w = (max(0, r * r - (Double(y) - c.y) * (Double(y) - c.y))).squareRoot()
                            let a = max(0, Int(c.x - w)), b = min(W, Int(c.x + w) + 1)
                            if a < b { for x in a..<b { h[y * W + x] = 0 } }
                        }
                    }
                }
                var live = 0
                for y in 0..<H {
                    let by = (y & 3) << 2
                    for x in 0..<W {
                        let i = y * W + x, v = Int(h[i])
                        if v == 0 { f[i] = 0; continue }
                        live += 1
                        f[i] = lut[max(0, min(319, v + 24 + BAY[by | (x & 3)]))]
                    }
                }
                hLive = live
            }
        }
        guard let img = makeImage(fireBuf) else { return }
        let t = SKTexture(cgImage: img); t.filteringMode = .nearest
        fireNode.texture = t
        // ぼかした光(1/4・1/8 に縮めて、なめらかに引き伸ばして足す)
        glow1.texture = shrink(img, by: 4)
        glow2.texture = shrink(img, by: 8)
    }

    private func makeImage(_ buf: [UInt32]) -> CGImage? {
        let data = buf.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let prov = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: DragonLayer.W, height: DragonLayer.H, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: DragonLayer.W * 4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    private func shrink(_ img: CGImage, by k: Int) -> SKTexture? {
        let w = DragonLayer.W / k, h = DragonLayer.H / k
        guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        c.interpolationQuality = .medium
        c.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let s = c.makeImage() else { return nil }
        let t = SKTexture(cgImage: s); t.filteringMode = .linear
        return t
    }

    // MARK: 描く(画面の書き換えごと)

    /// 竜王の場面で、毎フレーム呼ぶ。boss は本体の絵(位置・大きさ)
    func render(_ sim: Simulation, boss: SKSpriteNode) {
        let lv = min(max(sim.dragonForm, 0), 3), C = DragonLayer.FXC[lv].map(DragonLayer.col)
        let B = sim.bossPosition
        // 横向きに飛ぶ間は、炎の尾を本体のうしろに描く
        fireNode.zPosition = sim.dragon.pose != 0 ? 1.9 : 2.1
        glow1.zPosition = fireNode.zPosition + 0.01; glow2.zPosition = fireNode.zPosition + 0.02
        fireNode.isHidden = !fireOn; glow1.isHidden = !fireOn; glow2.isHidden = !fireOn
        drawBackground(sim, lv: lv, C: C)
        // うしろ: 範囲攻撃の予告と、ボスのうしろの光
        clear(backC)
        drawZones(backC, sim, front: false, C: C, lv: lv)
        drawAura(backC, B: B, lv: lv)
        backNode.texture = texture(backC)
        // 手前: 当たっている範囲攻撃・予告の印・炎の柱・弾・爆発・鎖
        clear(frontC)
        drawZones(frontC, sim, front: true, C: C, lv: lv)
        for m in sim.dragon.marks { drawMark(frontC, m, C: C) }
        drawBeams(frontC, sim, C: C)
        drawBullets(frontC, sim, C: C, lv: lv)
        drawFlashes(frontC, C: C)
        if sim.dragon.bind > 0 { drawBind(frontC, sim, C: C) }
        frontNode.texture = texture(frontC)
        // 光(足し合わせる): 大きい弾のまわり・火花
        clear(haloC)
        drawHalos(haloC, sim, C: C)
        haloNode.texture = texture(haloC)
        clear(sparkC)
        drawParticles(sparkC, C: C)
        sparkNode.texture = texture(sparkC)
        // いちばん上: 被弾で赤いふち・姿のカットイン・白い光
        clear(overC)
        drawOverlay(overC, sim, C: C, lv: lv, boss: boss)
        overNode.texture = texture(overC)
    }

    private func clear(_ c: CGContext) {
        c.saveGState(); c.setBlendMode(.copy); c.setFillColor(CGColor(gray: 0, alpha: 0)); c.fill(CGRect(x: 0, y: 0, width: DragonLayer.W, height: DragonLayer.H)); c.restoreGState()
    }
    private func texture(_ c: CGContext) -> SKTexture? {
        guard let img = c.makeImage() else { return nil }
        let t = SKTexture(cgImage: img); t.filteringMode = .nearest
        return t
    }

    // MARK: 背景

    private func cloudTex(_ lv: Int) -> CGImage? {
        if let c = clouds[lv] { return c }
        let col = DragonLayer.BGC[lv].3
        var buf = [UInt32](repeating: 0, count: 256 * 256)
        for y in 0..<256 { for i in 0..<256 {
            let n = Int(NOISE[(i >> 1) + ((y >> 1) << 7)]), a: UInt32 = n < 128 ? 0 : n < 152 ? 40 : n < 180 ? 70 : 105
            buf[y * 256 + i] = UInt32(col[0]) * a / 255 | (UInt32(col[1]) * a / 255) << 8 | (UInt32(col[2]) * a / 255) << 16 | a << 24
        } }
        let data = buf.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let prov = CGDataProvider(data: data as CFData) else { return nil }
        let img = CGImage(width: 256, height: 256, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 1024, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        clouds[lv] = img
        return img
    }
    /// まるい光(中心が濃く、ふちで消える)
    private func glowSpr(_ hex: String) -> CGImage? {
        if let g = glowImgs[hex] { return g }
        guard let c = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let base = DragonLayer.col(hex)
        let cols = [base, base.copy(alpha: 0.6)!, base.copy(alpha: 0.2)!, base.copy(alpha: 0)!] as CFArray
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cols, locations: [0, 0.35, 0.7, 1]) {
            c.drawRadialGradient(g, startCenter: CGPoint(x: 32, y: 32), startRadius: 0, endCenter: CGPoint(x: 32, y: 32), endRadius: 32, options: [])
        }
        let img = c.makeImage()
        glowImgs[hex] = img
        return img
    }
    private func drawImage(_ c: CGContext, _ img: CGImage, _ r: CGRect) {
        // 上下を返した座標で、絵が逆さまにならないように描く
        c.saveGState(); c.translateBy(x: r.minX, y: r.maxY); c.scaleBy(x: 1, y: -1)
        c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height)); c.restoreGState()
    }

    /// 背景: 姿ごとの空・流れる雲・火の粉。覚醒2は稲妻、覚醒3は天からの光
    private func drawBackground(_ sim: Simulation, lv: Int, C: [CGColor]) {
        let c = bgC, B = DragonLayer.BGC[lv], T = Double(self.T), W = DragonLayer.Wd, H = DragonLayer.Hd
        let hx = DragonLayer.FXC[lv]
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [DragonLayer.col(B.0), DragonLayer.col(B.1)] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        for (x, y, s) in stars {
            let yy = (y + T * 0.3 * Double(s)).truncatingRemainder(dividingBy: H)
            c.setFillColor(DragonLayer.col(s > 1 ? "#5a5078" : "#2e2846")); c.fill(CGRect(x: floor(x), y: floor(yy), width: 1, height: 1))
        }
        if let ct = cloudTex(lv) {
            c.interpolationQuality = .none
            for (sc, sp, al, ox) in [(1.5, 0.35, 0.55, 40.0), (2.5, 0.8, 0.5, 170.0)] {
                c.setAlpha(al)
                let S = 256 * sc, off = (T * sp).truncatingRemainder(dividingBy: S), dx = sin(T * 0.004 + sc) * 30 + ox
                var y = off - S
                while y < H {
                    var x = -S + dx.truncatingRemainder(dividingBy: S)
                    while x < W { drawImage(c, ct, CGRect(x: x.rounded(), y: y.rounded(), width: S, height: S)); x += S }
                    y += S
                }
            }
            c.setAlpha(1)
        }
        if lv == 3 {      // 天からの光
            c.saveGState(); c.setBlendMode(.plusLighter); c.setFillColor(C[2])
            for i in 0..<7 {
                let di = Double(i), a = Double.pi / 2 + (di - 3) * 0.2 + sin(T * 0.006 + di * 1.7) * 0.07, w = 0.035 + 0.02 * DragonLayer.hs(di, 3)
                c.setAlpha(max(0, 0.05 + 0.035 * sin(T * 0.02 + di * 2.1)))
                c.move(to: CGPoint(x: W / 2, y: -90)); c.addLine(to: CGPoint(x: W / 2 + cos(a - w) * 900, y: -90 + sin(a - w) * 900)); c.addLine(to: CGPoint(x: W / 2 + cos(a + w) * 900, y: -90 + sin(a + w) * 900))
                c.fillPath()
            }
            c.restoreGState()
        }
        if lv == 2 {      // 稲妻
            let seg = self.T / 64, ph = self.T % 64
            if DragonLayer.hs(Double(seg), 1) < 0.7 && ph < 10 {
                if ph < 3 { c.setFillColor(CGColor(srgbRed: 230 / 255, green: 120 / 255, blue: 1, alpha: 0.10)); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
                let x0 = 30 + DragonLayer.hs(Double(seg), 2) * (W - 60), a: CGFloat = ph < 6 || ph % 2 == 1 ? 1 : 0.4, len = 300 + DragonLayer.hs(Double(seg), 3) * 240
                func bolt(_ x0: Double, _ y0: Double, _ len0: Double, _ s: Double, _ w: Int) {
                    var x = x0, y = y0, len = len0, n = 0
                    c.move(to: CGPoint(x: x, y: y))
                    while len > 0 && n < 40 {
                        x += (DragonLayer.hs(Double(n), s) - 0.5) * 34; y += 12 + DragonLayer.hs(Double(n), s + 5) * 16; len -= 20; n += 1
                        c.addLine(to: CGPoint(x: x, y: y))
                        if w > 1 && DragonLayer.hs(Double(n), s + 9) < 0.18 { c.strokePath(); bolt(x, y, len * 0.5, s + Double(n) * 3, 1); c.move(to: CGPoint(x: x, y: y)) }
                    }
                    c.strokePath()
                }
                c.setLineJoin(.miter)
                c.setAlpha(0.35 * a); c.setStrokeColor(C[1]); c.setLineWidth(5); bolt(x0, -4, len, Double(seg), 2)
                c.setAlpha(a); c.setStrokeColor(DragonLayer.white); c.setLineWidth(1.5); bolt(x0, -4, len, Double(seg), 2)
                c.setAlpha(1)
            }
        }
        // 足元の明かり
        let foot = DragonLayer.col(B.2)
        if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [foot.copy(alpha: 0)!, foot.copy(alpha: lv > 0 ? 0x50 / 255.0 : 0x40 / 255.0)!] as CFArray, locations: [0, 1]) {
            c.saveGState(); c.clip(to: CGRect(x: 0, y: H * 0.6, width: W, height: H * 0.4))
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: H * 0.6), end: CGPoint(x: 0, y: H), options: [])
            c.restoreGState()
        }
        // 火の粉(のぼっていく)
        for i in 0..<46 {
            let di = Double(i), sp = 0.35 + DragonLayer.hs(di, 7) * 1.3
            let y = H + 6 - (T * sp + DragonLayer.hs(di, 8) * 640).truncatingRemainder(dividingBy: 640), x = DragonLayer.hs(di, 9) * W + sin(T * 0.03 + di) * 10
            if (self.T + i * 7) % 20 >= 14 { continue }
            c.setFillColor(i % 5 == 0 ? DragonLayer.col(hx[3]) : i % 2 == 1 ? DragonLayer.col(hx[2]) : DragonLayer.col(hx[1]))
            c.setAlpha(max(0, min(1, 0.25 + 0.6 * (y / H))))
            let s: Double = i % 7 == 0 ? 2 : 1
            c.fill(CGRect(x: floor(x), y: floor(y), width: s, height: s))
        }
        c.setAlpha(1)
        // 大技のため中・炎が出ている間は、背景を暗くして光を目立たせる
        var dim = fireOn ? 0.2 : 0
        for z in sim.dragon.zones where !z.active {
            let k = Double(z.t) / Double(max(1, z.warn))
            if z.shape == .beam { dim = max(dim, 0.4 * k) }
            dim = max(dim, (z.shape == .safe ? 0.5 : z.style == .boom ? 0.3 : 0) * k)
        }
        if dim > 0 { c.setFillColor(CGColor(gray: 0, alpha: dim)); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
        bgNode.texture = texture(c)
    }

    /// ボスのうしろの光
    private func drawAura(_ c: CGContext, B: Point, lv: Int) {
        guard let g = glowSpr(DragonLayer.FXC[lv][1]) else { return }
        let r = 190 + Double(lv) * 16 + 10 * sin(Double(T) * 0.07)
        c.saveGState(); c.setBlendMode(.plusLighter)
        c.setAlpha([0.12, 0.26, 0.32, 0.4][lv] + 0.05 * sin(Double(T) * 0.11))
        c.interpolationQuality = .medium
        drawImage(c, g, CGRect(x: B.x - r, y: B.y - r * 0.8 + 10, width: r * 2, height: r * 1.6))
        c.restoreGState()
    }

    // MARK: 範囲攻撃

    private func disc(_ c: CGContext, _ x: Double, _ y: Double, _ r: Double, _ col: CGColor, _ a: Double = 1) {
        guard r > 0 else { return }
        c.setAlpha(a); c.setFillColor(col)
        c.fillEllipse(in: CGRect(x: x.rounded() - r, y: y.rounded() - r, width: r * 2, height: r * 2)); c.setAlpha(1)
    }
    private func arc(_ c: CGContext, _ x: Double, _ y: Double, _ r: Double, _ a0: Double = 0, _ a1: Double = 2 * .pi) {
        c.addArc(center: CGPoint(x: x, y: y), radius: max(0, r), startAngle: a0, endAngle: a1, clockwise: false)
    }
    private func tri(_ c: CGContext, _ p: [(Double, Double)]) {
        c.move(to: CGPoint(x: p[0].0, y: p[0].1)); for q in p.dropFirst() { c.addLine(to: CGPoint(x: q.0, y: q.1)) }; c.closePath(); c.fillPath()
    }

    private func formColor(_ lv: Int, _ k: Int) -> CGColor {
        // 竜王の色の表(dragon_forms.json)の色。尻尾に使う
        let hex = DragonLayer.tailColors[lv][k] ?? DragonLayer.tailColors[0][k] ?? "#ffffff"
        return DragonLayer.col(hex)
    }
    /// 竜王の体の色(forms.json の 1・2・3・6・7・8・9)
    private static let tailColors: [[Int: String]] = [
        [1: "#c62828", 2: "#861422", 3: "#f2623e", 6: "#ecb03c", 7: "#b07222", 8: "#ffe482", 9: "#f6d092"],
        [1: "#3a3060", 2: "#241e42", 3: "#605896", 6: "#46beff", 7: "#226ed2", 8: "#c8f4ff", 9: "#96dcff"],
        [1: "#461e64", 2: "#2c1046", 3: "#783ca0", 6: "#ff5adc", 7: "#aa28a0", 8: "#ffbefa", 9: "#e696f0"],
        [1: "#f4f0ec", 2: "#a49cbe", 3: "#ffffff", 6: "#ffce50", 7: "#c4821e", 8: "#fff6b0", 9: "#ffdc88"]]

    /// 尻尾の薙ぎ払い: うろこのある太い尻尾が、しなりながら横切る
    private func drawTail(_ c: CGContext, _ z: DragonZone, C: [CGColor], lv: Int) {
        let d = Double(z.sweep), tip = Simulation.tailTip(z), cy = z.y + z.h / 2, hh = z.h * 0.36, n = Int((DragonState.tailLength / 13).rounded())
        c.setAlpha(0.22); c.setFillColor(C[1]); c.fill(CGRect(x: z.x, y: z.y, width: z.w, height: z.h)); c.setAlpha(1)
        var P: [(Double, Double, Double)] = []
        for s in 0..<n {
            let ds = Double(s)
            P.append((tip - d * ds * 13, cy + sin(ds * 0.33 - Double(z.t) * 1.1) * hh * 0.42 * min(1, ds / 8), min(hh, 4 + ds * 1.05)))
        }
        for s in stride(from: n - 1, through: 0, by: -1) where s % 2 == 0 && s > 1 {
            let (x, y, r) = P[s]
            c.setFillColor(formColor(lv, 6)); tri(c, [(x - d * 2, y - r + 2), (x - d * (8 + r * 0.5), y - r - 5 - r * 0.45), (x - d * (10 + r * 0.3), y - r + 3)])
        }
        for s in stride(from: n - 1, through: 0, by: -1) { let (x, y, r) = P[s]; disc(c, x, y, r + 1.5, formColor(lv, 2)) }
        for s in stride(from: n - 1, through: 0, by: -1) { let (x, y, r) = P[s]; disc(c, x, y, r, formColor(lv, 1)) }
        for s in stride(from: n - 1, through: 0, by: -1) { let (x, y, r) = P[s]; disc(c, x, y + r * 0.5, r * 0.56, formColor(lv, 9)); disc(c, x + d * r * 0.2, y - r * 0.42, r * 0.36, formColor(lv, 3)) }
        c.setStrokeColor(formColor(lv, 2)); c.setLineWidth(1)
        for s in stride(from: n - 1, through: 2, by: -2) {
            let (x, y, r) = P[s]
            arc(c, x + d * r * 0.6, y, r * 0.95, d > 0 ? .pi * 0.62 : -.pi * 0.38, d > 0 ? .pi * 1.38 : .pi * 0.38); c.strokePath()
        }
        let (tx, ty, _) = P[0]
        c.setFillColor(formColor(lv, 7)); tri(c, [(tx + d * 52, ty), (tx + d * 8, ty - 20), (tx - d * 6, ty - 5), (tx - d * 6, ty + 5), (tx + d * 8, ty + 20)])
        c.setFillColor(formColor(lv, 6)); tri(c, [(tx + d * 48, ty), (tx + d * 8, ty - 16), (tx - d * 3, ty - 3), (tx - d * 3, ty + 3), (tx + d * 8, ty + 16)])
        c.setFillColor(formColor(lv, 8)); tri(c, [(tx + d * 46, ty), (tx + d * 10, ty - 8), (tx + d * 4, ty)])
        c.setStrokeColor(DragonLayer.white); c.setLineWidth(2); c.setAlpha(0.7)
        for i in 0..<5 {
            let y = z.y + 6 + DragonLayer.hs(Double(i), Double(z.t)) * (z.h - 12), l = 50 + DragonLayer.hs(Double(i), 3) * 90
            c.move(to: CGPoint(x: tip + d * 40, y: y)); c.addLine(to: CGPoint(x: tip + d * 40 + d * l, y: y)); c.strokePath()
        }
        c.setAlpha(1)
    }

    /// 範囲攻撃: front=false は予告(ボスより後ろ)、true は当たっている間(ボスより手前)
    private func drawZones(_ c: CGContext, _ sim: Simulation, front: Bool, C: [CGColor], lv: Int) {
        let W = DragonLayer.Wd, H = DragonLayer.Hd, B = sim.bossPosition
        for z in sim.dragon.zones where z.shape != .beam {
            let on = z.active, k = min(1, Double(z.t) / Double(max(1, z.warn))), blink = (z.t >> 2) % 2 == 1, zt = Double(z.t)
            if z.shape == .ring {
                // 咆哮の衝撃波: 太い輪 + 白い先頭 + うしろに薄い輪。外へ光のとげ
                guard front else { continue }
                let a0 = z.gapA + z.gapW, a1 = z.gapA - z.gapW + 2 * .pi
                let layers: [(Double, Double, CGColor, Double)] = [(0, z.th * 2.4, C[1], 0.14), (-z.th * 1.7, 1, C[1], 0.35), (-z.th * 1.2, 2, C[0], 0.5), (-z.th * 0.7, 2, C[1], 0.6),
                                                                  (0, z.th, C[1], 0.9), (0, z.th * 0.62, C[2], 1), (z.th * 0.2, z.th * 0.22, C[3], 1), (z.th * 0.48, 2, DragonLayer.white, 1)]
                for (dr, w, col, al) in layers where z.r + dr > 1 {
                    c.setStrokeColor(col); c.setLineWidth(w); c.setAlpha(al); arc(c, z.x, z.y, z.r + dr, a0, a1); c.strokePath()
                }
                c.setAlpha(1); c.setFillColor(C[3])
                var a = a0 + 0.04, i = 0
                while a < a1 {
                    let l = 4 + 9 * DragonLayer.hs(Double(i), Double((z.t >> 1) % 7)), rr = z.r + z.th * 0.5
                    tri(c, [(z.x + cos(a - 0.03) * rr, z.y + sin(a - 0.03) * rr), (z.x + cos(a) * (rr + l), z.y + sin(a) * (rr + l)), (z.x + cos(a + 0.03) * rr, z.y + sin(a + 0.03) * rr)])
                    a += 0.11; i += 1
                }
                for g in [a0, a1] { disc(c, z.x + cos(g) * z.r, z.y + sin(g) * z.r, z.th * 0.6, DragonLayer.white) }      // すき間の両端(ここを抜ける)
                continue
            }
            if on != front { continue }
            switch z.shape {
            case .rect:
                if !on {
                    // 予告: 影の帯・斜めの縞・流れる矢印
                    let d = Double(z.fly != 0 ? z.fly : z.sweep != 0 ? z.sweep : 1)
                    c.setFillColor(DragonLayer.black); c.setAlpha(0.25 + 0.3 * k); c.fill(CGRect(x: z.x, y: z.y, width: z.w, height: z.h))
                    c.saveGState(); c.clip(to: CGRect(x: z.x, y: z.y, width: z.w, height: z.h)); c.setFillColor(C[1]); c.setAlpha(0.1 + 0.16 * k)
                    var x = -z.h - 40 + ((zt * 2 * d).truncatingRemainder(dividingBy: 40) + 40).truncatingRemainder(dividingBy: 40)
                    while x < W + 40 { tri(c, [(x, z.y + z.h), (x + 18, z.y + z.h), (x + 18 + z.h, z.y), (x + z.h, z.y)]); x += 40 }
                    c.restoreGState()
                    c.setAlpha(0.6 + 0.4 * k); c.setFillColor(blink ? C[3] : C[2]); c.fill(CGRect(x: z.x, y: z.y, width: z.w, height: 2)); c.fill(CGRect(x: z.x, y: z.y + z.h - 2, width: z.w, height: 2))
                    c.setAlpha(0.5); c.setFillColor(C[1]); c.fill(CGRect(x: z.x, y: z.y + 4, width: z.w, height: 1)); c.fill(CGRect(x: z.x, y: z.y + z.h - 5, width: z.w, height: 1))
                    c.setFillColor(blink ? C[3] : C[2])
                    for i in 0..<7 {
                        let x = ((Double(i) * 60 + zt * 6 * d).truncatingRemainder(dividingBy: W + 60) + W + 60).truncatingRemainder(dividingBy: W + 60) - 30, y = z.y + z.h / 2, s = 1 + 0.5 * k
                        c.setAlpha(0.45 + 0.5 * k)
                        tri(c, [(x - d * 9 * s, y - 12 * s), (x + d * 7 * s, y), (x - d * 9 * s, y + 12 * s), (x - d * 3 * s, y)])
                    }
                    c.setAlpha(1)
                } else if z.sweep != 0 {
                    drawTail(c, z, C: C, lv: lv)
                } else {
                    // 本体が横切る帯: 風を切る光の筋(炎の尾は熱の地図が描く)
                    c.setFillColor(C[1]); c.setAlpha(0.2); c.fill(CGRect(x: z.x, y: z.y, width: z.w, height: z.h)); c.setAlpha(1)
                    let d = Double(z.fly != 0 ? z.fly : 1), bx = B.x
                    for i in 0..<16 {
                        let di = Double(i), y = z.y + 4 + (di * 37 + zt * 3).truncatingRemainder(dividingBy: max(1, z.h - 8)), l = 70 + (di * 53).truncatingRemainder(dividingBy: 150), x = bx - d * (20 + (di * 29).truncatingRemainder(dividingBy: 80))
                        c.setFillColor(i % 3 != 0 ? C[3] : DragonLayer.white); c.setAlpha(0.8)
                        c.fill(CGRect(x: d > 0 ? x - l : x, y: y, width: l, height: Double(1 + i % 2)))
                    }
                    c.setAlpha(1)
                }
            case .circle:
                if !on {
                    // 予告: 回る扇の影・二重の輪・目盛り。大爆発は、縮む輪で着弾までの残り時間が分かる
                    if z.warn > 4 && z.t > z.warn - 70 {
                        disc(c, z.x, z.y, z.r, DragonLayer.black, 0.2 + 0.15 * k); disc(c, z.x, z.y, z.r, C[1], 0.06 + 0.1 * k)
                        c.setFillColor(C[1]); c.setAlpha(0.08 + 0.12 * k)
                        for i in 0..<8 {
                            let a = Double(i) * 2 * .pi / 8 + zt * 0.025
                            c.move(to: CGPoint(x: z.x, y: z.y)); arc(c, z.x, z.y, z.r, a, a + 2 * .pi / 16); c.closePath(); c.fillPath()
                        }
                        c.setAlpha(1); c.setStrokeColor(blink ? DragonLayer.white : C[2]); c.setLineWidth(2); arc(c, z.x, z.y, z.r); c.strokePath()
                        if z.r > 40 {
                            c.setStrokeColor(C[1]); c.setLineWidth(1); arc(c, z.x, z.y, z.r - 5); c.strokePath()
                            c.setFillColor(C[2])
                            for i in 0..<16 {
                                let a = Double(i) * 2 * .pi / 16 - zt * 0.03
                                tri(c, [(z.x + cos(a - 0.03) * (z.r - 5), z.y + sin(a - 0.03) * (z.r - 5)), (z.x + cos(a) * (z.r - 13), z.y + sin(a) * (z.r - 13)), (z.x + cos(a + 0.03) * (z.r - 5), z.y + sin(a + 0.03) * (z.r - 5))])
                            }
                        }
                        if z.style == .boom {
                            c.setStrokeColor(DragonLayer.white); c.setLineWidth(2); arc(c, z.x, z.y, max(2, z.r * (1 - k))); c.strokePath()
                            c.setFillColor(DragonLayer.white); c.fill(CGRect(x: z.x - 8, y: z.y, width: 17, height: 1)); c.fill(CGRect(x: z.x, y: z.y - 8, width: 1, height: 17))
                        }
                        if z.style == .claw {
                            c.setStrokeColor(C[3]); c.setLineWidth(1); c.setAlpha(0.5 + 0.5 * k)
                            let s: Double = z.x > B.x ? 1 : -1
                            for off in [-14.0, 0, 14] { c.move(to: CGPoint(x: z.x + s * z.r * 0.5 + off, y: z.y - z.r * 0.6)); c.addLine(to: CGPoint(x: z.x - s * z.r * 0.5 + off, y: z.y + z.r * 0.6)); c.strokePath() }
                            c.setAlpha(1)
                        }
                    }
                }
            case .safe:
                if on {
                    let u = Double(z.t - z.warn) / Double(max(1, z.dur))
                    if u < 0.3 { c.setFillColor(DragonLayer.white); c.setAlpha(1 - u / 0.3); c.fill(CGRect(x: 0, y: 0, width: W, height: H)); c.setAlpha(1) }
                }
                for s in z.safe {
                    // 安全な輪: 天から光の柱が差し、中は暗いまま。二重の光の輪と回る印。外側の弧が残り時間
                    c.setFillColor(C[2])
                    for (w, al) in [(0.9, 0.07), (0.6, 0.08), (0.3, 0.1), (0.1, 0.2)] { c.setAlpha(min(1, al * (on ? 2 : 0.6 + k))); c.fill(CGRect(x: s.x - s.r * w, y: 0, width: s.r * w * 2, height: s.y)) }
                    c.setAlpha(1)
                    c.saveGState(); c.setBlendMode(.clear); c.fillEllipse(in: CGRect(x: s.x.rounded() - s.r, y: s.y.rounded() - s.r, width: s.r * 2, height: s.r * 2)); c.restoreGState()
                    disc(c, s.x, s.y, s.r, DragonLayer.col("#0d0a18"), 0.8); disc(c, s.x, s.y, s.r, C[2], 0.1 + 0.06 * sin(zt * 0.3))
                    c.setStrokeColor(DragonLayer.white); c.setLineWidth(3); arc(c, s.x, s.y, s.r); c.strokePath()
                    c.setStrokeColor(C[2]); c.setLineWidth(1); arc(c, s.x, s.y, s.r - 5); c.strokePath()
                    if !on { c.setStrokeColor(C[3]); c.setLineWidth(3); arc(c, s.x, s.y, s.r + 7, -.pi / 2, -.pi / 2 + 2 * .pi * (1 - k)); c.strokePath() }
                    c.setFillColor(DragonLayer.white)
                    for i in 0..<6 {
                        let a = Double(i) * 2 * .pi / 6 - zt * 0.05, x = (s.x + cos(a) * (s.r - 12)).rounded(), y = (s.y + sin(a) * (s.r - 12)).rounded()
                        c.fill(CGRect(x: x - 1, y: y - 2, width: 3, height: 5)); c.fill(CGRect(x: x - 2, y: y - 1, width: 5, height: 3))
                    }
                    c.setFillColor(C[2])
                    for i in 0..<4 {
                        let a = Double(i) * 2 * .pi / 4 + zt * 0.04, x = s.x + cos(a) * (s.r + 14), y = s.y + sin(a) * (s.r + 14)
                        tri(c, [(x, y - 5), (x + 3, y), (x, y + 5), (x - 3, y)])
                    }
                }
            default: break
            }
        }
    }

    /// 予告の印
    private func drawMark(_ c: CGContext, _ m: DragonMark, C: [CGColor]) {
        let blink = (m.t >> 2) % 2 == 1, mt = Double(m.t), red = DragonLayer.col("#ff3c3c")
        switch m.kind {
        case .target:      // ねらいの印: 回りながら縮む
            let r = max(10, 34 - mt * 0.6), a = mt * 0.12
            c.setStrokeColor(blink ? red : DragonLayer.white); c.setLineWidth(2)
            for i in 0..<4 { let di = Double(i); arc(c, m.x, m.y, r, a + di * .pi / 2 + 0.25, a + (di + 1) * .pi / 2 - 0.25); c.strokePath() }
            c.setLineWidth(1); c.setStrokeColor(C[2]); arc(c, m.x, m.y, r * 0.45); c.strokePath()
            c.setFillColor(red)
            for i in 0..<4 { let b = Double(i) * .pi / 2; c.fill(CGRect(x: (m.x + cos(b) * (r + 4)).rounded() - 1, y: (m.y + sin(b) * (r + 4)).rounded() - 1, width: 3, height: 3)) }
        case .wind:      // 風向き: 大きな矢印が流れる
            let d = Double(m.dir)
            for j in 0..<4 { for q in 0..<3 {
                let y = 270 + Double(j) * 76 + Double(q % 2) * 6, x = (mt * 7 + Double(q) * 54 + Double(j) * 30).truncatingRemainder(dividingBy: 240) * d + (d > 0 ? 40 : DragonLayer.Wd - 40), s = 1 + Double(q) * 0.25
                c.setFillColor(blink ? DragonLayer.white : DragonLayer.col("#fff6dc")); c.setAlpha(0.35 + 0.2 * Double(q))
                tri(c, [(x - d * 10 * s, y - 13 * s), (x + d * 8 * s, y), (x - d * 10 * s, y + 13 * s), (x - d * 4 * s, y)])
            } }
            c.setAlpha(1)
        case .crack:      // 地割れ: 光るひび
            let n = min(m.pts.count, 2 + m.t / 3)
            guard n >= 2 else { return }
            let pts = m.pts.prefix(n).enumerated().map { j, q in CGPoint(x: q.x + (j == 0 ? 0 : (j % 2 == 1 ? 2 : -2)), y: q.y) }
            c.setLineJoin(.miter)
            c.setAlpha(0.45); c.setStrokeColor(C[1]); c.setLineWidth(7); c.addLines(between: pts); c.strokePath()
            c.setAlpha(1); c.setStrokeColor(blink ? C[3] : C[2]); c.setLineWidth(3); c.addLines(between: pts); c.strokePath()
            c.setStrokeColor(DragonLayer.white); c.setLineWidth(1); c.addLines(between: pts); c.strokePath()
        }
    }

    /// 炎の柱: 予告(太さが分かる点線と、口元にたまる光)と、当たっている間の芯
    private func drawBeams(_ c: CGContext, _ sim: Simulation, C: [CGColor]) {
        for z in sim.dragon.zones where z.shape == .beam {
            let ux = cos(z.a), uy = sin(z.a), x2 = z.x + ux * z.len, y2 = z.y + uy * z.len
            if !z.active {
                let k = Double(z.t) / Double(max(1, z.warn))
                c.setStrokeColor(C[1]); c.setAlpha(0.25 + 0.35 * k); c.setLineWidth(1); c.setLineDash(phase: 0, lengths: [6, 5])
                for sd in [-1.0, 1] {
                    c.move(to: CGPoint(x: z.x - uy * sd * z.w * 0.5 * k, y: z.y + ux * sd * z.w * 0.5 * k)); c.addLine(to: CGPoint(x: x2 - uy * sd * z.w * 0.5 * k, y: y2 + ux * sd * z.w * 0.5 * k)); c.strokePath()
                }
                c.setLineDash(phase: 0, lengths: []); c.setAlpha(1); c.setStrokeColor(C[3])
                for i in 0..<10 {
                    let a = DragonLayer.hs(Double(i), 1) * 2 * .pi, d = (1 - (Double(z.t) * 0.05 + DragonLayer.hs(Double(i), 2)).truncatingRemainder(dividingBy: 1)) * 70
                    c.move(to: CGPoint(x: z.x + cos(a) * d, y: z.y + sin(a) * d)); c.addLine(to: CGPoint(x: z.x + cos(a) * (d + 10), y: z.y + sin(a) * (d + 10))); c.strokePath()
                }
                continue
            }
            // 炎の柱の芯: 白い芯と、流れる光の筋。口元に十字の閃光
            let k = min(1, Double(z.t - z.warn) / 8, Double(z.warn + z.dur - z.t) / 8), len = 760.0, zt = Double(z.t)
            c.setFillColor(C[3]); c.setAlpha(0.85); DragonLayer.beamPoly(c, z, wd: 0.42, amp: 0.14, sp: 1.0, ph: 2)
            c.setAlpha(1); c.setFillColor(DragonLayer.white); DragonLayer.beamPoly(c, z, wd: 0.2, amp: 0.2, sp: 1.3, ph: 4)
            c.setStrokeColor(DragonLayer.white); c.setLineWidth(1); c.setAlpha(0.75)
            for q in 0..<12 {
                let dq = Double(q), off = (dq / 11 - 0.5) * z.w * 0.8 * k, d0 = (zt * 18 + dq * 97).truncatingRemainder(dividingBy: len), l = 34 + Double(q % 3) * 18
                c.move(to: CGPoint(x: z.x + ux * d0 - uy * off, y: z.y + uy * d0 + ux * off)); c.addLine(to: CGPoint(x: z.x + ux * (d0 + l) - uy * off, y: z.y + uy * (d0 + l) + ux * off)); c.strokePath()
            }
            c.setAlpha(1)
            let R0 = z.w * (0.5 + 0.08 * sin(zt * 0.9)) * k
            c.setFillColor(DragonLayer.white)
            for i in 0..<4 {
                let a = Double(i) * .pi / 2 + zt * 0.05, l = R0 * (i % 2 == 1 ? 1.5 : 2.2)
                tri(c, [(z.x + cos(a) * l, z.y + sin(a) * l), (z.x + cos(a + .pi / 2) * 3, z.y + sin(a + .pi / 2) * 3), (z.x - cos(a + .pi / 2) * 3, z.y - sin(a + .pi / 2) * 3)])
            }
            disc(c, z.x, z.y, R0 * 0.55, C[3]); disc(c, z.x, z.y, R0 * 0.36, DragonLayer.white)
            if z.t - z.warn < 14 {
                let u = Double(z.t - z.warn) / 14
                c.setStrokeColor(C[3]); c.setLineWidth(4 * (1 - u) + 1); c.setAlpha(1 - u); arc(c, z.x, z.y, 10 + u * 120); c.strokePath(); c.setAlpha(1)
            }
        }
    }

    // MARK: 弾

    /// 大きさに合わせて、細かいドットで描いた竜王の弾(試射場の dspr)
    private func dspr(_ type: BulletLook.Kind, _ lv: Int, _ r: Double) -> CGImage? {
        let key = "\(type.rawValue):\(lv):\(r)"
        if let s = bulletSprites[key] { return s }
        let C = DragonLayer.FXC[lv].map(DragonLayer.col)
        let mul: Double = type == .flame ? 3.1 : type == .spine ? 2.7 : (type == .sun || type == .rock) ? 1.6 : 2.5
        let S = Int((r * mul).rounded(.up)) * 2 + 4, m = Double(S) / 2
        guard let x = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        x.translateBy(x: 0, y: CGFloat(S)); x.scaleBy(x: 1, y: -1)
        func circ(_ cx: Double, _ cy: Double, _ rr: Double, _ col: CGColor) { x.setFillColor(col); x.fillEllipse(in: CGRect(x: cx - rr, y: cy - rr, width: rr * 2, height: rr * 2)) }
        let pal = BulletArtData.palettes[type.rawValue]
        func P(_ ch: Character) -> CGColor { DragonLayer.col(pal[min(lv, pal.count - 1)][ch] ?? "#ffffff") }
        switch type {
        case .sun:
            circ(m, m, r * 1.34, C[0]); circ(m, m, r * 1.22, C[1]); circ(m, m, r * 1.02, C[2]); circ(m, m, r * 0.78, C[3]); circ(m - r * 0.12, m - r * 0.12, r * 0.46, DragonLayer.white)
        case .flame:
            for (s, col) in [(1.25, C[0]), (1.08, C[1]), (0.78, C[2]), (0.46, C[3])] {
                let rr = r * s, cy = m - r * 0.45
                x.setFillColor(col)
                x.addArc(center: CGPoint(x: m, y: cy), radius: rr, startAngle: .pi, endAngle: 0, clockwise: false)
                x.addQuadCurve(to: CGPoint(x: m, y: cy + rr * 2.5), control: CGPoint(x: m + rr, y: cy + rr * 0.9))
                x.addQuadCurve(to: CGPoint(x: m - rr, y: cy), control: CGPoint(x: m - rr, y: cy + rr * 0.9))
                x.fillPath()
            }
        case .slash, .gust:
            let gust = type == .gust
            let pal3 = gust ? [P("o"), P("L"), P("W")] : [C[1], C[2], DragonLayer.white], R = r * 1.9, cy = m + R * 0.35
            if gust {
                x.setStrokeColor(pal3[1]); x.setLineWidth(1)
                for (o, l) in [(-0.55, 0.9), (0, 1.25), (0.55, 0.9)] { x.move(to: CGPoint(x: m + o * R, y: cy - R * 0.55)); x.addLine(to: CGPoint(x: m + o * R, y: cy - R * 0.55 + R * l)); x.strokePath() }
            }
            circ(m, cy, R, pal3[0]); circ(m, cy, R - 1.5, pal3[1])
            let lw = max(2, r * 0.34)
            x.setStrokeColor(pal3[2]); x.setLineWidth(lw)
            x.addArc(center: CGPoint(x: m, y: cy), radius: R - 1.5 - lw / 2, startAngle: .pi * 1.12, endAngle: .pi * 1.88, clockwise: false); x.strokePath()
            x.setBlendMode(.clear); circ(m, cy + R * (gust ? 0.4 : 0.62), R * 1.16, DragonLayer.black); x.setBlendMode(.normal)
        case .rock:
            let pts = (0..<9).map { i -> (Double, Double) in let a = Double(i) * 2 * .pi / 9, rr = r * (1.0 + 0.36 * DragonLayer.hs(Double(i), r)); return (cos(a) * rr, sin(a) * rr) }
            func poly(_ s: Double, _ ox: Double, _ oy: Double, _ col: CGColor) {
                x.setFillColor(col); x.addLines(between: pts.map { CGPoint(x: m + $0.0 * s + ox, y: m + $0.1 * s + oy) }); x.closePath(); x.fillPath()
            }
            poly(1, 0, 0, P("o")); poly(0.86, 0, 0, P("r")); poly(0.62, -r * 0.2, -r * 0.22, P("R"))
            x.setStrokeColor(P("Y")); x.setLineWidth(1.2)
            x.move(to: CGPoint(x: m - r * 0.7, y: m + r * 0.1)); x.addLine(to: CGPoint(x: m - r * 0.1, y: m + r * 0.3)); x.addLine(to: CGPoint(x: m + r * 0.15, y: m - r * 0.2)); x.addLine(to: CGPoint(x: m + r * 0.7, y: m - r * 0.05))
            x.move(to: CGPoint(x: m - r * 0.1, y: m + r * 0.3)); x.addLine(to: CGPoint(x: m + r * 0.1, y: m + r * 0.8)); x.strokePath()
        case .spine:
            func t3(_ s: Double, _ col: CGColor, _ half: Bool) {
                x.setFillColor(col)
                var p = [CGPoint(x: m, y: m - r * 2.4 * s), CGPoint(x: m + r * 0.62 * s, y: m + r * 0.5 * s), CGPoint(x: m, y: m + r * 1.5 * s)]
                if !half { p.append(CGPoint(x: m - r * 0.62 * s, y: m + r * 0.5 * s)) }
                x.addLines(between: p); x.closePath(); x.fillPath()
            }
            t3(1.12, P("o"), false); t3(0.9, P("Y"), false); t3(0.9, P("y"), true)
            x.setFillColor(P("W")); x.fill(CGRect(x: m.rounded() - 1, y: (m - r * 1.9).rounded(), width: 1, height: (r * 1.6).rounded()))
        default: break
        }
        // ふちをぼかさない(ドット絵にそろえる)
        if let data = x.data?.assumingMemoryBound(to: UInt8.self) {
            for i in 0..<(S * S) {
                let a = data[i * 4 + 3]
                if a >= 110 {
                    if a < 255 { let f = 255.0 / Double(a); for k in 0..<3 { data[i * 4 + k] = UInt8(min(255, Double(data[i * 4 + k]) * f)) }; data[i * 4 + 3] = 255 }
                } else { data[i * 4] = 0; data[i * 4 + 1] = 0; data[i * 4 + 2] = 0; data[i * 4 + 3] = 0 }
            }
        }
        let img = x.makeImage()
        bulletSprites[key] = img
        return img
    }

    /// 1ドット 1 論理px の小さい弾の絵(火の粉・撃ち返す弾)
    private func smallSprite(_ k: BulletLook.Kind, _ lv: Int) -> CGImage? {
        let key = "s\(k.rawValue):\(lv)"
        if let s = bulletSprites[key] { return s }
        let map = BulletArtData.maps[k.rawValue], pals = BulletArtData.palettes[k.rawValue], pal = pals[min(lv, pals.count - 1)]
        let h = map.count, w = map[0].count
        guard let x = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        x.translateBy(x: 0, y: CGFloat(h)); x.scaleBy(x: 1, y: -1)
        for (j, row) in map.enumerated() { for (i, ch) in row.enumerated() {
            guard let hex = pal[ch] else { continue }
            x.setFillColor(DragonLayer.col(hex)); x.fill(CGRect(x: i, y: j, width: 1, height: 1))
        } }
        let img = x.makeImage()
        bulletSprites[key] = img
        return img
    }

    private func drawSprite(_ c: CGContext, _ img: CGImage, _ x: Double, _ y: Double, _ a: Double, _ sc: Double) {
        let w = Double(img.width) * sc, h = Double(img.height) * sc
        c.saveGState(); c.translateBy(x: x.rounded(), y: y.rounded()); if a != 0 { c.rotate(by: a) }
        c.interpolationQuality = .none
        drawImage(c, img, CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
        c.restoreGState()
    }

    private func drawBullets(_ c: CGContext, _ sim: Simulation, C: [CGColor], lv: Int) {
        for b in sim.bullets where b.isDragon && !b.isHiddenBody {
            guard let k = BulletLook.kind(of: b.look) else { continue }
            let t = b.age * 60
            var a = 0.0
            if BulletLook.isOriented(k) && (b.vx != 0 || b.vy != 0) { a = atan2(b.vy, b.vx) + .pi / 2 }
            if k == .rock { a = t * 0.25 }
            switch k {
            case .tornado:
                // 炎の竜巻: 熱の柱に、回る光の筋を重ねる
                let life = b.fuse * 60, g = min(1, t / 20, (life - t) / 20), ti = Int(t)
                for j in 1..<14 {
                    let (cx, cy, w) = DragonLayer.torGeo(b, j)
                    for kk in 0..<2 {
                        let r = DragonLayer.hs(Double(j * 2 + kk), Double(ti >> 3) + b.u2)
                        if r < 0.3 { continue }
                        let ph = (t * (0.36 + 0.1 * Double(kk)) + Double(j) * 1.9 + Double(kk) * 3.1).truncatingRemainder(dividingBy: 2 * .pi), len = 0.5 + 1.8 * DragonLayer.hs(Double(j), Double(kk + (ti >> 4)))
                        c.setLineWidth(r > 0.85 ? 2 : 1); c.setStrokeColor(r > 0.85 ? DragonLayer.white : r > 0.55 ? C[3] : C[2])
                        let p = CGMutablePath()
                        p.addArc(center: .zero, radius: 1, startAngle: ph, endAngle: ph + len, clockwise: false,
                                 transform: CGAffineTransform(translationX: cx, y: cy + (kk == 1 ? 2 : -1)).scaledBy(x: w * g * (0.75 + 0.35 * Double(kk)) + 1, y: max(1.5, w * 0.26)))
                        c.addPath(p); c.strokePath()
                    }
                }
                for i in 0..<9 {      // 巻き上げられる破片と火の粉: らせんを描いて上り、上で外へ散る
                    let di = Double(i), u = ((t * (0.9 + 0.3 * DragonLayer.hs(di, 1)) + di * 31).truncatingRemainder(dividingBy: 100)) / 100, j = u * 13
                    let (cx, cy, w) = DragonLayer.torGeo(b, min(13, Int(j))), ph = t * 0.3 + di * 2.4 + u * 6
                    let x = cx + cos(ph) * (w * g + 4 + u * 10), y = cy + sin(ph) * 3 - j.truncatingRemainder(dividingBy: 1) * 7
                    if sin(ph) < -0.2 && i % 3 != 0 { continue }
                    c.setFillColor(i % 3 == 0 ? DragonLayer.col("#3a2416") : i % 3 == 1 ? C[3] : DragonLayer.white)
                    c.fill(CGRect(x: x.rounded(), y: y.rounded(), width: i % 3 == 0 ? 3 : 2, height: 2))
                }
                c.setStrokeColor(C[2]); c.setLineWidth(1)
                for i in 0..<4 {      // 足元の渦(切れた弧)
                    let di = Double(i), ph = t * (0.18 + di * 0.03) + di * 2.1, len = 0.8 + DragonLayer.hs(di, Double(ti >> 4)) * 1.4
                    let p = CGMutablePath()
                    p.addArc(center: .zero, radius: 1, startAngle: ph, endAngle: ph + len, clockwise: false,
                             transform: CGAffineTransform(translationX: b.x, y: b.y + 38).scaledBy(x: max(0.01, (30 + di * 9) * g), y: 5 + di * 2))
                    c.addPath(p); c.strokePath()
                }
            case .flame where DragonLayer.isPyre(b):
                c.setFillColor(C[3]); c.fillEllipse(in: CGRect(x: b.x.rounded() - b.radius * 0.8, y: b.y.rounded() + 2 - b.radius * 0.36, width: b.radius * 1.6, height: b.radius * 0.72))
            case .sun, .flame, .slash, .gust, .rock, .spine:
                guard let s = dspr(k, lv, b.radius) else { continue }
                if k == .sun {       // 大火球: まわりに回る光のとげ
                    c.setLineWidth(1)
                    for i in 0..<14 {
                        let an = Double(i) * 2 * .pi / 14 + t * 0.07, r0 = b.radius * 1.4, r1 = b.radius * (i % 2 == 1 ? 2.0 : 2.7) + 2 * sin(t * 0.4 + Double(i) * 2)
                        c.setStrokeColor(i % 2 == 1 ? C[2] : C[3])
                        c.move(to: CGPoint(x: b.x + cos(an) * r0, y: b.y + sin(an) * r0)); c.addLine(to: CGPoint(x: b.x + cos(an) * r1, y: b.y + sin(an) * r1)); c.strokePath()
                    }
                }
                drawSprite(c, s, b.x, b.y, a, 1)
            case .ember, .pshot:
                if let s = smallSprite(k, lv) { drawSprite(c, s, b.x, b.y, a, 1.6) }
            default:
                if let s = smallSprite(k, lv) { drawSprite(c, s, b.x, b.y, a, 1) }
            }
        }
    }

    /// 大きい弾のまわりの光
    private func drawHalos(_ c: CGContext, _ sim: Simulation, C: [CGColor]) {
        let lv = min(max(sim.dragonForm, 0), 3)
        c.interpolationQuality = .medium
        for b in sim.bullets where b.isDragon && !b.isHiddenBody {
            guard let k = BulletLook.kind(of: b.look), k != .ember, k != .pshot else { continue }
            let t = Int(b.age * 60)
            let r = b.radius * (k == .sun ? 4.4 : k == .tornado ? 3 : 3.2) + (t % 4 < 2 ? 1 : 0)
            guard let g = glowSpr(k == .gust ? "#fff6dc" : DragonLayer.FXC[lv][1]) else { continue }
            c.setAlpha(k == .gust ? 0.3 : k == .sun ? 0.75 : 0.5)
            drawImage(c, g, CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2))
        }
        c.setAlpha(1)
    }

    // MARK: 爆発・斬撃・火花・鎖

    private func drawFlashes(_ c: CGContext, C: [CGColor]) {
        for f in flashes {
            let u = Double(f.t) / Double(f.life), e = 1 - (1 - u) * (1 - u)
            if f.slash != 0 {        // 爪の斬撃: 3本の刃が走り、白く光って消える
                let k = min(1, Double(f.t) / 4), a = 1 - max(0, (u - 0.45) / 0.55)
                c.setAlpha(a)
                for g in DragonLayer.slashGeo(f) {
                    c.setFillColor(C[1]); DragonLayer.blade(c, g, 9 * a, k); c.setFillColor(C[3]); DragonLayer.blade(c, g, 6 * a, k); c.setFillColor(DragonLayer.white); DragonLayer.blade(c, g, 3 * a, k)
                }
                c.setAlpha(1); continue
            }
            if f.ring {        // 姿が変わる瞬間の輪
                for k0 in [0.0, 0.2, 0.4] {
                    let v = (u - k0) / (1 - k0)
                    if v <= 0 { continue }
                    c.setStrokeColor(k0 > 0 ? C[2] : DragonLayer.white); c.setLineWidth(6 * (1 - v) + 1); c.setAlpha(1 - v)
                    arc(c, f.x, f.y, f.r * (0.1 + 1.2 * (1 - (1 - v) * (1 - v)))); c.strokePath()
                }
                c.setAlpha(1); continue
            }
            // 大爆発: 炎そのものは熱の地図が描く。ここは、白い閃光・衝撃波の輪・光のとげ・横一文字の光・集中線
            if f.t < 5 { disc(c, f.x, f.y, f.r * (0.5 + 0.1 * Double(f.t)), DragonLayer.white, 1 - Double(f.t) * 0.12) }
            for (k0, w, col) in [(0.0, 5.0, DragonLayer.white), (0.15, 3, C[2]), (0.3, 2, C[1])] {
                let v = (u - k0) / (1 - k0)
                if v <= 0 { continue }
                c.setStrokeColor(col); c.setLineWidth(w * (1 - v) + 1); c.setAlpha(1 - v)
                let rr = f.r * (0.5 + 1.25 * (1 - (1 - v) * (1 - v)))
                c.strokeEllipse(in: CGRect(x: f.x - rr, y: f.y - rr * (k0 > 0 ? 1 : 0.94), width: rr * 2, height: rr * 2 * (k0 > 0 ? 1 : 0.94)))
            }
            c.setAlpha(1)
            if u < 0.6 {
                for i in 0..<26 {
                    let a = DragonLayer.hs(Double(i), f.r) * 2 * .pi, r0 = f.r * (0.35 + 0.85 * e), r1 = r0 + f.r * (0.15 + 0.7 * DragonLayer.hs(Double(i), 2)) * (1 - u / 0.6)
                    c.setStrokeColor(i % 3 != 0 ? C[3] : DragonLayer.white); c.setLineWidth(i % 4 != 0 ? 1 : 2)
                    c.move(to: CGPoint(x: f.x + cos(a) * r0, y: f.y + sin(a) * r0)); c.addLine(to: CGPoint(x: f.x + cos(a) * r1, y: f.y + sin(a) * r1)); c.strokePath()
                }
            }
            if u < 0.35 {
                let v = 1 - u / 0.35, l = f.r * 2.6 * v
                c.setFillColor(DragonLayer.white); c.fill(CGRect(x: f.x - l, y: f.y - 1 - v * 2, width: l * 2, height: 2 + v * 4)); c.fill(CGRect(x: f.x - 1, y: f.y - l * 0.5, width: 2, height: l))
            }
            if f.r >= 100 && f.t < 9 {       // 集中線
                c.setFillColor(f.t % 2 == 1 ? DragonLayer.white : C[3]); c.setAlpha(0.8 - Double(f.t) * 0.07)
                for i in 0..<30 {
                    let a = (Double(i) + DragonLayer.hs(Double(i), Double(f.t >> 1))) * 2 * .pi / 30, r0 = f.r * 1.15 + 60 * DragonLayer.hs(Double(i), Double(4 + (f.t >> 1))), w = 0.012 + 0.02 * DragonLayer.hs(Double(i), 5)
                    tri(c, [(f.x + cos(a) * r0, f.y + sin(a) * r0), (f.x + cos(a - w) * 900, f.y + sin(a - w) * 900), (f.x + cos(a + w) * 900, f.y + sin(a + w) * 900)])
                }
                c.setAlpha(1)
            }
        }
    }

    private func drawParticles(_ c: CGContext, C: [CGColor]) {
        for q in fx where q.k != 1 {
            let u = q.t / q.life
            if q.k == 3 {
                c.setStrokeColor(DragonLayer.col("#fff6dc")); c.setAlpha(0.5 * (1 - u)); c.setLineWidth(1)
                c.move(to: CGPoint(x: q.x, y: q.y)); c.addLine(to: CGPoint(x: q.x - q.vx * 2.4, y: q.y - q.vy * 2.4)); c.strokePath(); c.setAlpha(1)
                continue
            }
            let col = q.k == 2 ? ((Int(q.t) >> 2) % 2 == 1 ? C[2] : C[1]) : (u < 0.25 ? DragonLayer.white : u < 0.5 ? C[3] : u < 0.75 ? C[2] : C[1])
            let s = max(1, (q.s * (1 - u * 0.6)).rounded())
            if q.k == 0 && s >= 2 {      // 火花は尾を引く
                c.setStrokeColor(col); c.setLineWidth(max(1, s - 1))
                c.move(to: CGPoint(x: q.x, y: q.y)); c.addLine(to: CGPoint(x: q.x - q.vx * 1.6, y: q.y - q.vy * 1.6)); c.strokePath()
            } else {
                c.setFillColor(col); c.fill(CGRect(x: (q.x - s / 2).rounded(), y: (q.y - s / 2).rounded(), width: s, height: s))
            }
        }
    }

    /// バインド中: 4本の鎖が自機をしばる
    private func drawBind(_ c: CGContext, _ sim: Simulation, C: [CGColor]) {
        let P = sim.player, T = Double(self.T)
        for i in 0..<4 {
            let a = Double.pi / 4 + Double(i) * .pi / 2 + sin(T * 0.05) * 0.1, L = 110.0, ux = cos(a), uy = sin(a)
            var d = 14.0
            while d < L {
                let j = Int(d / 6), x = P.x + ux * d, y = P.y + uy * d
                c.setFillColor(j % 2 == 1 ? C[3] : C[1]); c.setAlpha(1 - d / L * 0.7)
                if j % 2 == 1 { c.fill(CGRect(x: x.rounded() - 2, y: y.rounded() - 1, width: 5, height: 3)) } else { c.fill(CGRect(x: x.rounded() - 1, y: y.rounded() - 2, width: 3, height: 5)) }
                d += 6
            }
        }
        c.setAlpha(1); c.setStrokeColor((sim.dragon.bind >> 2) % 2 == 1 ? DragonLayer.white : C[2]); c.setLineWidth(2); arc(c, P.x, P.y, 14); c.strokePath()
        c.setStrokeColor(C[1]); c.setLineWidth(1); c.setLineDash(phase: T, lengths: [3, 3]); arc(c, P.x, P.y, 19); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
    }

    // MARK: いちばん上

    private func drawOverlay(_ c: CGContext, _ sim: Simulation, C: [CGColor], lv: Int, boss: SKSpriteNode) {
        let W = DragonLayer.Wd, H = DragonLayer.Hd
        // 被弾の瞬間は、画面のふちが赤く光る
        if sim.dragon.inv > 28 {
            let a = min(0.5, Double(sim.dragon.inv - 28) / 24)
            if let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(srgbRed: 1, green: 40 / 255, blue: 40 / 255, alpha: 0), CGColor(srgbRed: 1, green: 40 / 255, blue: 40 / 255, alpha: a)] as CFArray, locations: [0, 1]) {
                c.drawRadialGradient(g, startCenter: CGPoint(x: W / 2, y: H / 2), startRadius: 150, endCenter: CGPoint(x: W / 2, y: H / 2), endRadius: 380, options: [.drawsAfterEndLocation])
            }
        }
        // カットイン: 姿が変わった瞬間だけ(技名のカットインは入れない。Koshin の判断)
        if formCutT >= 0 { drawCutIn(c, Double(formCutT), 64, C: C, boss: boss) }
        if heat > 0 { heat -= 1; c.setFillColor(CGColor(gray: 1, alpha: Double(heat) / 40)); c.fill(CGRect(x: 0, y: 0, width: W, height: H)) }
    }

    private func faceImage(_ form: Int) -> CGImage? { DragonArt.face(form: form) }

    /// カットイン: 画面を横切る帯に、竜の目のアップと姿の名前
    private func drawCutIn(_ c: CGContext, _ t: Double, _ len: Double, C: [CGColor], boss: SKSpriteNode) {
        let W = DragonLayer.Wd, e = min(1, t / 6, (len - t) / 8), h = 88 * e, cyM = 318.0, y0 = cyM - h / 2
        c.saveGState(); c.clip(to: CGRect(x: 0, y: y0, width: W, height: h))
        c.setFillColor(CGColor(srgbRed: 6 / 255, green: 3 / 255, blue: 10 / 255, alpha: 0.86)); c.fill(CGRect(x: 0, y: y0, width: W, height: h))
        c.setFillColor(C[0]); c.setAlpha(0.55); c.fill(CGRect(x: 0, y: y0, width: W, height: h)); c.setAlpha(1)
        for i in 0..<18 {
            let di = Double(i), yy = y0 + DragonLayer.hs(di, 1) * h, l = 40 + DragonLayer.hs(di, 2) * 120
            let x = W - (t * (14 + DragonLayer.hs(di, 3) * 16) + DragonLayer.hs(di, 4) * 500).truncatingRemainder(dividingBy: W + 200)
            c.setFillColor(i % 3 != 0 ? C[1] : C[3]); c.setAlpha(0.5); c.fill(CGRect(x: x, y: floor(yy), width: l, height: 1))
        }
        c.setAlpha(1)
        // 竜の顔のアップ(待機の絵の顔のあたり)
        if let face = faceImage(formCut) {
            c.interpolationQuality = .none
            drawImage(c, face, CGRect(x: W - 186 + (1 - e) * 140 - t * 0.3, y: cyM - 44, width: 176, height: 88))
        }
        c.restoreGState()
        c.setFillColor(DragonLayer.white); c.fill(CGRect(x: 0, y: y0 - 2, width: W, height: 2)); c.fill(CGRect(x: 0, y: y0 + h, width: W, height: 2))
        c.setFillColor(C[2]); c.fill(CGRect(x: 0, y: y0 - 4, width: W, height: 1)); c.fill(CGRect(x: 0, y: y0 + h + 3, width: W, height: 1))
        guard e > 0.6 else { return }
        let small = formPhase > 1 ? String(format: L("dragon.cutin.awaken"), formPhase) : L("dragon.cutin.normal")
        let big = formCut > 0 ? L("dragon.form.\(formCut)") : L("enemy.boss.13")
        let x = 14 - (1 - e) * 80 + t * 0.25
        UIGraphicsPushContext(c)
        let sf = UIFont(name: "AvenirNext-Heavy", size: 13) ?? .boldSystemFont(ofSize: 13)
        (small as NSString).draw(at: CGPoint(x: x, y: cyM - 24 - 9), withAttributes: [.font: sf, .foregroundColor: UIColor(cgColor: C[2])])
        let bf = UIFont(name: "AvenirNext-Heavy", size: 26) ?? .boldSystemFont(ofSize: 26)
        (big as NSString).draw(at: CGPoint(x: x, y: cyM + 8 - 17), withAttributes: [.font: bf, .foregroundColor: UIColor.white, .strokeColor: UIColor.black, .strokeWidth: -6])
        UIGraphicsPopContext()
    }

    /// 画面のゆれ(大きな攻撃の瞬間)と、寄り(大爆発の瞬間)。カメラに入れる
    func cameraOffset() -> (dx: CGFloat, dy: CGFloat, zoom: CGFloat) {
        let sk = shake > 0.6 ? shake : 0
        return (CGFloat(((rand() - 0.5) * sk).rounded()), CGFloat(((rand() - 0.5) * sk).rounded()), CGFloat(1 + punch * 0.04))
    }
}
