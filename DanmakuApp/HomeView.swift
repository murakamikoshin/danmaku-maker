import DanmakuCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var deepLink: DeepLink
    @StateObject private var world = WorldViewModel()
    @State private var tab: Tab = .samples
    @State private var playing: SampleStage?
    @State private var detail: RemoteStage?
    @State private var editing = false
    @State private var showSettings = false
    @State private var query = ""
    @State private var searchError = false

    enum Tab: Hashable { case samples, world }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("", selection: $tab) {
                        Text("home.tab.samples").tag(Tab.samples)
                        Text("home.tab.world").tag(Tab.world)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .accessibilityIdentifier("home.tab")
                }
                if tab == .samples { samples } else { worldList }
            }
            .navigationTitle("app.title")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("home.search.prompt"))
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .onSubmit(of: .search) { Task { await search() } }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Label("home.settings", systemImage: "gearshape") }
                        .accessibilityIdentifier("home.settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editing = true } label: { Label("home.create", systemImage: "plus") }
                        .accessibilityIdentifier("home.create")
                }
            }
            .alert("home.search.notfound", isPresented: $searchError) { Button("OK", role: .cancel) {} }
        }
        .fullScreenCover(item: $playing) { s in
            PlayView(stage: s.stage, title: s.title) { playing = nil }
        }
        .fullScreenCover(isPresented: $editing) { EditorView { editing = false } }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $detail) { StageDetailView(remote: $0) }
        #if DEBUG
        .onAppear { applyLaunchArguments() }
        #endif
        .task(id: tab) { if tab == .world && world.stages.isEmpty { await world.reload() } }
        .onChange(of: world.sort) { _ in Task { await world.reload() } }
        .onChange(of: deepLink.stageID) { id in
            guard let id else { return }
            deepLink.stageID = nil
            Task { await open(id: id) }
        }
    }

    private var samples: some View {
        Section {
            ForEach(SampleStages.all) { s in
                Button { playing = s } label: { SampleRow(sample: s) }
            }
        } header: { Text("home.samples") }
    }

    @ViewBuilder private var worldList: some View {
        Section {
            Picker("", selection: $world.sort) {
                ForEach(StageSort.allCases) { Text(LocalizedStringKey($0.titleKey)).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
        }
        Section {
            if !Backend.isAvailable {
                Text("world.unavailable").foregroundStyle(.secondary)
            }
            ForEach(world.stages.filter { !blocks.isBlocked($0.authorUid) }) { s in
                Button { detail = s } label: { RemoteRow(stage: s) }
                    .onAppear { if s.id == world.stages.last?.id { Task { await world.loadMore() } } }
            }
            if world.isLoading { HStack { Spacer(); ProgressView(); Spacer() } }
            if world.failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("world.error").foregroundStyle(.secondary)
                    Button("world.retry") { Task { await world.loadMore() } }.buttonStyle(.bordered)
                }
            }
            if world.stages.isEmpty && !world.isLoading && !world.failed && Backend.isAvailable {
                Text("world.empty").foregroundStyle(.secondary)
            }
        }
        .refreshable { await world.reload() }
    }

    #if DEBUG
    /// スクリーンショット撮影用: `-open-stage o29`（公式ステージを開く）、`-open-editor`、`-open-boss-editor` は DEBUG ビルドだけ
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let i = args.firstIndex(of: "-open-stage"), args.indices.contains(i + 1),
               let s = SampleStages.all.first(where: { $0.id == args[i + 1] }) { playing = s }
            if args.contains("-open-editor") { editing = true }
        }
    }
    #endif

    private func search() async {
        let id = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard id.count == 5 else { searchError = true; return }
        await open(id: id)
    }

    private func open(id: String) async {
        if let s = try? await StageRepository().find(id: id), !blocks.isBlocked(s.authorUid) {
            detail = s
        } else {
            searchError = true
        }
    }
}

struct ModeBadge: View {
    let mode: Mode
    var body: some View {
        Text(mode == .boss ? "badge.boss" : "badge.survive")
            .font(.caption2.bold())
            .padding(.horizontal, 7).padding(.vertical, 1)
            .overlay(Capsule().stroke(lineWidth: 1))
            .foregroundStyle(mode == .boss ? Color(Palette.pink) : Color(Palette.bullets[1]))
    }
}

func detailText(_ st: Stage) -> String {
    st.mode == .boss ? String(format: L("detail.boss"), st.bossHp ?? 0, st.durationSec) : String(format: L("detail.survive"), st.durationSec)
}

struct SampleRow: View {
    let sample: SampleStage
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.title).font(.headline)
            HStack(spacing: 6) {
                ModeBadge(mode: sample.stage.mode)
                Text(detailText(sample.stage)).font(.caption).foregroundStyle(.secondary)
                Text(String(repeating: "★", count: sample.difficulty)).font(.caption).foregroundStyle(Color(Palette.gold))
            }
            Text(sample.aim).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
    }
}

struct RemoteRow: View {
    let stage: RemoteStage
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.name).font(.headline).lineLimit(2)
                HStack(spacing: 6) {
                    ModeBadge(mode: stage.stage.mode)
                    Text("\(detailText(stage.stage)) · by \(stage.authorName)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label("\(stage.plays)", systemImage: "gamecontroller")
                    Label("\(stage.clears)", systemImage: "flag.checkered")
                    Label("\(stage.likes)", systemImage: "heart")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack {
                Text(stage.clearRatePercent.map { "\($0)%" } ?? "—")
                    .font(.system(.title3, design: .monospaced)).foregroundStyle(Color(Palette.gold))
                Text("world.clearrate").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
