import SwiftUI
import UIKit
import DanmakuCore

// 編集画面で使う、ゲーム専用の部品(標準のピッカーやスライダーの代わり)

enum GameStyle {
    static let panel = Color(red: 0.11, green: 0.09, blue: 0.25)
    static let edge = Color.white.opacity(0.12)
    static let accent = LinearGradient(colors: [Color(Palette.pink), Color(UIColor(hex: 0xFF8A5C))], startPoint: .leading, endPoint: .trailing)
    static let cyan = LinearGradient(colors: [Color(UIColor(hex: 0x5CE1E6)), Color(UIColor(hex: 0x5C8AFF))], startPoint: .leading, endPoint: .trailing)
    static let gold = LinearGradient(colors: [Color(Palette.gold), Color(UIColor(hex: 0xFF9F5C))], startPoint: .leading, endPoint: .trailing)
}

func gameTap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    Task { @MainActor in AudioManager.shared.se(.tap) }
}

/// 押すとぷにっと縮んで、ぽんと戻るボタン
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

/// 大きなアクションボタン(テストプレイ・投稿など)
struct GameActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let fill: LinearGradient
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button { gameTap(); action() } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 17, weight: .heavy))
                Text(title).font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .background(fill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.35), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

/// 見出しつきのパネル
struct GamePanel<Content: View>: View {
    var title: LocalizedStringKey?
    var tint: Color = Color(Palette.gold)
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 2).fill(tint).frame(width: 4, height: 16)
                    Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(GameStyle.edge))
    }
}

/// 選べる丸いチップ(選ぶと色がついて光る)
struct Chip: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .heavy, design: .rounded))
            .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.75))
            .padding(.vertical, 8).padding(.horizontal, 14)
            .background(selected ? AnyShapeStyle(GameStyle.accent) : AnyShapeStyle(Color.white.opacity(0.08)), in: Capsule())
            .overlay(Capsule().stroke(selected ? Color.white.opacity(0.65) : Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: selected ? Color(Palette.pink).opacity(0.55) : .clear, radius: 7)
    }
}

struct ChipGrid<T: Hashable>: View {
    let items: [(T, String)]
    @Binding var selection: T
    var idPrefix = "chip"
    var minimum: CGFloat = 74

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimum), spacing: 8, alignment: .leading)], alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                Button {
                    gameTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selection = item.0 }
                } label: {
                    Chip(title: item.1, selected: selection == item.0)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityAddTraits(selection == item.0 ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(String(describing: item.0))")
            }
        }
    }
}

/// 弾の形のつまみがついたスライダー
struct GameSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geo in
            let w = max(1, geo.size.width - 24)
            let span = range.upperBound - range.lowerBound
            let frac = span > 0 ? (value - range.lowerBound) / span : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 8).padding(.horizontal, 12)
                Capsule().fill(GameStyle.accent).frame(width: max(8, w * frac + 12), height: 8).padding(.leading, 12)
                ZStack {
                    Circle().fill(Color(Palette.pink))
                    Circle().fill(Color.white).frame(width: 10, height: 10)
                }
                .frame(width: 24, height: 24)
                .shadow(color: Color(Palette.pink).opacity(0.7), radius: 6)
                .offset(x: w * frac)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { g in
                let f = min(1, max(0, (g.location.x - 12) / w))
                var v = range.lowerBound + f * span
                v = range.lowerBound + ((v - range.lowerBound) / step).rounded() * step
                v = min(range.upperBound, max(range.lowerBound, v))
                if v != value { value = v; UISelectionFeedbackGenerator().selectionChanged() }
            })
        }
        .frame(height: 30)
        .accessibilityElement()
        .accessibilityValue(Text(String(value)))
        .accessibilityAdjustableAction { dir in
            let next = dir == .increment ? value + step : value - step
            value = min(range.upperBound, max(range.lowerBound, next))
        }
    }
}

/// 大きな数字の「−/+」
struct CountStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    var idPrefix = "stepper"

    var body: some View {
        HStack(spacing: 14) {
            roundButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                .accessibilityIdentifier("\(idPrefix).minus")
            Text("\(value)")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Color(Palette.text))
                .frame(minWidth: 64)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
            roundButton("plus", enabled: value < range.upperBound) { value += 1 }
                .accessibilityIdentifier("\(idPrefix).plus")
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(GameStyle.accent, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1))
                .shadow(color: Color(Palette.pink).opacity(0.5), radius: 6)
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.35)
        .disabled(!enabled)
    }
}

