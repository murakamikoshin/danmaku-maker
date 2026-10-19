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
    @State private var query = ""
    @State private var searchError = false
    #if DEBUG
    @State private var showStoreDebug = false
    #endif

    enum Tab: Hashable { case samples, world }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(logo: "app.title") {
                Color.clear.frame(width: 38, height: 38)
            } trailing: {
                Button { gameTap(); editing = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                        Text("home.create").font(.system(size: 14, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .background(GameStyle.accent, in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.4)))
                    .shadow(color: Color(Palette.pink).opacity(0.5), radius: 6)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityIdentifier("home.create")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GameSearchField(text: $query, prompt: "home.search.prompt") { Task { await search() } }
                    GameTabs(items: [(Tab.samples, "home.tab.samples"), (Tab.world, "home.tab.world")], selection: $tab, idPrefix: "home.tab")
                    if tab == .samples { samples } else { worldList }
                }
                .padding(.horizontal, 16).padding(.bottom, 24).padding(.top, 4)
            }
            .refreshable { if tab == .world { await world.reload() } }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .alert("home.search.notfound", isPresented: $searchError) { Button("OK", role: .cancel) {} }
        .fullScreenCover(item: $playing) { s in
            PlayView(stage: s.stage, title: s.title) { playing = nil }
        }
        .fullScreenCover(isPresented: $editing) { EditorView { editing = false } }
        .sheet(item: $detail) { StageDetailView(remote: $0) }
        #if DEBUG
        .sheet(isPresented: $showStoreDebug) { StoreView() }
        #endif
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
        VStack(alignment: .leading, spacing: 10) {
            Text("home.samples").font(.system(size: 18, weight: .heavy, design: .rounded)).padding(.horizontal, 4)
            ForEach(SampleStages.all) { s in
                Button { gameTap(); playing = s } label: { SampleRow(sample: s) }
                    .buttonStyle(BounceButtonStyle())
            }
        }
    }

    @ViewBuilder private var worldList: some View {
        ChipGrid(items: StageSort.allCases.map { ($0, L($0.titleKey)) }, selection: $world.sort, idPrefix: "home.sort", minimum: 84)
        VStack(spacing: 10) {
            if !Backend.isAvailable {
                Text("world.unavailable").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(world.stages.filter { !blocks.isBlocked($0.authorUid) }) { s in
                Button { gameTap(); detail = s } label: { RemoteRow(stage: s) }
                    .buttonStyle(BounceButtonStyle())
                    .onAppear { if s.id == world.stages.last?.id { Task { await world.loadMore() } } }
            }
            if world.isLoading { HStack { Spacer(); ProgressView().tint(Color(Palette.pink)); Spacer() }.padding(.vertical, 8) }
            if world.failed {
                VStack(spacing: 8) {
                    Text("world.error").font(.footnote).foregroundStyle(.secondary)
                    Button { gameTap(); Task { await world.loadMore() } } label: { Chip(title: L("world.retry"), selected: true) }.buttonStyle(BounceButtonStyle())
                }
            }
            if world.stages.isEmpty && !world.isLoading && !world.failed && Backend.isAvailable {
                Text("world.empty").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
    }

    #if DEBUG
    /// スクリーンショット撮影用: `-open-stage o29`（公式ステージを開く）、`-open-editor`、`-open-boss-editor` は DEBUG ビルドだけ
    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func openRequested() {
            if let i = args.firstIndex(of: "-open-stage"), args.indices.contains(i + 1), playing == nil,
               let s = SampleStages.all.first(where: { $0.id == args[i + 1] }) { playing = s }
            if args.contains("-open-editor"), !editing { editing = true }
            if args.contains("-open-store"), !showStoreDebug { showStoreDebug = true }
        }
        // 画面の準備前だと表示が無視されることがあるので、数回に分けて試す
        for delay in [1.5, 5.0, 10.0] { DispatchQueue.main.asyncAfter(deadline: .now() + delay) { openRequested() } }
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
    private var tint: Color {
        switch mode {
        case .boss: return Color(Palette.pink)
        case .damage: return Color(Palette.gold)
        case .survive: return Color(UIColor(hex: 0x5CE1E6))
        }
    }
    var body: some View {
        Text(mode == .boss ? "badge.boss" : mode == .damage ? "badge.damage" : "badge.survive")
            .font(.system(size: 10, weight: .heavy, design: .rounded))
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .overlay(Capsule().stroke(tint.opacity(0.6), lineWidth: 1))
    }
}

func detailText(_ st: Stage) -> String {
    var text: String
    switch st.mode {
    case .boss: text = st.durationSec == 0 ? String(format: L("detail.boss.unlimited"), st.bossHp ?? 0) : String(format: L("detail.boss"), st.bossHp ?? 0, st.durationSec)
    case .damage: text = String(format: L("detail.damage"), st.durationSec)
    case .survive: text = String(format: L("detail.survive"), st.durationSec)
    }
    // 標準(ライフ1)以外のときだけ、耐久を添える
    if st.effectiveLifeMode == .hp { text += " · " + String(format: L("detail.life.hp"), st.effectiveLifeCount) }
    else if st.effectiveLifeCount > 1 { text += " · " + String(format: L("detail.life.lives"), st.effectiveLifeCount) }
    return text
}

struct SampleRow: View {
    let sample: SampleStage
    var body: some View {
        StageCardShell(mode: sample.stage.mode) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.title).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).lineLimit(1)
                HStack(spacing: 6) {
                    ModeBadge(mode: sample.stage.mode)
                    Text(detailText(sample.stage)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(String(repeating: "★", count: sample.difficulty)).font(.system(size: 12)).foregroundStyle(Color(Palette.gold))
                Text(sample.aim).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "play.fill").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(Palette.text).opacity(0.5))
        }
    }
}

struct RemoteRow: View {
    let stage: RemoteStage
    var body: some View {
        StageCardShell(mode: stage.stage.mode) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.name).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    ModeBadge(mode: stage.stage.mode)
                    Text("\(detailText(stage.stage)) · by \(stage.authorName)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 12) {
                    Label("\(stage.plays)", systemImage: "gamecontroller")
                    Label("\(stage.clears)", systemImage: "flag.checkered")
                    Label("\(stage.likes)", systemImage: "heart")
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                PercentRing(percent: stage.clearRatePercent)
                Text("world.clearrate").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
    }
}
