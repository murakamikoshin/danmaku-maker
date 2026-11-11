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
    /// ライフ(HP)の残り・最大・ボスに与えたダメージ。変わったときだけ呼ぶ
    var onStatus: ((Int, Int, Int) -> Void)?
    private var lastStatus = (-1, -1, -1)
    var onFinish: ((Simulation, [Move]) -> Void)?

    private var moves: [Move] = []
    private var accumulator = 0.0
    private var lastTime: TimeInterval?
    private var pending = CGPoint.zero
    private var touchLast: CGPoint?
    private var finished = false

    private let skin: Skin
    private let bulletTextures: [SKTexture]
    /// ブーメランの弾の絵(🪃の形。弾の色ごと)
    private let boomerangTextures: [SKTexture]
    private let shipNode: SKSpriteNode
    private let shipSkinFrames: [SKTexture]
    private let bossNode: SKSpriteNode
    /// ボスの動きの演出(見た目だけ): 前のフレームの位置と、残像を出す間引き用の数
    private var lastBossPoint: CGPoint?
    private var ghostTick = 0
    private var bossTexture: SKTexture
    private var bossFlashTexture: SKTexture
    private var customBossTextures: (SKTexture, SKTexture)?
    /// 専用の絵を持つボス(堕天使など)の待機アニメ。通常の姿と、覚醒した姿
    private var characterNormal: BossSprites.Art?
    private var characterAwakened: BossSprites.Art?
    /// 覚醒の演出: 覚醒した瞬間のステージ時刻(演出中だけ入っている)と、演出を出したか・衝撃波を出したか
    private var awakenStartT: Double?
    private var awakenShown = false
    private var awakenRingShown = false
    private let awakenOverlay = SKSpriteNode(color: .white, size: CGSize(width: 360, height: 540))
    /// 覚醒の演出の長さ(秒)と、姿が変わる時刻。ボスの段階が変わる間(Simulation の banner 1.2秒)に収める
    private static let awakenLength = 1.2
    private static let awakenSwap = 0.45
    private var mookNodes: [SKSpriteNode] = []
    /// 雑魚の絵が、どの発射台のものか(倒された雑魚を消すため)
    private var mookEmitterIndex: [Int] = []
    /// 倒されて、もう消した雑魚(発射台の番号)
    private var mookGone: Set<Int> = []
    private var bulletNodes: [SKSpriteNode] = []
    /// 深海の魔女「深淵」の暗転(提灯と自機のまわりだけ見える)。見た目だけで、計算には関わらない
    private let darkNode = SKShapeNode()
    /// ぷにまるの瞬間移動の行き先に出す予告の印(見た目だけ)
    private var warpMarks: [SKShapeNode] = []
    /// チャージビームの光線(外側の光と、白い芯)。使い回す
    private var beamNodes: [(glow: SKShapeNode, core: SKShapeNode)] = []
    /// 爆風(隕石・地雷の爆発)の円。使い回す
    private var blastNodes: [SKShapeNode] = []
    private var blastRadii: [CGFloat] = []
    private var shotNodes: [SKSpriteNode] = []
    private var markers: [SKShapeNode] = []
    private var starNodes: [(node: SKSpriteNode, y: Double, v: Double)] = []
    private let barFill = SKSpriteNode(color: Palette.gold, size: CGSize(width: 1, height: 5))
    private let centerLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")
    private var barSeparators: [SKSpriteNode] = []
    /// 演出(警告・撃破)を出すか。遊ぶ人の設定でオフにできる
    private let effectsOn: Bool
    /// 広告でもらった報酬の演出(自分の端末だけの見た目。計算には関わらない)
    private let fx: RewardFX
    private var fxFrame = 0
    private var fxLastHP = 0
    private var fxLastLife = 0
    private var auraNode: SKNode?
    private var shownWave = -1
    private var shownDefeats = 0
    /// 最後のボスを倒したとき、爆発を見せてから結果を出すための待ち(秒)
    private var finishDelay = 0.0
    private var warningLeft = 0.0
    private let warningOverlay = SKSpriteNode(color: UIColor(red: 1, green: 0.1, blue: 0.2, alpha: 1), size: CGSize(width: 360, height: 540))
    private let waveLabel = SKLabelNode(fontNamed: "AvenirNext-Heavy")

    init(stage: Stage, loadout: Loadout = Loadout(), effects: Bool = true, rewardFX: RewardFX = .none) {
        effectsOn = effects
        fx = rewardFX
        sim = Simulation(stage: stage, shotType: loadout.shot)
        // 弾・背景・自機は別々のテーマを選べる
        var skin = Skin.of(loadout.bullets)
        let bg = Skin.of(loadout.background)
        skin.background = bg.background; skin.star = bg.star
        let ship = Skin.of(loadout.ship)
        skin.shipColor = ship.shipColor; skin.shipShape = ship.shipShape
        self.skin = skin
        // 自分の画像(購入者のみ)。画像がなければ標準の絵に戻る
        if loadout.customBullet, let t = SpriteFactory.custom(.bullet) {
            bulletTextures = Array(repeating: t, count: Skin.of(.classic).bulletColors.count)
        } else {
            bulletTextures = SpriteFactory.bullets(loadout.bullets)
        }
        boomerangTextures = SpriteFactory.boomerangs(loadout.bullets)
        // ドット絵の自機(招待のごほうび)。自分の画像を使うときは、そちらを優先する
        let skinFrames = (loadout.customShip && SpriteFactory.custom(.ship) != nil) ? [] : (loadout.shipSkin.map(ShipSkin.textures) ?? [])
        shipSkinFrames = skinFrames
        shipNode = SKSpriteNode(texture: skinFrames.first ?? (loadout.customShip ? SpriteFactory.custom(.ship) : nil) ?? SpriteFactory.ship(loadout.ship))
        if loadout.customBoss, let t = SpriteFactory.custom(.boss), let f = SpriteFactory.custom(.boss, flash: true) {
            bossTexture = t; bossFlashTexture = f
            customBossTextures = (t, f)
        } else {
            bossTexture = SpriteFactory.boss(flash: false); bossFlashTexture = SpriteFactory.boss(flash: true)
        }
        bossNode = SKSpriteNode(texture: bossTexture)
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

    /// 爆風: 予告の間は赤い円(だんだん濃く)、当たる間は明るいオレンジの円
    private func drawBlast(_ b: Bullet, slot: Int) {
        while blastNodes.count <= slot {
            let n = SKShapeNode()
            n.zPosition = 3.4
            addChild(n)
            blastNodes.append(n)
            blastRadii.append(-1)
        }
        let n = blastNodes[slot]
        let r = CGFloat(b.radius)
        if blastRadii[slot] != r {
            n.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2), transform: nil)
            blastRadii[slot] = r
        }
        n.position = pos(b.x, b.y)
        n.isHidden = false
        if b.blastActive {
            let f = CGFloat(min(1, (b.age - b.fuse) / DanmakuConfig.blastActive))
            n.fillColor = UIColor.orange.withAlphaComponent(0.75 * (1 - f) + 0.2)
            n.strokeColor = UIColor.white.withAlphaComponent(0.9 * (1 - f))
            n.lineWidth = 3
        } else {
            let p = CGFloat(b.fuse > 0 ? min(1, b.age / b.fuse) : 1)
            n.fillColor = UIColor.red.withAlphaComponent(0.08 + 0.15 * p)
            n.strokeColor = UIColor.red.withAlphaComponent(0.5 + 0.4 * p)
            n.lineWidth = 2
        }
    }

    /// チャージビーム: ためている間は細い予告線(だんだん濃く太く)、撃っている間は太い光線と白い芯
    private func drawBeam(_ b: Bullet, slot: Int) {
        while beamNodes.count <= slot {
            let glow = SKShapeNode(), core = SKShapeNode()
            glow.zPosition = 3.5; glow.lineCap = .round; glow.glowWidth = 0
            core.lineCap = .round; core.strokeColor = .white
            glow.addChild(core)
            addChild(glow)
            beamNodes.append((glow, core))
        }
        let (glow, core) = beamNodes[slot]
        let path = CGMutablePath()
        path.move(to: pos(b.x, b.y))
        path.addLine(to: pos(b.x + b.vx * b.beamLength, b.y + b.vy * b.beamLength))
        glow.path = path; core.path = path
        glow.isHidden = false
        let color = skin.bulletColors[min(max(b.color, 0), skin.bulletColors.count - 1)]
        let look = BeamLook(b)
        glow.strokeColor = color.withAlphaComponent(look.alpha)
        glow.lineWidth = look.width
        glow.glowWidth = look.firing ? 4 : 0
        core.isHidden = !look.firing
        core.lineWidth = look.coreWidth
        core.alpha = look.alpha
    }

    /// 暗転の印(死神ではなく魔女の「深淵」)があるあいだ、画面を暗くして、提灯と自機のまわりだけ見せる
    private func updateDarkness(_ bs: [Bullet]) {
        guard let mark = bs.first(where: { $0.script == Bullet.darkScript }) else {
            if !darkNode.isHidden { darkNode.isHidden = true }
            return
        }
        if darkNode.parent == nil {
            darkNode.zPosition = 4.5
            darkNode.strokeColor = .clear
            darkNode.fillColor = UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1)
            addChild(darkNode)
        }
        // 出てくるときと消えるときは、なめらかに
        let fade = max(0, min(1, min(mark.age / 0.4, (mark.fuse - mark.age) / 0.6)))
        let W = CGFloat(GameScene.W), H = CGFloat(GameScene.H)
        let path = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: W, height: H))
        let lamp = pos(mark.x, mark.y), me = pos(sim.player.x, sim.player.y)
        path.addEllipse(in: CGRect(x: lamp.x - 46, y: lamp.y - 46, width: 92, height: 92))
        path.addEllipse(in: CGRect(x: me.x - 44, y: me.y - 44, width: 88, height: 88))
        darkNode.path = path
        darkNode.alpha = 0.93 * fade
        darkNode.isHidden = false
    }

    /// 瞬間移動する弾の行き先(移る 0.5 秒前から)に、点滅する輪を出す
    private func updateWarpMarks(_ bs: [Bullet]) {
        var used = 0
        for b in bs where b.script == Bullet.warpScript && b.homeLeft == 1 {
            while warpMarks.count <= used {
                let n = SKShapeNode(circleOfRadius: 12)
                n.strokeColor = UIColor(red: 1, green: 0.35, blue: 0.5, alpha: 1); n.fillColor = .clear; n.lineWidth = 2; n.zPosition = 4.6
                addChild(n); warpMarks.append(n)
            }
            let n = warpMarks[used]
            n.isHidden = false
            n.position = pos(b.u2, b.u3)
            let p = max(0, min(1, (b.fuse - b.age) / 0.5))
            n.setScale(0.5 + p)
            n.alpha = CGFloat(0.4 + 0.6 * (1 - p))
            used += 1
        }
        for i in used..<warpMarks.count where !warpMarks[i].isHidden { warpMarks[i].isHidden = true }
    }

    // MARK: ボスの構え・技中・硬直(見た目だけ。計算には関わらない)

    private var bossAction: BossSprites.Action?
    private var bossActionStart = 0.0

    /// 撃つ少し前に「構え」、撃っている間は「技中」(ループ)、撃ち終わると「硬直」、そのあと待機。絵がないボスは待機のまま
    private func updateBossAction(art: BossSprites.Art) {
        let now = sim.t, w = sim.waveT
        let windup = Double(art.actions[.windup]?.frames.count ?? 0) * BossSprites.actionFrameDuration
        let recover = Double(art.actions[.recover]?.frames.count ?? 0) * BossSprites.actionFrameDuration
        let shooting = sim.lastShotWaveT >= 0 && w - sim.lastShotWaveT < 0.3
        switch bossAction {
        case nil:
            if shooting, art.actions[.attack] != nil { bossAction = .attack; bossActionStart = now }
            else if let next = sim.untilNextShot, windup > 0, next <= windup { bossAction = .windup; bossActionStart = now - max(0, windup - next) }
        case .windup?:
            if shooting { bossAction = .attack; bossActionStart = now }
        case .attack?:
            if !shooting { bossAction = recover > 0 ? .recover : nil; bossActionStart = now }
        case .recover?:
            if shooting { bossAction = .attack; bossActionStart = now }
            else if now - bossActionStart >= recover { bossAction = nil }
        }
    }

    private func bossFrames(art: BossSprites.Art) -> ([SKTexture], [SKTexture]) {
        updateBossAction(art: art)
        if let a = bossAction, let set = art.actions[a] { return (set.frames, set.flash) }
        return (art.frames, art.flashFrames)
    }

    private func bossFrameIndex(count: Int) -> Int {
        guard let a = bossAction else { return BossSprites.frameIndex(at: sim.t) }
        let k = Int(max(0, sim.t - bossActionStart) / (a == .attack ? 0.1 : BossSprites.actionFrameDuration))
        return a == .attack ? k % count : min(k, count - 1)
    }

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
        bossNode.zPosition = 2
        bossNode.isHidden = !sim.isBoss
        addChild(bossNode)
        shipNode.zPosition = 3
        addChild(shipNode)
        if shipSkinFrames.count > 1 {
            shipNode.run(.repeatForever(.animate(with: shipSkinFrames, timePerFrame: 0.12, resize: false, restore: false)))
        }
        if effectsOn, let r = fx.aura { buildAura(r) }

        let back = SKSpriteNode(color: Palette.barBack, size: CGSize(width: W, height: 5))
        back.anchorPoint = CGPoint(x: 0, y: 1); back.position = CGPoint(x: 0, y: H); back.zPosition = 5
        addChild(back)
        barFill.anchorPoint = CGPoint(x: 0, y: 1); barFill.position = CGPoint(x: 0, y: H); barFill.zPosition = 6
        addChild(barFill)
        for f in [CGFloat(1) / 3, CGFloat(2) / 3] {
            let sep = SKSpriteNode(color: skin.background, size: CGSize(width: 2, height: 5))
            sep.anchorPoint = CGPoint(x: 0.5, y: 1); sep.position = CGPoint(x: W * f, y: H); sep.zPosition = 7
            addChild(sep)
            barSeparators.append(sep)
        }
        waveLabel.fontSize = 14
        waveLabel.fontColor = Palette.text
        waveLabel.horizontalAlignmentMode = .right
        waveLabel.verticalAlignmentMode = .top
        waveLabel.position = CGPoint(x: W - 8, y: H - 10)
        waveLabel.zPosition = 8
        waveLabel.isHidden = true
        addChild(waveLabel)
        warningOverlay.position = CGPoint(x: W / 2, y: H / 2)
        warningOverlay.zPosition = 9
        warningOverlay.alpha = 0
        addChild(warningOverlay)
        awakenOverlay.position = CGPoint(x: W / 2, y: H / 2)
        awakenOverlay.zPosition = 9.5
        awakenOverlay.alpha = 0
        addChild(awakenOverlay)
        enterWave(sim.waveIndex)
        centerLabel.fontSize = 28
        centerLabel.fontColor = Palette.text
        centerLabel.verticalAlignmentMode = .center
        centerLabel.position = CGPoint(x: W / 2, y: H / 2)
        centerLabel.zPosition = 8
        addChild(centerLabel)
    }

    /// 場面ごとに決まっている、ボスの見た目と大きさ(当たる範囲と同じ比率)、発射点の雑魚の姿
    private func applyEnemyLooks() {
        let bossSize = CGSize(width: EnemyArt.bossPoints(size: sim.bossSizeIndex), height: EnemyArt.bossPoints(size: sim.bossSizeIndex))
        characterNormal = nil; characterAwakened = nil
        if let c = sim.bossCharacter, let art = BossSprites.art(c, awakened: false) {
            // 専用の絵を持つボスは、自分の画像への差し替えより優先する(絵・位置・当たり判定が決まっているため)
            characterNormal = art
            characterAwakened = BossSprites.art(c, awakened: true)
            bossTexture = art.frames[0]; bossFlashTexture = art.flashFrames[0]
            bossNode.texture = bossTexture
            bossNode.size = CGSize(width: art.size.width * sim.bossScale, height: art.size.height * sim.bossScale)
        } else if let c = customBossTextures {
            bossTexture = c.0; bossFlashTexture = c.1
        } else {
            let look = sim.bossLookIndex
            bossTexture = SpriteFactory.bossTexture(look: look, size: sim.bossSizeIndex, flash: false)
            bossFlashTexture = SpriteFactory.bossTexture(look: look, size: sim.bossSizeIndex, flash: true)
        }
        if characterNormal == nil {
            bossNode.texture = bossTexture
            bossNode.size = bossSize
        }
        for n in mookNodes { n.removeFromParent() }
        mookNodes.removeAll(); mookEmitterIndex.removeAll(); mookGone.removeAll()
        guard let mookSize = sim.mookSizeIndex else { return }
        let W = GameScene.W, H = GameScene.H
        let tex = SpriteFactory.mookTexture(look: sim.mookLookIndex, size: mookSize)
        let side = EnemyArt.mookPoints(size: mookSize)
        for (idx, m) in sim.currentEmitters.enumerated() where Simulation.hasMook(m, boss: sim.isBoss) {
            let n = SKSpriteNode(texture: tex, size: CGSize(width: side, height: side))
            n.position = pos(m.x * Double(W), m.y * Double(H))
            n.zPosition = 1.5
            addChild(n)
            mookNodes.append(n)
            mookEmitterIndex.append(idx)
        }
    }

    /// 覚醒の演出(見た目だけ)。覚醒する段階に入った瞬間から1.2秒: 白くなって震え → 姿が変わって赤い衝撃波と「覚醒」
    /// ボスの動きの演出(見た目だけで、計算には関わらない): 横に動くと進む向きへ少し傾き、速く動くとき(ワープなど)は残像を残す
    private func animateBossMotion(to cur: CGPoint) {
        defer { lastBossPoint = cur }
        guard effectsOn, let last = lastBossPoint else { bossNode.zRotation = 0; return }
        let vx = (cur.x - last.x) * 60, vy = (cur.y - last.y) * 60   // 論理px/秒
        let target = max(-0.22, min(0.22, -vx * 0.0018))
        bossNode.zRotation += (target - bossNode.zRotation) * 0.2
        let speed = (vx * vx + vy * vy).squareRoot()
        ghostTick += 1
        guard speed > 150, ghostTick % 3 == 0 else { return }
        let ghost = SKSpriteNode(texture: bossNode.texture, size: bossNode.size)
        ghost.position = bossNode.position
        ghost.zRotation = bossNode.zRotation
        ghost.zPosition = bossNode.zPosition - 0.1
        ghost.alpha = 0.38
        ghost.colorBlendFactor = 0.5
        ghost.color = Palette.pink
        addChild(ghost)
        ghost.run(.sequence([.group([.fadeOut(withDuration: 0.3), .scale(to: 1.08, duration: 0.3)]), .removeFromParent()]))
    }

    private func updateAwaken(at bp: Point) {
        if sim.isAwakened && !awakenShown {
            awakenShown = true
            if effectsOn { awakenStartT = sim.t }
        } else if !sim.isAwakened {
            awakenShown = false; awakenStartT = nil; awakenRingShown = false
        }
        guard let st = awakenStartT else {
            if awakenOverlay.alpha != 0 { awakenOverlay.alpha = 0 }
            return
        }
        let e = sim.t - st
        if e >= GameScene.awakenLength {
            awakenStartT = nil
            awakenOverlay.alpha = 0
            return
        }
        if e < GameScene.awakenSwap {
            let k = e / GameScene.awakenSwap
            awakenOverlay.color = .white
            awakenOverlay.alpha = CGFloat(k * 0.85)
            // 震える
            bossNode.position.x += CGFloat(sin(e * 90) * 3 * k)
        } else {
            let k = (e - GameScene.awakenSwap) / (GameScene.awakenLength - GameScene.awakenSwap)
            awakenOverlay.color = UIColor(red: 1, green: 0.24, blue: 0.31, alpha: 1)
            awakenOverlay.alpha = CGFloat((1 - k) * 0.5)
            if !awakenRingShown {
                awakenRingShown = true
                let ring = SKShapeNode(circleOfRadius: 20)
                ring.strokeColor = UIColor(red: 1, green: 0.24, blue: 0.31, alpha: 1)
                ring.lineWidth = 4
                ring.fillColor = .clear
                ring.position = pos(bp.x, bp.y)
                ring.zPosition = 3
                addChild(ring)
                ring.run(.sequence([.group([.scale(to: 14, duration: 0.75), .fadeOut(withDuration: 0.75)]), .removeFromParent()]))
            }
        }
    }

    /// 場面が始まったときの表示のつくり直し: 発射位置の予告・ボスの出し入れ・帯の色・場面の数字・警告
    private func enterWave(_ index: Int) {
        lastBossPoint = nil
        shownWave = index
        awakenStartT = nil; awakenShown = false; awakenRingShown = false
        awakenOverlay.alpha = 0
        for m in markers { m.removeFromParent() }
        markers.removeAll()
        if !sim.isBoss && sim.stage.showsMarkers {
            let W = GameScene.W, H = GameScene.H
            for m in sim.currentEmitters where ![.rain, .sideL, .sideR, .corner].contains(m.t) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: 0, y: 7)); p.addLine(to: CGPoint(x: 7, y: 0))
                p.addLine(to: CGPoint(x: 0, y: -7)); p.addLine(to: CGPoint(x: -7, y: 0)); p.closeSubpath()
                let n = SKShapeNode(path: p)
                n.strokeColor = skin.bulletColors[min(max(m.k, 0), skin.bulletColors.count - 1)]
                n.lineWidth = 1
                n.position = pos(m.x * Double(W), m.y * Double(H))
                n.zPosition = 1
                n.isHidden = true
                addChild(n)
                markers.append(n)
            }
        }
        bossNode.isHidden = !sim.isBoss
        applyEnemyLooks()
        barFill.color = sim.isBoss ? Palette.pink : Palette.gold
        for sep in barSeparators { sep.isHidden = !sim.isBoss }
        waveLabel.isHidden = sim.waveCount <= 1
        waveLabel.text = "WAVE \(index + 1)/\(sim.waveCount)"
        // 警告: ボスの場面の開始前に、赤い点滅とサイレン(演出がオフなら、出さない)
        if sim.warningNow && effectsOn {
            warningLeft = index == 0 ? DanmakuConfig.readySeconds : Wave.intermissionSeconds
            AudioManager.shared.se(.warning)
        }
        if index > 0 {
            centerLabel.text = "WAVE \(index + 1)"
            centerLabel.fontColor = Palette.gold
            centerLabel.isHidden = false
        }
    }

    /// 被弾した場所から復活する（広告を見たあと／広告削除の購入者）
    func revive() {
        sim.revive()
        finishDelay = 0
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
            // 最後のボスを倒したときは、爆発を少し見せてから結果を出す(演出がオフなら、すぐ)
            if sim.outcome == .cleared && sim.defeats > 0 && effectsOn && sim.lastDefeatEffect != .none && finishDelay < 1.4 {
                finishDelay += 1.0 / 60.0
                return
            }
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
        renderMooks()
        if effectsOn { renderRewardFX() }
        shipNode.alpha = sim.isShielded ? (Int(now * 10) % 2 == 0 ? 0.35 : 1) : 1

        // 弾（スプライトを使い回す）
        let bs = sim.bullets
        while bulletNodes.count < bs.count {
            let n = SKSpriteNode(texture: bulletTextures[0])
            n.zPosition = 4
            addChild(n)
            bulletNodes.append(n)
        }
        var beamCount = 0
        var blastCount = 0
        for i in 0..<bulletNodes.count {
            let n = bulletNodes[i]
            if i < bs.count {
                let b = bs[i]
                if b.isBeam {
                    // チャージビームは、弾の絵ではなく光線で描く
                    n.isHidden = true
                    drawBeam(b, slot: beamCount)
                    beamCount += 1
                    continue
                }
                if b.isBlast {
                    // 爆風は、予告の円 → 明るい円で描く
                    n.isHidden = true
                    drawBlast(b, slot: blastCount)
                    blastCount += 1
                    continue
                }
                if b.isDormant && !b.dormantGlow {
                    // 待機中の弾・暗転の印: 見えない
                    n.isHidden = true
                    continue
                }
                n.isHidden = false
                n.position = pos(b.x, b.y)
                if let tex = BulletArt.texture(look: b.look) {
                    // ボス専用の弾: ドット絵を、進む向きへ回して描く(見た目だけ。当たる半径は BulletLook)
                    if n.texture !== tex { n.texture = tex }
                    let size = BulletArt.drawSize(b)
                    if n.size != size { n.size = size }
                    n.zRotation = -BulletArt.rotation(b)
                    let alpha: CGFloat = b.dormantGlow ? 0.25 : 1   // 鎖が伸びる前の、薄い予告線
                    if n.alpha != alpha { n.alpha = alpha }
                    continue
                }
                let boomerang = b.drawsAsBoomerang
                n.texture = boomerang ? boomerangTextures[min(max(b.color, 0), boomerangTextures.count - 1)] : bulletTextures[b.color]
                // 巨大弾は、当たる範囲に合わせて大きく描く。ブーメランは🪃の形で、くるくる回す
                // 膨らむ泡など、広さを持つ弾は、当たる広さに合わせて描く
                let size = b.isGiant ? CGSize(width: DanmakuConfig.giantDrawRadius * 2, height: DanmakuConfig.giantDrawRadius * 2)
                    : boomerang ? CGSize(width: 16, height: 16)
                    : b.radius > 0 ? CGSize(width: max(12, (b.radius + 4) * 2), height: max(12, (b.radius + 4) * 2)) : bulletTextures[0].size()
                if n.size != size { n.size = size }
                n.zRotation = boomerang ? CGFloat(lastTime ?? 0) * 14 + CGFloat(i) : 0
                // 止まった地雷は点滅する(爆発が近いほど速く)
                if b.mineStopped {
                    let fast = b.fuse - b.age < 0.8
                    n.alpha = sin((lastTime ?? 0) * (fast ? 40 : 14)) > 0 ? 1 : 0.35
                } else if n.alpha != 1 { n.alpha = 1 }
            } else if !n.isHidden {
                n.isHidden = true
            }
        }

        for i in beamCount..<beamNodes.count where !beamNodes[i].glow.isHidden { beamNodes[i].glow.isHidden = true }
        for i in blastCount..<blastNodes.count where !blastNodes[i].isHidden { blastNodes[i].isHidden = true }

        updateDarkness(bs)
        updateWarpMarks(bs)

        if sim.waveIndex != shownWave { enterWave(sim.waveIndex) }
        if sim.defeats > shownDefeats {
            shownDefeats = sim.defeats
            if effectsOn { playDefeat(at: sim.lastDefeatPosition, effect: sim.lastDefeatEffect) }
        }
        if warningLeft > 0 {
            warningLeft -= 1.0 / 60.0
            let phase = sin(now * 14)
            warningOverlay.alpha = CGFloat(max(0, phase)) * 0.28
            centerLabel.text = "WARNING!"
            centerLabel.fontColor = UIColor(red: 1, green: 0.35, blue: 0.4, alpha: 1)
            centerLabel.isHidden = false
            if warningLeft <= 0 { warningOverlay.alpha = 0 }
        }
        if sim.isBoss {
            let bp = sim.bossPosition
            bossNode.position = pos(bp.x, bp.y)
            updateAwaken(at: bp)
            animateBossMotion(to: CGPoint(x: bp.x, y: bp.y))
            if let normal = characterNormal {
                let swapped = awakenStartT.map { sim.t - $0 >= GameScene.awakenSwap } ?? true
                let art = (sim.isAwakened && swapped ? characterAwakened : nil) ?? normal
                // キャラクターのボスの大きさ(当たり判定と同じ倍率)
                bossNode.size = CGSize(width: art.size.width * sim.bossScale, height: art.size.height * sim.bossScale)
                let (frames, flashFrames) = bossFrames(art: art)
                let i = bossFrameIndex(count: frames.count)
                bossNode.texture = sim.flash > 0 ? flashFrames[i] : frames[i]
            } else {
                bossNode.texture = sim.flash > 0 ? bossFlashTexture : bossTexture
            }
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
            let ratio = sim.isDamageRace ? 1.0 : max(0, Double(sim.hp)) / Double(max(1, sim.waveBossHp))
            barFill.size.width = max(0.001, W * CGFloat(ratio))
        } else {
            // ボスのいない場面(連戦でボスを倒したあとの耐えきる場面など)では、自機の弾は撃たない。
            // 前の場面で描いた弾が、その場に止まって残らないように隠す
            for n in shotNodes where !n.isHidden { n.isHidden = true }
            // 発射台の印：撃ち始める0.6秒前から点滅し、撃ち終わったら消す
            var idx = 0
            for m in sim.currentEmitters where ![.rain, .sideL, .sideR, .corner].contains(m.t) {
                guard idx < markers.count else { break }
                let n = markers[idx]; idx += 1
                let lead = m.s - sim.waveT
                let end = min(m.e, sim.waveLimit)
                if sim.waveT >= end || lead > 0.6 { n.isHidden = true; continue }
                n.isHidden = false
                n.alpha = lead > 0 ? (Int(floor(lead * 10)) % 2 != 0 ? 0.15 : 0.7) : 0.35
            }
            let p = max(0, min(1, sim.waveT / max(1, sim.waveLimit)))
            barFill.size.width = max(0.001, W * CGFloat(p))
        }

        if warningLeft > 0 {
            // 警告の表示中は、上で文字を出している
        } else if sim.t < 0 {
            centerLabel.text = L("play.ready"); centerLabel.fontColor = Palette.text; centerLabel.isHidden = false
        } else if sim.isIntermission {
            centerLabel.text = "WAVE \(sim.waveIndex + 1)"; centerLabel.fontColor = Palette.gold; centerLabel.isHidden = false
        } else if sim.isBoss && sim.banner > 0 {
            if let st = awakenStartT {
                // 覚醒の演出中: 白くなっている間は文字を出さず、姿が変わったら「覚醒」を出す
                let e = sim.t - st
                centerLabel.text = L("play.awaken")
                centerLabel.fontColor = UIColor(red: 1, green: 0.24, blue: 0.31, alpha: 1)
                centerLabel.isHidden = e < GameScene.awakenSwap
            } else {
                centerLabel.text = String(format: L("play.phase"), sim.phase)
                centerLabel.fontColor = Palette.gold; centerLabel.isHidden = false
            }
        } else {
            centerLabel.isHidden = true
            centerLabel.fontColor = Palette.text
        }
        onTime?(sim.stage.isUnlimitedTime ? max(0, sim.t) : max(0, sim.waveLimit - max(0, sim.waveT)))
        let status = (sim.lifeLeft, sim.lifeMax, sim.damageDealt)
        if status != lastStatus {
            if lastStatus.0 > status.0 && lastStatus.0 >= 0 {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                if status.0 > 0 { AudioManager.shared.se(.lifeLost) }
            }
            lastStatus = status
            onStatus?(status.0, status.1, status.2)
        }
        // 被弾したら、自機が赤くひらめく
        shipNode.color = .red
        shipNode.colorBlendFactor = sim.hitFlash > 0 ? 0.85 : 0
    }

    // MARK: 撃破の演出(見た目だけ。計算には関わらない)

    /// ボスを倒した場所に、選ばれた演出を出す
    private func playDefeat(at p: Point, effect: DefeatEffect) {
        guard effect != .none else { return }
        let center = pos(p.x, p.y)
        if let r = fx.burst { rewardBurst(r, at: center) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        switch effect {
        case .none: return
        case .explosion:
            AudioManager.shared.se(.boom)
            flashScreen(UIColor.white, peak: 0.55, duration: 0.35)
            ring(at: center, color: UIColor(hex: 0xFFD166), maxRadius: 150, width: 6, duration: 0.55)
            ring(at: center, color: UIColor(hex: 0xFF6B9D), maxRadius: 100, width: 4, duration: 0.45)
            burst(at: center, count: 46, colors: [0xFFD166, 0xFF8A5C, 0xFF6B9D, 0xFFFFFF].map { UIColor(hex: $0) }, speed: 70...230, size: 3...7, life: 0.6...1.1, gravity: 60)
        case .fireworks:
            AudioManager.shared.se(.sparkle)
            for (i, c) in [0xFF6B9D, 0x5CE1E6, 0xFFD166, 0xB28DFF, 0x7CF29C].enumerated() {
                let off = CGPoint(x: center.x + CGFloat(cos(Double(i) * 1.26) * 38), y: center.y + CGFloat(sin(Double(i) * 1.26) * 38))
                run(after: Double(i) * 0.12) { [weak self] in
                    self?.burst(at: off, count: 22, colors: [UIColor(hex: UInt32(c)), .white], speed: 60...170, size: 3...6, life: 0.7...1.2, gravity: 40)
                }
            }
            ring(at: center, color: .white, maxRadius: 120, width: 3, duration: 0.5)
        case .hearts:
            AudioManager.shared.se(.sparkle)
            for i in 0..<16 {
                let n = SKLabelNode(text: "♥")
                n.fontName = "AvenirNext-Heavy"
                n.fontSize = CGFloat.random(in: 16...30)
                n.fontColor = [UIColor(hex: 0xFF6B9D), UIColor(hex: 0xFF8FB8), UIColor(hex: 0xFFB3D1)][i % 3]
                n.position = center
                n.zPosition = 7
                addChild(n)
                let dx = CGFloat.random(in: -90...90), dy = CGFloat.random(in: 60...190)
                let t = Double.random(in: 0.9...1.5)
                n.run(.sequence([.group([.moveBy(x: dx, y: dy, duration: t), .fadeOut(withDuration: t), .scale(to: 1.5, duration: t)]), .removeFromParent()]))
            }
            ring(at: center, color: UIColor(hex: 0xFF6B9D), maxRadius: 110, width: 4, duration: 0.5)
        case .stardust:
            AudioManager.shared.se(.sparkle)
            for i in 0..<28 {
                let n = SKLabelNode(text: i % 3 == 0 ? "✦" : "★")
                n.fontName = "AvenirNext-Heavy"
                n.fontSize = CGFloat.random(in: 10...24)
                n.fontColor = [UIColor(hex: 0xFFD166), UIColor(hex: 0xFFF2B3), .white][i % 3]
                n.position = center
                n.zPosition = 7
                addChild(n)
                let a = Double.random(in: 0...(2 * .pi)), r = CGFloat.random(in: 40...170)
                let t = Double.random(in: 0.7...1.3)
                n.run(.sequence([.group([.moveBy(x: CGFloat(cos(a)) * r, y: CGFloat(sin(a)) * r, duration: t), .fadeOut(withDuration: t), .rotate(byAngle: CGFloat.random(in: -3...3), duration: t)]), .removeFromParent()]))
            }
            flashScreen(UIColor(hex: 0xFFD166), peak: 0.25, duration: 0.5)
        }
    }

    private func run(after delay: Double, _ block: @escaping () -> Void) {
        self.run(.sequence([.wait(forDuration: delay), .run(block)]))
    }

    private func flashScreen(_ color: UIColor, peak: CGFloat, duration: Double) {
        let n = SKSpriteNode(color: color, size: CGSize(width: GameScene.W, height: GameScene.H))
        n.position = CGPoint(x: GameScene.W / 2, y: GameScene.H / 2)
        n.zPosition = 9
        n.alpha = 0
        addChild(n)
        n.run(.sequence([.fadeAlpha(to: peak, duration: duration * 0.2), .fadeOut(withDuration: duration * 0.8), .removeFromParent()]))
    }

    fileprivate func ring(at p: CGPoint, color: UIColor, maxRadius: CGFloat, width: CGFloat, duration: Double) {
        let n = SKShapeNode(circleOfRadius: 4)
        n.strokeColor = color
        n.fillColor = .clear
        n.lineWidth = width
        n.position = p
        n.zPosition = 7
        addChild(n)
        n.run(.sequence([.group([.scale(to: maxRadius / 4, duration: duration), .fadeOut(withDuration: duration)]), .removeFromParent()]))
    }

    fileprivate func burst(at p: CGPoint, count: Int, colors: [UIColor], speed: ClosedRange<CGFloat>, size: ClosedRange<CGFloat>,
                       life: ClosedRange<Double>, gravity: CGFloat) {
        for i in 0..<count {
            let d = CGFloat.random(in: size)
            let n = SKSpriteNode(color: colors[i % colors.count], size: CGSize(width: d, height: d))
            n.position = p
            n.zPosition = 7
            addChild(n)
            let a = Double.random(in: 0...(2 * .pi)), v = CGFloat.random(in: speed), t = Double.random(in: life)
            let dx = CGFloat(cos(a)) * v * CGFloat(t), dy = CGFloat(sin(a)) * v * CGFloat(t) - gravity * CGFloat(t) * CGFloat(t)
            n.run(.sequence([.group([.moveBy(x: dx, y: dy, duration: t), .fadeOut(withDuration: t), .scale(to: 0.2, duration: t)]), .removeFromParent()]))
        }
    }
}