/// 自機の耐久の見本: ライフ制はハート、HP制は目盛り
struct LifePreview: View {
    let mode: LifeMode
    let count: Int

    /// 1行に並べる数。多いときは折り返して、画面の幅からはみ出さないようにする
    private var perRow: Int { mode == .lives ? 8 : 12 }
    private var rows: [Int] {
        stride(from: 0, to: max(count, 0), by: perRow).map { min(perRow, count - $0) }
    }

    var body: some View {
        switch mode {
        case .lives:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, n in
                    HStack(spacing: 6) {
                        ForEach(0..<n, id: \.self) { _ in
                            Image(systemName: "heart.fill").font(.system(size: 22)).foregroundStyle(Color(Palette.pink))
                                .shadow(color: Color(Palette.pink).opacity(0.7), radius: 5)
                        }
                    }
                }
            }
        case .hp:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, n in
                    HStack(spacing: 2) {
                        ForEach(0..<n, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 2).fill(Color(Palette.bullets[4])).frame(width: 9, height: 16)
                        }
                    }
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

// MARK: モードのカード

struct ModeCards: View {
    let mode: Mode
    let onSelect: (Mode) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
            card(.survive, "editor.mode.survive", "editor.mode.survive.sub") {
                ZStack {
                    GameShipShape().fill(Color(UIColor(hex: 0x5CE1E6)))
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                }.frame(width: 24, height: 28)
            }
            card(.boss, "editor.mode.boss", "editor.mode.boss.sub") {
                GameBossShape().fill(Color(Palette.pink), style: FillStyle(eoFill: true)).frame(width: 34, height: 34)
            }
            card(.sequence, "editor.mode.sequence", "editor.mode.sequence.sub") {
                ZStack {
                    GameBossShape().fill(Color(Palette.bullets[3]), style: FillStyle(eoFill: true)).frame(width: 30, height: 30).offset(x: 6, y: 4)
                    GameBossShape().fill(Color(Palette.pink), style: FillStyle(eoFill: true)).frame(width: 24, height: 24).offset(x: -8, y: -3)
                }.frame(width: 40, height: 34)
            }
            card(.damage, "editor.mode.damage", "editor.mode.damage.sub") {
                ZStack {
                    GameBossShape().fill(Color(Palette.gold), style: FillStyle(eoFill: true)).frame(width: 34, height: 34)
                    Image(systemName: "bolt.fill").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(Palette.background))
                }
            }
        }
    }

    private func card<Icon: View>(_ m: Mode, _ title: LocalizedStringKey, _ sub: LocalizedStringKey, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = mode == m
        return Button {
            gameTap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { onSelect(m) }
        } label: {
            VStack(spacing: 6) {
                icon().frame(height: 36)
                Text(title).font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                Text(sub).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(selected ? AnyShapeStyle(LinearGradient(colors: [Color(Palette.gold).opacity(0.28), Color(Palette.pink).opacity(0.18)], startPoint: .top, endPoint: .bottom)) : AnyShapeStyle(GameStyle.panel),
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? Color(Palette.gold) : GameStyle.edge, lineWidth: selected ? 2 : 1))
            .shadow(color: selected ? Color(Palette.gold).opacity(0.45) : .clear, radius: 8)
            .scaleEffect(selected ? 1.03 : 1)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("editor.mode.\(m.rawValue)")
    }
}

// MARK: ボスの動き

