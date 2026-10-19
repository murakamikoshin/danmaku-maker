import SwiftUI
import DanmakuCore

struct EditorView: View {
    @StateObject private var model: EditorModel
    @State private var testRun: TestRun?
    @State private var publishing = false
    @State private var confirmRevert = false
    @State private var collapsedCards: Set<Int> = []

    private func collapsedBinding(_ i: Int) -> Binding<Bool> {
        Binding(get: { collapsedCards.contains(i) },
                set: { if $0 { collapsedCards.insert(i) } else { collapsedCards.remove(i) } })
    }
    /// 「かんたん」は、モード・名前・時間・発射台だけ。「くわしく」は、ライフ・BGM・見た目・演出なども出す
    @AppStorage("editor.advanced.v1") private var advanced = false
    let onClose: () -> Void

    init(entry: SavedStage, onClose: @escaping () -> Void) {
        _model = StateObject(wrappedValue: EditorModel(entry: entry))
        self.onClose = onClose
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "editor.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { onClose() }
                    .accessibilityIdentifier("editor.close")
            } trailing: {
                Button { confirmRevert = true } label: {
                    Label("editor.revert", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(Palette.gold)).labelStyle(.titleAndIcon)
                }
                .disabled(!model.canRevert).opacity(model.canRevert ? 1 : 0.35)
                .accessibilityIdentifier("editor.revert")
                Label("editor.autosaved", systemImage: "checkmark.icloud.fill").font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Color(Palette.bullets[4])).labelStyle(.titleAndIcon)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    GameTabs(items: [(false, "editor.simple"), (true, "editor.advanced")], selection: $advanced, idPrefix: "editor.level")
                    Text(advanced ? "editor.advanced.note" : "editor.simple.note").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    GamePanel(title: "editor.condition") {
                        ModeCards(mode: model.draft.mode, onSelect: model.setMode)
                    }
                    GamePanel(title: "editor.section.basic", tint: Color(UIColor(hex: 0x5CE1E6))) {
                        NameFields(draft: $model.draft)
                    }
                    ShotPanel(model: model)
                    if model.draft.mode == .sequence {
                        WavesSection(model: model, advanced: advanced)
                    } else {
                        TimingPanel(model: model)
                        if advanced { EffectsPanel(model: model) }
                    }
                    if advanced {
                        LifePanel(model: model)
                        BGMPanel(model: model)
                        LookPanel(model: model)
                        if model.draft.mode != .sequence {
                            GamePanel(title: "editor.enemy", tint: Color(Palette.bullets[3])) {
                                EnemyControls(showBoss: model.draft.mode != .survive,
                                              bossSize: $model.draft.bossSize, bossLook: $model.draft.bossLook,
                                              mooks: $model.draft.mooks, mookLook: $model.draft.mookLook)
                            }
                        }
                        MarkerPanel(model: model)
                        CustomLookPanel(model: model)
                    }
                    if model.draft.mode != .sequence {
                        ForEach(Array(model.draft.emitters.indices), id: \.self) { i in
                            // プレビューは、カードの設定を動かしている間も画面の上に残す(下の項目を設定しながら見える)
                            Section {
                                EmitterCard(index: i, emitter: $model.draft.emitters[i], isBoss: model.draft.mode != .survive,
                                            look: PreviewLook(draft: model.draft), advanced: advanced,
                                            duration: model.draft.duration == 0 ? 180 : model.draft.duration, canDelete: model.draft.emitters.count > 1,
                                            onDelete: { model.removeEmitter(at: i); collapsedCards = [] },
                                            externalCollapsed: collapsedBinding(i), showPreview: false)
                            } header: {
                                if !collapsedCards.contains(i) {
                                    EmitterPreview(emitter: model.draft.emitters[i], isBoss: model.draft.mode != .survive, look: PreviewLook(draft: model.draft))
                                        .frame(maxHeight: 200)
                                        .frame(maxWidth: .infinity)
                                        .padding(6)
                                        .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 14))
                                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GameStyle.edge))
                                        .padding(.vertical, 4)
                                        .background(Color(Palette.background))
                                }
                            }
                        }
                        AddButton(enabled: model.canAdd) { model.addEmitter() }
                            .accessibilityIdentifier("editor.add")
                    }

                    StatusBox(verified: model.isVerified)
                    HStack(spacing: 10) {
                        GameActionButton(title: "editor.test", systemImage: "play.fill", fill: GameStyle.cyan) {
                            testRun = TestRun(stage: model.stage, customs: model.draft.customImages)
                        }
                        .accessibilityIdentifier("editor.test")
                        GameActionButton(title: model.isPublished ? "editor.posted" : "editor.post", systemImage: "paperplane.fill", fill: GameStyle.accent,
                                         enabled: model.isVerified && model.canPublish && !model.isPublished) { publishing = true }
                        .accessibilityIdentifier("editor.post")
                    }
                    // 投稿ボタンが押せない理由を、はっきり出す
                    if !model.isPublished, model.isVerified, !model.canPublish {
                        Text("editor.hint.name").font(.caption.bold()).foregroundStyle(Color(Palette.gold)).frame(maxWidth: .infinity, alignment: .leading)
                    } else if !model.isPublished, !model.isVerified {
                        Text("editor.hint.clear").font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16).padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: model.draft) { _ in model.save() }
        .confirmationDialog("editor.revert.title", isPresented: $confirmRevert, titleVisibility: .visible) {
            Button("editor.revert.do", role: .destructive) { model.revert() }
            Button("common.cancel", role: .cancel) {}
        } message: { Text("editor.revert.message") }
        .fullScreenCover(item: $testRun) { run in
            PlayView(stage: run.stage, title: L("editor.test.prefix") + (run.stage.name), isTest: true, customs: run.customs,
                     onResult: { result, moves in
                         if result.outcome == .cleared { model.markVerified(stage: run.stage, replay: Replay(moves: moves)) }
                     },
                     onExit: { testRun = nil })
        }
        .sheet(isPresented: $publishing) {
            if let replay = model.clearReplay {
                PublishFlowView(stage: model.stage, authorName: model.draft.authorName, replay: replay) { id in model.published(id: id) }
            }
        }
    }
}

