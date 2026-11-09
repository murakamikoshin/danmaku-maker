import SwiftUI
import DanmakuCore

/// 発射台カード用のループプレビュー。DanmakuCore の emit をそのまま使い、ダミー自機が左右に動く
final class PreviewEngine {
    static let height = 330.0
    private var t = 0.0
    private var next = 0.0
    private var shot = 0
    private var rng = Mulberry32(seed: 1)
    private var last: Date?
    private(set) var bullets: [Bullet] = []
    private(set) var player = Point(x: 180, y: PreviewEngine.height - 40)

    func advance(to now: Date, emitter m: Emitter, boss: Bool, character: BossCharacter? = nil) {
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        t += dt
        player = Point(x: 180 + sin(t * 0.9) * 90, y: PreviewEngine.height - 40)
        let atBoss = boss && !m.firesFromPoint
        // 専用の絵を持つボスは、実際のゲームと同じ位置(待機のゆれの最初)から撃つ
        let home = character?.position(waveT: 0)
        let cx = atBoss ? (home?.x ?? 180) : m.x * DanmakuConfig.width
        let cy = atBoss ? (home?.y ?? DanmakuConfig.height * 0.18) : m.y * DanmakuConfig.height
        while t >= next {
            Emit.emit(m, shot: shot, cx: cx, cy: cy, px: player.x, py: player.y, rng: &rng, into: &bullets)
            shot += 1
            next += max(0.05, m.i)
        }
        var w = 0
        var born: [Bullet] = []
        for i in 0..<bullets.count {
            var b = bullets[i]
            // ゲーム本体と同じ動き(止まる・分裂・追尾・加速・反射)
            let motion = b.advance(dt: dt, width: DanmakuConfig.width, playerX: player.x, playerY: player.y)
            if motion == .burst {
                born.append(contentsOf: b.fragments())
                continue
            }
            if motion == .gone { continue }   // 撃ち終わったチャージビーム
            if !b.isRing && (b.x < -20 || b.x > DanmakuConfig.width + 20 || b.y < -20 || b.y > PreviewEngine.height + 20) { continue }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        bullets.append(contentsOf: born)
    }
}

struct EmitterPreview: View {
    let emitter: Emitter
    let isBoss: Bool
    let look: PreviewLook
    @State private var engine = PreviewEngine()
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        // 作者が選んだ見た目(弾の色と形・背景・自機)と、じぶんの画像を、そのまま使う
        let _ = cosmetics.customImageRevision
        let skin = Skin.of(look.bullets)
        let bg = Skin.of(look.background)
        let bulletImages = SpriteFactory.bulletImages(look.bullets)
        let boomerangImages = SpriteFactory.boomerangImages(look.bullets)
        let own = cosmetics.ownership.hasCustomImages
        let customBullet = (own && look.customs.bullet) ? CustomImageStore.load(.bullet) : nil
        let customShip = (own && look.customs.ship) ? CustomImageStore.load(.ship) : nil
        let shipImage = customShip ?? SpriteFactory.shipImage(look.ship)
        let bossImage = (own && look.customs.boss) ? CustomImageStore.load(.boss) : nil
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                engine.advance(to: timeline.date, emitter: emitter, boss: isBoss, character: BossCharacter.of(look: look.bossLook))
                let s = size.width / DanmakuConfig.width
                ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(bg.background)))
                ctx.scaleBy(x: s, y: s)
                drawSource(&ctx, skin: skin, bossImage: bossImage)
                // 自機(当たる場所の白い点つき)
                let sw: CGFloat = 20, sh: CGFloat = 24
                let pt = engine.player
                let custom = customShip != nil
                let shipRect = CGRect(x: pt.x - (custom ? 12 : sw / 2), y: pt.y - (custom ? 12 : sh / 2), width: custom ? 24 : sw, height: custom ? 24 : sh)
                ctx.draw(Image(uiImage: shipImage), in: shipRect)
                if custom { ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 2.5, y: pt.y - 2.5, width: 5, height: 5)), with: .color(.white)) }
                // 弾
                for b in engine.bullets {
                    ctx.drawBullet(b, images: bulletImages, boomerangs: boomerangImages, colors: skin.bulletColors,
                                   time: timeline.date.timeIntervalSinceReferenceDate, custom: customBullet)
                }
            }
        }
        .aspectRatio(DanmakuConfig.width / PreviewEngine.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func drawSource(_ ctx: inout GraphicsContext, skin: Skin, bossImage: UIImage?) {
        if isBoss {
            // 専用の絵を持つボスは、実際のゲームと同じ位置・大きさで描く
            if let c = BossCharacter.of(look: look.bossLook), let art = BossSprites.art(c, awakened: false) {
                let p = c.position(waveT: 0)
                ctx.draw(Image(uiImage: art.still).interpolation(.none),
                         in: CGRect(x: p.x - art.size.width / 2, y: p.y - art.size.height / 2, width: art.size.width, height: art.size.height))
            } else {
                // ボスの大きさは、当たる範囲と同じ比率(小・中・大)
                let side = EnemyArt.bossPoints(size: look.bossSize)
                let rect = CGRect(x: 180 - side / 2, y: DanmakuConfig.height * 0.18 - side / 2, width: side, height: side)
                if let bossImage { ctx.draw(Image(uiImage: bossImage), in: rect) }
                else { ctx.draw(Image(uiImage: EnemyArt.bossImage(look: look.bossLook, size: look.bossSize, flash: false)), in: rect) }
            }
        }
        if let mooks = look.mooks, (!isBoss || emitter.firesFromPoint) && ![.rain, .sideL, .sideR, .corner].contains(emitter.t) {
            let side = EnemyArt.mookPoints(size: mooks)
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            ctx.draw(Image(uiImage: EnemyArt.mookImage(look: look.mookLook, size: mooks)), in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
        }
        if (!isBoss || emitter.firesFromPoint) && ![.rain, .sideL, .sideR, .corner].contains(emitter.t) {
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - 8)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + 8)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y)); p.closeSubpath()
            ctx.stroke(p, with: .color(Color(skin.bulletColors[min(max(emitter.k, 0), skin.bulletColors.count - 1)])), lineWidth: 2)
        }
    }

}

