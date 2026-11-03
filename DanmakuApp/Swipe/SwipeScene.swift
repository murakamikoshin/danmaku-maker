import SpriteKit
import UIKit
import DanmakuCore

/// スワイプ弾幕の描画と入力（仕様書 6 章）。計算は SwipeModel（DanmakuCore）にあり、ここは固定ステップで進めて、起きたことを演出にする。
/// 演出は見た目だけで、当たり判定や記録には関わらない。
final class SwipeScene: SKScene {
    private static let W = CGFloat(DanmakuConfig.width)
    private static let H = CGFloat(DanmakuConfig.height)
    private static let dragScale = 1.2

    private weak var model: SwipeModel?
    private let effectsOn: Bool
    private let reduceMotion = UIAccessibility.isReduceMotionEnabled

    private let world = SKNode()
    private var starNodes: [(node: SKSpriteNode, y: Double, v: Double, z: Double)] = []
    private var bulletNodes: [SKSpriteNode] = []
    private var beamNodes: [(glow: SKShapeNode, core: SKShapeNode)] = []
    private var blastNodes: [SKShapeNode] = []
    private var blastRadii: [CGFloat] = []
    private let shipNode = SKShapeNode()
    private let dotNode = SKShapeNode(circleOfRadius: 2.6)
    private let flameNode = SKShapeNode()
    private let shieldNode = SKShapeNode(circleOfRadius: 16)
    private let grazeRing = SKShapeNode(circleOfRadius: 18)
    private let auraNode = SKShapeNode(circleOfRadius: 20)
    private var orbs: [SKShapeNode] = []
    private let bgNode = SKSpriteNode()
    private let darken = SKSpriteNode(color: .black, size: CGSize(width: 360, height: 540))
    private let flash = SKSpriteNode(color: .white, size: CGSize(width: 360, height: 540))
    private let timeBar = SKSpriteNode(color: SwipePalette.cyan, size: CGSize(width: 1, height: 6))

    private var sparks: [Spark] = []
    private var sparkPool: [SKSpriteNode] = []
    private var labels: [FloatText] = []
    private var coins: [Coin] = []
    private var rings: [(node: SKShapeNode, t: Double, dur: Double, r: CGFloat)] = []
    private var bigTexts: [BigText] = []
    private let bulletTextures: [SKTexture]

    private var accumulator = 0.0
    private var lastTime: TimeInterval?
    private var pending = CGPoint.zero
    private var touchLast: CGPoint?
    private var touchStart: CGPoint?
    private var touching = false

    private var shake = 0.0
    private var flashAlpha = 0.0
    private var glow = 0.0
    private var slowLeft = 0.0
    private var resultTimer = 0.0
    private var lastPhase: SwipeModel.Phase = .title
    private var comboShownAt = 0.0
    private var coinCount = 0
    private var goTicked = false
    private var bestBefore = 0
    private var lastSecondTick = -1
    private var clock = 0.0

    var onAdvance: (() -> Void)?

    struct Spark { var node: SKSpriteNode; var vx: CGFloat; var vy: CGFloat; var life: Double; var max: Double; var gravity: CGFloat }
    struct FloatText { var node: SKLabelNode; var life: Double; var max: Double; var rise: CGFloat }
    struct Coin { var node: SKShapeNode; var vx: CGFloat; var vy: CGFloat; var age: Double }
    struct BigText { var node: SKLabelNode; var life: Double; var max: Double; var base: CGFloat; var x: CGFloat; var y: CGFloat; var shake: CGFloat }

    init(model: SwipeModel, effects: Bool) {
        self.model = model
        effectsOn = effects
        bulletTextures = SwipeScene.makeBulletTextures()
        super.init(size: CGSize(width: SwipeScene.W, height: SwipeScene.H))
        scaleMode = .aspectFit
        backgroundColor = SwipePalette.background
        build()
    }
    required init?(coder aDecoder: NSCoder) { fatalError() }