private struct TestRun: Identifiable {
    let id = UUID()
    let stage: Stage
    let customs: CustomImageChoice
}

/// プレビューや見本に使う、作者が選んだ見た目
struct PreviewLook: Equatable {
    var bullets: Theme = .classic
    var background: Theme = .classic
    var ship: Theme = .classic
    var customs: CustomImageChoice = .none
    /// ボスの大きさ・見た目、雑魚の姿の大きさ(nil は出さない)・見た目
    var bossSize = 1
    var bossLook = 0
    var mooks: Int?
    var mookLook = 0

    init() {}
    init(draft: Draft) {
        bullets = draft.themeBullets; background = draft.themeBackground; ship = draft.themeShip
        customs = draft.customImages
        bossSize = draft.bossSize; bossLook = draft.bossLook; mooks = draft.mooks; mookLook = draft.mookLook
    }
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

/// 自機の撃ち方。ステージごとに作者が決めて、遊ぶ全員が同じ撃ち方になる(買った撃ち方だけ選べる)
private struct ShotPanel: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showShop = false

    var body: some View {
        GamePanel(title: "editor.shot", tint: Color(Palette.gold)) {
            Text("editor.shot.note").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(ShotType.allCases, id: \.self) { shot in
                    let owned = cosmetics.ownership.has(shot) || model.draft.shot == shot
                    Button {
                        gameTap()
                        if owned { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.draft.shot = shot } } else { showShop = true }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                Chip(title: L(shot.nameKey), selected: model.draft.shot == shot)
                                if !owned { Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(Palette.gold)).padding(4) }
                            }
                        }
                        .opacity(owned ? 1 : 0.7)
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("editor.shot.\(shot.rawValue)")
                }
            }
            Text(LocalizedStringKey(model.draft.shot.detailKey)).font(.caption2).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showShop) { ShopView() }
    }
}

/// ボスの大きさと見た目、雑魚の姿(見た目だけ)。ボスの大きさは、弾が当たる範囲も変える
private struct EnemyControls: View {
    let showBoss: Bool
    @Binding var bossSize: Int
    @Binding var bossLook: Int
    @Binding var mooks: Int?
    @Binding var mookLook: Int

