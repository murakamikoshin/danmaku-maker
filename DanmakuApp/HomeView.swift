import DanmakuCore
import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var deepLink: DeepLink
    @StateObject private var world = WorldViewModel()
    @State private var tab: Tab = .samples
    /// 世界のステージの絞り込み欄(クリア条件・難しさ)を開いているか。はじめは畳んでおく(場所を取るので)
    @AppStorage("home.world.filterOpen") private var filterOpen = false
    @State private var playing: SampleStage?
    @State private var detail: RemoteStage?
    /// 自分が世界に投稿したステージと、実績の合計(マイステージの下に出す)
    @State private var posted = MyStageSummary()
    @State private var postedLoaded = false
    @StateObject private var saved = LocalStageStore.shared
    @State private var editingEntry: SavedStage?
    @State private var playingMine: SavedStage?
    @State private var deletingEntry: SavedStage?
    @State private var worldDeleteFailed = false
    @State private var publishingEntry: SavedStage?
    @State private var query = ""
    @State private var searchError = false
    /// 一覧がスクロール中か(世界のステージのプレビュー・タイトルを止める)
    @State private var listScrolling = false
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
                    DailyRewardBanner()
                    GameSearchField(text: $query, prompt: "home.search.prompt") { Task { await search() } }
                    GameTabs(items: [(Tab.samples, "home.tab.samples"), (Tab.mine, "home.tab.mine"), (Tab.world, "home.tab.world")], selection: $tab, idPrefix: "home.tab")
                    switch tab {
                    case .samples: samples
                    case .mine: mine; postedSection
                    case .world: worldList
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24).padding(.top, 4)
                .trackListScrollingFallback($listScrolling)
            }
            .refreshable { if tab == .world { await world.reload() } }
            .trackListScrolling($listScrolling)
            .environment(\.listScrolling, listScrolling)
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
            PublishFlowView(stage: entry.stage, authorName: AuthorName.current.isEmpty ? entry.draft.authorName : AuthorName.current,
                            replay: entry.isVerified ? entry.verifiedReplay.flatMap({ Replay(encoded: $0) }) : nil) { id in
                var e = saved.stage(id: entry.id) ?? entry
                e.publishedStage = e.stage; e.publishedID = id
                saved.update(e)
                Task { await CosmeticsStore.shared.refreshPosts(uid: auth.uid); await CosmeticsStore.shared.refreshBossTickets(uid: auth.uid) }
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
        .sheet(item: $detail) { s in StageDetailView(remote: s, onShowAuthor: { showAuthor($0) }) }
        #if DEBUG
        .sheet(isPresented: $showStoreDebug) { StoreView() }
        #endif
        #if DEBUG
        .onAppear { applyLaunchArguments() }
        #endif
        .task(id: tab) { if tab == .world && world.stages.isEmpty { await world.reload() } }
        .task(id: "\(tab == .mine)-\(auth.isMember)") { if tab == .mine { await loadPosted() } }
        .onChange(of: world.sort) { _ in Task { await world.reload() } }
        .onChange(of: world.mode) { _ in Task { await world.reload() } }
        .onChange(of: world.difficulty) { _ in Task { await world.reload() } }
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

    private func loadPosted() async {
        guard auth.isMember, Backend.isAvailable else { posted = MyStageSummary(); postedLoaded = false; return }
        if let s = try? await StageRepository().mine() { posted = s; postedLoaded = true }
    }

    /// 自分が世界に投稿したステージ: もらったハート・遊ばれた数などの合計と、すぐ開ける一覧
    @ViewBuilder private var postedSection: some View {
        if auth.isMember && postedLoaded && !posted.list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("mystats.title").font(.system(size: 18, weight: .heavy, design: .rounded)).padding(.horizontal, 4)
                HStack(spacing: 0) {
                    statCell("heart.fill", posted.likes, "mystats.likes", Color(Palette.pink))
                    statCell("gamecontroller.fill", posted.plays, "mystats.plays", Color(UIColor(hex: 0x5CE1E6)))
                    statCell("flag.checkered", posted.clears, "mystats.clears", Color(Palette.gold))
                    statCell("bubble.left.fill", posted.comments, "mystats.comments", Color(Palette.bullets[4]))
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                Text(String(format: L("mystats.list"), posted.stages)).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.secondary).padding(.horizontal, 4)
                ForEach(posted.list) { s in
                    Button { gameTap(); detail = s } label: { RemoteRow(stage: s) }
                        .buttonStyle(BounceButtonStyle())
                }
            }
            .padding(.top, 8)
        }
    }

    private func statCell(_ icon: String, _ value: Int, _ label: LocalizedStringKey, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(tint)
            Text("\(value)").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var samples: some View {
        LazyVStack(alignment: .leading, spacing: 10) {
            Text("home.samples").font(.system(size: 18, weight: .heavy, design: .rounded)).padding(.horizontal, 4)
            ForEach(SampleStages.all) { s in
                Button { gameTap(); playing = s } label: { SampleRow(sample: s) }
                    .buttonStyle(BounceButtonStyle())
            }
        }
    }

    /// この作者のステージだけを、世界のステージ一覧に出す(詳細画面は閉じる)
    private func showAuthor(_ s: RemoteStage) {
        detail = nil
        query = ""; world.query = ""
        world.author = AuthorFilter(uid: s.authorUid, name: s.authorName)
        tab = .world
        Task { await world.reload() }
    }

    @ViewBuilder private var worldList: some View {
        if let a = world.author {
            // 作者で絞り込み中(解除すると、ふつうの一覧に戻る)
            HStack {
                Label(String(format: L("world.author.filter"), a.name), systemImage: "person.crop.rectangle.stack")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.gold)).lineLimit(1)
                Spacer()
                Button { gameTap(); world.author = nil; Task { await world.reload() } } label: { Chip(title: L("world.author.clear"), selected: false) }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("home.author.clear")
            }
        }
        if world.searching {
            HStack {
                Label(String(format: L("world.search.result"), world.query), systemImage: "magnifyingglass")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.gold)).lineLimit(1)
                Spacer()
                Button { gameTap(); query = ""; world.query = ""; Task { await world.reload() } } label: { Chip(title: L("world.search.clear"), selected: false) }
                    .buttonStyle(BounceButtonStyle())
            }
        }
        // クリア条件(モード)の絞り込みは、並び順のチップとは見た目も場所も分ける(同じチップが2段続くと、どちらが何か分かりにくかった)
        filters
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("world.sort.title", "arrow.up.arrow.down")
            ChipGrid(items: StageSort.allCases.map { ($0, L($0.titleKey)) }, selection: $world.sort, idPrefix: "home.sort", minimum: 84)
        }
        .opacity(world.searching ? 0.4 : 1).disabled(world.searching)
        // 画面に映った行だけを作る(行のプレビューとタイトルを、映ったときに動かし、外れたら止めるため)
        LazyVStack(spacing: 10) {
            if !Backend.isAvailable {
                Text("world.unavailable").font(.footnote).foregroundStyle(.secondary)
            }
            let visible = world.stages.filter { !blocks.isBlocked($0.authorUid) }
            ForEach(visible) { s in
                Button { gameTap(); detail = s } label: { RemoteRow(stage: s) }
                    .buttonStyle(.plain)
                    // 一覧に出ている最後の行が見えたら、続きを読む(ブロックした人のステージが最後でも止まらない)
                    .onAppear { if s.id == visible.last?.id { Task { await loadMoreWorld() } } }
            }
            if world.isLoading { HStack { Spacer(); ProgressView().tint(Color(Palette.pink)); Spacer() }.padding(.vertical, 8) }
            // 念のため、続きがあるときは「もっと見る」も出す(自動で読まれなかったときに、古いステージまでたどれるように)
            if !world.isLoading && !world.reachedEnd && !world.failed && !world.searching && !visible.isEmpty {
                Button { gameTap(); Task { await loadMoreWorld() } } label: { Chip(title: L("world.more"), selected: false) }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("home.world.more")
            }
            if world.failed {
                VStack(spacing: 8) {
                    Text("world.error").font(.footnote).foregroundStyle(.secondary)
                    Button { gameTap(); Task { await loadMoreWorld() } } label: { Chip(title: L("world.retry"), selected: true) }.buttonStyle(BounceButtonStyle())
                }
            }
            if world.stages.isEmpty && !world.isLoading && !world.failed && Backend.isAvailable {
                Text(world.searching ? "world.search.empty" : "world.empty").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 20)
            }
        }
    }

    private func loadMoreWorld() async {
        await world.loadMore { !blocks.isBlocked($0.authorUid) }
    }

    private static let modeOptions: [(Mode?, String)] = [
        (nil, "world.filter.all"), (.survive, "editor.mode.survive"), (.boss, "editor.mode.boss"),
        (.damage, "editor.mode.damage"), (.sequence, "editor.mode.sequence"),
    ]

    /// 絞り込み(クリア条件・難しさ)。畳めるようにして、畳んでいる間は、今かけている条件を1行で見せる
    private var filters: some View {
        let modeText = world.mode.flatMap { m in Self.modeOptions.first { $0.0 == m }.map { L($0.1) } }
        let diffText = world.difficulty.map { L($0.titleKey) }
        let active = [modeText, diffText].compactMap { $0 }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                gameTap()
                withAnimation(.easeInOut(duration: 0.2)) { filterOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "line.3.horizontal.decrease.circle\(active.isEmpty ? "" : ".fill")")
                        .foregroundStyle(active.isEmpty ? Color(Palette.text).opacity(0.7) : Color(Palette.gold))
                    Text("world.filter.toggle").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                    if !filterOpen && !active.isEmpty {
                        Text(active.joined(separator: " / ")).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.gold)).lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold)).foregroundStyle(Color(Palette.text).opacity(0.6))
                        .rotationEffect(.degrees(filterOpen ? 180 : 0))
                }
                .padding(.vertical, 10).padding(.horizontal, 14)
                .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(GameStyle.edge))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("home.filter.toggle")
            if filterOpen {
                modeFilter
                difficultyFilter
            }
        }
    }

    /// クリア条件の絞り込み: 見出しと、今の条件を出すプルダウン。絞り込み中は色をつけて目立たせる
    private var modeFilter: some View {
        return VStack(alignment: .leading, spacing: 8) {
            sectionLabel("world.filter.title", "flag.checkered")
            ChipGrid(items: Self.modeOptions.map { ($0.0, L($0.1)) }, selection: $world.mode, idPrefix: "home.mode", minimum: 70)
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GameStyle.edge))
    }

    /// 難しさ(クリア率)の絞り込み。挑戦が10回以上のステージだけが対象
    private var difficultyFilter: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("world.filter.difficulty", "gauge.with.dots.needle.67percent")
            ChipGrid(items: [(nil as WorldDifficulty?, L("world.filter.all"))] + WorldDifficulty.allCases.map { ($0 as WorldDifficulty?, L($0.titleKey)) },
                     selection: $world.difficulty, idPrefix: "home.diff", minimum: 70)
            if world.difficulty != nil { Text("world.diff.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.55)) }
        }
        .padding(.vertical, 10).padding(.horizontal, 14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(GameStyle.edge))
    }

    private func sectionLabel(_ key: LocalizedStringKey, _ symbol: String) -> some View {
        Label(key, systemImage: symbol)
            .font(.system(size: 13, weight: .heavy, design: .rounded))
            .foregroundStyle(Color(Palette.text).opacity(0.8))
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

    /// 上の検索欄: 5文字のステージIDならそのステージを開き、そうでなければ(見つからなければ)ステージ名で探す
    private func search() async {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let id = raw.uppercased()
        if id.range(of: "^[2-9A-HJKMNP-Z]{5}$", options: .regularExpression) != nil,
           let s = try? await StageRepository().find(id: id), !blocks.isBlocked(s.authorUid) {
            detail = s
            return
        }
        tab = .world
        world.query = raw
        await world.reload()
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

/// 一覧の見せ場の静止画(作者が決めた1枚)。読み込めなければ、動くプレビューにする
struct PreviewStillTile: View {
    let url: URL
    let stage: Stage
    let playing: Bool
    let visible: Bool
    var size: CGFloat = 56

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.interpolation(.medium).resizable().scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.21))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.21).stroke(Color.white.opacity(0.15), lineWidth: 1))
            case .failure:
                StageMiniPreview(stage: stage, playing: playing, visible: visible)
            default:
                Color(Skin.of(stage.lookBackground).background).frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.21))
            }
        }
        .accessibilityHidden(true)
    }
}

