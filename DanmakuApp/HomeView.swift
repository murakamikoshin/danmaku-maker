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
    @StateObject private var saved = LocalStageStore.shared
    @State private var editingEntry: SavedStage?
    @State private var playingMine: SavedStage?
    @State private var deletingEntry: SavedStage?
    @State private var worldDeleteFailed = false
    @State private var publishingEntry: SavedStage?
    @State private var query = ""
    @State private var searchError = false
    #if DEBUG
    @State private var showStoreDebug = false
    #endif

    enum Tab: Hashable { case samples, mine, world }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                LogoTitle(text: "app.title", size: 27)
                Spacer(minLength: 8)
                Button { gameTap(); newStage() } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .heavy))
                        Text("home.create").font(.system(size: 14, weight: .heavy, design: .rounded)).lineLimit(1)
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
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GameSearchField(text: $query, prompt: "home.search.prompt") { Task { await search() } }
                    GameTabs(items: [(Tab.samples, "home.tab.samples"), (Tab.mine, "home.tab.mine"), (Tab.world, "home.tab.world")], selection: $tab, idPrefix: "home.tab")
                    switch tab {
                    case .samples: samples
                    case .mine: mine
                    case .world: worldList
                    }
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
        .fullScreenCover(item: $editingEntry) { entry in EditorView(entry: entry) { editingEntry = nil } }
        .fullScreenCover(item: $playingMine) { entry in
            // マイステージから遊んでクリアしても、テストプレイと同じ「クリア確認済み」にする(復活を使ったクリアは、サーバーで検証できないので除く)
            PlayView(stage: entry.stage, title: entry.displayName, customs: entry.draft.customImages,
                     onResult: { result, moves in
                         guard result.outcome == .cleared, !result.revived else { return }
                         var e = saved.stage(id: entry.id) ?? entry
                         guard e.stage == entry.stage else { return }
                         e.verifiedStage = entry.stage
                         e.verifiedReplay = Replay(moves: moves).encoded()
                         saved.update(e)
                     },
                     onExit: { playingMine = nil })
        }
        .sheet(item: $publishingEntry) { entry in
            if let r = entry.verifiedReplay.flatMap({ Replay(encoded: $0) }) {
                PublishFlowView(stage: entry.stage, authorName: AuthorName.current.isEmpty ? entry.draft.authorName : AuthorName.current, replay: r) { id in
                    var e = saved.stage(id: entry.id) ?? entry
                    e.publishedStage = e.stage; e.publishedID = id
                    saved.update(e)
                    Task { await CosmeticsStore.shared.refreshPosts(uid: auth.uid) }
                }
            }
        }
        .confirmationDialog("mystage.delete.title", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }), titleVisibility: .visible) {
            if let e = deletingEntry, e.publishedID != nil {
                // 投稿済み: 世界から消すか、端末のコピーだけ消すかを選ぶ
                Button("mystage.delete.world", role: .destructive) { Task { await deleteFromWorld(e) } }
                Button("mystage.delete.local", role: .destructive) { saved.delete(id: e.id) }
            } else {
                Button("mystage.delete", role: .destructive) { if let e = deletingEntry { saved.delete(id: e.id) } }
            }
            Button("common.cancel", role: .cancel) {}
        } message: { Text(deletingEntry?.publishedID != nil ? "mystage.delete.world.message" : "mystage.delete.message") }
        .alert("mystage.delete.failed", isPresented: $worldDeleteFailed) { Button("OK", role: .cancel) {} }
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

    /// 世界から消す(端末のコピーは残し、投稿済みの印だけ外す)
    private func deleteFromWorld(_ e: SavedStage) async {
        guard let id = e.publishedID else { return }
        guard await StageRepository().deleteStage(id: id) else { worldDeleteFailed = true; return }
        var v = saved.stage(id: e.id) ?? e
        v.publishedStage = nil; v.publishedID = nil
        saved.update(v)
    }

    /// 新しいステージを作って、すぐに編集画面を開く(作った時点で、マイステージに保存される)
    private func newStage() {
        guard let s = saved.create() else { return }
        tab = .mine
        editingEntry = s
    }

    /// マイステージ: 作ったステージを、投稿しなくても保存して、いつでも遊べる・直せる
    private var mine: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("home.mine").font(.system(size: 18, weight: .heavy, design: .rounded)).padding(.horizontal, 4)
            Text("home.mine.note").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 4)
            if saved.stages.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.pencil").font(.system(size: 34)).foregroundStyle(Color(Palette.pink))
                    Text("home.mine.empty").font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    GameActionButton(title: "home.create", systemImage: "plus", fill: GameStyle.accent) { newStage() }
                }
                .padding(.vertical, 24).frame(maxWidth: .infinity)
            } else {
                ForEach(saved.stages) { e in MyStageRow(entry: e, onPlay: { playingMine = e }, onEdit: { editingEntry = e },
                                                         onPublish: { if e.draft.name.trimmingCharacters(in: .whitespaces).isEmpty || (AuthorName.current.isEmpty && e.draft.authorName.trimmingCharacters(in: .whitespaces).isEmpty) { editingEntry = e } else { publishingEntry = e } }, onDelete: { deletingEntry = e }) }
            }
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
            if args.contains("-open-editor"), editingEntry == nil, let first = saved.stages.first ?? saved.create() { editingEntry = first }
            // 画面確認用: 連戦(雑魚 → 中ボス → 大ボス)のステージを作って、編集画面を開く
            if args.contains("-open-sequence-editor"), editingEntry == nil, var e = saved.create() {
                e.draft.mode = .sequence
                e.draft.name = "連戦テスト"
                e.draft.authorName = "Koshin"
                var w1 = DraftWave(kind: .survive); w1.duration = 20
                var w2 = DraftWave(kind: .boss); w2.bossHp = 200; w2.duration = 30; w2.defeat = DefeatEffect.fireworks.rawValue
                var w3 = DraftWave(kind: .boss); w3.bossHp = 800; w3.duration = 90; w3.warning = true; w3.defeat = DefeatEffect.explosion.rawValue
                e.draft.waves = [w1, w2, w3]
                saved.update(e)
                editingEntry = e
            }
            // 画面確認用: 保存した最初のステージで遊ぶ
            if args.contains("-play-first-mine"), playingMine == nil, let first = saved.stages.first { playingMine = first }
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
        case .sequence: return Color(Palette.bullets[3])
        case .survive: return Color(UIColor(hex: 0x5CE1E6))
        }
    }
    var body: some View {
        Text(mode == .boss ? "badge.boss" : mode == .damage ? "badge.damage" : mode == .sequence ? "badge.sequence" : "badge.survive")
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
    case .sequence: text = String(format: L("detail.sequence"), st.waves?.count ?? 1, st.durationSec)
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


/// マイステージの1行。タップで遊ぶ。編集・投稿・削除のボタンつき
struct MyStageRow: View {
    let entry: SavedStage
    let onPlay: () -> Void
    let onEdit: () -> Void
    let onPublish: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button { gameTap(); onPlay() } label: {
                StageCardShell(mode: entry.stage.mode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.displayName).font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).lineLimit(1)
                        HStack(spacing: 6) {
                            ModeBadge(mode: entry.stage.mode)
                            Text(detailText(entry.stage)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            if entry.isPublished { tag("mystage.posted", Color(Palette.gold)) }
                            else if entry.isVerified { tag("mystage.cleared", Color(Palette.bullets[4])) }
                            else { tag("mystage.notcleared", Color.white.opacity(0.5)) }
                            Text(entry.updatedAt, style: .relative).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.fill").font(.system(size: 14, weight: .heavy)).foregroundStyle(Color(Palette.text).opacity(0.5))
                }
            }
            .buttonStyle(BounceButtonStyle())
            HStack(spacing: 8) {
                action("mystage.edit", "pencil", Color(UIColor(hex: 0x5CE1E6)), onEdit)
                action(entry.isPublished ? "mystage.posted" : "mystage.publish", "paperplane.fill", Color(Palette.pink), onPublish)
                    .opacity(entry.isVerified && !entry.isPublished ? 1 : 0.4)
                    .disabled(!(entry.isVerified && !entry.isPublished))
                action("mystage.delete", "trash", Color(Palette.pink).opacity(0.8), onDelete)
            }
            .padding(.horizontal, 4)
        }
    }

    private func tag(_ key: LocalizedStringKey, _ color: Color) -> some View {
        Text(key).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 1).overlay(Capsule().stroke(color.opacity(0.7), lineWidth: 1))
    }

    private func action(_ key: LocalizedStringKey, _ symbol: String, _ color: Color, _ run: @escaping () -> Void) -> some View {
        Button { gameTap(); run() } label: {
            Label(key, systemImage: symbol).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(color)
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(BounceButtonStyle())
    }
}
