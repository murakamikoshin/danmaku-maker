import SwiftUI
import UIKit
import DanmakuCore

// 編集画面などで使う、ゲーム専用の部品(標準のピッカーやスライダーの代わり)。色・字体・形の決まりは DesignSystem.swift

func gameTap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
    Task { @MainActor in AudioManager.shared.se(.tap) }
}

/// 押すと、キーのように少し沈むボタン
struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(y: configuration.isPressed ? 3 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// 大きなアクションボタン(テストプレイ・投稿など)。べた塗りの面に黒い文字、下に厚み
struct GameActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let fill: LinearGradient
    var enabled = true
    let action: () -> Void

    var body: some View {
        Button { gameTap(); action() } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage).font(.system(size: 15, weight: .black))
                Text(title).font(.display(15)).multilineTextAlignment(.center).minimumScaleFactor(0.7)
            }
            .foregroundStyle(GameStyle.ink)
            .frame(maxWidth: .infinity).padding(.vertical, 13).padding(.horizontal, 10)
            .background(KeyCap(fill: fill, radius: 14))
            .padding(.bottom, 4)
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

/// 見出しつきのパネル
struct GamePanel<Content: View>: View {
    var title: LocalizedStringKey?
    var tint: Color = GameStyle.yellow
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                HStack(spacing: 8) {
                    Rectangle().fill(tint).frame(width: 8, height: 8)
                    Text(title).font(.display(15)).foregroundStyle(GameStyle.text)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gamePanel(radius: 18)
    }
}

/// 選べるチップ(選ぶと黄色になる)
struct Chip: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(selected ? GameStyle.ink : GameStyle.text.opacity(0.85))
            .padding(.vertical, 8).padding(.horizontal, 13)
            .background(selected ? GameStyle.yellow : GameStyle.panelHi, in: PixelRect(cornerRadius: 8))
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

/// 四角いつまみがついたスライダー
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
                Rectangle().fill(GameStyle.panelHi).frame(height: 8).padding(.horizontal, 12)
                Rectangle().fill(GameStyle.yellow).frame(width: max(0, w * frac), height: 8).padding(.leading, 12)
                ZStack {
                    PixelRect(cornerRadius: 8).fill(Color.black.opacity(0.5)).offset(y: 3)
                    PixelRect(cornerRadius: 8).fill(Color.white)
                    Rectangle().fill(GameStyle.ink).frame(width: 6, height: 6)
                }
                .frame(width: 24, height: 24)
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
                .font(.display(34))
                .foregroundStyle(GameStyle.text)
                .frame(minWidth: 64)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: value)
            roundButton("plus", enabled: value < range.upperBound) { value += 1 }
                .accessibilityIdentifier("\(idPrefix).plus")
        }
    }

    private func roundButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 18, weight: .black)).foregroundStyle(GameStyle.ink)
                .frame(width: 44, height: 42)
                .background(KeyCap(fill: GameStyle.yellow, radius: 10, depth: 3))
                .padding(.bottom, 3)
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
                            Image(systemName: "heart.fill").font(.system(size: 22)).foregroundStyle(GameStyle.pinkColor)
                        }
                    }
                }
            }
        case .hp:
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, n in
                    HStack(spacing: 2) {
                        ForEach(0..<n, id: \.self) { _ in
                            Rectangle().fill(GameStyle.green).frame(width: 9, height: 16)
                        }
                    }
                }
            }
            .padding(4)
            .background(Color.black.opacity(0.4), in: PixelRect(cornerRadius: 5))
        }
    }
}

// MARK: モードのカード

