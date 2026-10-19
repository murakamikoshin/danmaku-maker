import SwiftUI
import DanmakuCore

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
            EmitterPreview(emitter: emitter, isBoss: isBoss, look: look)

            VStack(alignment: .leading, spacing: 6) {
                Text("editor.pattern").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                PatternTiles(selection: Binding(get: { emitter.t }, set: { emitter.changePattern(to: $0) }), index: index)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("editor.color.label").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                ColorSwatches(selection: $emitter.k, index: index, theme: look.bullets)
            }

            if advanced {
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
            SliderRow(label: "editor.interval", value: $emitter.i, range: 0.05...2, step: 0.05) { String(format: "%.2fs", $0) }
            SliderRow(label: "editor.count", value: Binding(get: { Double(emitter.c) }, set: { emitter.c = Int($0) }), range: 1...36, step: 1) { String(Int($0)) }
            SliderRow(label: "editor.speed", value: $emitter.v, range: 1...5, step: 0.25) { String(format: "%.2f", $0) }
            if advanced {
                SliderRow(label: angleLabel, value: $emitter.r, range: -90...90, step: 1, disabled: emitter.t == .rain || emitter.t == .heart) { "\(Int($0))°" }
            }
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
        case .accel, .bounce: return "angle.spread"
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