// MARK: 報酬の演出(軌跡・被弾の光・オーラ・撃破)。見た目だけで、ゲームの計算には関わらない

extension GameScene {
    fileprivate func buildAura(_ r: Reward) {
        let color = RewardArt.uiColor(r)
        let node = SKNode()
        node.zPosition = 2.5
        let n = RewardArt.particleCount(r)
        switch r.style {
        case .ring:
            let c = SKShapeNode(circleOfRadius: 16)
            c.strokeColor = color; c.fillColor = .clear; c.lineWidth = 1.5; c.alpha = 0.8
            node.addChild(c)
            node.run(.repeatForever(.sequence([.scale(to: 1.25, duration: 0.7), .scale(to: 1.0, duration: 0.7)])))
        case .dots, .star, .wave:
            for i in 0..<n {
                let a = CGFloat(i) / CGFloat(n) * 2 * .pi
                let d = SKSpriteNode(color: i % 2 == 0 ? color : RewardArt.accent(r), size: CGSize(width: r.style == .star ? 4 : 3, height: r.style == .star ? 4 : 3))
                if r.style == .star { d.zRotation = .pi / 4 }
                d.position = CGPoint(x: cos(a) * 17, y: sin(a) * 17)
                node.addChild(d)
            }
            node.run(.repeatForever(.rotate(byAngle: r.style == .wave ? -2 * .pi : 2 * .pi, duration: r.style == .wave ? 2.4 : 3.2)))
        }
        auraNode = node
        addChild(node)
    }