struct ModeCards: View {
    let mode: Mode
    let onSelect: (Mode) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
            card(.survive, "editor.mode.survive", "editor.mode.survive.sub")
            card(.boss, "editor.mode.boss", "editor.mode.boss.sub")
            card(.sequence, "editor.mode.sequence", "editor.mode.sequence.sub")
            card(.damage, "editor.mode.damage", "editor.mode.damage.sub")
        }
    }

    private func card(_ m: Mode, _ title: LocalizedStringKey, _ sub: LocalizedStringKey) -> some View {
        let selected = mode == m
        return Button {
            gameTap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { onSelect(m) }
        } label: {
            VStack(spacing: 6) {
                // 選択中は、そのクリア条件の色の札に濃い紺の絵。それ以外は、クリア条件の色の絵
                ModeGlyph(mode: m, size: 32, color: selected ? GameStyle.onTint : nil,
                          core: selected ? GameStyle.tint(m) : (m == .damage ? GameStyle.panelHi : .white))
                    .frame(height: 36)
                Text(title).font(.display(14)).foregroundStyle(selected ? GameStyle.onTint : GameStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(sub).font(.system(size: 10, weight: .bold)).foregroundStyle(selected ? GameStyle.onTint.opacity(0.75) : GameStyle.dim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 6)
            .background(KeyCap(fill: selected ? GameStyle.tint(m) : GameStyle.panelHi, radius: 14, depth: selected ? 4 : 0))
            .padding(.bottom, 4)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("editor.mode.\(m.rawValue)")
    }
}

// MARK: ボスの動き

struct BossMoveCards: View {
    @Binding var move: Int
    /// 見本の速さ(ゲームの 1.6 倍。短い枠で動きが分かるように)
    private static let demoSpeed = 1.6
    /// 逆向きの動き(7〜10)と、もとの動き。向きがある動き(横ゆっくり・横はやい・円・8の字)だけ、逆向きにできる
    private static let reversePairs: [Int: Int] = [1: 9, 2: 10, 4: 7, 5: 8]
    private var base: Int { Self.reversePairs.first { $0.value == move }?.key ?? move }
    private var reversed: Bool { move >= 7 }
    private var canReverse: Bool { Self.reversePairs[base] != nil }

    var body: some View {
        VStack(spacing: 10) {
            grid
            if canReverse {
                HStack {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.pinkColor)
                    Text("editor.boss.reverse").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                    Spacer()
                    GameToggle(isOn: Binding(get: { reversed }, set: { move = $0 ? (Self.reversePairs[base] ?? base) : base }))
                }
                .accessibilityIdentifier("editor.boss.reverse")
            }
        }
    }

    private func shown(_ i: Int) -> Int { (reversed ? Self.reversePairs[i] : nil) ?? i }

    private var grid: some View {
        // 7 種類を 4 列の表にする(小さい枠のまま、1 画面に収まる)
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(0..<7, id: \.self) { i in
                let selected = base == i
                Button {
                    gameTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { move = (reversed ? Self.reversePairs[i] : nil) ?? i }
                } label: {
                    VStack(spacing: 4) {
                        VisibleTimeline(interval: 1.0 / 30.0) { tl in
                            Canvas { ctx, size in
                                // ゲームと同じ式(Simulation.bossPoint)で、ボスの位置と動く道すじを描く
                                let t = tl.date.timeIntervalSinceReferenceDate * Self.demoSpeed
                                func at(_ p: Point) -> CGPoint {
                                    CGPoint(x: size.width * p.x / DanmakuConfig.width,
                                            y: size.height * min(max((p.y / DanmakuConfig.height - 0.05) / 0.4, 0.1), 0.9))
                                }
                                var track = Path()
                                var first = true
                                for k in 0...120 {
                                    let q = at(Simulation.bossPoint(move: shown(i), t: Double(k) * 0.2))
                                    if first { track.move(to: q); first = false } else { track.addLine(to: q) }
                                }
                                ctx.stroke(track, with: .color(Color.white.opacity(0.18)), style: StrokeStyle(lineWidth: 2, dash: [3, 3]))
                                let c = at(Simulation.bossPoint(move: shown(i), t: t))
                                let rect = CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)
                                ctx.fill(GameBossShape().path(in: rect), with: .color(GameStyle.pinkColor), style: FillStyle(eoFill: true))
                            }
                        }
                        .frame(height: 40)
                        Text(L("editor.boss.move.\(i)")).font(.system(size: 11, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                            .foregroundStyle(GameStyle.text)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6).padding(.horizontal, 3)
                    .background(selected ? AnyShapeStyle(GameStyle.yellow.opacity(0.16)) : AnyShapeStyle(GameStyle.panelHi), in: PixelRect(cornerRadius: 12))
                    .overlay(PixelRect(cornerRadius: 12).strokeBorder(selected ? GameStyle.yellow : Color.clear, lineWidth: 2))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("editor.boss.move.\(i)")
            }
        }
    }
}

// MARK: ボスの位置

/// ボスの動きの中心を決める小さな画面。ボスのアイコンをドラッグ(タップ)して置く。標準は真ん中の少し上
struct BossPositionPad: View {
    @Binding var x: Double?
    @Binding var y: Double?
    private static let xr = 0.2...0.8, yr = 0.1...0.3
    private static let stdX = 0.5, stdY = 0.2
    /// 画面の上半分(0〜0.5)を、横 240 の枠で見せる
    private let w: CGFloat = 240
    private var h: CGFloat { w * 0.5 * CGFloat(DanmakuConfig.height / DanmakuConfig.width) }

    private var cx: Double { x ?? Self.stdX }
    private var cy: Double { y ?? Self.stdY }
    private var isStandard: Bool { x == nil && y == nil }

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                PixelRect(cornerRadius: 12).fill(Color.black.opacity(0.35))
                // 置ける範囲
                PixelRect(cornerRadius: 8).fill(GameStyle.pinkColor.opacity(0.10))
                    .overlay(PixelRect(cornerRadius: 8).stroke(GameStyle.pinkColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    .frame(width: w * CGFloat(Self.xr.upperBound - Self.xr.lowerBound), height: h * CGFloat((Self.yr.upperBound - Self.yr.lowerBound) / 0.5))
                    .offset(x: w * CGFloat(Self.xr.lowerBound), y: h * CGFloat(Self.yr.lowerBound / 0.5))
                // 動きの道すじは出さない(動きは上のカードで選ぶ)。ここは「中心」だけ
                GameBossShape().fill(GameStyle.pinkColor, style: FillStyle(eoFill: true))
                    .frame(width: 26, height: 26)
                    .offset(x: w * CGFloat(cx) - 13, y: h * CGFloat(cy / 0.5) - 13)
            }
            .frame(width: w, height: h)
            .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                let nx = min(max(Double(v.location.x / w), Self.xr.lowerBound), Self.xr.upperBound)
                let ny = min(max(Double(v.location.y / h) * 0.5, Self.yr.lowerBound), Self.yr.upperBound)
                let rx = (nx * 20).rounded() / 20, ry = (ny * 20).rounded() / 20
                x = abs(rx - Self.stdX) < 0.001 ? nil : rx
                y = abs(ry - Self.stdY) < 0.001 ? nil : ry
            })
            .accessibilityIdentifier("editor.boss.position")
            Button { gameTap(); x = nil; y = nil } label: {
                Text("editor.boss.position.reset").font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(isStandard ? GameStyle.text.opacity(0.4) : GameStyle.text)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 8)).overlay(PixelRect(cornerRadius: 8).stroke(GameStyle.edge))
            }
            .buttonStyle(BounceButtonStyle()).disabled(isStandard)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: パターンの選択