    private func sizeItems() -> [(Int, String)] { [(0, L("editor.size.0")), (1, L("editor.size.1")), (2, L("editor.size.2"))] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showBoss {
                Text("editor.enemy.size").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                ChipGrid(items: sizeItems(), selection: $bossSize, idPrefix: "editor.boss.size")
                Text("editor.enemy.size.note").font(.caption2).foregroundStyle(.secondary)
                Text("editor.enemy.bosslook").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                looks(selection: $bossLook, idPrefix: "editor.boss.look") { EnemyArt.bossImage(look: $0, size: 1, flash: false) } name: { L("enemy.boss.\($0)") }
            }
            Text("editor.enemy.mooks").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            ChipGrid(items: [(-1, L("editor.enemy.none")), (0, L("editor.size.0")), (1, L("editor.size.1")), (2, L("editor.size.2"))],
                     selection: Binding(get: { mooks ?? -1 }, set: { mooks = $0 < 0 ? nil : $0 }), idPrefix: "editor.mook.size")
            if mooks != nil {
                Text("editor.enemy.mooklook").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                looks(selection: $mookLook, idPrefix: "editor.mook.look") { EnemyArt.mookImage(look: $0, size: 1) } name: { L("enemy.mook.\($0)") }
            }
        }
    }

    private func looks(selection: Binding<Int>, idPrefix: String, image: @escaping (Int) -> UIImage, name: @escaping (Int) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<EnemyArt.looks, id: \.self) { n in
                    let selected = selection.wrappedValue == n
                    Button { gameTap(); withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selection.wrappedValue = n } } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: image(n)).resizable().frame(width: 36, height: 36)
                            Text(name(n)).font(.system(size: 11, weight: .heavy, design: .rounded))
                                .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.75))
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(selected ? AnyShapeStyle(Color(Palette.pink).opacity(0.22)) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color(Palette.pink) : GameStyle.edge, lineWidth: selected ? 2 : 1))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("\(idPrefix).\(n)")
                }
            }.padding(.vertical, 2)
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
                Spacer(minLength: 0)
            }
            LifePreview(mode: model.draft.lifeMode, count: min(range.upperBound, max(range.lowerBound, model.draft.lifeCount)))
                .frame(maxWidth: .infinity, alignment: .leading)
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
            Text(label).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                .frame(width: 84, alignment: .leading)
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


/// BGM の選択(押すと試聴できる)。選ばなければ、モードごとの標準の曲
private struct BGMPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var audio = AudioManager.shared
    private let names = ["bgm.0", "bgm.1", "bgm.2", "bgm.3", "bgm.4"]
    private let tints: [Color] = [Color(Palette.pink), Color(UIColor(hex: 0x8E5CFF)), Color(UIColor(hex: 0x5CE1E6)), Color(Palette.gold), Color(Palette.bullets[3])]

    private var selected: Int {
        model.draft.bgm ?? (model.draft.mode == .survive ? 0 : 1)
    }

    var body: some View {
        GamePanel(title: "editor.bgm", tint: Color(Palette.bullets[3])) {
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let on = selected == i
                    Button {
                        gameTap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.draft.bgm = i }
                        AudioManager.shared.preview(.forNumber(i))
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(tints[i].opacity(on ? 0.35 : 0.15))
                                Image(systemName: on ? "speaker.wave.2.fill" : "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(tints[i])
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(LocalizedStringKey(names[i])).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                                Text(L("\(names[i]).sub")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(tints[i]) }
                        }
                        .padding(10)
                        .background(on ? tints[i].opacity(0.14) : Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(on ? tints[i] : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("editor.bgm.\(i)")
                }
            }
            Text("editor.bgm.note").font(.caption).foregroundStyle(.secondary)
        }
        .onDisappear { AudioManager.shared.play(.menu) }
    }
}