    /// 倒せる雑魚: 弾が当たると白く光り、倒されると小さく弾けて消える(見た目だけ。計算は Simulation)
    private func renderMooks() {
        for (k, n) in mookNodes.enumerated() where k < mookEmitterIndex.count {
            let idx = mookEmitterIndex[k]
            if sim.mookDestroyed(idx) {
                guard !mookGone.contains(idx) else { continue }
                mookGone.insert(idx)
                if effectsOn {
                    let burst = SKSpriteNode(texture: n.texture, size: n.size)
                    burst.position = n.position; burst.zPosition = 6
                    burst.color = .white; burst.colorBlendFactor = 1
                    addChild(burst)
                    burst.run(.sequence([.group([.scale(to: 1.8, duration: 0.25), .fadeOut(withDuration: 0.25)]), .removeFromParent()]))
                }
                n.isHidden = true
                AudioManager.shared.se(.boom)
                continue
            }
            let lit = idx < sim.mookFlash.count && sim.mookFlash[idx] > 0
            n.color = .white
            n.colorBlendFactor = lit ? 0.85 : 0
        }
    }

    fileprivate func renderRewardFX() {
        fxFrame += 1
        auraNode?.position = shipNode.position
        // 軌跡: 3フレームごとに、自機の後ろに小さな粒を残す
        if let r = fx.trail, fxFrame % 3 == 0 {
            let color = RewardArt.uiColor(r)
            let size: CGFloat = r.style == .star ? 5 : 4
            let n = SKSpriteNode(color: fxFrame % 6 == 0 ? color : RewardArt.accent(r), size: CGSize(width: size, height: size))
            if r.style == .star { n.zRotation = .pi / 4 }
            let wobble: CGFloat = r.style == .wave ? CGFloat(sin(Double(fxFrame) * 0.4)) * 6 : 0
            n.position = CGPoint(x: shipNode.position.x + wobble, y: shipNode.position.y - 10)
            n.zPosition = 2.8
            addChild(n)
            if r.style == .ring {
                n.removeFromParent()
                ring(at: CGPoint(x: shipNode.position.x, y: shipNode.position.y - 8), color: color, maxRadius: 14, width: 1.2, duration: 0.35)
            } else {
                n.run(.sequence([.group([.moveBy(x: 0, y: -18, duration: 0.4), .fadeOut(withDuration: 0.4), .scale(to: 0.2, duration: 0.4)]), .removeFromParent()]))
            }
        }
        // 被弾の光: ライフかHPが減ったときに、自機の位置に散らす
        let hp = sim.hp, life = sim.lifeLeft
        if (hp < fxLastHP || life < fxLastLife), let r = fx.hitSpark {
            let colors = [RewardArt.uiColor(r), RewardArt.accent(r), .white]
            burst(at: shipNode.position, count: RewardArt.particleCount(r) * 3, colors: colors, speed: 50...160, size: 2...5, life: 0.4...0.8, gravity: 0)
            if r.style == .ring { ring(at: shipNode.position, color: RewardArt.uiColor(r), maxRadius: 60, width: 3, duration: 0.45) }
        }
        fxLastHP = hp
        fxLastLife = life
    }

    fileprivate func rewardBurst(_ r: Reward, at center: CGPoint) {
        let colors = [RewardArt.uiColor(r), RewardArt.accent(r), .white]
        burst(at: center, count: RewardArt.particleCount(r) * 6, colors: colors, speed: 60...220, size: 3...7, life: 0.7...1.3, gravity: r.style == .star ? 60 : 0)
        ring(at: center, color: RewardArt.uiColor(r), maxRadius: 130, width: 4, duration: 0.6)
    }
}
