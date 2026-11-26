import SwiftUI
import SpriteKit
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
    /// いま流している発射台の設定(どれか1つでも変わったら、最初からやり直す)
    private var current: Emitter?
    /// ランダムの狙い方の乱数(ゲームと同じく、狙う場所をここから引く)
    private var aimRng = Mulberry32(seed: 7)

    /// ボスの、いまの位置(ステージで決めた動き・位置の指定どおり。ゲームと同じ式)
    private(set) var bossAt = Point(x: 180, y: DanmakuConfig.height * 0.18)

    /// 映っていない間は止める(次に映ったとき、離れていた時間を一度に進めない)
    func pause() { last = nil }

    func advance(to now: Date, emitter m: Emitter, boss: Bool, look: PreviewLook) {
        let character = BossCharacter.of(look: look.bossLook)
        // 設定(パターン・狙い方・数・速さ・向き・色・形など)を変えたら、前の弾と撃つ時刻を捨てて、すぐ新しい設定で撃ち始める。
        // 前は、パターンと狙い方を変えたときだけやり直していたので、数や速さを変えても、古い弾が飛び終わるまで見本が変わらなかった
        if current != m {
            current = m
            t = 0; next = 0; shot = 0; bullets = []; rng = Mulberry32(seed: 1); aimRng = Mulberry32(seed: 7)
        }
        let dt = min(0.05, last.map { now.timeIntervalSince($0) } ?? 0)
        last = now
        t += dt
        player = Point(x: 180 + sin(t * 0.9) * 90, y: PreviewEngine.height - 40)
        let atBoss = boss && !m.firesFromPoint
        // ボスは、ステージで決めた動き・位置のとおりに動きながら撃つ(ゲームと同じ式)
        bossAt = look.bossPoint(t: t)
        let cx = atBoss ? bossAt.x : m.x * DanmakuConfig.width
        let cy = atBoss ? bossAt.y : m.y * DanmakuConfig.height
        // キャラクターのボスの大きさに合わせて、技の出る場所を広げる・縮める(ゲームと同じ)
        if character != nil { Emit.anchorScale = look.characterScale }
        defer { Emit.anchorScale = 1 }
        while t >= next {
            let before = bullets.count
            // ゲームと同じ計算で、狙い方に合わせて撃つ
            Simulation.emitAimed(m, shot: shot, cx: cx, cy: cy, px: player.x, py: player.y, aimRng: &aimRng, rng: &rng, into: &bullets)
            if let sh = m.sh { for j in before..<bullets.count { bullets[j].look = UInt8(sh) } }
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
    /// 画面の大きさ(見本が映っているかの判定に使う。少し外まで含めて、出てくる直前から動かす)
    @MainActor static var screenBounds: CGRect {
        let b = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.bounds ?? CGRect(x: 0, y: 0, width: 430, height: 932)
        return b.insetBy(dx: 0, dy: -80)
    }
    let emitter: Emitter
    let isBoss: Bool
    let look: PreviewLook
    @State private var engine = PreviewEngine()
    @EnvironmentObject private var cosmetics: CosmeticsStore

    var body: some View {
        if isBoss, BossCharacter.of(look: look.bossLook) == .dragon, emitter.t.bossCharacter == .dragon {
            // 竜王の技は、ゲーム画面そのもので見せる(絵・炎・範囲攻撃・弾・背景・速さがゲームと同じ)
            DragonMovePreview(emitter: emitter, look: look)
        } else {
            patternPreview
        }
    }

    @ViewBuilder private var patternPreview: some View {
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
        // 画面に映っていない見本は、計算も描画もしない(連戦で発射台が多いと、画面の外の見本まで動いて重くなっていた)
        Color.clear
        .aspectRatio(DanmakuConfig.width / PreviewEngine.height, contentMode: .fit)
        .overlay(GeometryReader { geo in
        // 60 コマまで(120Hz の画面で倍の回数を描かない)。画面から外れたカードは止める
        VisibleTimeline(interval: 1.0 / 60) { timeline in
            let onScreen = geo.frame(in: .global).intersects(EmitterPreview.screenBounds)
            Canvas { ctx, size in
                guard onScreen else {
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(bg.background)))
                    engine.pause()
                    return
                }
                engine.advance(to: timeline.date, emitter: emitter, boss: isBoss, look: look)
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
                                   time: timeline.date.timeIntervalSinceReferenceDate, custom: customBullet, theme: look.bullets)
                }
            }
        }
        })
        .clipShape(PixelRect(cornerRadius: 10))
        .accessibilityHidden(true)
    }

    private func drawSource(_ ctx: inout GraphicsContext, skin: Skin, bossImage: UIImage?) {
        if isBoss {
            // 専用の絵を持つボスは、実際のゲームと同じ位置・大きさで描く
            if let c = BossCharacter.of(look: look.bossLook), let art = BossSprites.art(c, awakened: false) {
                let p = engine.bossAt
                let k = look.characterScale
                ctx.draw(Image(uiImage: art.still).interpolation(.none),
                         in: CGRect(x: p.x - art.size.width * k / 2, y: p.y - art.size.height * k / 2, width: art.size.width * k, height: art.size.height * k))
            } else {
                // ボスの大きさは、当たる範囲と同じ比率(小・中・大)
                let side = EnemyArt.bossPoints(size: look.bossSize)
                let p = engine.bossAt
                let rect = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
                if let bossImage { ctx.draw(Image(uiImage: bossImage), in: rect) }
                else { ctx.draw(Image(uiImage: EnemyArt.bossImage(look: look.bossLook, size: look.bossSize, flash: false)), in: rect) }
            }
        }
        if let mooks = look.mooks, (!isBoss || emitter.firesFromPoint) && !emitter.isPositionless {
            let side = EnemyArt.mookPoints(size: mooks)
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            ctx.draw(Image(uiImage: EnemyArt.mookImage(look: look.mookLook, size: mooks)), in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
        }
        if (!isBoss || emitter.firesFromPoint) && !emitter.isPositionless {
            let c = CGPoint(x: emitter.x * DanmakuConfig.width, y: emitter.y * DanmakuConfig.height)
            var p = Path()
            p.move(to: CGPoint(x: c.x, y: c.y - 8)); p.addLine(to: CGPoint(x: c.x + 8, y: c.y))
            p.addLine(to: CGPoint(x: c.x, y: c.y + 8)); p.addLine(to: CGPoint(x: c.x - 8, y: c.y)); p.closeSubpath()
            ctx.stroke(p, with: .color(Color(skin.bulletColors[min(max(emitter.k, 0), skin.bulletColors.count - 1)])), lineWidth: 2)
        }
    }

}