struct BossMoveCards: View {
    @Binding var move: Int
    private static let motions: [(a: Double, w: Double)] = [(0, 0), (0.25, 0.6), (0.32, 1.3)]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { i in
                let selected = move == i
                Button {
                    gameTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { move = i }
                } label: {
                    VStack(spacing: 4) {
                        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                            Canvas { ctx, size in
                                let t = tl.date.timeIntervalSinceReferenceDate
                                let m = BossMoveCards.motions[i]
                                let cx = size.width * (0.5 + m.a * sin(t * m.w * 1.6))
                                let rect = CGRect(x: cx - 12, y: size.height / 2 - 12, width: 24, height: 24)
                                // 動く範囲の線
                                let lo = size.width * (0.5 - m.a), hi = size.width * (0.5 + m.a)
                                ctx.stroke(Path { p in p.move(to: CGPoint(x: lo, y: size.height / 2)); p.addLine(to: CGPoint(x: hi, y: size.height / 2)) },
                                           with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                                ctx.fill(GameBossShape().path(in: rect), with: .color(Color(Palette.pink)), style: FillStyle(eoFill: true))
                            }
                        }
                        .frame(height: 34)
                        Text(L("editor.boss.move.\(i)")).font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(Palette.text))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 8).padding(.horizontal, 4)
                    .background(selected ? AnyShapeStyle(Color(Palette.pink).opacity(0.2)) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color(Palette.pink) : GameStyle.edge, lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? Color(Palette.pink).opacity(0.45) : .clear, radius: 7)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("editor.boss.move.\(i)")
            }
        }
    }
}

// MARK: パターンの選択

struct PatternTiles: View {
    @Binding var selection: DanmakuCore.Pattern
    let index: Int
    /// 専用の絵を持つボスを選んでいるときは、そのボスだけの技も出す
    var character: BossCharacter? = nil
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showShop = false
    private let keys: [DanmakuCore.Pattern: String] = [
        .ring: "pattern.ring", .spiral: "pattern.spiral", .aim: "pattern.aim", .rain: "pattern.rain", .sweep: "pattern.sweep",
        .sideL: "pattern.sideL", .sideR: "pattern.sideR", .corner: "pattern.corner", .homing: "pattern.homing",
        .flower: "pattern.flower", .star: "pattern.star", .heart: "pattern.heart", .beam: "pattern.beam",
        .cross: "pattern.cross", .accel: "pattern.accel", .bounce: "pattern.bounce",
        .stopgo: "pattern.stopgo", .split: "pattern.split", .timed: "pattern.timed",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let character {
                Text(LocalizedStringKey("editor.pattern.bosssection.\(character.rawValue)")).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                grid(DanmakuCore.Pattern.allCases.filter { $0.bossCharacter == character })
            }
            grid(freePatterns)
            Text("editor.pattern.adsection").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary).padding(.top, 4)
            grid(DanmakuCore.Pattern.ad)
            Text("editor.pattern.pack2section").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary).padding(.top, 4)
            grid(DanmakuCore.Pattern.pack2)
            customSection
        }
        .sheet(isPresented: $showShop) { ShopView() }
    }

    /// 最初から使えるパターン。旧「渦巻き」(spiral)は放射と同じ計算なので出さず、新しい渦巻き(swirl)をその場所に出す
    /// (古いステージで旧渦巻きを選んでいるときだけ、そのまま見えるように残す)
    private var freePatterns: [DanmakuCore.Pattern] {
        var list: [DanmakuCore.Pattern] = []
        for p in DanmakuCore.Pattern.allCases where !p.isAd && !p.isPack2 && p != .custom && p != .swirl && p.bossCharacter == nil {
            if p == .spiral {
                list.append(.swirl)
                if selection == .spiral { list.append(.spiral) }
            } else {
                list.append(p)
            }
        }
        return list
    }

    @ObservedObject private var library = PatternLibrary.shared
    @Binding var emitter: Emitter

    /// 弾幕作成モードで作った弾幕(選ぶと、描いた軌道がこの発射台に入る)
    @ViewBuilder private var customSection: some View {
        if cosmetics.ownership.hasPatternMaker || !library.items.isEmpty {
            Text("editor.pattern.mysection").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary).padding(.top, 4)
            if library.items.isEmpty {
                Text("editor.pattern.mynone").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(library.items) { item in
                    let selected = emitter.t == .custom && emitter.path == item.path
                    Button {
                        gameTap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            emitter.t = .custom; emitter.path = item.path; emitter.c = item.copies; emitter.v = item.speed; emitter.r = 0
                        }
                    } label: {
                        VStack(spacing: 3) {
                            CustomPatternIcon(path: item.path).frame(width: 40, height: 40)
                            Text(item.name).font(.system(size: 10, weight: .heavy, design: .rounded))
                                .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.7)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(selected ? AnyShapeStyle(Color(Palette.pink).opacity(0.22)) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color(Palette.pink) : GameStyle.edge, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(BounceButtonStyle())
                }
            }
        }
    }

    private func grid(_ patterns: [DanmakuCore.Pattern]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
            ForEach(patterns, id: \.self) { p in
                let selected = selection == p
                let locked = !cosmetics.ownership.has(p) && selection != p
                Button {
                    gameTap()
                    if locked { showShop = true; return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selection = p }
                } label: {
                    VStack(spacing: 3) {
                        PatternIcon(pattern: p, selected: selected).frame(width: 40, height: 40)
                        Text(LocalizedStringKey(keys[p] ?? "pattern.\(p.rawValue)")).font(.system(size: 10, weight: .heavy, design: .rounded))
                            .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.7))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(selected ? AnyShapeStyle(Color(Palette.pink).opacity(0.22)) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color(Palette.pink) : GameStyle.edge, lineWidth: selected ? 2 : 1))
                    .shadow(color: selected ? Color(Palette.pink).opacity(0.45) : .clear, radius: 6)
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(Color(Palette.gold))
                                .padding(4).background(Color.black.opacity(0.55), in: Circle()).offset(x: 3, y: -3)
                        }
                    }
                    .opacity(locked ? 0.7 : 1)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("emitter.pattern.\(index).\(p.rawValue)")
            }
        }
    }
}