/// ステージの見た目(弾の色と形・背景・自機)。作者が決めて、遊ぶ全員に、そう見える。買ったものだけ選べる
private struct LookPanel: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showShop = false
    @State private var rewardHint: Theme?

    var body: some View {
        GamePanel(title: "editor.look", tint: Color(Palette.pink)) {
            Text("editor.look.note").font(.caption).foregroundStyle(.secondary)
            ForEach(ThemePart.allCases, id: \.self) { part in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(part.nameKey)).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(Theme.allCases, id: \.self) { tile(part, $0) } }.padding(.vertical, 2)
                    }
                }
            }
            if let t = rewardHint, let need = t.unlockPosts, !cosmetics.ownership.hasUnlocked(t) {
                Text(String(format: L("editor.look.rewardhint"), max(0, need - cosmetics.ownership.posts)))
                    .font(.caption.bold()).foregroundStyle(Color(Palette.gold))
            }
            if Theme.paid.contains(where: { !cosmetics.ownership.has(.bullets, of: $0) || !cosmetics.ownership.has(.background, of: $0) || !cosmetics.ownership.has(.ship, of: $0) }) {
                Button { gameTap(); showShop = true } label: { Chip(title: L("editor.look.shop"), selected: false) }.buttonStyle(BounceButtonStyle())
            }
        }
        .sheet(isPresented: $showShop) { ShopView() }
    }

    private func current(_ part: ThemePart) -> Theme {
        switch part {
        case .bullets: return model.draft.themeBullets
        case .background: return model.draft.themeBackground
        case .ship: return model.draft.themeShip
        }
    }

    private func set(_ part: ThemePart, _ t: Theme) {
        switch part {
        case .bullets: model.draft.themeBullets = t
        case .background: model.draft.themeBackground = t
        case .ship: model.draft.themeShip = t
        }
    }

    private func tile(_ part: ThemePart, _ t: Theme) -> some View {
        let selected = current(part) == t
        let owned = cosmetics.ownership.has(part, of: t)
        let skin = Skin.of(t)
        return Button {
            gameTap()
            if owned { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { set(part, t) } }
            else if t.unlockPosts != nil { rewardHint = t }
            else { showShop = true }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch part {
                    case .bullets:
                        HStack(spacing: 1) { ForEach(0..<3, id: \.self) { Image(uiImage: SpriteFactory.bulletImages(t)[$0]).resizable().frame(width: 15, height: 15) } }
                    case .background:
                        RoundedRectangle(cornerRadius: 6).fill(Color(skin.background)).frame(width: 46, height: 30)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2)))
                    case .ship:
                        Image(uiImage: SpriteFactory.shipImage(t)).resizable().frame(width: 22, height: 26)
                    }
                }
                .frame(width: 56, height: 36)
                Text(LocalizedStringKey(t.nameKey)).font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? Color.white : Color(Palette.text).opacity(0.75))
            }
            .padding(.vertical, 8).padding(.horizontal, 8)
            .background(selected ? AnyShapeStyle(Color(Palette.pink).opacity(0.22)) : AnyShapeStyle(Color.white.opacity(0.06)), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color(Palette.pink) : GameStyle.edge, lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topTrailing) {
                if !owned {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(Color(Palette.gold))
                        .padding(4).background(Color.black.opacity(0.55), in: Circle()).offset(x: 3, y: -3)
                }
            }
            .opacity(owned ? 1 : 0.7)
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("editor.look.\(part.rawValue).\(t.rawValue)")
    }
}

/// 発射位置の予告(点線のひし形)を出すか。出さないと、難しくなる(生き残りだけ)
private struct MarkerPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if model.draft.mode == .survive {
            GamePanel(title: "editor.markers", tint: Color(Palette.bullets[4])) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("editor.markers.show").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        Text("editor.markers.note").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GameToggle(isOn: Binding(get: { !model.draft.hideMarkers }, set: { model.draft.hideMarkers = !$0 }))
                        .accessibilityIdentifier("editor.markers.toggle")
                }
            }
        }
    }
}


/// じぶんの画像(この端末で遊ぶときだけ。投稿すると外れて、他の人にはテーマの見た目だけが見える)
private struct CustomLookPanel: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showShop = false

    private func binding(_ slot: CustomSlot) -> Binding<Bool> {
        switch slot {
        case .boss: return Binding(get: { model.draft.customBoss }, set: { model.draft.customBoss = $0 })
        case .bullet: return Binding(get: { model.draft.customBullet }, set: { model.draft.customBullet = $0 })
        case .ship: return Binding(get: { model.draft.customShip }, set: { model.draft.customShip = $0 })
        }
    }

    var body: some View {
        let _ = cosmetics.customImageRevision
        GamePanel(title: "editor.custom", tint: Color(Palette.gold)) {
            Text("editor.custom.note").font(.caption).foregroundStyle(.secondary)
            if cosmetics.ownership.hasCustomImages {
                ForEach(CustomSlot.allCases) { slot in
                    let image = CustomImageStore.load(slot)
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.08))
                            if let image { Image(uiImage: image).resizable().scaledToFill().clipShape(Circle()) }
                            else { Image(systemName: "photo").foregroundStyle(.secondary) }
                        }.frame(width: 40, height: 40)
                        Text(LocalizedStringKey(slot.nameKey)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        Spacer()
                        if image == nil {
                            Button { gameTap(); showShop = true } label: { Chip(title: L("editor.custom.pick"), selected: false) }.buttonStyle(BounceButtonStyle())
                        } else {
                            GameToggle(isOn: binding(slot))
                        }
                    }
                }
            } else {
                Button { gameTap(); showShop = true } label: { Chip(title: L("editor.custom.buy"), selected: true) }.buttonStyle(BounceButtonStyle())
            }
        }
        .sheet(isPresented: $showShop) { ShopView() }
    }
}