/// 竜王の技の見本。ゲーム画面(GameScene)を、見本用(自機は当たらない・効果音なし・指で動かさない)にして小さく動かす。
/// この技を出す段階の姿で、この技だけを置いたボス戦。終わったら(または見た目・間隔を変えたら)最初から
/// 竜王の技の見本は、ゲーム画面を丸ごと動かすので重い(絵も大きい)。連戦などで竜王の技の発射台がいくつも並ぶと、
/// 見本が同時にいくつも動いて、古い端末ではメモリが足りずにアプリが落ちることがあった。動かすのは、いちばん最近
/// 画面に出た・設定を変えた1つだけにする(ほかは技の絵を止めて出す)
@MainActor final class DragonPreviewHub: ObservableObject {
    static let shared = DragonPreviewHub()
    @Published private(set) var active: UUID?
    func claim(_ id: UUID) { if active != id { active = id } }
    func release(_ id: UUID) { if active == id { active = nil } }
}

private struct DragonMovePreview: View {
    let emitter: Emitter
    let look: PreviewLook
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @ObservedObject private var hub = DragonPreviewHub.shared
    @State private var id = UUID()
    @State private var scene: GameScene?
    @State private var built: Spec?

    /// 見本を作るのに使う値の組。変わったら、この値そのものから作り直す。
    /// (onChange の中から self.emitter を読むと、1つ前の画面の値になることがあり、選んだ技の1つ前の技が見本に出ていた)
    struct Spec: Equatable {
        var emitter: Emitter
        var look: PreviewLook
        /// この技を出すいちばん早い段階の姿(作者が段階ごとに選んだもの。選んでいなければ、ゲームと同じく通常。竜王は覚醒を使わない)
        var form: Int {
            let p = Emitter.phases(of: emitter.ph).min() ?? 1
            if let f = look.forms, p - 1 < f.count { return min(max(f[p - 1], 0), 3) }
            return 0
        }
    }
    private var spec: Spec { Spec(emitter: emitter, look: look) }

