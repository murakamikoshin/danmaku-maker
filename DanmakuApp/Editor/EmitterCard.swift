import SwiftUI
import DanmakuCore

/// 発射間隔のスライダーの目盛り。0.05〜2 秒は 0.05 秒きざみ(40 段)、2.5〜15 秒は 0.5 秒きざみ(26 段)。計算の値は秒のまま
enum IntervalScale {
    static let fineSteps = 40
    static let maxIndex = fineSteps + 25   // 2.5 秒 〜 15 秒

    static func seconds(_ index: Int) -> Double {
        let i = min(max(index, 0), maxIndex)
        let v = i < fineSteps ? Double(i + 1) * 0.05 : 2.0 + Double(i - fineSteps + 1) * 0.5
        return (v * 100).rounded() / 100
    }

    /// 一番近い目盛り
    static func index(_ s: Double) -> Int {
        let v = min(max(s.isFinite ? s : 1, Emitter.minInterval), Emitter.maxInterval)
        if v <= 2 { return min(fineSteps - 1, max(0, Int((v / 0.05).rounded()) - 1)) }
        return min(maxIndex, fineSteps - 1 + Int(((v - 2.0) / 0.5).rounded()))
    }

    static func label(_ s: Double) -> String { s <= 2 ? String(format: "%.2fs", s) : String(format: "%.1fs", s) }
}

struct EmitterCard: View {
    let index: Int
    @Binding var emitter: Emitter
    let isBoss: Bool
    let look: PreviewLook
    /// 「くわしく」のとき、発射位置・時間・段階・間隔・角度など、細かい設定も出す
    var advanced = true
    let duration: Int
    let canDelete: Bool
    let onDelete: () -> Void
    /// 畳んだ状態を外で持つとき(プレビューを画面の上に固定する画面)。持たなければ、カードの中で持つ
    var externalCollapsed: Binding<Bool>? = nil
    /// カードの中にプレビューを出すか(連戦の場面は、場面ごとのカードの中)
    var showPreview = true
    @State private var localCollapsed = false
    private var collapsed: Bool {
        get { externalCollapsed?.wrappedValue ?? localCollapsed }
        nonmutating set { if let b = externalCollapsed { b.wrappedValue = newValue } else { localCollapsed = newValue } }
    }

    /// カード全体を畳む(位置の設定などを探しやすくする)と、パターンの一覧を開いているか
    @State private var patternOpen = false