/// パターンを表す小さな絵
struct PatternIcon: View {
    let pattern: DanmakuCore.Pattern
    let selected: Bool

    /// 広告で解放するパターンの絵の点(0〜1の位置)。初期値で3回撃って、少し進めた弾の並び。パターンごとに最初に1回だけ計算する
    private final class SampleCache: @unchecked Sendable {
        let lock = NSLock()
        var points: [DanmakuCore.Pattern: [CGPoint]] = [:]
    }
    private static let samples = SampleCache()

    static func sample(_ p: DanmakuCore.Pattern) -> [CGPoint] {
        samples.lock.lock(); defer { samples.lock.unlock() }
        if let c = samples.points[p] { return c }
        guard let d = p.recipeDefaults else { return [] }
        let m = Emitter(t: p, x: 0.5, y: 0.15, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 0)
        var rng = Mulberry32(seed: 11)
        var bullets: [Bullet] = []
        let cx = DanmakuConfig.width * 0.5, cy = 50.0
        for k in 0..<3 {
            Emit.emit(m, shot: k, cx: cx, cy: cy, px: cx, py: 300, rng: &rng, into: &bullets)
            // 1回ごとに少し進める(古い弾ほど遠くまで進む)
            for i in 0..<bullets.count { for _ in 0..<6 { _ = bullets[i].advance(dt: 1.0 / 30, width: DanmakuConfig.width, playerX: cx, playerY: 300) } }
        }
        let pts = bullets.compactMap { b -> CGPoint? in
            let x = b.x / DanmakuConfig.width, y = (b.y - 20) / 200
            return (0...1).contains(x) && (0...1).contains(y) ? CGPoint(x: x, y: y) : nil
        }
        samples.points[p] = Array(pts.prefix(90))
        return samples.points[p]!
    }

