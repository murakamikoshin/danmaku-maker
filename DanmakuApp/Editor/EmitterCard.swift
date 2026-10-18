import SwiftUI
import DanmakuCore

struct EmitterCard: View {
    let index: Int
    @Binding var emitter: Emitter
    let isBoss: Bool
    let duration: Int
    let canDelete: Bool
    let onDelete: () -> Void

    private static let patternKeys: [Pattern: String] = [
        .ring: "pattern.ring", .spiral: "pattern.spiral", .aim: "pattern.aim", .rain: "pattern.rain", .sweep: "pattern.sweep",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: L("editor.emitter"), index + 1)).font(.headline).foregroundStyle(Color(Palette.gold))
                Spacer()
                if canDelete {
                    Button("editor.delete", action: onDelete).buttonStyle(.bordered).controlSize(.small)
                        .accessibilityIdentifier("emitter.delete.\(index)")
                }
            }
            EmitterPreview(emitter: emitter, isBoss: isBoss)
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("editor.pattern").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { emitter.t }, set: { emitter.changePattern(to: $0) })) {
                        ForEach(Pattern.allCases, id: \.self) { Text(LocalizedStringKey(EmitterCard.patternKeys[$0]!)).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .accessibilityIdentifier("emitter.pattern.\(index)")
                }
                Spacer()
                ColorSwatches(selection: $emitter.k, index: index)
            }
            if isBoss {
                VStack(alignment: .leading, spacing: 4) {
                    Text("editor.phase").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $emitter.ph) {
                        Text("phase.all").tag(0)
                        Text("phase.1").tag(1); Text("phase.2").tag(2); Text("phase.3").tag(3)
                    }
                    .pickerStyle(.menu).labelsHidden()
                }
            } else {
                SliderRow(label: "editor.x", value: $emitter.x, range: 0...1, step: 0.05, disabled: emitter.t == .rain) { "\(Int($0 * 100))%" }
                SliderRow(label: "editor.y", value: $emitter.y, range: 0...0.6, step: 0.05, disabled: emitter.t == .rain) { "\(Int($0 * 100))%" }
                SliderRow(label: "editor.start", value: $emitter.s, range: 0...Double(duration), step: 0.5) { String(format: "%g%@", $0, L("unit.s")) }
                SliderRow(label: "editor.end", value: Binding(get: { min(emitter.e, Double(duration)) }, set: { emitter.e = $0 }),
                          range: 0...Double(duration), step: 0.5) { $0 >= Double(duration) ? L("editor.until.end") : String(format: "%g%@", $0, L("unit.s")) }
            }
            SliderRow(label: "editor.interval", value: $emitter.i, range: 0.05...2, step: 0.05) { String(format: "%.2fs", $0) }
            SliderRow(label: "editor.count", value: Binding(get: { Double(emitter.c) }, set: { emitter.c = Int($0) }), range: 1...36, step: 1) { String(Int($0)) }
            SliderRow(label: "editor.speed", value: $emitter.v, range: 1...5, step: 0.25) { String(format: "%.2f", $0) }
            SliderRow(label: angleLabel, value: $emitter.r, range: -90...90, step: 1, disabled: emitter.t == .rain) { "\(Int($0))°" }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.11, green: 0.09, blue: 0.25)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(Palette.barBack)))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("emitter.card.\(index)")
    }

    private var angleLabel: LocalizedStringKey {
        switch emitter.t {
        case .ring, .spiral: return "angle.rotate"
        case .aim: return "angle.spread"
        case .rain: return "angle.none"
        case .sweep: return "angle.swing"
        }
    }
}

private struct ColorSwatches: View {
    @Binding var selection: Int
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<5, id: \.self) { j in
                Circle().fill(Color(Palette.bullets[j])).frame(width: 26, height: 26)
                    .overlay(Circle().stroke(Color.white, lineWidth: selection == j ? 2 : 0).padding(-3))
                    .onTapGesture { selection = j }
                    .accessibilityLabel(Text(String(format: L("editor.color"), j + 1)))
                    .accessibilityAddTraits(selection == j ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("emitter.color.\(index).\(j)")
            }
        }
    }
}