    private func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: SwipeScene.H - y) }

    // MARK: 部品

    private static func makeBulletTextures() -> [SKTexture] {
        SwipePalette.bullets.map { color in
            let size = CGSize(width: 24, height: 24)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                let c = ctx.cgContext
                c.setFillColor(color.withAlphaComponent(0.28).cgColor)
                c.fillEllipse(in: CGRect(x: 0, y: 0, width: 24, height: 24))
                c.setFillColor(color.cgColor)
                c.fillEllipse(in: CGRect(x: 6, y: 6, width: 12, height: 12))
                c.setFillColor(UIColor.white.cgColor)
                c.fillEllipse(in: CGRect(x: 9, y: 9, width: 6, height: 6))
            }
            return SKTexture(image: img)
        }
    }

    private func build() {
        addChild(world)
        // 背景（縦のグラデーション。色は演出の強さで変わる）
        let gradient = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 64)).image { ctx in
            let cs = CGColorSpaceCreateDeviceRGB()
            let g = CGGradient(colorsSpace: cs, colors: [UIColor.white.cgColor, UIColor(white: 0.25, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: 64), options: [])
        }
        bgNode.texture = SKTexture(image: gradient)
        bgNode.size = CGSize(width: SwipeScene.W, height: SwipeScene.H)
        bgNode.position = CGPoint(x: SwipeScene.W / 2, y: SwipeScene.H / 2)
        bgNode.zPosition = -10
        bgNode.colorBlendFactor = 1
        bgNode.color = UIColor(hue: 265 / 360, saturation: 0.7, brightness: 0.1, alpha: 1)
        world.addChild(bgNode)
        var rng = Mulberry32(seed: 11)
        for _ in 0..<90 {
            let z = rng.next()
            let s = 0.6 + z * 1.6
            let n = SKSpriteNode(color: UIColor(white: 1, alpha: 0.25 + z * 0.6), size: CGSize(width: s, height: s))
            n.zPosition = -5
            let x = rng.next() * 360, y = rng.next() * 540
            n.position = p(x, y)
            world.addChild(n)
            starNodes.append((n, y, 20 + 160 * z, z))
        }
        // 自機
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 11)); path.addLine(to: CGPoint(x: -8, y: -9)); path.addLine(to: CGPoint(x: 0, y: -5)); path.addLine(to: CGPoint(x: 8, y: -9)); path.closeSubpath()
        shipNode.path = path
        shipNode.fillColor = SwipePalette.cyan; shipNode.strokeColor = .clear; shipNode.glowWidth = 3
        shipNode.zPosition = 6
        dotNode.fillColor = .white; dotNode.strokeColor = .clear; dotNode.zPosition = 7
        let fp = CGMutablePath()
        fp.move(to: CGPoint(x: -4, y: -7)); fp.addLine(to: CGPoint(x: 0, y: -16)); fp.addLine(to: CGPoint(x: 4, y: -7)); fp.closeSubpath()
        flameNode.path = fp; flameNode.fillColor = UIColor(hex: 0xFF8A3D); flameNode.strokeColor = .clear; flameNode.zPosition = 5.5
        shieldNode.strokeColor = .white; shieldNode.fillColor = .clear; shieldNode.lineWidth = 1.5; shieldNode.zPosition = 6.5
        grazeRing.strokeColor = SwipePalette.cyan.withAlphaComponent(0.25); grazeRing.fillColor = .clear; grazeRing.lineWidth = 1
        grazeRing.path = CGPath(ellipseIn: CGRect(x: -18, y: -18, width: 36, height: 36), transform: nil).copy(dashingWithPhase: 0, lengths: [3, 4])
        grazeRing.zPosition = 5
        auraNode.fillColor = .clear; auraNode.lineWidth = 3; auraNode.blendMode = .add; auraNode.zPosition = 5; auraNode.alpha = 0
        for n in [shipNode, dotNode, flameNode, shieldNode, grazeRing, auraNode] { world.addChild(n) }
        for _ in 0..<14 {
            let o = SKShapeNode(circleOfRadius: 2.2)
            o.fillColor = .white; o.strokeColor = .clear; o.blendMode = .add; o.zPosition = 5; o.isHidden = true
            world.addChild(o); orbs.append(o)
        }
        timeBar.anchorPoint = CGPoint(x: 0, y: 1); timeBar.position = CGPoint(x: 0, y: SwipeScene.H); timeBar.zPosition = 20
        addChild(timeBar)
        darken.position = CGPoint(x: SwipeScene.W / 2, y: SwipeScene.H / 2); darken.zPosition = 15; darken.alpha = 0
        flash.position = darken.position; flash.zPosition = 16; flash.alpha = 0; flash.blendMode = .add
        addChild(darken); addChild(flash)
    }

    // MARK: 入力

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first else { return }
        touchLast = t.location(in: self); touchStart = touchLast; touching = true
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let last = touchLast else { return }
        let q = t.location(in: self)
        pending.x += (q.x - last.x) * SwipeScene.dragScale
        pending.y -= (q.y - last.y) * SwipeScene.dragScale
        touchLast = q
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { touchLast = nil; touchStart = nil; touching = false }
        guard let model, let s = touchStart, let t = touches.first else { return }
        let q = t.location(in: self)
        let up = q.y - s.y, moved = hypot(q.x - s.x, q.y - s.y)
        // 結果の表示中だけ、上スワイプ（40 以上）かタップ（14 未満）ですぐ次へ
        if (model.phase == .cleared || model.phase == .failed) && (up >= 40 || moved < 14) { advance() }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchLast = nil; touchStart = nil; touching = false }

    private func advance() { resultTimer = 0; onAdvance?() }

    private func takeMove() -> Move {
        func take(_ v: inout CGFloat) -> Int8 {
            let units = max(-127, min(127, Int((Double(v) / Move.unit).rounded(.towardZero))))
            v -= CGFloat(Double(units) * Move.unit)
            return Int8(units)
        }
        return Move(dx: take(&pending.x), dy: take(&pending.y))
    }

    // MARK: ループ

    override func update(_ currentTime: TimeInterval) {
        guard let model else { return }
        let dt = lastTime.map { min(0.05, currentTime - $0) } ?? 0
        lastTime = currentTime
        clock = currentTime
        let phase = model.phase
        if phase != lastPhase { phaseChanged(from: lastPhase, to: phase, model: model); lastPhase = phase }

        accumulator += dt
        while accumulator >= DanmakuConfig.step {
            accumulator -= DanmakuConfig.step
            if model.phase == .go { model.stepGo(takeMove()) }
            else if model.phase == .playing {
                if let ev = model.stepPlay(takeMove()) { handle(ev, model: model) }
            } else { pending = .zero; break }
        }
        let fxDt = slowLeft > 0 ? dt * 0.16 : dt
        if slowLeft > 0 { slowLeft -= dt }
        stepEffects(fxDt, model: model)
        render(model: model)

        // 結果のあとは自動で次へ（指が触れている間は進まない）
        if model.phase == .cleared || model.phase == .failed {
            if !touching { resultTimer -= dt }
            if resultTimer <= 0 { advance(); resultTimer = 99 }
        }
    }

    private func phaseChanged(from: SwipeModel.Phase, to: SwipeModel.Phase, model: SwipeModel) {
        switch to {
        case .transition, .starting:
            clearEffects()
        case .go:
            goTicked = false; bestBefore = model.bestStreak
            pending = .zero; accumulator = 0; lastSecondTick = -1; shake = 0
            SwipeAudio.shared.whoosh()
            bigText("GO!", size: 70, color: SwipePalette.cyan, life: 0.55, x: 180, y: 270)
            SwipeAudio.shared.go()
        case .cleared: resultTimer = model.scoring.streak > bestBefore ? 1.6 : 1.05
        case .failed: resultTimer = 1.45
        default: break
        }
    }

    // MARK: できごと

    private var heat: Double { min(1, Double(model?.scoring.combo ?? 0) / 60) }

    private func handle(_ ev: SwipeClipPlayer.Events, model: SwipeModel) {
        let sc = model.scoring
        let lang = model.language
        var made = 0
        for (b, g) in ev.grazes {
            glow = 1; comboShownAt = clock
            SwipeAudio.shared.graze(combo: g.combo, now: clock)
            if g.combo % 5 == 0 { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            guard effectsOn, made < 40 else { continue }
            made += 1
            burst(at: p(b.x, b.y), count: 4 + min(8, g.level), colors: [.white, SwipePalette.bullet(b.color), SwipePalette.gold], speed: CGFloat(140 + g.level * 20)...CGFloat(200 + g.level * 20), life: 0.3)
            floatText("+" + ScoreFormat.short(g.points, lang), at: p(b.x, b.y), size: CGFloat(10 + min(7, g.level)), color: g.level >= 4 ? SwipePalette.gold : .white)
            if g.doubled {
                let lv = g.level
                let col = lv >= 6 ? SwipePalette.pink : lv >= 4 ? SwipePalette.gold : SwipePalette.cyan
                bigText("×" + ScoreFormat.short(sc.multiplier, lang), size: CGFloat(54 + lv * 3), color: col, life: 0.7, x: 180, y: 540 - 194, shake: 5)
                SwipeAudio.shared.multiplier(level: lv)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                shake = max(shake, 5)
            }
        }
        if let bomb = ev.bomb {
            let me = p(model.player?.sim.player.x ?? 180, model.player?.sim.player.y ?? 459)
            ring(at: me, maxRadius: 440, color: SwipePalette.gold, dur: 0.6)
            spawnCoins(bomb.bullets, center: me)
            bigText("BOMB!!", size: 66, color: SwipePalette.gold, life: 0.9, x: 180, y: 270)
            flashAlpha = reduceMotion ? 0.34 : 0.85; shake = reduceMotion ? 3 : 14
            floatText("+" + ScoreFormat.short(bomb.coins.total, lang), at: CGPoint(x: me.x, y: me.y + 40), size: 22, color: SwipePalette.gold)
            SwipeAudio.shared.bomb()
            hapticPattern()
        }
        if let c = ev.clear {
            let me = p(model.player?.sim.player.x ?? 180, model.player?.sim.player.y ?? 459)
            ring(at: me, maxRadius: 440, color: SwipePalette.gold, dur: 0.7)
            spawnCoins(c.bullets, center: me)
            bigText("CLEAR!", size: 72, color: SwipePalette.gold, life: 1.1, x: 180, y: 270, shake: 3)
            floatText("+" + ScoreFormat.short(c.result.bonus, lang), at: CGPoint(x: 180, y: 300), size: 26, color: .white)
            if c.result.streak >= 2 {
                floatText("×3^\(c.result.streak)", at: CGPoint(x: 180, y: 330), size: 22, color: SwipePalette.cyan)
            }
            if [5, 10, 15, 20, 30, 50].contains(c.result.streak) {
                bigText(String(format: L("swipe.streak.n"), c.result.streak), size: 40, color: SwipePalette.pink, life: 1.0, x: 180, y: 540 - 330)
            }
            if c.result.streak > bestBefore && bestBefore > 0 {
                bigText("NEW RECORD", size: 34, color: SwipePalette.gold, life: 1.4, x: 180, y: 540 - 380)
                SwipeAudio.shared.record()
            }
            confetti()
            flashAlpha = reduceMotion ? 0.18 : 0.45; shake = reduceMotion ? 2 : 8
            SwipeAudio.shared.clear()
            for i in 0..<3 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 * Double(i)) { UIImpactFeedbackGenerator(style: .medium).impactOccurred() } }
        }
        if let hit = ev.hitAt {
            let q = p(hit.x, hit.y)
            burst(at: q, count: 60, colors: [.white, SwipePalette.cyan, SwipePalette.pink], speed: 60...320, life: 0.8)
            ring(at: q, maxRadius: 90, color: UIColor.red, dur: 0.5)
            flashAlpha = reduceMotion ? 0.28 : 0.7; shake = reduceMotion ? 4 : 16
            slowLeft = 0.5
            let left = Double(SwipeClip.playSteps - (model.player?.step ?? 0)) / 120
            bigText(String(format: L("swipe.left.sec"), left), size: 44, color: SwipePalette.pink, life: 1.2, x: 180, y: 540 - 200)
            if sc.streak == 0, model.clipsPlayed >= 2 { bigText(String(format: L("swipe.ended.n"), model.clipsPlayed), size: 22, color: .white, life: 1.2, x: 180, y: 540 - 250) }
            SwipeAudio.shared.fail()
            for i in 0..<3 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 * Double(i)) { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() } }
        }
        // 残り 3 秒
        let leftSec = Double(SwipeClip.playSteps - (model.player?.step ?? 0)) / 120
        if leftSec <= 3, ev.end == nil {
            let s = Int(leftSec.rounded(.up))
            if s != lastSecondTick && s > 0 && s <= 3 { lastSecondTick = s; SwipeAudio.shared.tick(high: s == 1) }
        }
    }

    private func hapticPattern() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    }

    // MARK: 演出の部品

    private func burst(at pt: CGPoint, count: Int, colors: [UIColor], speed: ClosedRange<CGFloat>, life: Double) {
        guard effectsOn else { return }
        for _ in 0..<count where sparks.count < 400 {
            let n = sparkPool.popLast() ?? SKSpriteNode(color: .white, size: CGSize(width: 3, height: 3))
            n.color = colors.randomElement()!; n.position = pt; n.alpha = 1; n.isHidden = false; n.blendMode = .add; n.zPosition = 10
            if n.parent == nil { world.addChild(n) }
            let a = CGFloat.random(in: 0..<(2 * .pi)), v = CGFloat.random(in: speed)
            sparks.append(Spark(node: n, vx: cos(a) * v, vy: sin(a) * v, life: life, max: life, gravity: 0))
        }
    }

    private func confetti() {
        guard effectsOn else { return }
        for _ in 0..<(reduceMotion ? 40 : 150) where sparks.count < 500 {
            let n = sparkPool.popLast() ?? SKSpriteNode(color: .white, size: CGSize(width: 5, height: 3))
            n.color = SwipePalette.bullets.randomElement()!; n.size = CGSize(width: 5, height: 3); n.position = CGPoint(x: .random(in: 0...360), y: 560); n.alpha = 1; n.isHidden = false; n.blendMode = .alpha; n.zPosition = 11
            if n.parent == nil { world.addChild(n) }
            sparks.append(Spark(node: n, vx: .random(in: -60...60), vy: .random(in: -260 ... -80), life: 1.4, max: 1.4, gravity: -60))
        }
    }

    private func floatText(_ s: String, at pt: CGPoint, size: CGFloat, color: UIColor) {
        guard labels.count < 60 else { return }
        let n = SKLabelNode(attributedText: outlined(s, size: size, color: color))
        n.position = pt; n.zPosition = 12
        world.addChild(n)
        labels.append(FloatText(node: n, life: 0.6, max: 0.6, rise: 18))
    }

    private func bigText(_ s: String, size: CGFloat, color: UIColor, life: Double, x: CGFloat, y: CGFloat, shake: CGFloat = 0) {
        let n = SKLabelNode(attributedText: outlined(s, size: size, color: color))
        n.position = CGPoint(x: x, y: y); n.zPosition = 14
        n.verticalAlignmentMode = .center
        addChild(n)
        bigTexts.append(BigText(node: n, life: life, max: life, base: 1, x: x, y: y, shake: reduceMotion ? shake * 0.25 : shake))
    }

    private func outlined(_ s: String, size: CGFloat, color: UIColor) -> NSAttributedString {
        let font = SwipePalette.display(size)
        let para = NSMutableParagraphStyle(); para.alignment = .center
        return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .strokeColor: SwipePalette.outline, .strokeWidth: -20, .paragraphStyle: para])
    }

    private func ring(at pt: CGPoint, maxRadius: CGFloat, color: UIColor, dur: Double) {
        guard effectsOn else { return }
        let n = SKShapeNode(circleOfRadius: 10)
        n.strokeColor = color; n.fillColor = .clear; n.lineWidth = 4; n.position = pt; n.zPosition = 9; n.blendMode = .add
        world.addChild(n)
        rings.append((n, 0, dur, maxRadius))
    }

    private func spawnCoins(_ bullets: [Bullet], center: CGPoint) {
        for b in bullets where !b.isBeam && !b.isBlast && coins.count < 600 {
            let n = SKShapeNode(circleOfRadius: 3.5)
            n.fillColor = SwipePalette.gold; n.strokeColor = .white; n.lineWidth = 0.8; n.glowWidth = 2; n.position = p(b.x, b.y); n.zPosition = 9
            world.addChild(n)
            let a = CGFloat.random(in: 0..<(2 * .pi))
            coins.append(Coin(node: n, vx: cos(a) * 90, vy: sin(a) * 90, age: 0))
        }
    }

    private func clearEffects() {
        for s in sparks { s.node.removeFromParent() }
        sparks.removeAll()
        for l in labels { l.node.removeFromParent() }; labels.removeAll()
        for b in bigTexts { b.node.removeFromParent() }; bigTexts.removeAll()
        for c in coins { c.node.removeFromParent() }; coins.removeAll()
        for r in rings { r.node.removeFromParent() }; rings.removeAll()
        flashAlpha = 0; shake = 0; slowLeft = 0; coinCount = 0
    }

    // MARK: 毎フレーム

    private func stepEffects(_ dt: Double, model: SwipeModel) {
        let me = p(model.player?.sim.player.x ?? 180, model.player?.sim.player.y ?? 459)
        var i = 0
        while i < sparks.count {
            sparks[i].life -= dt
            if sparks[i].life <= 0 { sparks[i].node.isHidden = true; sparkPool.append(sparks[i].node); sparks.remove(at: i); continue }
            sparks[i].node.position.x += sparks[i].vx * CGFloat(dt)
            sparks[i].node.position.y += sparks[i].vy * CGFloat(dt)
            sparks[i].vy += sparks[i].gravity * CGFloat(dt)
            sparks[i].node.alpha = CGFloat(sparks[i].life / sparks[i].max)
            i += 1
        }
        i = 0
        while i < labels.count {
            labels[i].life -= dt
            if labels[i].life <= 0 { labels[i].node.removeFromParent(); labels.remove(at: i); continue }
            let f = 1 - labels[i].life / labels[i].max
            labels[i].node.alpha = CGFloat(1 - f * f)
            labels[i].node.position.y += labels[i].rise * CGFloat(dt / labels[i].max)
            i += 1
        }
        i = 0
        while i < bigTexts.count {
            bigTexts[i].life -= dt
            if bigTexts[i].life <= 0 { bigTexts[i].node.removeFromParent(); bigTexts.remove(at: i); continue }
            let age = bigTexts[i].max - bigTexts[i].life
            let scale: CGFloat = age < 0.1 ? 0.3 + CGFloat(age / 0.1) * 1.1 : age < 0.25 ? 1.4 - CGFloat((age - 0.1) / 0.15) * 0.4 : 1
            bigTexts[i].node.setScale(scale)
            let fade = bigTexts[i].life / bigTexts[i].max
            bigTexts[i].node.alpha = fade < 0.25 ? CGFloat(fade / 0.25) : 1
            let s = age < 0.3 ? bigTexts[i].shake : 0
            bigTexts[i].node.position = CGPoint(x: bigTexts[i].x + CGFloat.random(in: -s...s), y: bigTexts[i].y + CGFloat.random(in: -s...s))
            i += 1
        }
        i = 0
        while i < rings.count {
            rings[i].t += dt
            let f = rings[i].t / rings[i].dur
            if f >= 1 { rings[i].node.removeFromParent(); rings.remove(at: i); continue }
            rings[i].node.setScale(rings[i].r / 10 * CGFloat(f))
            rings[i].node.alpha = CGFloat(1 - f)
            rings[i].node.lineWidth = 4 / max(0.1, rings[i].node.xScale)
            i += 1
        }
        i = 0
        while i < coins.count {
            coins[i].age += dt
            if coins[i].age < 0.15 {
                coins[i].node.position.x += coins[i].vx * CGFloat(dt); coins[i].node.position.y += coins[i].vy * CGFloat(dt)
            } else {
                let dx = me.x - coins[i].node.position.x, dy = me.y - coins[i].node.position.y
                let d = max(1, hypot(dx, dy))
                coins[i].vx = coins[i].vx * 0.9 + dx / d * 3200 * CGFloat(dt)
                coins[i].vy = coins[i].vy * 0.9 + dy / d * 3200 * CGFloat(dt)
                coins[i].node.position.x += coins[i].vx * CGFloat(dt); coins[i].node.position.y += coins[i].vy * CGFloat(dt)
                if d < 12 {
                    coins[i].node.removeFromParent(); coins.remove(at: i)
                    coinCount += 1
                    SwipeAudio.shared.coin(n: coinCount, now: clock)
                    continue
                }
            }
            i += 1
        }
        shake = max(0, shake - dt * 30 * 0.5 - shake * dt * 5)
        flashAlpha = max(0, flashAlpha - dt * 2.2)
        glow = max(0, glow - dt * 4)
    }

    private func render(model: SwipeModel) {
        let sc = model.scoring
        let lv = sc.level
        // 揺れ
        world.position = shake > 0.1 ? CGPoint(x: .random(in: -shake...shake), y: .random(in: -shake...shake)) : .zero
        flash.alpha = CGFloat(flashAlpha) * (model.phase == .failed ? 1 : 1)
        flash.color = model.phase == .failed ? .red : (flashAlpha > 0 ? SwipePalette.gold : .white)
        darken.alpha = model.phase == .go ? 0.25 : 0
        // 背景: 色相は強さで変わる
        bgNode.color = UIColor(hue: CGFloat(265 - (lv - 1) * 9).truncatingRemainder(dividingBy: 360) / 360, saturation: 0.7, brightness: CGFloat(0.07 + 0.01 * Double(lv)), alpha: 1)
        let speed = 1 + Double(sc.combo) / 18
        for s in starNodes {
            let y = (s.y + clock * s.v * speed).truncatingRemainder(dividingBy: 540)
            s.node.position = p(Double(s.node.position.x), y)
        }

        guard let sim = model.player?.sim, model.phase != .transition, model.phase != .starting, model.phase != .title else {
            for n in bulletNodes { n.isHidden = true }
            for n in [shipNode, dotNode, flameNode, shieldNode, grazeRing, auraNode] { n.isHidden = true }
            for o in orbs { o.isHidden = true }
            for b in beamNodes { b.glow.isHidden = true }
            for b in blastNodes { b.isHidden = true }
            return
        }
        let dead = model.phase == .failed
        let me = p(sim.player.x, sim.player.y)
        for n in [shipNode, dotNode, flameNode] { n.isHidden = dead; n.position = me }
        flameNode.xScale = 0.8 + 0.4 * CGFloat(abs(sin(clock * 30)))
        shieldNode.isHidden = dead || !sim.isShielded
        shieldNode.position = me
        shieldNode.alpha = Int(clock * 12) % 2 == 0 ? 1 : 0.3
        grazeRing.isHidden = dead; grazeRing.position = me
        grazeRing.strokeColor = sc.combo > 0 ? SwipePalette.gold.withAlphaComponent(Int(clock * 8) % 2 == 0 ? 0.7 : 0.35) : SwipePalette.cyan.withAlphaComponent(0.25)
        // 自機の光
        let h = min(1, Double(sc.combo) / 60)
        auraNode.isHidden = dead || sc.combo == 0
        if !auraNode.isHidden {
            let hue: Double
            if sc.combo < 30 { hue = 190 + (45 - 190) * Double(sc.combo) / 30 }
            else if sc.combo < 48 { hue = 45 + (330 - 45) * Double(sc.combo - 30) / 18 }
            else { hue = (clock * 300).truncatingRemainder(dividingBy: 360) }
            let col = UIColor(hue: CGFloat(hue.truncatingRemainder(dividingBy: 360) / 360), saturation: 0.9, brightness: 1, alpha: 1)
            let r = 20 + h * 46 + glow * 12
            auraNode.position = me; auraNode.strokeColor = col; auraNode.alpha = CGFloat(0.35 + 0.4 * h)
            auraNode.setScale(CGFloat(r / 20))
            let count = min(14, sc.combo / 6)
            for (k, o) in orbs.enumerated() {
                o.isHidden = k >= count
                if k < count {
                    let a = clock * 3 + Double(k) * (2 * .pi / Double(max(1, count)))
                    let rr = 15 + h * 12
                    o.position = CGPoint(x: me.x + CGFloat(cos(a) * rr), y: me.y + CGFloat(sin(a) * rr)); o.fillColor = col
                }
            }
        } else { for o in orbs { o.isHidden = true } }

        // 弾
        let bs = sim.bullets
        while bulletNodes.count < bs.count {
            let n = SKSpriteNode(texture: bulletTextures[0], size: CGSize(width: 24, height: 24))
            n.zPosition = 4; world.addChild(n); bulletNodes.append(n)
        }
        var beamN = 0, blastN = 0
        for i in 0..<bulletNodes.count {
            let n = bulletNodes[i]
            guard i < bs.count else { n.isHidden = true; continue }
            let b = bs[i]
            if b.isBeam { n.isHidden = true; drawBeam(b, slot: beamN); beamN += 1; continue }
            if b.isBlast { n.isHidden = true; drawBlast(b, slot: blastN); blastN += 1; continue }
            n.isHidden = false
            n.position = p(b.x, b.y)
            n.texture = bulletTextures[((b.color % 6) + 6) % 6]
            let base: CGFloat = b.isGiant ? CGFloat(DanmakuConfig.giantDrawRadius * 2) : b.radius > 0 ? CGFloat(max(12, (b.radius + 4) * 2)) : 12
            n.size = CGSize(width: base * 2, height: base * 2)   // 本体の直径 base、光はその 2 倍
        }
        for k in beamN..<beamNodes.count { beamNodes[k].glow.isHidden = true }
        for k in blastN..<blastNodes.count { blastNodes[k].isHidden = true }

        // 時間の棒
        let left = Double(SwipeClip.playSteps - model.playStep) / Double(SwipeClip.playSteps)
        let urgent = left * 10 <= 3 && model.phase == .playing
        timeBar.size.width = max(0.001, 360 * CGFloat(left))
        timeBar.color = model.phase == .cleared ? SwipePalette.gold : urgent && Int(clock * 8) % 2 == 0 ? SwipePalette.pink : urgent ? .white : SwipePalette.cyan
    }

    private func drawBlast(_ b: Bullet, slot: Int) {
        while blastNodes.count <= slot {
            let n = SKShapeNode(); n.zPosition = 3.4; world.addChild(n); blastNodes.append(n); blastRadii.append(-1)
        }
        let n = blastNodes[slot]
        let r = CGFloat(b.radius)
        if blastRadii[slot] != r { n.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil); blastRadii[slot] = r }
        n.position = p(b.x, b.y); n.isHidden = false
        if b.blastActive {
            let f = CGFloat(min(1, (b.age - b.fuse) / DanmakuConfig.blastActive))
            n.fillColor = UIColor.orange.withAlphaComponent(0.75 * (1 - f) + 0.2); n.strokeColor = UIColor.white.withAlphaComponent(0.9 * (1 - f)); n.lineWidth = 3
        } else {
            let q = CGFloat(b.fuse > 0 ? min(1, b.age / b.fuse) : 1)
            n.fillColor = UIColor.red.withAlphaComponent(0.08 + 0.15 * q); n.strokeColor = UIColor.red.withAlphaComponent(0.5 + 0.4 * q); n.lineWidth = 2
        }
    }

    private func drawBeam(_ b: Bullet, slot: Int) {
        while beamNodes.count <= slot {
            let glow = SKShapeNode(), core = SKShapeNode()
            glow.zPosition = 3.5; glow.lineCap = .round
            core.lineCap = .round; core.strokeColor = .white
            glow.addChild(core); world.addChild(glow); beamNodes.append((glow, core))
        }
        let (glow, core) = beamNodes[slot]
        let path = CGMutablePath()
        path.move(to: p(b.x, b.y)); path.addLine(to: p(b.x + b.vx * BeamLook.length, b.y + b.vy * BeamLook.length))
        glow.path = path; core.path = path; glow.isHidden = false
        let look = BeamLook(b)
        glow.strokeColor = SwipePalette.bullet(b.color).withAlphaComponent(look.alpha)
        glow.lineWidth = look.width; glow.glowWidth = look.firing ? 4 : 0
        core.isHidden = !look.firing; core.lineWidth = look.coreWidth; core.alpha = look.alpha
    }
}
