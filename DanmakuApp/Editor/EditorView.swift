import SwiftUI
import DanmakuCore

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @State private var testRun: TestRun?
    @State private var showPublishSoon = false
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ModePicker(mode: model.draft.mode, onSelect: model.setMode)
                    NameFields(draft: $model.draft)
                    TimingFields(model: model)
                    ForEach(Array(model.draft.emitters.indices), id: \.self) { i in
                        EmitterCard(index: i, emitter: $model.draft.emitters[i], isBoss: model.draft.mode == .boss,
                                    duration: model.draft.duration, canDelete: model.draft.emitters.count > 1,
                                    onDelete: { model.removeEmitter(at: i) })
                    }
                    Button { model.addEmitter() } label: { Label("editor.add", systemImage: "plus") }
                        .buttonStyle(.bordered)
                        .disabled(!model.canAdd)
                        .accessibilityIdentifier("editor.add")
                    StatusBox(verified: model.isVerified)
                    HStack {
                        Button("editor.test") { testRun = TestRun(stage: model.stage) }
                            .buttonStyle(.borderedProminent).tint(Color(Palette.bullets[1]))
                            .accessibilityIdentifier("editor.test")
                        Button("editor.post") { showPublishSoon = true }
                            .buttonStyle(.borderedProminent).tint(Color(Palette.pink))
                            .disabled(!model.isVerified)
                            .accessibilityIdentifier("editor.post")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(Palette.background).ignoresSafeArea())
            .navigationTitle("editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("editor.close", action: onClose) } }
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.draft) { _ in model.save() }
        .fullScreenCover(item: $testRun) { run in
            PlayView(stage: run.stage, title: L("editor.test.prefix") + (run.stage.name), isTest: true,
                     onResult: { result, moves in
                         if result.outcome == .cleared { model.markVerified(stage: run.stage, replay: Replay(moves: moves)) }
                     },
                     onExit: { testRun = nil })
        }
        .alert("editor.post.soon", isPresented: $showPublishSoon) { Button("OK", role: .cancel) {} }
    }
}

private struct TestRun: Identifiable {
    let id = UUID()
    let stage: Stage
}

private struct ModePicker: View {
    let mode: Mode
    let onSelect: (Mode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.condition").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                option(.survive, "editor.mode.survive", "editor.mode.survive.sub")
                option(.boss, "editor.mode.boss", "editor.mode.boss.sub")
            }
        }
    }

    private func option(_ m: Mode, _ title: LocalizedStringKey, _ sub: LocalizedStringKey) -> some View {
        Button { onSelect(m) } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(sub).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.11, green: 0.09, blue: 0.25)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(mode == m ? Color(Palette.gold) : Color(Palette.barBack), lineWidth: mode == m ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editor.mode.\(m.rawValue)")
    }
}

private struct NameFields: View {
    @Binding var draft: Draft

    var body: some View {
        HStack(spacing: 10) {
            field("editor.name", text: $draft.name, limit: EditorModel.maxName, id: "editor.name")
            field("editor.author", text: $draft.authorName, limit: EditorModel.maxAuthor, id: "editor.author")
        }
    }

    private func field(_ label: LocalizedStringKey, text: Binding<String>, limit: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { v in if v.count > limit { text.wrappedValue = String(v.prefix(limit)) } }
                .accessibilityIdentifier(id)
        }
    }
}

private struct TimingFields: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.draft.mode == .boss ? "editor.limit" : "editor.endure").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: Binding(get: { model.draft.duration }, set: model.setDuration)) {
                        ForEach(model.durations, id: \.self) { Text(String(format: L("unit.seconds"), $0)).tag($0) }
                    }
                    .pickerStyle(.menu).labelsHidden()
                    .accessibilityIdentifier("editor.duration")
                }
                if model.draft.mode == .boss {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("editor.boss.move").font(.caption).foregroundStyle(.secondary)
                        Picker("", selection: $model.draft.bossMove) {
                            Text("editor.boss.move.0").tag(0)
                            Text("editor.boss.move.1").tag(1)
                            Text("editor.boss.move.2").tag(2)
                        }
                        .pickerStyle(.menu).labelsHidden()
                    }
                }
                Spacer(minLength: 0)
            }
            if model.draft.mode == .boss {
                SliderRow(label: "editor.boss.hp", value: Binding(get: { Double(model.draft.bossHp) }, set: { model.draft.bossHp = Int($0) }),
                          range: 100...1000, step: 50) { String(Int($0)) }
                Text("editor.boss.note").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    var disabled = false
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.footnote).foregroundStyle(.secondary).frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range, step: step).tint(Color(Palette.pink)).disabled(disabled)
            Text(format(value)).font(.system(.footnote, design: .monospaced)).frame(width: 64, alignment: .trailing)
        }
        .opacity(disabled ? 0.4 : 1)
    }
}

private struct StatusBox: View {
    let verified: Bool

    var body: some View {
        Text(verified ? "editor.status.ok" : "editor.status.need")
            .font(.subheadline)
            .foregroundStyle(verified ? Color(Palette.bullets[4]) : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(Palette.background)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(verified ? Color(Palette.bullets[4]) : Color(Palette.barBack)))
            .accessibilityIdentifier(verified ? "editor.status.ok" : "editor.status.need")
    }
}
