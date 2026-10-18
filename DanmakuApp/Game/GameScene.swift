import SpriteKit
import DanmakuCore

/// 描画と入力だけを担当するシーン。計算は DanmakuCore.Simulation に任せ、固定ステップ(1/120秒)で進める
final class GameScene: SKScene {
    private static let W = CGFloat(DanmakuConfig.width)
    private static let H = CGFloat(DanmakuConfig.height)
    /// ドラッグ量に掛ける倍率
    private static let dragScale = 1.2

    private(set) var sim: Simulation
    var onTime: ((Double) -> Void)?
    var onFinish: ((Simulation, [Move]) -> Void)?

    private var moves: [Move] = []
    private var accumulator = 0.0
    private var lastTime: TimeInterval?
    private var pending = CGPoint.zero
    private var touchLast: CGPoint?
    private var finished = false

    private let skin: Skin
    private let bulletTextures: [SKTexture]
    private let shipNode: SKSpriteNode
    private let bossNode = SKSpriteNode(texture: SpriteFactory.boss(flash: false))
    private let bossTexture = SpriteFactory.boss(flash: false)
    private let bossFlashTexture = SpriteFactory.boss(flash: true)
    private var bulletNodes: [SKSpriteNode] = []
    private var shotNodes: [SKSpriteNode] = []
    private var markers: [SKShapeNode] = []
    private var starNodes: [(node: SKSpriteNode, y: Double, v: Double)] = []
    private let barFill = SKSpriteNode(color: Palette.gold, size: CGSize(width: 1, height: 5))
    private let centerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")

    init(stage: Stage, loadout: Loadout = Loadout()) {
        sim = Simulation(stage: stage, shotType: loadout.shot)
        // 弾・背景・自機は別々のテーマを選べる
        var skin = Skin.of(loadout.bullets)
        let bg = Skin.of(loadout.background)
        skin.background = bg.background; skin.star = bg.star
        let ship = Skin.of(loadout.ship)
        skin.shipColor = ship.shipColor; skin.shipShape = ship.shipShape
        self.skin = skin
        bulletTextures = SpriteFactory.bullets(loadout.bullets)
        shipNode = SKSpriteNode(texture: SpriteFactory.ship(loadout.ship))
        #if DEBUG
        sim.invincible = ProcessInfo.processInfo.arguments.contains("-uitest-invincible")
        #endif
        super.init(size: CGSize(width: GameScene.W, height: GameScene.H))
        scaleMode = .aspectFit
        backgroundColor = skin.background
        buildNodes()
    }

    required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not used") }