    var body: some View {
        ZStack {
            if let scene, hub.active == id {
                // SpriteView は最初に渡したシーンを持ち続けるので、作り直したら見た目ごと差し替える
                SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                    .id(ObjectIdentifier(scene))
            } else {
                // 動いていない見本: 技の絵(ショップ・パターンの一覧と同じ絵)を止めて出す
                Color(Skin.of(look.background).background)
                if let img = BossPatternIcon.image(emitter.t) {
                    Image(uiImage: img).resizable().interpolation(.none).scaledToFit().padding(8)
                }
            }
        }
        .aspectRatio(DanmakuConfig.width / DanmakuConfig.height, contentMode: .fit)
        .frame(maxHeight: 380)
        .clipShape(PixelRect(cornerRadius: 10))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear { hub.claim(id); if scene == nil || built != spec { rebuild(spec) } }
        .onChange(of: spec) { hub.claim(id); rebuild($0) }
        // ほかの見本が動き出したら、このゲーム画面は片付ける(メモリを空ける)。また動かすときに作り直す
        .onChange(of: hub.active) { a in if a != id { scene = nil; built = nil } }
        .onDisappear { hub.release(id); scene = nil; built = nil }
    }

    private func rebuild(_ sp: Spec) {
        guard hub.active == id else { scene = nil; built = nil; return }
        var e = sp.emitter
        e.s = 0; e.e = 60; e.ph = 0
        let look = sp.look
        var st = Stage(name: "", mode: .boss, durationSec: 60, bossHp: 9999, bossMove: look.bossMove, emitters: [e], lifeMode: .lives, lifeCount: 9,
                       bossSize: look.bossSize, bossLook: BossCharacter.dragon.rawValue)
        st.bossX = look.bossX; st.bossY = look.bossY
        st.forms = [sp.form, sp.form, sp.form]
        var lo = Loadout()
        lo.bullets = look.bullets; lo.background = look.background; lo.ship = look.ship
        let own = cosmetics.ownership.hasCustomImages
        lo.customBullet = own && look.customs.bullet
        lo.customShip = own && look.customs.ship
        let s = GameScene(stage: st.sanitized(), loadout: lo, preview: true)
        // 時間が来た・ボスを倒したら、同じ見本を最初から(そのあいだに設定が変わっていたら、何もしない)
        let current = $built
        s.onFinish = { _, _ in DispatchQueue.main.async { if current.wrappedValue == sp && DragonPreviewHub.shared.active == id { rebuild(sp) } } }
        scene = s
        built = sp
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
            width = b.radius > 0 ? CGFloat(b.radius * 2) : 18
            coreWidth = width / 3
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
        // 黒っぽい暗い色の予告線は、ゲームと同じく明るい灰色で出す
        let color = !look.firing && Skin.isDark(UIColor(color)) ? Color(white: 0.8) : color
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
    func drawBullet(_ b: Bullet, images: [UIImage], boomerangs: [UIImage], colors: [UIColor], scale s: CGFloat = 1, time: Double, custom: UIImage? = nil, sizeBoost: CGFloat = 1, theme: Theme = .classic) {
        let i = min(max(b.color, 0), colors.count - 1)
        let color = Color(colors[i])
        if b.isBeam { drawBeam(b, color: color, scale: s); return }
        if b.isBlast { drawBlast(b, color: color, scale: s, time: time); return }
        let c = CGPoint(x: b.x * s, y: b.y * s)
        if (b.isDormant && !b.dormantGlow) || b.blinkHidden { return }   // 待機中の弾・暗転の印・瞬間移動弾が飛ぶ直前は見えない
        if let art = BulletArt.image(look: b.look) {
            // ボス専用の弾: ドット絵を、進む向きへ回して描く(最近傍補間)
            var g = self
            if b.dormantGlow { g.opacity = 0.25 }
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(BulletArt.rotation(b)))
            let drawSize = BulletArt.drawSize(b)
            let w = drawSize.width * s * sizeBoost, h = drawSize.height * s * sizeBoost
            g.draw(Image(uiImage: art).interpolation(.none), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            return
        }
        if b.drawsAsBar {
            // 「棒」(細長いカプセル): ゲームと同じ絵を、進む向きへ回して描く
            let imgs = SpriteFactory.barImages(theme)
            let w: CGFloat = 17 * s * sizeBoost, h: CGFloat = 8 * s * sizeBoost
            var g = self
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(atan2(b.vy, b.vx)))
            g.draw(Image(uiImage: imgs[min(i, imgs.count - 1)]), in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            return
        }
        if b.drawsAsBoomerang {
            var g = self
            g.translateBy(x: c.x, y: c.y)
            g.rotate(by: .radians(time * 14))
            g.draw(Image(uiImage: boomerangs[min(i, boomerangs.count - 1)]), in: CGRect(x: -8 * s * sizeBoost, y: -8 * s * sizeBoost, width: 16 * s * sizeBoost, height: 16 * s * sizeBoost))
            return
        }
        let r: CGFloat = b.isGiant ? DanmakuConfig.giantDrawRadius : max(6, b.radius + 4)
        let rr = max(r * s * sizeBoost, 1.8)
        let rect = CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)
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
        // 実際のゲームと同じく、ランダムの狙い方は今月の並びで見せる
        var s = Simulation(stage: stage, month: Simulation.month(of: Date()))
        s.invincible = true
        while s.t < 0 && s.outcome == .playing { s.step(.zero) }
        let target = Double(stage.effectivePreviewStart)
        // 開始秒ちょうどは、撃った直後で弾がほとんど写らない(一覧の画像が背景だけに見えた)。
        // 少なくとも leadSec 秒進め、弾がそろうまで(最大 maxLeadSec 秒)さらに進める。
        // 撃ち始めが遅いステージも、最初の弾が出るところから流れる(弾が出る前に最初へ戻り続けていた)
        while s.t < target + maxLeadSec {
            if s.t >= target + leadSec && s.bullets.count >= enoughBullets { break }
            var next = s
            tick(&next)
            if crossed(next) { break }
            s = next
        }
        return s
    }