/// チャージビームの見た目(ゲーム本体・エディタの見本で同じ)。当たる太さ(DanmakuConfig.beamHitRadiusSquared)に近い太さで描く
struct BeamLook {
    /// 光線の長さ(画面の外まで届く長さ)
    static let length = 900.0
    let firing: Bool
    let width: CGFloat
    let coreWidth: CGFloat
    let alpha: CGFloat

    init(_ b: Bullet) {
        if b.beamFiring {
            // 撃っている間: 太い光線。終わりぎわに薄くなって消える
            let f = (b.age - DanmakuConfig.beamCharge) / b.beamFireTime
            firing = true
            width = 18
            coreWidth = 6
            alpha = CGFloat(f > 0.75 ? max(0, (1 - f) / 0.25) : 1)
        } else {
            // ためている間: 細い予告線が、だんだん太く濃くなる(当たらない)
            let p = b.beamChargeProgress
            firing = false
            width = CGFloat(1 + 3 * p)
            coreWidth = 0
            alpha = CGFloat(0.25 + 0.5 * p)
        }
    }
}

extension GraphicsContext {
    /// チャージビームを描く(エディタの見本・パターンの絵)
    func drawBeam(_ b: Bullet, color: Color, scale: CGFloat = 1) {
        let look = BeamLook(b)
        var p = Path()
        p.move(to: CGPoint(x: b.x * scale, y: b.y * scale))
        p.addLine(to: CGPoint(x: (b.x + b.vx * b.beamLength) * scale, y: (b.y + b.vy * b.beamLength) * scale))
        let style = StrokeStyle(lineWidth: look.width * scale, lineCap: .round)
        stroke(p, with: .color(color.opacity(look.alpha)), style: style)
        if look.firing {
            stroke(p, with: .color(.white.opacity(look.alpha)), style: StrokeStyle(lineWidth: look.coreWidth * scale, lineCap: .round))
        }
    }
}