private struct AddButton: View {
    let enabled: Bool
    var title: LocalizedStringKey = "editor.add"
    let action: () -> Void

    var body: some View {
        Button { gameTap(); action() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 20))
                Text(title).font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(Color(Palette.gold))
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(Palette.gold).opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

/// ボス戦・ダメージ勝負の演出: 開始前の警告と、撃破の演出(見た目だけ)
private struct EffectsPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if model.draft.mode == .boss || model.draft.mode == .damage {
            GamePanel(title: "editor.effects", tint: Color(Palette.pink)) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("editor.warning").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        Text("editor.warning.note").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GameToggle(isOn: $model.draft.bossWarning)
                }
                if model.draft.mode == .boss {
                    DefeatPicker(selection: $model.draft.bossDefeat)
                }
            }
        }
    }
}

/// 撃破の演出の選択(なし・爆発・花火・ハート・星くず)
struct DefeatPicker: View {
    @Binding var selection: Int
    private let items: [(DefeatEffect, String, Color)] = [
        (.none, "defeat.none", .gray), (.explosion, "defeat.explosion", Color(Palette.gold)), (.fireworks, "defeat.fireworks", Color(Palette.bullets[1])),
        (.hearts, "defeat.hearts", Color(Palette.pink)), (.stardust, "defeat.stardust", Color(Palette.bullets[3])),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.defeat").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            ChipGrid(items: items.map { ($0.0.rawValue, L($0.1)) }, selection: $selection, idPrefix: "editor.defeat", minimum: 78)
        }
    }
}

/// 連戦: 場面を足す・消す・並べ替える。場面ごとに、種類(雑魚だけ / ボス)・時間・HP・発射台を決める
private struct WavesSection: View {
    @ObservedObject var model: EditorModel
    let advanced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GamePanel(title: "editor.waves", tint: Color(Palette.bullets[3])) {
                HStack {
                    Text(String(format: L("editor.waves.count"), model.draft.waves.count)).font(.system(size: 14, weight: .heavy, design: .rounded))
                    Spacer()
                    Text(String(format: L("editor.waves.total"), Stage.sequenceTotalSeconds(model.draft.waves.map(\.wave)))).font(.caption).foregroundStyle(.secondary)
                }
                // 場面の並びの見取り図: 雑魚だけは細い星、ボスは大きな星
                HStack(spacing: 6) {
                    ForEach(Array(model.draft.waves.enumerated()), id: \.element.id) { idx, w in
                        VStack(spacing: 2) {
                            ZStack {
                                Circle().fill((w.kind == .boss ? Color(Palette.pink) : Color(UIColor(hex: 0x5CE1E6))).opacity(0.2)).frame(width: 34, height: 34)
                                if w.kind == .boss { GameBossShape().fill(Color(Palette.pink), style: FillStyle(eoFill: true)).frame(width: 24, height: 24) }
                                else { GameShipShape().fill(Color(UIColor(hex: 0x5CE1E6))).frame(width: 14, height: 18) }
                            }
                            Text("\(idx + 1)").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
                        }
                        if idx < model.draft.waves.count - 1 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
            }
            ForEach(Array(model.draft.waves.enumerated()), id: \.element.id) { idx, w in
                WaveCard(model: model, index: idx, waveID: w.id, advanced: advanced)
            }
            HStack(spacing: 8) {
                AddButton(enabled: model.canAddWave, title: "editor.wave.add.survive") { model.addWave(.survive) }
                    .accessibilityIdentifier("editor.wave.add.survive")
                AddButton(enabled: model.canAddWave, title: "editor.wave.add.boss") { model.addWave(.boss) }
                    .accessibilityIdentifier("editor.wave.add.boss")
            }
        }
    }
}