    /// 位置を選ばないパターン(画面の端や四隅などから出る)
    private var positionless: Bool { [.rain, .sideL, .sideR, .corner].contains(emitter.t) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 8) {
                    bulletBadge
                    Text(String(format: L("editor.emitter"), index + 1)).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
                }
                Spacer()
                Button { gameTap(); withAnimation(.easeInOut(duration: 0.2)) { collapsed.toggle() } } label: {
                    Image(systemName: collapsed ? "chevron.down.circle.fill" : "chevron.up.circle.fill")
                        .font(.system(size: 22)).foregroundStyle(Color(Palette.text).opacity(0.6))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityIdentifier("emitter.collapse.\(index)")
                if canDelete {
                    Button { gameTap(); onDelete() } label: {
                        Label("editor.delete", systemImage: "trash.fill").font(.system(size: 12, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(Palette.pink))
                            .padding(.vertical, 6).padding(.horizontal, 10)
                            .background(Color(Palette.pink).opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("emitter.delete.\(index)")
                }
            }
            if collapsed {
                // 畳んだときは、1行の要約だけ
                Text("\(L("pattern.\(emitter.t.rawValue)")) · \(String(format: "%.2fs", emitter.i)) · \(emitter.c)")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            }
            if !collapsed {
            if showPreview { EmitterPreview(emitter: emitter, isBoss: isBoss, look: look) }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("editor.pattern").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    Spacer()
                    // 一覧は大きいので、選んだら畳む。いまのパターンだけを見せて、下の設定に早く行けるようにする
                    Button { gameTap(); withAnimation(.easeInOut(duration: 0.2)) { patternOpen.toggle() } } label: {
                        HStack(spacing: 4) {
                            Text(L("pattern.\(emitter.t.rawValue)")).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                            Image(systemName: patternOpen ? "chevron.up" : "chevron.down").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 10)
                        .background(Color.white.opacity(0.1), in: Capsule())
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("emitter.pattern.toggle.\(index)")
                }
                if patternOpen {
                    PatternTiles(selection: Binding(get: { emitter.t }, set: { emitter.changePattern(to: $0); withAnimation(.easeInOut(duration: 0.2)) { patternOpen = false } }), index: index, character: isBoss ? BossCharacter.of(look: look.bossLook) : nil, emitter: $emitter)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("editor.color.label").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                ColorSwatches(selection: $emitter.k, index: index, theme: look.bullets)
            }

            if advanced {
                // 弾の形: 標準(パターンごとの形) / くの字(ブーメラン) / 丸。見た目だけ(当たる範囲は同じ)
                VStack(alignment: .leading, spacing: 6) {
                    Text("editor.shape.label").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    ChipGrid(items: [(0, L("editor.shape.auto")), (1, L("editor.shape.hook")), (2, L("editor.shape.round"))],
                             selection: Binding(get: { emitter.sh ?? 0 }, set: { emitter.sh = $0 == 0 ? nil : $0 }),
                             idPrefix: "emitter.shape.\(index)", minimum: 80)
                }
                // 左右反転(線対称): 発射位置・向き・回る向きを、画面の左右で反転して撃つ
                HStack {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right").font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(Palette.pink))
                    Text("editor.mirror").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                    Spacer()
                    GameToggle(isOn: Binding(get: { emitter.mir == 1 }, set: { emitter.mir = $0 ? 1 : nil }))
                }
                .accessibilityIdentifier("emitter.mirror.\(index)")
                if isBoss {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("editor.origin").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        ChipGrid(items: [(0, L("editor.origin.boss")), (1, L("editor.origin.point"))],
                                 selection: $emitter.p, idPrefix: "emitter.origin.\(index)", minimum: 110)
                    }
                    if emitter.firesFromPoint && !positionless {
                        SliderRow(label: "editor.x", value: $emitter.x, range: 0...1, step: 0.05) { "\(Int($0 * 100))%" }
                        SliderRow(label: "editor.y", value: $emitter.y, range: 0...0.6, step: 0.05) { "\(Int($0 * 100))%" }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("editor.phase").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        ChipGrid(items: [(0, L("phase.all")), (1, L("phase.1")), (2, L("phase.2")), (3, L("phase.3"))],
                                 selection: $emitter.ph, idPrefix: "emitter.phase.\(index)", minimum: 64)
                    }
                } else {
                    SliderRow(label: "editor.x", value: $emitter.x, range: 0...1, step: 0.05, disabled: positionless) { "\(Int($0 * 100))%" }
                    SliderRow(label: "editor.y", value: $emitter.y, range: 0...0.6, step: 0.05, disabled: positionless) { "\(Int($0 * 100))%" }
                    SliderRow(label: "editor.start", value: $emitter.s, range: 0...Double(duration), step: 0.5) { String(format: "%g%@", $0, L("unit.s")) }
                    SliderRow(label: "editor.end", value: Binding(get: { min(emitter.e, Double(duration)) }, set: { emitter.e = $0 }),
                              range: 0...Double(duration), step: 0.5) { $0 >= Double(duration) ? L("editor.until.end") : String(format: "%g%@", $0, L("unit.s")) }
                }
            } else if !isBoss && !positionless {
                // かんたん: 生き残りの発射台は、位置だけ選べる(時間は、最初から最後まで)
                SliderRow(label: "editor.x", value: $emitter.x, range: 0...1, step: 0.05) { "\(Int($0 * 100))%" }
                SliderRow(label: "editor.y", value: $emitter.y, range: 0...0.6, step: 0.05) { "\(Int($0 * 100))%" }
            }
            // 間隔: 2 秒までは 0.05 秒きざみ(これまでと同じ)、それより先は 0.5 秒きざみで 15 秒まで(1本のスライダーのまま)
            SliderRow(label: "editor.interval", value: Binding(get: { Double(IntervalScale.index(emitter.i)) }, set: { emitter.i = IntervalScale.seconds(Int($0)) }),
                      range: 0...Double(IntervalScale.maxIndex), step: 1) { IntervalScale.label(IntervalScale.seconds(Int($0))) }
            SliderRow(label: "editor.count", value: Binding(get: { Double(emitter.c) }, set: { emitter.c = Int($0) }), range: 1...36, step: 1) { String(Int($0)) }
            SliderRow(label: "editor.speed", value: $emitter.v, range: 1...5, step: 0.25) { String(format: "%.2f", $0) }
            SliderRow(label: "editor.rotate", value: Binding(get: { Double(emitter.a) }, set: { emitter.a = Int($0) }),
                      range: -180...180, step: 15, disabled: !emitter.canRotate) { "\(Int($0))°" }
            if advanced {
                SliderRow(label: angleLabel, value: $emitter.r, range: -90...90, step: 1, disabled: emitter.t == .rain || emitter.t == .heart) { "\(Int($0))" + (emitter.t == .kitsuneTorii || emitter.t == .reaperDeadline ? "px" : "°") }
            }
            }   // if !collapsed
        }
        .padding(14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(GameStyle.edge))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emitter.card.\(index)")
    }