struct RemoteRow: View {
    let stage: RemoteStage
    @Environment(\.listScrolling) private var scrolling
    @ObservedObject private var badges = ProfileBadgeStore.shared
    /// 画面に映っているか(一覧は LazyVStack なので、映ったとき・外れたときに変わる)
    @State private var visible = false
    var body: some View {
        // 画面に映っていて、スクロール中でないときだけ、プレビューとタイトルを動かす
        let playing = visible && !scrolling
        StageCardShell(mode: stage.stage.mode,
                       thumbnail: stage.stage.hidesPreview
                           ? AnyView(SpoilerTile())
                           : stage.hasPreviewImage ? AnyView(PreviewStillTile(url: stage.previewImageURL, stage: stage.stage, playing: playing, visible: visible))
                           : AnyView(StageMiniPreview(stage: stage.stage, playing: playing, visible: visible))) {
            VStack(alignment: .leading, spacing: 4) {
                MarqueeTitle(text: stage.name, font: .system(size: 16, weight: .heavy, design: .rounded), playing: playing, visible: visible)
                    .foregroundStyle(Color(Palette.text))
                HStack(spacing: 6) {
                    ModeBadge(mode: stage.stage.mode)
                    // 作者の名前の横に、称号と王冠(あれば)
                    HStack(spacing: 0) {
                        Text("\(detailText(stage.stage)) · by ").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).layoutPriority(1)
                        BadgedName(name: stage.authorName, badge: badges.badge(stage.authorUid), size: 11, weight: .semibold, baseColor: .secondary, inlineChip: true)
                    }
                }
                HStack(spacing: 12) {
                    Label("\(stage.plays)", systemImage: "gamecontroller")
                    Label("\(stage.clears)", systemImage: "flag.checkered")
                    Label("\(stage.likes)", systemImage: "heart")
                    Label("\(stage.comments)", systemImage: "bubble.left")
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                PercentRing(percent: stage.clearRatePercent)
                Text("world.clearrate").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            }
        }
        .onAppear { visible = true; badges.request([stage.authorUid]) }
        .onDisappear { visible = false }
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
                action(entry.isPublished ? "mystage.posted" : (entry.isVerified ? "mystage.publish" : "mystage.publish.unlisted"), "paperplane.fill", Color(Palette.pink), onPublish)
                    .opacity(entry.isPublished ? 0.4 : 1)
                    .disabled(entry.isPublished)
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