    /// 頭出しで、開始秒から最低限進める秒数・弾がそろったとみなす数・最大で進める秒数
    static let leadSec = 1.5
    static let enoughBullets = 8
    static let maxLeadSec = 10.0

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
/// 作者が決めた見せ場の1枚(静止画)。一覧に出す画像を作るときと、同じ見た目で使う。動くプレビューと同じ描き方(同じ計算・同じ絵)
struct StageStillView: View {
    let stage: Stage
    var size: CGFloat = 168
    var boost: CGFloat = 1.4

    var body: some View {
        let skin = Skin.of(stage.lookBullets)
        let bg = Skin.of(stage.lookBackground).background
        Canvas { ctx, sz in
            let engine = MiniStageEngine(stage: stage)
            StageMiniPreview.draw(&ctx, sim: engine.sim, skin: skin, theme: stage.lookBullets, scale: sz.width / DanmakuConfig.width, boost: boost, time: 0)
        }
        .frame(width: size, height: size)
        .background(Color(bg))
    }

    /// 送る PNG(168×168 を 2 倍で描く。ふつう 10〜30KB)
    @MainActor static func png(for stage: Stage) -> Data? {
        compatRenderImage(StageStillView(stage: stage), scale: 2)?.pngData()
    }
}

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
    /// 同時に動かす数を絞る(一覧に映っている行が全部、ゲームと同じ計算を毎秒 120 回していて重かった)。枠をもらえない行は止まった絵
    @ObservedObject private var gate = MiniPreviewGate.shared
    @State private var token = UUID()
    private var running: Bool { playing && gate.allows(token) }