    var body: some View {
        Canvas { ctx, size in
            let col = selected ? Color(Palette.pink) : Color(Palette.text).opacity(0.55)
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func dot(_ x: Double, _ y: Double, _ r: Double = 2.6) {
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(col))
            }
            let w = size.width, h = size.height
            switch pattern {
            case .ring:
                for i in 0..<10 { let a = Double(i) * .pi / 5; dot(c.x + cos(a) * 14, c.y + sin(a) * 14) }
            case .spiral, .swirl:
                for i in 0..<14 { let a = Double(i) * 0.75, r = 3 + Double(i) * 1.0; dot(c.x + cos(a) * r, c.y + sin(a) * r, 2.2) }
            case .aim:
                dot(c.x, 6, 3.4)
                for i in 0..<3 { let a = Double.pi / 2 + (Double(i) - 1) * 0.35; for k in 1...3 { dot(c.x + cos(a) * Double(k) * 9, 6 + sin(a) * Double(k) * 9, 2) } }
            case .rain:
                for (i, x) in [8.0, 16, 24, 32].enumerated() { dot(x, 8 + Double(i % 2) * 8); dot(x, 24 + Double(i % 2) * 6, 2) }
            case .sweep:
                dot(c.x, 5, 3.4)
                for i in 0..<5 { let a = Double.pi / 2 + (Double(i) - 2) * 0.4; for k in 1...3 { dot(c.x + cos(a) * Double(k) * 9, 5 + sin(a) * Double(k) * 9, 2) } }
            case .sideL:
                for (i, y) in [8.0, 18, 28, 36].enumerated() { for k in 0..<3 { dot(4 + Double(k) * 9 + Double(i % 2) * 4, y, 2.2) } }
            case .sideR:
                for (i, y) in [8.0, 18, 28, 36].enumerated() { for k in 0..<3 { dot(w - 4 - Double(k) * 9 - Double(i % 2) * 4, y, 2.2) } }
            case .flower:
                for i in 0..<20 {
                    let a = Double(i) * .pi / 10
                    let f = 0.4 + 0.6 * abs(cos(2.5 * a))
                    dot(c.x + cos(a) * 17 * f, c.y + sin(a) * 17 * f, 2.2)
                }
            case .star:
                for i in 0..<20 {
                    let a = Double(i) * .pi / 10 - .pi / 2
                    let u = (Double(i) / 4).truncatingRemainder(dividingBy: 1)
                    let f = 0.45 + 0.55 * abs(u - 0.5) * 2
                    dot(c.x + cos(a) * 17 * f, c.y + sin(a) * 17 * f, 2.2)
                }
            case .heart:
                for i in 0..<24 {
                    let a = Double(i) * .pi / 12
                    let q = -a
                    let sq = abs(cos(q)).squareRoot()
                    let rr = (2 - 2 * sin(q) + sin(q) * sq / (sin(q) + 1.4)) / 4
                    let f = 0.15 + 0.85 * max(0, min(1, rr))
                    dot(c.x + cos(a) * 17 * f, c.y + sin(a) * 17 * f, 2.2)
                }
            case .beam:
                dot(c.x, 5, 3.4)
                for k in 1...5 { dot(c.x, 5 + Double(k) * 6.5, 2.2) }
            case .cross:
                for arm in 0..<4 {
                    let a = Double(arm) * .pi / 2
                    for k in 1...3 { dot(c.x + cos(a) * Double(k) * 6, c.y + sin(a) * Double(k) * 6, 2.2) }
                }
                dot(c.x, c.y, 3)
            case .accel:
                dot(c.x, 5, 3.4)
                for k in 1...4 { dot(c.x, 5 + Double(k * k) * 1.9 + 4, 1.6 + Double(k) * 0.35) }
            case .bounce:
                dot(c.x, 5, 3.4)
                let pts: [(Double, Double)] = [(c.x + 1, 11), (c.x - 8, 18), (c.x - 15, 24), (c.x - 8, 30), (c.x + 1, 36)]
                for q in pts { dot(q.0, q.1, 2) }
            case .stopgo:
                dot(c.x, 5, 3.4)
                dot(c.x, 17, 2.2); dot(c.x, 24, 2.2)
                dot(c.x + 9, 31, 2.2); dot(c.x - 9, 31, 2.2)
            case .split:
                dot(c.x, 5, 3.4)
                dot(c.x, 15, 2.6)
                for k in 0..<6 {
                    let a = Double(k) * .pi / 3 + .pi / 6
                    dot(c.x + cos(a) * 11, 28 + sin(a) * 9, 1.8)
                }
            case .timed:
                for k in 0..<10 {
                    let a = Double(k) * .pi / 5
                    dot(c.x + cos(a) * 14, c.y + sin(a) * 14, 2.2)
                }
                dot(c.x, c.y, 3)
            case .homing:
                // 弧を描いて、下の自機へ曲がっていく弾
                dot(c.x, 5, 3.4)
                for k in 1...5 {
                    let t = Double(k) / 5
                    dot(c.x + sin(t * 2.6) * 13 * (1 - t * 0.2), 5 + t * 30, 2.2)
                }
                dot(w - 8, h - 6, 3.0)
            case .corner:
                for (cx, cy, sx, sy) in [(3.0, 3.0, 1.0, 1.0), (w - 3, 3, -1.0, 1.0), (3, h - 3, 1.0, -1.0), (w - 3, h - 3, -1.0, -1.0)] {
                    for k in 0..<3 { dot(cx + sx * Double(k) * 7, cy + sy * Double(k) * 7, 2.2) }
                }
            case .chargeBeam:
                // 発射口から下へ: 細い予告線と、太い光線(白い芯つき)
                dot(c.x, 5, 3.4)
                var thin = Path(); thin.move(to: CGPoint(x: c.x - 9, y: 6)); thin.addLine(to: CGPoint(x: c.x - 13, y: h - 3))
                ctx.stroke(thin, with: .color(col.opacity(0.5)), lineWidth: 1)
                var line = Path(); line.move(to: CGPoint(x: c.x, y: 7)); line.addLine(to: CGPoint(x: c.x, y: h - 3))
                ctx.stroke(line, with: .color(col), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                ctx.stroke(line, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            case .sweepLaser:
                // 発射口から、扇形に振られる光線(残像つき)
                dot(c.x, 5, 3.4)
                for (i, a) in [-0.55, -0.2, 0.15, 0.5].enumerated() {
                    var p = Path(); p.move(to: CGPoint(x: c.x, y: 6))
                    p.addLine(to: CGPoint(x: c.x + sin(a) * (h - 6), y: 6 + cos(a) * (h - 6)))
                    let last = i == 3
                    ctx.stroke(p, with: .color(col.opacity(last ? 1 : 0.25 + 0.15 * Double(i))), style: StrokeStyle(lineWidth: last ? 6 : 2, lineCap: .round))
                    if last { ctx.stroke(p, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
                }
            case .mine:
                // 止まった地雷と、爆風の届く範囲
                for (x, y) in [(c.x - 9, c.y - 4), (c.x + 9, c.y + 6)] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - 9, y: y - 9, width: 18, height: 18)), with: .color(col.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 3.5, y: y - 3.5, width: 7, height: 7)), with: .color(col))
                }
            case .meteor:
                // 予告の円に、上から落ちてくる大きな弾
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 13, y: c.y - 2, width: 26, height: 18)), with: .color(col.opacity(0.6)), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 6, y: 2, width: 12, height: 12)), with: .color(col))
                for k in 1...3 { dot(c.x - Double(k) * 3, 2 - Double(k) * 2 + 6, 1.4) }
            case .gridLaser:
                for x in [w * 0.3, w * 0.7] {
                    var p = Path(); p.move(to: CGPoint(x: x, y: 2)); p.addLine(to: CGPoint(x: x, y: h - 2))
                    ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
                for y in [h * 0.35, h * 0.72] {
                    var p = Path(); p.move(to: CGPoint(x: 2, y: y)); p.addLine(to: CGPoint(x: w - 2, y: y))
                    ctx.stroke(p, with: .color(col.opacity(0.55)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                }
            case .gravity:
                // 投げ上げて落ちてくる放物線
                for side in [-1.0, 1.0] { for k in 0..<6 { let t = Double(k) / 5; dot(c.x + side * t * 16, h - 6 - (1 - (2 * t - 1) * (2 * t - 1)) * 26, 2) } }
            case .orbit:
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22)), with: .color(col.opacity(0.3)), lineWidth: 1)
                dot(c.x, c.y, 3)
                for k in 0..<5 { let a = Double(k) * 2 * .pi / 5; dot(c.x + cos(a) * 11, c.y + sin(a) * 11, 2.2) }
            case .snake:
                for k in 0..<7 { let t = Double(k); dot(c.x - 12 + t * 4, c.y + sin(t * 0.9) * 7, k == 6 ? 3.2 : 2.2) }
            case .bubble:
                for (i, r) in [3.0, 6.0, 10.0].enumerated() {
                    let y = 8 + Double(i) * 11
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: y - r / 2, width: r * 2, height: r * 2)), with: .color(col.opacity(0.5 + 0.2 * Double(i))), lineWidth: 1.5)
                }
            case .angelTwin:
                // 左右のオーブから、逆回転の螺旋
                for side in [-1.0, 1.0] {
                    for i in 0..<8 { let a = Double(i) * 0.8 * side + (side < 0 ? 0 : 1.2), r = 2 + Double(i) * 1.5; dot(c.x + side * 11 + cos(a) * r, c.y + sin(a) * r, 1.8) }
                }
            case .angelFeather:
                // 羽が扇状に広がって、落ちる
                for (i, x) in [-14.0, -8, 0, 8, 14].enumerated() {
                    var p = Path()
                    let y = 8 + Double(abs(i - 2)) * 5 + (i % 2 == 0 ? 6 : 0)
                    p.addEllipse(in: CGRect(x: c.x + x - 2, y: y, width: 4, height: 9))
                    ctx.fill(p, with: .color(col))
                }
            case .angelHalo:
                // 光輪の形に並んだ破片
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 15, y: c.y - 10, width: 30, height: 20)), with: .color(col.opacity(0.3)), lineWidth: 1)
                for i in 0..<9 { let a = Double(i) * 2 * .pi / 9; dot(c.x + cos(a) * 15, c.y + sin(a) * 10, 2.2) }
            case .angelCross:
                // 逆さ十字のレーザー
                for (dx, dy, len) in [(0.0, 1.0, 16.0), (0.0, -1.0, 8.0), (1.0, 0.0, 12.0), (-1.0, 0.0, 12.0)] {
                    var p = Path(); p.move(to: CGPoint(x: c.x, y: c.y - 3)); p.addLine(to: CGPoint(x: c.x + dx * len, y: c.y - 3 + dy * len))
                    ctx.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            case .angelParadise:
                // 閉じてくる輪(抜け道が1か所)
                for i in 0..<14 where i != 3 && i != 4 { let a = Double(i) * 2 * .pi / 14; dot(c.x + cos(a) * 15, c.y + sin(a) * 15, 2.2) }
            case .giantOrb:
                dot(c.x, 5, 3.4)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 6, width: 22, height: 22)), with: .color(col))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 2, width: 7, height: 7)), with: .color(.white.opacity(0.6)))
            default:
                // 広告で解放するパターン: 実際に出る弾を少し進めた形を、小さく描く(ゲームと同じ計算)
                for q in PatternIcon.sample(pattern) { dot(q.x * w, q.y * h, 1.5) }
            }
        }
    }
}