extension GraphicsContext {
    /// 弾を1つ描く(エディタの見本・ショップの見本で同じ)。種類ごとに形を変える:
    /// ビームは光線、爆風は予告の円→衝撃、ブーメランは回る🪃、地雷は止まると点滅、巨大弾・膨らむ泡は当たる広さに合わせた大きさ
    func drawBullet(_ b: Bullet, images: [UIImage], boomerangs: [UIImage], colors: [UIColor], scale s: CGFloat = 1, time: Double, custom: UIImage? = nil) {
        let i = min(max(b.color, 0), colors.count - 1)
        let color = Color(colors[i])
        if b.isBeam { drawBeam(b, color: color, scale: s); return }
        if b.isBlast { drawBlast(b, color: color, scale: s, time: time); return }
        let c = CGPoint(x: b.x * s, y: b.y * s)
        if b.script == Bullet.boomerangScript {
            var g = self
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(time * 14))
            g.draw(Image(uiImage: boomerangs[min(i, boomerangs.count - 1)]), in: CGRect(x: -8 * s, y: -8 * s, width: 16 * s, height: 16 * s))
            return
        }
        let r: CGFloat = b.isGiant ? DanmakuConfig.giantDrawRadius : max(6, b.radius + 4)
        let rect = CGRect(x: c.x - r * s, y: c.y - r * s, width: r * 2 * s, height: r * 2 * s)
        var g = self
        if b.mineStopped {
            // 止まった地雷: 爆発が近いほど速く点滅し、爆風の届く範囲を薄く見せる
            let left = max(0, b.fuse - b.age)
            g.opacity = sin(time * (left < 0.8 ? 40 : 14)) > 0 ? 1 : 0.35
            let br = DanmakuConfig.mineBlastRadius * s
            stroke(Path(ellipseIn: CGRect(x: c.x - br, y: c.y - br, width: br * 2, height: br * 2)), with: .color(.red.opacity(0.35)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
        g.draw(Image(uiImage: custom ?? images[min(i, images.count - 1)]), in: rect)
    }

    /// 爆風: 予告の間は赤い点線の円(だんだん濃く)、当たる間は明るい円
    func drawBlast(_ b: Bullet, color: Color, scale s: CGFloat = 1, time: Double) {
        let r = b.radius * s
        let rect = CGRect(x: b.x * s - r, y: b.y * s - r, width: r * 2, height: r * 2)
        if b.blastActive {
            let f = min(1, (b.age - b.fuse) / DanmakuConfig.blastActive)
            fill(Path(ellipseIn: rect), with: .color(Color.orange.opacity(0.75 * (1 - f) + 0.2)))
            fill(Path(ellipseIn: rect.insetBy(dx: r * 0.45, dy: r * 0.45)), with: .color(.white.opacity(0.8 * (1 - f))))
        } else {
            let p = b.fuse > 0 ? min(1, b.age / b.fuse) : 1
            fill(Path(ellipseIn: rect), with: .color(.red.opacity(0.08 + 0.15 * p)))
            stroke(Path(ellipseIn: rect), with: .color(.red.opacity(0.5 + 0.4 * p)), style: StrokeStyle(lineWidth: 1.5 * s, dash: [4 * s, 3 * s]))
            // 落ちてくるまでの残りを、内側に縮む円で見せる
            let ir = r * (1 - p)
            stroke(Path(ellipseIn: CGRect(x: b.x * s - ir, y: b.y * s - ir, width: ir * 2, height: ir * 2)), with: .color(color.opacity(0.7)), lineWidth: 1.2 * s)
        }
    }
}

// MARK: - 世界のステージ一覧の、動くミニプレビューと、流れるタイトル

/// 一覧がスクロール中か。スクロール中は、プレビューとタイトルの動きを止める
private struct ListScrollingKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var listScrolling: Bool {
        get { self[ListScrollingKey.self] }
        set { self[ListScrollingKey.self] = newValue }
    }
}

private struct ScrollTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// iOS 17 用: 中身の位置が動いている間を「スクロール中」とみなす(動きが 0.15 秒止まったら終わり)
private struct ScrollProbe: ViewModifier {
    @Binding var scrolling: Bool
    @State private var settle: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { g in
                Color.clear.preference(key: ScrollTopKey.self, value: g.frame(in: .global).minY.rounded())
            })
            .onPreferenceChange(ScrollTopKey.self) { _ in
                if !scrolling { scrolling = true }
                settle?.cancel()
                settle = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    if !Task.isCancelled { scrolling = false }
                }
            }
    }
}

