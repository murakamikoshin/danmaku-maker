import SwiftUI
import DanmakuCore

struct HomeView: View {
    @State private var playing: SampleStage?
    @State private var editing = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SampleStages.all) { s in
                        Button { playing = s } label: { StageRow(sample: s) }
                    }
                } header: {
                    Text("home.samples")
                }
            }
            .navigationTitle("app.title")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: { Label("home.create", systemImage: "plus") }
                        .accessibilityIdentifier("home.create")
                }
            }
        }
        .fullScreenCover(isPresented: $editing) { EditorView { editing = false } }
        .fullScreenCover(item: $playing) { s in
            PlayView(stage: s.stage, title: L(s.nameKey)) { playing = nil }
        }
    }
}

struct StageRow: View {
    let sample: SampleStage

    var body: some View {
        let st = sample.stage
        VStack(alignment: .leading, spacing: 4) {
            Text(L(sample.nameKey)).font(.headline)
            HStack(spacing: 6) {
                Text(st.mode == .boss ? "badge.boss" : "badge.survive")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7).padding(.vertical, 1)
                    .overlay(Capsule().stroke(lineWidth: 1))
                    .foregroundStyle(st.mode == .boss ? Color(Palette.pink) : Color(Palette.bullets[1]))
                Text(st.mode == .boss
                     ? String(format: L("detail.boss"), st.bossHp ?? 0, st.durationSec)
                     : String(format: L("detail.survive"), st.durationSec))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    HomeView()
}