// MARK: 全画面で使う部品

/// アプリのロゴ風タイトル(光る文字と、弾の飾り)
struct LogoTitle: View {
    let text: LocalizedStringKey
    var size: CGFloat = 32

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    ZStack {
                        Circle().fill(Color(Palette.bullets[i]))
                        Circle().fill(Color.white).frame(width: 4, height: 4)
                    }
                    .frame(width: 8, height: 8)
                    .shadow(color: Color(Palette.bullets[i]).opacity(0.8), radius: 4)
                }
            }
            Text(text)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(LinearGradient(colors: [.white, Color(Palette.pink), Color(Palette.gold)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(Palette.pink).opacity(0.8), radius: 10)
                .shadow(color: .black.opacity(0.5), radius: 2, y: 2)
        }
    }
}

/// 画面の上の見出し(左に戻る・右にボタンなど)
struct ScreenHeader<Leading: View, Trailing: View>: View {
    var title: LocalizedStringKey?
    var logo: LocalizedStringKey?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            HStack { leading; Spacer(minLength: 0); trailing }
            if let logo { LogoTitle(text: logo) }
            if let title {
                Text(title).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }
}

/// 丸い小さなボタン(閉じる・戻るなど)
struct RoundIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var tint: Color = Color(Palette.text)
    let action: () -> Void

    var body: some View {
        Button { gameTap(); action() } label: {
            Image(systemName: systemImage).font(.system(size: 15, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.1), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2)))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityLabel(Text(label))
    }
}