    private var bulletBadge: some View {
        ZStack {
            Circle().fill(Color(Skin.of(look.bullets).bulletColors[min(max(emitter.k, 0), 4)]))
            Circle().fill(Color.white).frame(width: 9, height: 9)
        }
        .frame(width: 22, height: 22)
    }

    private var angleLabel: LocalizedStringKey {
        switch emitter.t {
        case .ring, .spiral: return "angle.rotate"
        case .aim, .corner: return "angle.spread"
        case .rain: return "angle.none"
        case .sweep: return "angle.swing"
        case .sideL, .sideR: return "angle.jitter"
        case .homing: return "angle.turn"
        case .flower, .star, .cross: return "angle.rotate"
        case .heart: return "angle.none"
        case .beam: return "angle.aimshift"
        case .accel, .bounce, .stopgo, .split: return "angle.spread"
        case .timed: return "angle.rotate"
        case .custom: return "angle.rotate"
        case .angelTwin: return "angle.rotate"
        case .angelParadise: return "angle.gap"
        case .angelFeather, .angelHalo, .angelCross: return "angle.none"
        case .iceCage, .iceIcicles, .iceBlizzard, .iceFreeze, .iceMirror: return "angle.none"
        case .reaperDeadline: return "angle.gap"
        case .reaperScythe, .reaperSouls, .reaperChains, .reaperRiver: return "angle.none"
        case .kitsuneTorii: return "angle.gap"
        case .kitsuneLanterns, .kitsuneBarrier, .kitsuneSunshower, .kitsuneDance: return "angle.none"
        default:
            // 広告で解放するパターン: 形によって、角度の意味が違う
            guard let r = emitter.t.recipe else { return "angle.none" }
            switch r.mode {
            case 0: return r.spin == 0 ? "angle.none" : "angle.rotate"
            case 1: return r.fan < 0 ? "angle.none" : (r.fan > 0 ? "angle.none" : "angle.spread")
            default: return r.sweepAmp > 0 ? "angle.swing" : (r.fan == 0 ? "angle.spread" : "angle.none")
            }
        }
    }
}

/// 弾の色の選択(ゲームの弾と同じ、色つきの円に白い芯)
private struct ColorSwatches: View {
    @Binding var selection: Int
    let index: Int
    let theme: Theme
    private var colors: [UIColor] { Skin.of(theme).bulletColors }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<5, id: \.self) { j in
                let selected = selection == j
                Button {
                    gameTap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) { selection = j }
                } label: {
                    ZStack {
                        Circle().fill(Color(colors[j]))
                        Circle().fill(Color.white).frame(width: 14, height: 14)
                    }
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Color.white, lineWidth: selected ? 2.5 : 0).padding(-4))
                    .shadow(color: Color(colors[j]).opacity(selected ? 0.9 : 0), radius: 8)
                    .scaleEffect(selected ? 1.15 : 1)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel(Text(String(format: L("editor.color"), j + 1)))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("emitter.color.\(index).\(j)")
            }
        }
    }
}