struct PatternTiles: View {
    @Binding var selection: DanmakuCore.Pattern
    let index: Int
    /// 専用の絵を持つボスを選んでいるときは、そのボスだけの技も出す
    var character: BossCharacter? = nil
    @EnvironmentObject private var cosmetics: CosmeticsStore
    /// 持っていないパターンを押したとき(ショップのその商品を開く。開く画面は外で持つ。
    /// この一覧は畳んだり、スクロールで作り直されたりするので、ここで画面を持つと、開いた画面が壊れて暗いまま止まることがあった)
    var onLocked: (String) -> Void = { _ in }
    /// パターンが入っている、ショップのカードの名札
    static func shopCard(for p: DanmakuCore.Pattern) -> String {
        if DanmakuCore.Pattern.ad.contains(p) { return "adpatterns" }
        if DanmakuCore.Pattern.pack2.contains(p) { return "patterns2" }
        if p == .custom { return "maker" }
        if let b = p.bossCharacter { return "boss.\(b.productKey)" }
        return "patterns"
    }
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
                Text(L("editor.pattern.bosssection.\(character.rawValue)")).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                grid(DanmakuCore.Pattern.allCases.filter { $0.bossCharacter == character })
            }
            grid(freePatterns)
            Text("editor.pattern.adsection").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).padding(.top, 4)
            grid(DanmakuCore.Pattern.ad)
            Text("editor.pattern.pack2section").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).padding(.top, 4)
            grid(DanmakuCore.Pattern.pack2)
            customSection
        }
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
            Text("editor.pattern.mysection").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).padding(.top, 4)
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
                            Text(item.name).font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(selected ? GameStyle.yellow : GameStyle.text.opacity(0.75)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(selected ? AnyShapeStyle(GameStyle.yellow.opacity(0.16)) : AnyShapeStyle(GameStyle.panelHi), in: PixelRect(cornerRadius: 12))
                        .overlay(PixelRect(cornerRadius: 12).strokeBorder(selected ? GameStyle.yellow : Color.clear, lineWidth: 2))
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
                    if locked { onLocked(Self.shopCard(for: p)); return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selection = p }
                } label: {
                    VStack(spacing: 3) {
                        PatternIcon(pattern: p, selected: selected).frame(width: 40, height: 40)
                        Text(LocalizedStringKey(keys[p] ?? "pattern.\(p.rawValue)")).font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(selected ? GameStyle.yellow : GameStyle.text.opacity(0.75))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(selected ? AnyShapeStyle(GameStyle.yellow.opacity(0.16)) : AnyShapeStyle(GameStyle.panelHi), in: PixelRect(cornerRadius: 12))
                    .overlay(PixelRect(cornerRadius: 12).strokeBorder(selected ? GameStyle.yellow : Color.clear, lineWidth: 2))
                    .overlay(alignment: .topTrailing) {
                        if locked {
                            Image(systemName: "lock.fill").font(.system(size: 10, weight: .heavy)).foregroundStyle(GameStyle.yellow)
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
        if let img = BossPatternIcon.image(pattern) {
            // ボスの専用の技: 実際の弾の絵で描いた見本
            Image(uiImage: img).resizable().interpolation(.none).scaledToFit()
                .opacity(selected ? 1 : 0.85)
        } else {
            dots
        }
    }

    private var dots: some View {
        Canvas(renderer: draw)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        do {
            let col = selected ? GameStyle.yellow : GameStyle.text.opacity(0.6)
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

/// アプリのロゴ風タイトル(厚みのある黄色い文字と、弾の飾り)
struct LogoTitle: View {
    let text: LocalizedStringKey
    var size: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    ZStack {
                        Circle().fill(Color(Palette.bullets[i]))
                        Circle().fill(Color.white).frame(width: 4, height: 4)
                    }
                    .frame(width: 9, height: 9)
                }
            }
            Text(text).font(.display(size)).lineLimit(1).minimumScaleFactor(0.6)
                .thick(GameStyle.yellow, shade: GameStyle.yellowShade, depth: size * 0.1)
        }
    }
}

/// 画面の上の見出し(左に戻る・右にボタンなど)
struct ScreenHeader<Leading: View, Trailing: View>: View {
    var title: LocalizedStringKey?
    var logo: LocalizedStringKey?
    /// 見出しを、左のボタンのすぐ右に置く(右側にボタンや表示が多い画面で、重ならないように)
    var leadingTitle = false
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            HStack(spacing: 10) {
                leading
                if leadingTitle, let title {
                    Text(title).font(.display(19)).foregroundStyle(GameStyle.text).lineLimit(1).minimumScaleFactor(0.6).layoutPriority(1)
                }
                Spacer(minLength: 0)
                trailing
            }
            if let logo { LogoTitle(text: logo) }
            if let title, !leadingTitle {
                Text(title).font(.display(19)).foregroundStyle(GameStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 50)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
    }
}

/// 四角い小さなボタン(閉じる・戻るなど)
struct RoundIconButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var tint: Color = GameStyle.text
    let action: () -> Void

    var body: some View {
        Button { gameTap(); action() } label: {
            Image(systemName: systemImage).font(.system(size: 15, weight: .black)).foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .gamePanel(radius: 10, fill: GameStyle.panelHi)
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
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { selection = item.0 }
                } label: {
                    Text(item.1).font(.display(13))
                        .lineLimit(1).minimumScaleFactor(0.6)
                        .foregroundStyle(selected ? GameStyle.ink : GameStyle.dim)
                        .frame(maxWidth: .infinity).padding(.vertical, 9).padding(.horizontal, 4)
                        .overlay(alignment: .topTrailing) {
                            if badges.contains(item.0) {
                                Rectangle().fill(GameStyle.pinkColor).frame(width: 8, height: 8).padding(.top, 4).padding(.trailing, 5)
                            }
                        }
                        .background {
                            if selected {
                                PixelRect(cornerRadius: 10).fill(GameStyle.yellow)
                                    .matchedGeometryEffect(id: "sel", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(String(describing: item.0))")
            }
        }
        .padding(4)
        .gamePanel(radius: 14)
    }
}

/// ゲーム風のオン・オフスイッチ(四角いつまみ)
struct GameToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                PixelRect(cornerRadius: 8).fill(isOn ? GameStyle.yellow : GameStyle.panelHi)
                    .frame(width: 52, height: 30)
                    .overlay(PixelRect(cornerRadius: 8).strokeBorder(isOn ? GameStyle.yellow : GameStyle.edge, lineWidth: 2))
                ZStack {
                    PixelRect(cornerRadius: 6).fill(isOn ? GameStyle.ink : GameStyle.dim)
                    Rectangle().fill(isOn ? GameStyle.yellow : GameStyle.panelHi).frame(width: 6, height: 6)
                }
                .frame(width: 22, height: 22).padding(4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(Text(isOn ? "On" : "Off"))
    }
}

/// クリア条件を表す四角いアイコン(クリア条件の色の札に、黒い絵)
struct ModeIcon: View {
    let mode: Mode
    var size: CGFloat = 46

    var body: some View {
        ModeGlyph(mode: mode, size: size * 0.6, color: GameStyle.onTint, core: GameStyle.tint(mode))
            .frame(width: size, height: size)
            .background(GameStyle.tint(mode), in: PixelRect(cornerRadius: size * 0.22))
    }
}

/// ステージのカード(一覧の1行)。左の帯の色で、クリア条件が分かる
struct StageCardShell<Content: View>: View {
    let mode: Mode
    /// 左のアイコンの代わりに出すもの(世界のステージの動くプレビューなど)。nil ならクリア条件のアイコン
    var thumbnail: AnyView? = nil
    @ViewBuilder var content: Content

    /// 左の帯の幅。アイコンだけのときは太い帯にアイコンを乗せ、プレビューがあるときは細い帯にする
    private var band: CGFloat { thumbnail == nil ? 50 : 6 }

    var body: some View {
        HStack(spacing: 12) {
            if let thumbnail { thumbnail }
            content
        }
        .padding(12)
        .padding(.leading, band)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .leading) {
            ZStack(alignment: .leading) {
                GameStyle.panel
                GameStyle.tint(mode).frame(width: band)
                if thumbnail == nil {
                    ModeGlyph(mode: mode, size: 28, color: GameStyle.onTint, core: GameStyle.tint(mode)).frame(width: band)
                }
            }
        }
        .clipShape(PixelRect(cornerRadius: 16))
        .overlay(PixelRect(cornerRadius: 16).strokeBorder(GameStyle.edge, lineWidth: 2))
        .hardShadow(radius: 16, depth: 3)
        .padding(.bottom, 3)
        .contentShape(Rectangle())
    }
}

/// クリア率などを表すリング
struct PercentRing: View {
    let percent: Int?
    var body: some View {
        ZStack {
            Circle().stroke(GameStyle.panelHi, lineWidth: 5)
            if let percent {
                Circle().trim(from: 0, to: CGFloat(percent) / 100)
                    .stroke(GameStyle.yellow, style: StrokeStyle(lineWidth: 5, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            Text(percent.map { "\($0)%" } ?? "—")
                .font(.system(size: 12, weight: .black)).foregroundStyle(GameStyle.text)
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
            Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.dim)
            TextField("", text: $text, prompt: Text(prompt).foregroundColor(GameStyle.dim.opacity(0.7)))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .bold))
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(GameStyle.dim) }.buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .gamePanel(radius: 10)
    }
}