/// すべり込む選択ハイライトつきのタブ切り替え
struct GameTabs<T: Hashable>: View {
    let items: [(T, LocalizedStringKey)]
    @Binding var selection: T
    var idPrefix = "tabs"
    /// 赤い点で知らせるタブ(受け取れるごほうびがあるときなど)
    var badges: Set<T> = []
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.0) { item in
                let selected = selection == item.0
                Button {
                    gameTap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { selection = item.0 }
                } label: {
                    Text(item.1).font(.system(size: 15, weight: .heavy, design: .rounded))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.6))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                        .overlay(alignment: .topTrailing) {
                            if badges.contains(item.0) {
                                Circle().fill(Color.red).frame(width: 9, height: 9).padding(.top, 5).padding(.trailing, 6)
                            }
                        }
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: 12).fill(GameStyle.accent)
                                    .shadow(color: Color(Palette.pink).opacity(0.5), radius: 6)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(String(describing: item.0))")
            }
        }
        .padding(4)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GameStyle.edge))
    }
}

/// ゲーム風のオン・オフスイッチ(弾のつまみ)
struct GameToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? AnyShapeStyle(GameStyle.accent) : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(width: 52, height: 30)
                    .overlay(Capsule().stroke(Color.white.opacity(0.25)))
                ZStack {
                    Circle().fill(isOn ? Color.white : Color(Palette.text).opacity(0.7))
                    Circle().fill(isOn ? Color(Palette.pink) : Color.black.opacity(0.3)).frame(width: 9, height: 9)
                }
                .frame(width: 24, height: 24).padding(3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// モードを表す丸いアイコン
struct ModeIcon: View {
    let mode: Mode
    var size: CGFloat = 46

    private var tint: Color {
        switch mode {
        case .survive: return Color(UIColor(hex: 0x5CE1E6))
        case .boss: return Color(Palette.pink)
        case .damage: return Color(Palette.gold)
        case .sequence: return Color(Palette.bullets[3])
        }
    }

    var body: some View {
        ZStack {
            Circle().fill(tint.opacity(0.18))
            Circle().stroke(tint.opacity(0.7), lineWidth: 1.5)
            switch mode {
            case .survive:
                ZStack {
                    GameShipShape().fill(tint)
                    Circle().fill(Color.white).frame(width: size * 0.12, height: size * 0.12)
                }.frame(width: size * 0.42, height: size * 0.5)
            case .boss:
                GameBossShape().fill(tint, style: FillStyle(eoFill: true)).frame(width: size * 0.6, height: size * 0.6)
            case .sequence:
                ZStack {
                    GameBossShape().fill(tint, style: FillStyle(eoFill: true)).frame(width: size * 0.5, height: size * 0.5).offset(x: size * 0.1, y: size * 0.06)
                    GameBossShape().fill(Color(Palette.pink), style: FillStyle(eoFill: true)).frame(width: size * 0.42, height: size * 0.42).offset(x: -size * 0.13, y: -size * 0.05)
                }
            case .damage:
                ZStack {
                    GameBossShape().fill(tint, style: FillStyle(eoFill: true)).frame(width: size * 0.6, height: size * 0.6)
                    Image(systemName: "bolt.fill").font(.system(size: size * 0.24, weight: .heavy)).foregroundStyle(Color(Palette.background))
                }
            }
        }
        .frame(width: size, height: size)
    }
}

/// ステージのカード(一覧の1行)。モードの色で縁が光る
struct StageCardShell<Content: View>: View {
    let mode: Mode
    @ViewBuilder var content: Content

    private var tint: Color {
        switch mode {
        case .survive: return Color(UIColor(hex: 0x5CE1E6))
        case .boss: return Color(Palette.pink)
        case .damage: return Color(Palette.gold)
        case .sequence: return Color(Palette.bullets[3])
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ModeIcon(mode: mode)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(tint.opacity(0.45), lineWidth: 1.5))
        .shadow(color: tint.opacity(0.18), radius: 8)
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

/// クリア率などを表すリング
struct PercentRing: View {
    let percent: Int?
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 5)
            if let percent {
                Circle().trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(GameStyle.gold, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Text(percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
        }
        .frame(width: 48, height: 48)
    }
}

/// 検索欄
struct GameSearchField: View {
    @Binding var text: String
    let prompt: LocalizedStringKey
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .background(GameStyle.panel, in: Capsule())
        .overlay(Capsule().stroke(GameStyle.edge))
    }
}