private struct WaveCard: View {
    @ObservedObject var model: EditorModel
    let index: Int
    let waveID: UUID
    let advanced: Bool

    private var i: Int { model.draft.waves.firstIndex { $0.id == waveID } ?? 0 }
    private var wave: DraftWave { model.draft.waves[i] }

    var body: some View {
        if model.draft.waves.indices.contains(i) {
            content
        }
    }

    private var content: some View {
        var look = PreviewLook(draft: model.draft)
        look.bossSize = wave.bossSize ?? 1; look.bossLook = wave.bossLook ?? 0; look.mooks = wave.mooks; look.mookLook = wave.mookLook ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(format: L("editor.wave.title"), i + 1)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
                Spacer()
                if model.draft.waves.count > 1 {
                    iconButton("chevron.up", enabled: i > 0) { model.moveWave(waveID, by: -1) }
                    iconButton("chevron.down", enabled: i < model.draft.waves.count - 1) { model.moveWave(waveID, by: 1) }
                    iconButton("trash.fill", enabled: true, tint: Color(Palette.pink)) { model.removeWave(waveID) }
                        .accessibilityIdentifier("editor.wave.delete.\(i)")
                }
            }
            ChipGrid(items: [(WaveKind.survive, L("editor.wave.kind.survive")), (WaveKind.boss, L("editor.wave.kind.boss"))],
                     selection: Binding(get: { wave.kind }, set: { model.draft.waves[i].setKind($0) }), idPrefix: "editor.wave.kind.\(i)", minimum: 130)
            Text(wave.kind == .boss ? "editor.wave.limit" : "editor.endure").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
            ChipGrid(items: wave.durations.map { ($0, String(format: L("unit.seconds"), $0)) },
                     selection: Binding(get: { wave.duration }, set: { model.draft.waves[i].setDuration($0) }), idPrefix: "editor.wave.duration.\(i)")
            if wave.kind == .boss { bossControls }
            ForEach(Array(wave.emitters.indices), id: \.self) { e in
                EmitterCard(index: e, emitter: Binding(get: { model.draft.waves[i].emitters[e] }, set: { model.draft.waves[i].emitters[e] = $0 }),
                            isBoss: wave.kind == .boss, look: look, advanced: advanced, duration: wave.duration,
                            canDelete: wave.emitters.count > 1, onDelete: { model.removeEmitter(e, fromWave: waveID) })
            }
            AddButton(enabled: wave.emitters.count < DanmakuConfig.maxEmitters) { model.addEmitter(toWave: waveID) }
        }
        .padding(14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color(Palette.bullets[3]).opacity(0.5), lineWidth: 1.5))
    }

    @ViewBuilder private var bossControls: some View {
                Text("editor.boss.move").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                BossMoveCards(move: Binding(get: { wave.bossMove }, set: { model.draft.waves[i].bossMove = $0 }))
                SliderRow(label: "editor.boss.hp", value: Binding(get: { Double(wave.bossHp) }, set: { model.draft.waves[i].bossHp = Int($0) }),
                          range: 100...1000, step: 50) { String(Int($0)) }
                if advanced {
                    EnemyControls(showBoss: true,
                                  bossSize: Binding(get: { wave.bossSize ?? 1 }, set: { model.draft.waves[i].bossSize = $0 }),
                                  bossLook: Binding(get: { wave.bossLook ?? 0 }, set: { model.draft.waves[i].bossLook = $0 }),
                                  mooks: Binding(get: { wave.mooks }, set: { model.draft.waves[i].mooks = $0 }),
                                  mookLook: Binding(get: { wave.mookLook ?? 0 }, set: { model.draft.waves[i].mookLook = $0 }))
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("editor.warning").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                            Text("editor.warning.note").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        GameToggle(isOn: Binding(get: { wave.warning }, set: { model.draft.waves[i].warning = $0 }))
                    }
                    DefeatPicker(selection: Binding(get: { wave.defeat }, set: { model.draft.waves[i].defeat = $0 }))
                }
    }

    private func iconButton(_ symbol: String, enabled: Bool, tint: Color = Color(Palette.text), action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(Color.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }
}