extension View {
    /// ScrollView 本体に付ける(iOS 18 以降の標準の通知。`onScrollPhaseChange` は iOS 18 SDK=Xcode 16 以降でだけ存在する)
    @ViewBuilder func trackListScrolling(_ scrolling: Binding<Bool>) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) {
            self.onScrollPhaseChange { _, phase in
                if scrolling.wrappedValue != phase.isScrolling { scrolling.wrappedValue = phase.isScrolling }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// ScrollView の中身に付ける(iOS 17 用。18 以降では何もしない)
    @ViewBuilder func trackListScrollingFallback(_ scrolling: Binding<Bool>) -> some View {
        #if compiler(>=6.0)
        if #available(iOS 18.0, *) { self } else { self.modifier(ScrollProbe(scrolling: scrolling)) }
        #else
        self.modifier(ScrollProbe(scrolling: scrolling))
        #endif
    }
}

/// ミニプレビューの計算。ステージの最初の数秒だけを、ゲーム本体と同じ計算で、くり返し流す。
/// ボスの段階が変わる・覚醒する・次の場面へ進むところは見せない(サプライズを守る)ので、そこで最初に戻る
final class MiniStageEngine {
    let stage: Stage
    private(set) var sim: Simulation
    /// 頭出しした状態(作者が決めた開始秒。ループで戻るのはここ)
    private var origin: Simulation
    /// くり返す終わりの時刻(秒)= 開始秒 + 4〜8秒(ステージの長さの30%)
    private let endT: Double
    private var last: Date?
    private var carry = 0.0

    init(stage: Stage) {
        self.stage = stage
        let o = MiniStageEngine.cued(stage)
        origin = o
        sim = o
        let d = Double(stage.durationSec)
        let window = d > 0 ? min(8, max(4, d * 0.3)) : 8
        endT = o.t + window
    }

    /// 1ティック進める(見えない自機を、1秒ごとに左右へゆっくり動かす。自機狙いの弾が向きを変えるように)
    private static func tick(_ s: inout Simulation) {
        let dx: Int8 = (s.tick / 120) % 2 == 0 ? 2 : -2
        s.step(Move(dx: dx, dy: 0))
    }

    /// 場面・段階が変わった(見せてはいけない)か、終わったか
    private static func crossed(_ s: Simulation) -> Bool { s.outcome != .playing || s.waveIndex > 0 || s.phase > 1 }

    /// 最初から、作者が決めた開始秒まで進めた状態。READY の間は飛ばす。
    /// 開始秒より前に、ボスの段階変化・覚醒・次の場面が来るときは、その直前で止める(サプライズを守る)
    private static func cued(_ stage: Stage) -> Simulation {
        var s = Simulation(stage: stage)
        s.invincible = true
        while s.t < 0 && s.outcome == .playing { s.step(.zero) }
        let target = Double(stage.effectivePreviewStart)
        while s.t < target {
            var next = s
            tick(&next)
            if crossed(next) { break }
            s = next
        }
        return s
    }

    func restart() {
        sim = origin
        last = nil
        carry = 0
    }

    /// 止める(次に動かしたとき、止まっていた時間は進めない)
    func pause() { last = nil }

    func advance(to now: Date) {
        let dt = min(0.1, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        carry += dt
        let step = DanmakuConfig.step
        while carry >= step {
            carry -= step
            MiniStageEngine.tick(&sim)
            if MiniStageEngine.crossed(sim) || sim.t >= endT {
                restart()
                last = now
                return
            }
        }
    }
}

/// 世界のステージ一覧の左に出す、動く小さなプレビュー(自機・当たり判定なし。弾は大きめに描く)。
/// 画面の上側(360×360)を切り取って見せる
struct StageMiniPreview: View {
    let stage: Stage
    /// 動かすか(画面に映っていて、スクロール中でない)
    let playing: Bool
    /// 画面に映っているか(映らなくなったら、最初に戻す)
    let visible: Bool
    var size: CGFloat = 56
    /// 弾を実際より大きく描く倍率(小さい枠でもつぶれないように。大きく出すときは小さめ)
    var boost: CGFloat = 1.6

    private final class Holder { var engine: MiniStageEngine? }
    @State private var holder = Holder()

    var body: some View {
        let skin = Skin.of(stage.lookBullets)
        let bg = Skin.of(stage.lookBackground).background
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing)) { timeline in
            Canvas { ctx, sz in
                if holder.engine?.stage != stage { holder.engine = MiniStageEngine(stage: stage) }
                guard let engine = holder.engine else { return }
                if playing { engine.advance(to: timeline.date) } else { engine.pause() }
                let s = sz.width / DanmakuConfig.width
                Self.draw(&ctx, sim: engine.sim, skin: skin, scale: s, boost: boost, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .background(Color(bg))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.21))
        .overlay(RoundedRectangle(cornerRadius: size * 0.21).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .onChange(of: visible) { _, v in if !v { holder.engine?.restart() } }
        .accessibilityHidden(true)
    }

    private static func draw(_ ctx: inout GraphicsContext, sim: Simulation, skin: Skin, scale s: CGFloat, boost: CGFloat, time: Double) {
        if sim.isBoss {
            let p = sim.bossPosition
            let c = CGPoint(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s)
            if let ch = sim.bossCharacter, let art = BossSprites.art(ch, awakened: false) {
                let w = art.size.width * s * 1.3, h = art.size.height * s * 1.3
                ctx.draw(Image(uiImage: art.still).interpolation(.none), in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            } else {
                let side = EnemyArt.bossPoints(size: sim.bossSizeIndex) * s * 1.3
                ctx.draw(Image(uiImage: EnemyArt.bossImage(look: sim.bossLookIndex, size: sim.bossSizeIndex, flash: false)),
                         in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
            }
        }
        let colors = skin.bulletColors
        for b in sim.bullets {
            let color = Color(colors[min(max(b.color, 0), colors.count - 1)])
            if b.isBeam { ctx.drawBeam(b, color: color, scale: s); continue }
            if b.isBlast { ctx.drawBlast(b, color: color, scale: s, time: time); continue }
            // 小さい枠でもつぶれないよう、実際より大きめに描く
            let base: CGFloat = b.isGiant ? CGFloat(DanmakuConfig.giantDrawRadius) : CGFloat(max(4, b.radius + 2))
            let r = max(1.8, base * s * boost)
            ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(b.x) * s - r, y: CGFloat(b.y) * s - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }
}

/// 「プレビューなし」のステージの、一覧の左の枠(ネタバレ防止)。中身は見せない
struct SpoilerTile: View {
    var size: CGFloat = 56
    var body: some View {
        VStack(spacing: 2) {
            Text("？？？").font(.system(size: size * 0.26, weight: .heavy, design: .rounded))
            Text("world.preview.spoiler").font(.system(size: size * 0.13, weight: .bold, design: .rounded))
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 3)
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.21))
        .overlay(RoundedRectangle(cornerRadius: size * 0.21).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("world.preview.spoiler"))
    }
}

/// 一覧のセルを長押ししている間だけ出す、大きなプレビュー(指を離すと消える)
struct StageHoldPreview: View {
    let stage: RemoteStage
    var body: some View {
        let side = min(UIScreen.main.bounds.width - 48, 340)
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
            VStack(spacing: 12) {
                StageMiniPreview(stage: stage.stage, playing: true, visible: true, size: side, boost: 1.15)
                    .shadow(color: .black.opacity(0.5), radius: 16)
                Text(stage.name).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.center).padding(.horizontal, 24)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
        .accessibilityHidden(true)
    }
}

/// 1行に収まらないタイトルを、横に流して最後まで見せる。
/// 先頭で2秒止まる → 一定の速さで末尾まで流れる → 末尾で1秒止まる → 先頭へパッと戻る、をくり返す。
/// 速さはタイトルの長さによらず同じ。収まるタイトルは動かさない
struct MarqueeTitle: View {
    let text: String
    let font: Font
    /// 動かすか(画面に映っていて、スクロール中でない)
    let playing: Bool
    /// 画面に映っているか(映らなくなったら、先頭に戻す)
    let visible: Bool

    static let speed: CGFloat = 30
    static let holdStart = 2.0
    static let holdEnd = 1.0

    private final class Clock {
        var elapsed = 0.0
        var last: Date?
        func tick(_ now: Date, running: Bool) -> Double {
            if running { elapsed += min(0.1, last.map { now.timeIntervalSince($0) } ?? 0); last = now } else { last = nil }
            return elapsed
        }
        func reset() { elapsed = 0; last = nil }
    }

    private struct TextWidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }
    private struct BoxWidthKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
    }

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var clock = Clock()

    var body: some View {
        let overflow = max(0, textWidth - boxWidth)
        let moving = playing && overflow > 0.5
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moving)) { timeline in
            Text(text).font(font).lineLimit(1).fixedSize()
                .background(GeometryReader { g in Color.clear.preference(key: TextWidthKey.self, value: g.size.width) })
                .offset(x: -Self.offset(elapsed: clock.tick(timeline.date, running: moving), overflow: overflow))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(GeometryReader { g in Color.clear.preference(key: BoxWidthKey.self, value: g.size.width) })
        .clipped()
        .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
        .onPreferenceChange(BoxWidthKey.self) { boxWidth = $0 }
        .onChange(of: visible) { _, v in if !v { clock.reset() } }
        .onChange(of: text) { clock.reset() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }

    /// 経過時間から、左へずらす量を出す
    static func offset(elapsed: Double, overflow: CGFloat) -> CGFloat {
        guard overflow > 0.5 else { return 0 }
        let travel = Double(overflow / speed)
        let cycle = holdStart + travel + holdEnd
        let e = elapsed.truncatingRemainder(dividingBy: cycle)
        if e < holdStart { return 0 }
        return min(overflow, CGFloat(e - holdStart) * speed)
    }
}
