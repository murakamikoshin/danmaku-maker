import SwiftUI
import DanmakuCore

struct EditorView: View {
    @StateObject private var model = EditorModel()
    @State private var testRun: TestRun?
    @State private var publishing = false
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GamePanel(title: "editor.condition") {
                        ModeCards(mode: model.draft.mode, onSelect: model.setMode)
                    }
                    GamePanel(title: "editor.section.basic", tint: Color(UIColor(hex: 0x5CE1E6))) {
                        NameFields(draft: $model.draft)
                    }
                    TimingPanel(model: model)
                    LifePanel(model: model)
                    ForEach(Array(model.draft.emitters.indices), id: \.self) { i in
                        EmitterCard(index: i, emitter: $model.draft.emitters[i], isBoss: model.draft.mode != .survive,
                                    duration: model.draft.duration, canDelete: model.draft.emitters.count > 1,
                                    onDelete: { model.removeEmitter(at: i) })
                    }
                    Button { gameTap(); model.addEmitter() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "plus.circle.fill").font(.system(size: 20))
                            Text("editor.add").font(.system(size: 16, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Color(Palette.gold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(Palette.gold).opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .opacity(model.canAdd ? 1 : 0.4)
                    .disabled(!model.canAdd)
                    .accessibilityIdentifier("editor.add")

                    StatusBox(verified: model.isVerified)
                    HStack(spacing: 10) {
                        GameActionButton(title: "editor.test", systemImage: "play.fill", fill: GameStyle.cyan) {
                            testRun = TestRun(stage: model.stage)
                        }
                        .accessibilityIdentifier("editor.test")
                        GameActionButton(title: "editor.post", systemImage: "paperplane.fill", fill: GameStyle.accent,
                                         enabled: model.isVerified && model.canPublish) { publishing = true }
                        .accessibilityIdentifier("editor.post")
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(Palette.background).ignoresSafeArea())
            .navigationTitle("editor.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("editor.close", action: onClose).accessibilityIdentifier("editor.close") } }
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
        .sheet(isPresented: $publishing) {
            if let replay = model.clearReplay {
                PublishFlowView(stage: model.stage, authorName: model.draft.authorName, replay: replay) { model.published() }
            }
        }
    }
}

private struct TestRun: Identifiable {
    let id = UUID()
    let stage: Stage
}

private struct NameFields: View {
    @Binding var draft: Draft

    var body: some View {
        VStack(spacing: 10) {
            field("editor.name", prompt: "editor.name.placeholder", text: $draft.name, limit: EditorModel.maxName, id: "editor.name")
            field("editor.author", prompt: "editor.author.placeholder", text: $draft.authorName, limit: EditorModel.maxAuthor, id: "editor.author")
        }
    }

    private func field(_ label: LocalizedStringKey, prompt: LocalizedStringKey, text: Binding<String>, limit: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.vertical, 11).padding(.horizontal, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(GameStyle.edge))
                .onChange(of: text.wrappedValue) { v in if v.count > limit { text.wrappedValue = String(v.prefix(limit)) } }
                .accessibilityIdentifier(id)
        }
    }
}

/// 制限時間(生き残る時間)、ボスの動き、ボスのHP
private struct TimingPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GamePanel(title: model.draft.mode == .survive ? "editor.endure" : "editor.limit", tint: Color(Palette.bullets[2])) {
            ChipGrid(items: model.durations.map { ($0, $0 == 0 ? L("editor.unlimited") : String(format: L("unit.seconds"), $0)) },
                     selection: Binding(get: { model.draft.duration }, set: model.setDuration),
                     idPrefix: "editor.duration")
            if model.draft.mode != .survive {
                VStack(alignment: .leading, spacing: 8) {
                    Text("editor.boss.move").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    BossMoveCards(move: $model.draft.bossMove)
                }
            }
            if model.draft.mode == .boss {
                if model.draft.duration == 0 { Text("editor.unlimited.note").font(.caption).foregroundStyle(.secondary) }
                SliderRow(label: "editor.boss.hp", value: Binding(get: { Double(model.draft.bossHp) }, set: { model.draft.bossHp = Int($0) }),
                          range: 100...1000, step: 50) { String(Int($0)) }
                Text("editor.boss.note").font(.caption).foregroundStyle(.secondary)
            } else if model.draft.mode == .damage {
                Text("editor.damage.note").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// 自機のライフ(ライフ制・HP制)
private struct LifePanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let range = model.draft.lifeMode == .lives ? Stage.livesRange : Stage.hpRange
        GamePanel(title: "editor.life", tint: Color(Palette.pink)) {
            ChipGrid(items: [(LifeMode.lives, L("editor.life.lives")), (LifeMode.hp, L("editor.life.hp"))],
                     selection: Binding(get: { model.draft.lifeMode }, set: model.setLifeMode),
                     idPrefix: "editor.life.mode", minimum: 110)
            HStack {
                CountStepper(value: Binding(get: { min(range.upperBound, max(range.lowerBound, model.draft.lifeCount)) },
                                            set: { model.draft.lifeCount = $0 }),
                             range: range, idPrefix: "editor.life.count")
                Spacer(minLength: 8)
                LifePreview(mode: model.draft.lifeMode, count: min(range.upperBound, max(range.lowerBound, model.draft.lifeCount)))
            }
            Text(model.draft.lifeMode == .lives ? "editor.life.note.lives" : "editor.life.note.hp")
                .font(.caption).foregroundStyle(.secondary)
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
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary).frame(width: 74, alignment: .leading)
            GameSlider(value: $value, range: range, step: step).allowsHitTesting(!disabled)
            Text(format(value))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.vertical, 4).padding(.horizontal, 6)
                .frame(width: 64)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .opacity(disabled ? 0.35 : 1)
    }
}

private struct StatusBox: View {
    let verified: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: verified ? "checkmark.seal.fill" : "flag.checkered")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(verified ? Color(Palette.bullets[4]) : Color(Palette.gold))
            Text(verified ? "editor.status.ok" : "editor.status.need")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(verified ? Color(Palette.bullets[4]) : Color(Palette.text))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(verified ? Color(Palette.bullets[4]) : GameStyle.edge, lineWidth: verified ? 2 : 1))
        .accessibilityIdentifier(verified ? "editor.status.ok" : "editor.status.need")
    }
}