    var body: some View {
        let skin = Skin.of(stage.lookBullets)
        let bg = Skin.of(stage.lookBackground).background
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !running)) { timeline in
            Canvas { ctx, sz in
                if holder.engine?.stage != stage { holder.engine = MiniStageEngine(stage: stage) }
                guard let engine = holder.engine else { return }
                if running { engine.advance(to: timeline.date) } else { engine.pause() }
                let s = sz.width / DanmakuConfig.width
                Self.draw(&ctx, sim: engine.sim, skin: skin, theme: stage.lookBullets, scale: s, boost: boost, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .frame(width: size, height: size)
        .background(Color(bg))
        .clipShape(PixelRect(cornerRadius: size * 0.21))
        .overlay(PixelRect(cornerRadius: size * 0.21).stroke(GameStyle.edge, lineWidth: 1))
        .onChange(of: visible) { v in if !v { holder.engine?.restart() } }
        .onAppear { gate.set(token, active: playing) }
        .onChange(of: playing) { gate.set(token, active: $0) }
        .onDisappear { gate.set(token, active: false) }
        .accessibilityHidden(true)
    }

    fileprivate static func draw(_ ctx: inout GraphicsContext, sim: Simulation, skin: Skin, theme: Theme, scale s: CGFloat, boost: CGFloat, time: Double) {
        if sim.isBoss {
            let p = sim.bossPosition
            let c = CGPoint(x: CGFloat(p.x) * s, y: CGFloat(p.y) * s)
            if let ch = sim.bossCharacter, let art = BossSprites.art(ch, awakened: false) {
                let w = art.size.width * s * 1.3 * sim.bossScale, h = art.size.height * s * 1.3 * sim.bossScale
                ctx.draw(Image(uiImage: art.still).interpolation(.none), in: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h))
            } else {
                let side = EnemyArt.bossPoints(size: sim.bossSizeIndex) * s * 1.3
                ctx.draw(Image(uiImage: EnemyArt.bossImage(look: sim.bossLookIndex, size: sim.bossSizeIndex, flash: false)),
                         in: CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
            }
        }
        let colors = skin.bulletColors
        // ゲーム本体と同じ弾の絵(白い芯・テーマごとの形)を使う。小さい枠でもつぶれないよう、少し大きめに描く
        let images = SpriteFactory.bulletImages(theme), boomerangs = SpriteFactory.boomerangImages(theme)
        for b in sim.bullets {
            ctx.drawBullet(b, images: images, boomerangs: boomerangs, colors: colors, scale: s, time: time, sizeBoost: boost, theme: theme)
        }
    }
}

/// 「プレビューなし」のステージの、一覧の左の枠(ネタバレ防止)。中身は見せない
struct SpoilerTile: View {
    var size: CGFloat = 56
    var body: some View {
        VStack(spacing: 2) {
            Text("？？？").font(.system(size: size * 0.26, weight: .heavy))
            Text("world.preview.spoiler").font(.system(size: size * 0.13, weight: .bold))
                .lineLimit(2).minimumScaleFactor(0.6).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 3)
        .frame(width: size, height: size)
        .background(GameStyle.panelHi)
        .clipShape(PixelRect(cornerRadius: size * 0.21))
        .overlay(PixelRect(cornerRadius: size * 0.21).stroke(GameStyle.edge, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("world.preview.spoiler"))
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
        // 幅は親に合わせる(長いタイトルが自分の幅を主張して、行を横に押し広げないよう、文字は overlay で動かす)
        Text(" ").font(font).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !moving)) { timeline in
                    Text(text).font(font).lineLimit(1).fixedSize()
                        .background(GeometryReader { g in Color.clear.preference(key: TextWidthKey.self, value: g.size.width) })
                        .offset(x: -Self.offset(elapsed: clock.tick(timeline.date, running: moving), overflow: overflow))
                }
            }
        .background(GeometryReader { g in Color.clear.preference(key: BoxWidthKey.self, value: g.size.width) })
        .clipped()
        .onPreferenceChange(TextWidthKey.self) { textWidth = $0 }
        .onPreferenceChange(BoxWidthKey.self) { boxWidth = $0 }
        .onChange(of: visible) { v in if !v { clock.reset() } }
        .onChange(of: text) { _ in clock.reset() }
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


/// 一覧の動く見本を、同時にいくつまで動かすか(先に頼んだ順)。抜けたら、次に待っている見本が動き出す
@MainActor final class MiniPreviewGate: ObservableObject {
    static let shared = MiniPreviewGate()
    static let limit = 3
    @Published private var order: [UUID] = []
    func allows(_ id: UUID) -> Bool { order.prefix(Self.limit).contains(id) }
    func set(_ id: UUID, active: Bool) {
        if active { if !order.contains(id) { order.append(id) } } else { order.removeAll { $0 == id } }
    }
}