    private func pos(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: GameScene.H - y) }

    private func buildNodes() {
        let W = GameScene.W, H = GameScene.H
        var rng = Mulberry32(seed: 7)
        for _ in 0..<70 {
            let x = rng.next() * Double(W), y = rng.next() * Double(H)
            let s = rng.next() * 1.4 + 0.3, v = rng.next() * 30 + 10
            let n = SKSpriteNode(color: skin.star, size: CGSize(width: s, height: s))
            n.zPosition = 0
            n.position = pos(x, y)
            addChild(n)
            starNodes.append((n, y, v))
        }
        if !sim.isBoss {
            for m in sim.stage.emitters where m.t != .rain {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: 7)); p.addLine(to: CGPoint(x: 7, y: 0))
                p.addLine(to: CGPoint(x: 0, y: -7)); p.addLine(to: CGPoint(x: -7, y: 0)); p.closeSubpath()
                let n = SKShapeNode(path: p)
                n.strokeColor = skin.bulletColors[m.k]
                n.lineWidth = 1
                n.position = pos(m.x * Double(W), m.y * Double(H))
                n.zPosition = 1
                n.isHidden = true
                addChild(n)
                markers.append(n)
            }
        } else {
            bossNode.zPosition = 2
            addChild(bossNode)
        }
        shipNode.zPosition = 3
        addChild(shipNode)

        let back = SKSpriteNode(color: Palette.barBack, size: CGSize(width: W, height: 5))
        back.anchorPoint = CGPoint(x: 0, y: 1); back.position = CGPoint(x: 0, y: H); back.zPosition = 5
        addChild(back)
        barFill.anchorPoint = CGPoint(x: 0, y: 1); barFill.position = CGPoint(x: 0, y: H); barFill.zPosition = 6
        barFill.color = sim.isBoss ? Palette.pink : Palette.gold
        addChild(barFill)
        if sim.isBoss {
            for f in [CGFloat(1) / 3, CGFloat(2) / 3] {
                let s = SKSpriteNode(color: skin.background, size: CGSize(width: 2, height: 5))
                s.anchorPoint = CGPoint(x: 0.5, y: 1); s.position = CGPoint(x: W * f, y: H); s.zPosition = 7
                addChild(s)
            }
        }
        centerLabel.fontSize = 28
        centerLabel.fontColor = Palette.text
        centerLabel.verticalAlignmentMode = .center
        centerLabel.position = CGPoint(x: W / 2, y: H / 2)
        centerLabel.zPosition = 8
        addChild(centerLabel)
    }

    /// 被弾した場所から復活する（広告を見たあと／広告削除の購入者）
    func revive() {
        sim.revive()
        finished = false
        lastTime = nil
        accumulator = 0
    }

    // MARK: 入力（画面のどこでもドラッグで相対移動）

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let t = touches.first { touchLast = t.location(in: self) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touches.first, let last = touchLast else { return }
        let p = t.location(in: self)
        pending.x += (p.x - last.x) * GameScene.dragScale
        pending.y -= (p.y - last.y) * GameScene.dragScale   // SpriteKit は上が +y
        touchLast = p
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { touchLast = nil }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchLast = nil }

    /// たまったドラッグ量から、このステップの移動量(0.25px単位の整数)を取り出す
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
        if !finished {
            let dt = lastTime.map { min(0.05, currentTime - $0) } ?? 0
            lastTime = currentTime
            accumulator += dt
            while accumulator >= DanmakuConfig.step && sim.outcome == .playing {
                accumulator -= DanmakuConfig.step
                let m = takeMove()
                moves.append(m)
                sim.step(m)
            }
        }
        render(currentTime)
        if !finished && sim.outcome != .playing {
            finished = true
            onFinish?(sim, moves)
        }
    }

    private func render(_ now: TimeInterval) {
        let W = GameScene.W, H = GameScene.H
        for s in starNodes {
            s.node.position = pos(Double(s.node.position.x), (s.y + now * s.v).truncatingRemainder(dividingBy: Double(H)))
        }
        shipNode.position = pos(sim.player.x, sim.player.y)
        shipNode.alpha = sim.isShielded ? (Int(now * 10) % 2 == 0 ? 0.35 : 1) : 1

        // 弾（スプライトを使い回す）
        let bs = sim.bullets
        while bulletNodes.count < bs.count {
            let n = SKSpriteNode(texture: bulletTextures[0])
            n.zPosition = 4
            addChild(n)
            bulletNodes.append(n)
        }
        for i in 0..<bulletNodes.count {
            let n = bulletNodes[i]
            if i < bs.count {
                let b = bs[i]
                n.isHidden = false
                n.position = pos(b.x, b.y)
                n.texture = bulletTextures[b.color]
            } else if !n.isHidden {
                n.isHidden = true
            }
        }

        if sim.isBoss {
            let bp = sim.bossPosition
            bossNode.position = pos(bp.x, bp.y)
            bossNode.texture = sim.flash > 0 ? bossFlashTexture : bossTexture
            let ss = sim.shots
            while shotNodes.count < ss.count {
                let n = SKSpriteNode(color: Palette.gold, size: CGSize(width: 3, height: 10))
                n.name = "shot"
                n.zPosition = 2
                addChild(n)
                shotNodes.append(n)
            }
            for i in 0..<shotNodes.count {
                if i < ss.count {
                    shotNodes[i].isHidden = false
                    shotNodes[i].position = pos(ss[i].x, ss[i].y - 1)
                    shotNodes[i].size = ss[i].damage > 1 ? CGSize(width: 6, height: 14) : CGSize(width: 3, height: 10)
                    shotNodes[i].color = ss[i].damage > 1 ? skin.shipColor : Palette.gold
                }
                else { shotNodes[i].isHidden = true }
            }
            let ratio = max(0, Double(sim.hp)) / Double(sim.stage.bossHp ?? 1)
            barFill.size.width = max(0.001, W * CGFloat(ratio))
        } else {
            // 発射台の印：撃ち始める0.6秒前から点滅し、撃ち終わったら消す
            var idx = 0
            for m in sim.stage.emitters where m.t != .rain {
                let n = markers[idx]; idx += 1
                let lead = m.s - sim.t
                let end = min(m.e, Double(sim.stage.durationSec))
                if sim.t >= end || lead > 0.6 { n.isHidden = true; continue }
                n.isHidden = false
                n.alpha = lead > 0 ? (Int(floor(lead * 10)) % 2 != 0 ? 0.15 : 0.7) : 0.35
            }
            let p = max(0, min(1, sim.t / Double(sim.stage.durationSec)))
            barFill.size.width = max(0.001, W * CGFloat(p))
        }

        if sim.t < 0 {
            centerLabel.text = L("play.ready"); centerLabel.isHidden = false
        } else if sim.isBoss && sim.banner > 0 {
            centerLabel.text = String(format: L("play.phase"), sim.phase)
            centerLabel.fontColor = Palette.gold; centerLabel.isHidden = false
        } else {
            centerLabel.isHidden = true
            centerLabel.fontColor = Palette.text
        }
        onTime?(max(0, Double(sim.stage.durationSec) - max(0, sim.t)))
    }
}
