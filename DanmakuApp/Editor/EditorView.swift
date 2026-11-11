import SwiftUI
import DanmakuCore

struct EditorView: View {
    @StateObject private var model: EditorModel
    @State private var testRun: TestRun?
    @State private var publishing = false
    @State private var naming = false
    @State private var proceedToPublish = false
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
            ScreenHeader(title: "editor.title", leadingTitle: true) {
                RoundIconButton(systemImage: "xmark", label: "editor.close") {
                    // 試聴した BGM は、エディタを閉じるまで流し続ける(スクロールで項目が画面外に出ても切り替えない)
                    AudioManager.shared.play(.menu)
                    onClose()
                }
                    .accessibilityIdentifier("editor.close")
            } trailing: {
                Button { confirmRevert = true } label: {
                    Label("editor.revert", systemImage: "arrow.uturn.backward").font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(GameStyle.yellow).labelStyle(.titleAndIcon)
                }
                .disabled(!model.canRevert).opacity(model.canRevert ? 1 : 0.35)
                .accessibilityIdentifier("editor.revert")
                Label("editor.autosaved", systemImage: "checkmark.icloud.fill").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(GameStyle.green).labelStyle(.titleAndIcon)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    GameTabs(items: [(false, "editor.simple"), (true, "editor.advanced")], selection: $advanced, idPrefix: "editor.level")
                    Text(advanced ? "editor.advanced.note" : "editor.simple.note").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
                    GamePanel(title: "editor.condition") {
                        ModeCards(mode: model.draft.mode, onSelect: model.setMode)
                    }
                    GamePanel(title: "editor.section.basic", tint: GameStyle.cyanColor) {
                        NameFields(draft: $model.draft)
                    }
                    ShotPanel(model: model)
                    if model.draft.mode == .sequence {
                        WavesSection(model: model, advanced: advanced)
                    } else {
                        TimingPanel(model: model)
                        // ボスの見た目・大きさ・覚醒(と雑魚)。ボスの動きの欄(時間の欄)のすぐ下に置く。
                        // ボス戦では「かんたん」でも出す(奥にあって見つけにくかったため)。耐久の雑魚は「くわしく」だけ
                        if advanced || model.draft.mode != .survive {
                            GamePanel(title: "editor.enemy", tint: GameStyle.violet) {
                                EnemyControls(showBoss: model.draft.mode != .survive,
                                              bossSize: $model.draft.bossSize, bossLook: $model.draft.bossLook,
                                              mooks: $model.draft.mooks, mookLook: $model.draft.mookLook, awaken: $model.draft.awaken,
                                              mooksBreakable: $model.draft.mooksBreakable,
                                              mookHits: $model.draft.mookHits,
                                              mooksClear: model.draft.mode == .survive ? $model.draft.mooksClear : nil,
                                              usesCharacterPatterns: model.draft.emitters.contains { $0.t.bossCharacter != nil },
                                              convertCharacterPatterns: { model.convertCharacterPatterns() })
                            }
                        }
                        if advanced { EffectsPanel(model: model) }
                    }
                    if advanced {
                        LifePanel(model: model)
                        BGMPanel(model: model)
                        LookPanel(model: model)
                        RewardFxPanel(model: model)
                        WorldPreviewPanel(model: model)
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
                                        .background(GameStyle.night, in: PixelRect(cornerRadius: 14))
                                        .overlay(PixelRect(cornerRadius: 14).stroke(GameStyle.edge))
                                        .padding(.vertical, 4)
                                        .background(GameStyle.night)
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
                        GameActionButton(title: model.isPublished ? "editor.posted" : (model.isVerified ? "editor.post" : "editor.post.unlisted"), systemImage: "paperplane.fill", fill: GameStyle.accent,
                                         enabled: !model.isPublished) {
                            // 名前が空なら、先に入力画面を挟む
                            if model.canPublish { publishing = true } else { naming = true }
                        }
                        .accessibilityIdentifier("editor.post")
                    }
                    // 投稿ボタンが押せない理由を、はっきり出す
                    if !model.isPublished, !model.isVerified {
                        Text("editor.hint.unlisted").font(.caption.bold()).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16).padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(GameStyle.night.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onChange(of: model.draft) { _ in model.save() }
        .gameDialog("editor.revert.title", isPresented: $confirmRevert, message: "editor.revert.message") {
            [GameDialogAction(title: "editor.revert.do", role: .destructive) { model.revert() }, .cancel()]
        }
        .fullScreenCover(item: $testRun, onDismiss: {
            // テストプレイから戻ったら、試聴していた BGM を流し直す
            if let i = model.previewingBGM { AudioManager.shared.preview(.forNumber(i)) }
        }) { run in
            PlayView(stage: run.stage, title: L("editor.test.prefix") + (run.stage.name), isTest: true, customs: run.customs,
                     onResult: { result, moves in
                         if result.outcome == .cleared { model.markVerified(stage: run.stage, replay: Replay(moves: moves)) }
                     },
                     onExit: { testRun = nil })
        }
        .sheet(isPresented: $naming, onDismiss: {
            if proceedToPublish { proceedToPublish = false; publishing = true }
        }) {
            NamePromptSheet(draft: $model.draft, canPublish: model.canPublish) { proceedToPublish = true; naming = false }
        }
        .sheet(isPresented: $publishing) {
            PublishFlowView(stage: model.stage, authorName: model.draft.authorName, replay: model.isVerified ? model.clearReplay : nil) { id in model.published(id: id) }
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
    /// キャラクターのボスの大きさの倍率(半径 ÷ 40。図形のボスは 1)
    var characterScale: Double {
        guard BossCharacter.of(look: bossLook) != nil, DanmakuConfig.characterRadiusRange.contains(bossSize) else { return 1 }
        return Double(bossSize) / DanmakuConfig.characterBaseRadius
    }

    init() {}
    init(draft: Draft) {
        bullets = draft.themeBullets; background = draft.themeBackground; ship = draft.themeShip
        customs = draft.customImages
        bossSize = draft.bossSize; bossLook = draft.bossLook; mooks = draft.mooks; mookLook = draft.mookLook
    }
}

/// 投稿ボタンを押したとき、ステージ名か作者名が空なら出す入力画面
private struct NamePromptSheet: View {
    @Binding var draft: Draft
    let canPublish: Bool
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("editor.namePrompt.title").font(.display(18)).foregroundStyle(GameStyle.text)
            Text("editor.namePrompt.note").font(.caption.bold()).foregroundStyle(.secondary)
            NameFields(draft: $draft)
            GameActionButton(title: "editor.namePrompt.go", systemImage: "paperplane.fill", fill: GameStyle.accent, enabled: canPublish, action: onContinue)
                .accessibilityIdentifier("editor.namePrompt.go")
            Spacer(minLength: 0)
        }
        .padding(20)
        .background(GameStyle.night.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.medium])
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
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Spacer()
                Text("\(text.wrappedValue.count)/\(limit)").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
            }
            TextField("", text: text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold))
                .padding(.vertical, 11).padding(.horizontal, 12)
                .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
                .onChange(of: text.wrappedValue) { v in if v.count > limit { text.wrappedValue = String(v.prefix(limit)) } }
                .accessibilityIdentifier(id)
        }
    }
}

/// 制限時間(生き残る時間)、ボスの動き、ボスのHP
private struct TimingPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        GamePanel(title: model.draft.mode == .survive ? "editor.endure" : "editor.limit", tint: GameStyle.yellow) {
            ChipGrid(items: model.durations.map { ($0, $0 == 0 ? L("editor.unlimited") : String(format: L("unit.seconds"), $0)) },
                     selection: Binding(get: { model.draft.duration }, set: model.setDuration),
                     idPrefix: "editor.duration")
            if model.draft.mode != .survive {
                VStack(alignment: .leading, spacing: 8) {
                    Text("editor.boss.move").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    BossMoveCards(move: $model.draft.bossMove)
                    Text("editor.boss.position").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    BossPositionPad(x: $model.draft.bossX, y: $model.draft.bossY)
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
        GamePanel(title: "editor.shot", tint: GameStyle.yellow) {
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
                                if !owned { Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(GameStyle.yellow).padding(4) }
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
        .sheet(isPresented: $showShop) { ShopView(focus: "shots") }
    }
}

/// ボスの大きさと見た目、雑魚の姿(見た目だけ)。ボスの大きさは、弾が当たる範囲も変える
private struct EnemyControls: View {
    let showBoss: Bool
    @Binding var bossSize: Int
    @Binding var bossLook: Int
    @Binding var mooks: Int?
    @Binding var mookLook: Int
    /// 覚醒する段階(nil は覚醒しない)。専用の絵を持つボスを選んだときだけ出す
    @Binding var awaken: Int?
    /// 雑魚を倒せるか(雑魚を出すときだけ選べる)
    @Binding var mooksBreakable: Bool
    /// 倒せる雑魚を倒すのに当てる回数(1〜50)
    @Binding var mookHits: Int
    /// 雑魚を全部倒したら次へ(耐える場面だけ。nil は出さない)
    var mooksClear: Binding<Bool>? = nil
    /// 連戦の場面か(説明の文を「次の場面へ」にする)
    var inSequence = false
    @EnvironmentObject private var cosmetics: CosmeticsStore
    /// いま置いている発射台に、キャラクターのボス専用の技があるか。見た目を変えると使えなくなるので、確認してから「放射」に置き換える
    var usesCharacterPatterns = false
    var convertCharacterPatterns: () -> Void = {}
    @State private var pendingLook: Int?
    @State private var showBossShop = false
    @State private var lockedInfo = false

    /// 持っていない(お試し中の)キャラクターのボスか。招待限定のボスは、お試しではなく鍵
    private func isTrial(_ look: Int) -> Bool {
        guard let b = BossCharacter.of(look: look), !b.inviteLimited else { return false }
        return !cosmetics.ownership.has(b)
    }
    private func isLocked(_ look: Int) -> Bool {
        guard let b = BossCharacter.of(look: look), b.inviteLimited else { return false }
        return !cosmetics.ownership.has(b)
    }

    /// ボスの見た目を選んだとき: 専用の技を置いているのに、そのボスをやめるなら、先に確認する
    private var lookChoice: Binding<Int> {
        Binding(get: { bossLook }, set: { new in
            // 招待限定のボス(ぷにまる)は、お試しなし。持っていなければ、鍵の説明だけ出す
            if let b = BossCharacter.of(look: new), b.inviteLimited, !cosmetics.ownership.has(b) { lockedInfo = true; return }
            let leaves = usesCharacterPatterns && BossCharacter.of(look: new) != BossCharacter.of(look: bossLook)
            if leaves { pendingLook = new } else { select(new) }
        })
    }

    private var isCharacter: Bool { BossCharacter.of(look: bossLook) != nil }

    /// 見た目を選ぶ。ぷにまるは覚醒が秘密なので、覚醒の段階を選ばせず、はじめから覚醒するようにする(ほかのボスに替えたら戻す)
    private func select(_ new: Int) {
        let was = BossCharacter.of(look: bossLook) == .puni
        // 図形のボスとキャラクターのボスでは、大きさの範囲が違う。行き来したら標準の大きさに戻す
        if (BossCharacter.of(look: bossLook) == nil) != (BossCharacter.of(look: new) == nil) { bossSize = 1 }
        bossLook = new
        if BossCharacter.of(look: new) == .puni { awaken = 3 } else if was { awaken = nil }
    }

    /// 選べる見た目。招待限定のボス(ぷにまる)も並べる(持っていなければ鍵つき。選べない)
    private var lookChoices: [Int] { EnemyArt.bossLookChoices }

    private func sizeItems() -> [(Int, String)] { [(0, L("editor.size.0")), (1, L("editor.size.1")), (2, L("editor.size.2"))] }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showBoss {
                if isCharacter {
                    Text("editor.enemy.size").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    // キャラクターのボス: 半径 20〜60px(標準 40)。絵と、技の弾が出る場所も、同じ倍率で変わる
                    SliderRow(label: "editor.enemy.size.radius",
                              value: Binding(get: { DanmakuConfig.characterRadiusRange.contains(bossSize) ? Double(bossSize) : DanmakuConfig.characterBaseRadius },
                                             set: { let v = Int($0.rounded()); bossSize = Double(v) == DanmakuConfig.characterBaseRadius ? 1 : v }),
                              range: Double(DanmakuConfig.characterRadiusRange.lowerBound)...Double(DanmakuConfig.characterRadiusRange.upperBound), step: 1) { "\(Int($0))px" }
                        .accessibilityIdentifier("editor.boss.size")
                    Text("editor.enemy.character.size.note").font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text("editor.enemy.size").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    // スライダーで半径(px)を決める。小・中・大と同じ値は、保存のときに 0・1・2 に戻る
                    SliderRow(label: "editor.enemy.size.radius",
                              value: Binding(get: { DanmakuConfig.bossRadius(size: bossSize) }, set: { bossSize = DanmakuConfig.bossSize(forRadius: Int($0.rounded())) }),
                              range: Double(DanmakuConfig.bossRadiusRange.lowerBound)...Double(DanmakuConfig.bossRadiusRange.upperBound), step: 1) { "\(Int($0))px" }
                        .accessibilityIdentifier("editor.boss.size")
                    Text("editor.enemy.size.note").font(.caption2).foregroundStyle(.secondary)
                }
                Text("editor.enemy.bosslook").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                looks(selection: lookChoice, choices: lookChoices, idPrefix: "editor.boss.look", trial: isTrial, locked: isLocked) { EnemyArt.bossImage(look: $0, size: 1, flash: false) } name: { L("enemy.boss.\($0)") }
                if let b = BossCharacter.of(look: bossLook), !cosmetics.ownership.has(b) {
                    // お試し中: テストプレイまでは使える。公開には購入かチケットが要る
                    VStack(alignment: .leading, spacing: 8) {
                        Label("editor.boss.trial", systemImage: "hourglass").font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.ink)
                        Text(b.inviteLimited ? "editor.boss.trial.invite" : "editor.boss.trial.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(GameStyle.ink.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                        if b.purchasable {
                            Button { gameTap(); showBossShop = true } label: {
                                // 文字の色は keyCap より内側で決める(keyCap は黄色いキー用の黒い文字を付けるので、外側で変えても効かない)
                                Label("editor.boss.trial.shop", systemImage: "bag.fill").font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(GameStyle.text)
                                    .padding(.vertical, 7).padding(.horizontal, 12)
                                    .keyCap(GameStyle.panel, radius: 10, depth: 2)
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityIdentifier("editor.boss.trial.shop")
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameStyle.yellow, in: PixelRect(cornerRadius: 12))
                    .accessibilityIdentifier("editor.boss.trial")
                    .sheet(isPresented: $showBossShop) { ShopView(initialTab: .bosses, focus: "boss.\(b.productKey)") }
                }
                if isCharacter && BossCharacter.of(look: bossLook) != .puni {
                    Text("editor.awaken.title").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    ChipGrid(items: [(0, L("editor.enemy.none"))] + BossCharacter.awakenPhases.map { ($0, String(format: L("play.phase"), $0)) },
                             selection: Binding(get: { awaken ?? 0 }, set: { awaken = $0 == 0 ? nil : $0 }), idPrefix: "editor.awaken")
                    Text("editor.awaken.note").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text("editor.enemy.mooks").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: [(-1, L("editor.enemy.none")), (0, L("editor.size.0")), (1, L("editor.size.1")), (2, L("editor.size.2"))],
                     selection: Binding(get: { mooks ?? -1 }, set: { mooks = $0 < 0 ? nil : $0 }), idPrefix: "editor.mook.size")
            if mooks != nil {
                // 雑魚を倒せるか。倒すと、その発射台はその場面では撃たなくなる(耐久でも、オンのときだけ自機が撃つ)
                HStack(spacing: 10) {
                    Image(systemName: "scope").font(.system(size: 15, weight: .bold)).foregroundStyle(GameStyle.text.opacity(0.8)).frame(width: 22)
                    Text("editor.mooks.breakable").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                    Spacer()
                    GameToggle(isOn: $mooksBreakable)
                }
                .accessibilityIdentifier("editor.mooks.breakable")
                if mooksBreakable {
                    let r = DanmakuConfig.mookHitsRange
                    SliderRow(label: "editor.mooks.hits",
                              value: Binding(get: { Double(min(max(mookHits, r.lowerBound), r.upperBound)) }, set: { mookHits = Int($0.rounded()) }),
                              range: Double(r.lowerBound)...Double(r.upperBound), step: 1) { String(format: L("editor.mooks.hits.value"), Int($0)) }
                        .accessibilityIdentifier("editor.mooks.hits")
                    if let mooksClear {
                        // 雑魚を全部倒したら次へ(最後ならクリア)。時間内に倒しきれないと失敗
                        HStack(spacing: 10) {
                            Image(systemName: "flag.checkered").font(.system(size: 15, weight: .bold)).foregroundStyle(GameStyle.text.opacity(0.8)).frame(width: 22)
                            Text(inSequence ? "editor.mooks.clear.wave" : "editor.mooks.clear.stage").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            GameToggle(isOn: mooksClear)
                        }
                        .accessibilityIdentifier("editor.mooks.clear")
                        Text(inSequence ? "editor.mooks.clear.wave.note" : "editor.mooks.clear.stage.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("editor.mooks.breakable.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("editor.enemy.mooklook").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                looks(selection: $mookLook, choices: Array(0..<EnemyArt.looks), idPrefix: "editor.mook.look", trial: { _ in false }, locked: { _ in false }) { EnemyArt.mookImage(look: $0, size: 1) } name: { L("enemy.mook.\($0)") }
            }
        }
        .gameDialog("editor.boss.locked.title", isPresented: $lockedInfo, message: "editor.boss.locked.message") { [.ok()] }
        .gameDialog("editor.boss.change.title", isPresented: Binding(get: { pendingLook != nil }, set: { if !$0 { pendingLook = nil } }),
                    message: "editor.boss.change.message") {
            let new = pendingLook
            return [GameDialogAction(title: "editor.boss.change.replace") {
                        if let new { convertCharacterPatterns(); select(new) }
                        pendingLook = nil
                    }, .cancel { pendingLook = nil }]
        }
    }

    private func looks(selection: Binding<Int>, choices: [Int], idPrefix: String, trial: @escaping (Int) -> Bool, locked: @escaping (Int) -> Bool, image: @escaping (Int) -> UIImage, name: @escaping (Int) -> String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(choices, id: \.self) { n in
                    let selected = selection.wrappedValue == n
                    Button { gameTap(); withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { selection.wrappedValue = n } } label: {
                        VStack(spacing: 4) {
                            Image(uiImage: image(n)).resizable().frame(width: 36, height: 36)
                                .colorMultiply(locked(n) ? .black : .white)
                                .overlay { if locked(n) { Image(systemName: "lock.fill").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.yellow) } }
                            Text(name(n)).font(.system(size: 11, weight: .heavy))
                                .foregroundStyle(selected ? GameStyle.yellow : GameStyle.text.opacity(0.75))
                        }
                        .overlay(alignment: .topTrailing) {
                            if trial(n) {
                                // 持っていないボスは「お試し」(テストプレイまで)
                                Text("editor.boss.trial.tag").font(.system(size: 9, weight: .black)).foregroundStyle(GameStyle.ink)
                                    .padding(.horizontal, 4).padding(.vertical, 1)
                                    .background(GameStyle.yellow, in: PixelRect(cornerRadius: 4))
                                    .offset(x: 8, y: -6)
                            }
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(selected ? AnyShapeStyle(GameStyle.yellow.opacity(0.16)) : AnyShapeStyle(GameStyle.panelHi), in: PixelRect(cornerRadius: 12))
                        .overlay(PixelRect(cornerRadius: 12).strokeBorder(selected ? GameStyle.yellow : Color.clear, lineWidth: 2))
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
        GamePanel(title: "editor.life", tint: GameStyle.pinkColor) {
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
            Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                .lineLimit(2).minimumScaleFactor(0.8).fixedSize(horizontal: false, vertical: true)
                .frame(width: 84, alignment: .leading)
            GameSlider(value: $value, range: range, step: step).allowsHitTesting(!disabled)
            Text(format(value))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .padding(.vertical, 4).padding(.horizontal, 6)
                .frame(width: 64)
                .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 8))
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
                .foregroundStyle(verified ? GameStyle.green : GameStyle.yellow)
            Text(verified ? "editor.status.ok" : "editor.status.need")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(verified ? GameStyle.green : GameStyle.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(GameStyle.panel, in: PixelRect(cornerRadius: 16))
        .overlay(PixelRect(cornerRadius: 16).stroke(verified ? GameStyle.green : GameStyle.edge, lineWidth: verified ? 2 : 1))
        .accessibilityIdentifier(verified ? "editor.status.ok" : "editor.status.need")
    }
}


/// BGM の選択(押すと試聴できる)。選ばなければ、モードごとの標準の曲
private struct BGMPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject private var audio = AudioManager.shared
    private let names = ["bgm.0", "bgm.1", "bgm.2", "bgm.3", "bgm.4"]
    private let tints: [Color] = [GameStyle.pinkColor, Color(UIColor(hex: 0x8E5CFF)), GameStyle.cyanColor, GameStyle.yellow, GameStyle.violet]

    private var selected: Int {
        model.draft.bgm ?? (model.draft.mode == .survive ? 0 : 1)
    }

    var body: some View {
        GamePanel(title: "editor.bgm", tint: GameStyle.violet) {
            VStack(spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let on = selected == i
                    Button {
                        gameTap()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { model.draft.bgm = i }
                        model.previewingBGM = i
                        AudioManager.shared.preview(.forNumber(i))
                    } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().fill(tints[i].opacity(on ? 0.35 : 0.15))
                                Image(systemName: on ? "speaker.wave.2.fill" : "music.note").font(.system(size: 14, weight: .bold)).foregroundStyle(tints[i])
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(LocalizedStringKey(names[i])).font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                                Text(L("\(names[i]).sub")).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(tints[i]) }
                        }
                        .padding(10)
                        .background(on ? tints[i].opacity(0.14) : Color.white.opacity(0.05), in: PixelRect(cornerRadius: 14))
                        .overlay(PixelRect(cornerRadius: 14).stroke(on ? tints[i] : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("editor.bgm.\(i)")
                }
            }
            Text("editor.bgm.note").font(.caption).foregroundStyle(.secondary)
        }
    }
}


/// 毎日のごほうびでもらった演出(軌跡・火花・オーラ・爆発)。ステージに付けると、遊ぶ全員にその演出が出る。もらったものだけ選べる
private struct RewardFxPanel: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var rewards: RewardStore
    @State private var showShop = false

    var body: some View {
        GamePanel(title: "editor.rewardfx", tint: GameStyle.yellow) {
            Text("editor.rewardfx.note").font(.caption).foregroundStyle(.secondary)
            ForEach(Reward.stageKinds, id: \.self) { kind in
                let owned = rewards.state.owned(kind)
                if !owned.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(kind.nameKey)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Button { gameTap(); set(nil, kind: kind) } label: {
                                    Image(systemName: "nosign").font(.title3).frame(width: 48, height: 48)
                                        .background(Color.white.opacity(chosen(kind) == nil ? 0.25 : 0.1), in: PixelRect(cornerRadius: 11))
                                }
                                .buttonStyle(.plain)
                                ForEach(owned.reversed(), id: \.self) { r in
                                    Button { gameTap(); set(r, kind: kind) } label: {
                                        RewardSwatch(reward: r, size: 48)
                                            .overlay(PixelRect(cornerRadius: 11).stroke(.white, lineWidth: chosen(kind) == r ? 2.5 : 0))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            if rewards.state.claimed == 0 {
                Text("editor.rewardfx.empty").font(.caption.bold()).foregroundStyle(GameStyle.yellow)
            }
            Button { gameTap(); showShop = true } label: { Chip(title: L("editor.rewardfx.shop"), selected: false) }.buttonStyle(BounceButtonStyle())
        }
        .sheet(isPresented: $showShop) { ShopView(focus: "daily") }
    }

    private func chosen(_ kind: RewardKind) -> Reward? {
        model.draft.rewardFx.compactMap(Reward.init(index:)).first { $0.kind == kind }
    }

    /// 種類ごとに1つ。nil なら、その種類を外す
    private func set(_ reward: Reward?, kind: RewardKind) {
        var list = model.draft.rewardFx.filter { Reward(index: $0)?.kind != kind }
        if let reward, rewards.state.has(reward) { list.append(reward.index) }
        model.draft.rewardFx = list
    }
}

/// ステージの見た目(弾の色と形・背景・自機)。作者が決めて、遊ぶ全員に、そう見える。買ったものだけ選べる
private struct LookPanel: View {
    @ObservedObject var model: EditorModel
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @State private var showShop = false
    /// ショップで移動する先(押した見た目のテーマ。全体の「ショップへ」は、まだ持っていない最初のテーマ)
    @State private var lookFocus = "customimages"
    @State private var rewardHint: Theme?

    var body: some View {
        GamePanel(title: "editor.look", tint: GameStyle.pinkColor) {
            Text("editor.look.note").font(.caption).foregroundStyle(.secondary)
            ForEach(ThemePart.allCases, id: \.self) { part in
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(part.nameKey)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { ForEach(Theme.allCases, id: \.self) { tile(part, $0) } }.padding(.vertical, 2)
                    }
                }
            }
            if let t = rewardHint, let need = t.unlockPosts, !cosmetics.ownership.hasUnlocked(t) {
                Text(String(format: L("editor.look.rewardhint"), max(0, need - cosmetics.ownership.posts)))
                    .font(.caption.bold()).foregroundStyle(GameStyle.yellow)
            }
            if let firstLocked = Theme.paid.first(where: { !cosmetics.ownership.has(.bullets, of: $0) || !cosmetics.ownership.has(.background, of: $0) || !cosmetics.ownership.has(.ship, of: $0) }) {
                Button { gameTap(); lookFocus = "theme.\(firstLocked.rawValue)"; showShop = true } label: { Chip(title: L("editor.look.shop"), selected: false) }.buttonStyle(BounceButtonStyle())
            }
        }
        .sheet(isPresented: $showShop) { ShopView(focus: lookFocus) }
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
            else { lookFocus = "theme.\(t.rawValue)"; showShop = true }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    switch part {
                    case .bullets:
                        HStack(spacing: 1) { ForEach(0..<3, id: \.self) { Image(uiImage: SpriteFactory.bulletImages(t)[$0]).resizable().frame(width: 15, height: 15) } }
                    case .background:
                        PixelRect(cornerRadius: 6).fill(Color(skin.background)).frame(width: 46, height: 30)
                            .overlay(PixelRect(cornerRadius: 6).stroke(GameStyle.edge))
                    case .ship:
                        Image(uiImage: SpriteFactory.shipImage(t)).resizable().frame(width: 22, height: 26)
                    }
                }
                .frame(width: 56, height: 36)
                Text(LocalizedStringKey(t.nameKey)).font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(selected ? GameStyle.yellow : GameStyle.text.opacity(0.75))
            }
            .padding(.vertical, 8).padding(.horizontal, 8)
            .background(selected ? AnyShapeStyle(GameStyle.yellow.opacity(0.16)) : AnyShapeStyle(GameStyle.panelHi), in: PixelRect(cornerRadius: 12))
            .overlay(PixelRect(cornerRadius: 12).strokeBorder(selected ? GameStyle.yellow : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if !owned {
                    Image(systemName: "lock.fill").font(.system(size: 9, weight: .heavy)).foregroundStyle(GameStyle.yellow)
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

/// 世界のステージ一覧の動くプレビュー: 始める秒(長さの30%まで)と、見せない設定(ネタバレ防止)。見た目だけで、遊びには関わらない
private struct WorldPreviewPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        let stage = model.draft.stage
        let maxStart = stage.maxPreviewStart
        let start = min(model.draft.previewStart, maxStart)
        GamePanel(title: "editor.preview", tint: GameStyle.yellow) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("editor.preview.off").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                        Text("editor.preview.off.note").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    GameToggle(isOn: $model.draft.noPreview).accessibilityIdentifier("editor.preview.off.toggle")
                }
                if !model.draft.noPreview {
                    HStack {
                        Text("editor.preview.start").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                        Spacer()
                        Text(String(format: L("editor.preview.seconds"), start)).font(.system(size: 15, weight: .heavy)).monospacedDigit().foregroundStyle(GameStyle.text)
                    }
                    if maxStart > 0 {
                        GameSlider(value: Binding(get: { Double(start) }, set: { model.draft.previewStart = Int($0) }),
                                   range: 0...Double(maxStart), step: 1)
                            .accessibilityIdentifier("editor.preview.start.slider")
                        Text(String(format: L("editor.preview.start.note"), maxStart)).font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("editor.preview.start.short").font(.caption).foregroundStyle(.secondary)
                    }
                    // 世界のステージ一覧と同じ計算・速さで見せる
                    HStack { Spacer()
                        StageMiniPreview(stage: stage, playing: true, visible: true, size: 120, boost: 1.3)
                        Spacer() }
                }
            }
        }
    }
}

/// 発射位置の予告(点線のひし形)を出すか。出さないと、難しくなる(生き残りだけ)
private struct MarkerPanel: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if model.draft.mode == .survive {
            GamePanel(title: "editor.markers", tint: GameStyle.green) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("editor.markers.show").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
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
        GamePanel(title: "editor.custom", tint: GameStyle.yellow) {
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
                        Text(LocalizedStringKey(slot.nameKey)).font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
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
        .sheet(isPresented: $showShop) { ShopView(focus: "customimages") }
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
                Text(title).font(.display(14))
            }
            .foregroundStyle(GameStyle.yellow)
            .frame(maxWidth: .infinity).padding(.vertical, 14)
            .overlay(PixelRect(cornerRadius: 16).strokeBorder(GameStyle.yellow.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [6, 5])))
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
            GamePanel(title: "editor.effects", tint: GameStyle.pinkColor) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("editor.warning").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
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
        (.none, "defeat.none", .gray), (.explosion, "defeat.explosion", GameStyle.yellow), (.fireworks, "defeat.fireworks", GameStyle.cyanColor),
        (.hearts, "defeat.hearts", GameStyle.pinkColor), (.stardust, "defeat.stardust", GameStyle.violet),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.defeat").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
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
            GamePanel(title: "editor.waves", tint: GameStyle.violet) {
                HStack {
                    Text(String(format: L("editor.waves.count"), model.draft.waves.count)).font(.system(size: 14, weight: .heavy))
                    Spacer()
                    Text(String(format: L("editor.waves.total"), Stage.sequenceTotalSeconds(model.draft.waves.map(\.wave)))).font(.caption).foregroundStyle(.secondary)
                }
                // 場面の並びの見取り図: 雑魚だけは細い星、ボスは大きな星
                HStack(spacing: 6) {
                    ForEach(Array(model.draft.waves.enumerated()), id: \.element.id) { idx, w in
                        VStack(spacing: 2) {
                            ZStack {
                                Circle().fill((w.kind == .boss ? GameStyle.pinkColor : GameStyle.cyanColor).opacity(0.2)).frame(width: 34, height: 34)
                                if w.kind == .boss { GameBossShape().fill(GameStyle.pinkColor, style: FillStyle(eoFill: true)).frame(width: 24, height: 24) }
                                else { GameShipShape().fill(GameStyle.cyanColor).frame(width: 14, height: 18) }
                            }
                            Text("\(idx + 1)").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
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
                Text(String(format: L("editor.wave.title"), i + 1)).font(.display(15)).foregroundStyle(GameStyle.yellow)
                Spacer()
                if model.draft.waves.count > 1 {
                    iconButton("chevron.up", enabled: i > 0) { model.moveWave(waveID, by: -1) }
                    iconButton("chevron.down", enabled: i < model.draft.waves.count - 1) { model.moveWave(waveID, by: 1) }
                    iconButton("trash.fill", enabled: true, tint: GameStyle.pinkColor) { model.removeWave(waveID) }
                        .accessibilityIdentifier("editor.wave.delete.\(i)")
                }
            }
            ChipGrid(items: [(WaveKind.survive, L("editor.wave.kind.survive")), (WaveKind.boss, L("editor.wave.kind.boss"))],
                     selection: Binding(get: { wave.kind }, set: { model.draft.waves[i].setKind($0) }), idPrefix: "editor.wave.kind.\(i)", minimum: 130)
            Text(wave.kind == .boss ? "editor.wave.limit" : "editor.endure").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: wave.durations.map { ($0, String(format: L("unit.seconds"), $0)) },
                     selection: Binding(get: { wave.duration }, set: { model.draft.waves[i].setDuration($0) }), idPrefix: "editor.wave.duration.\(i)")
            if wave.kind == .boss { bossControls } else { mookControls }
            ForEach(Array(wave.emitters.indices), id: \.self) { e in
                EmitterCard(index: e, emitter: Binding(get: { model.draft.waves[i].emitters[e] }, set: { model.draft.waves[i].emitters[e] = $0 }),
                            isBoss: wave.kind == .boss, look: look, advanced: advanced, duration: wave.duration,
                            canDelete: wave.emitters.count > 1, onDelete: { model.removeEmitter(e, fromWave: waveID) })
            }
            AddButton(enabled: wave.emitters.count < DanmakuConfig.maxEmitters) { model.addEmitter(toWave: waveID) }
        }
        .padding(14)
        .background(GameStyle.panel, in: PixelRect(cornerRadius: 20))
        .overlay(PixelRect(cornerRadius: 20).stroke(GameStyle.violet.opacity(0.5), lineWidth: 1.5))
    }

    @ViewBuilder private var bossControls: some View {
                // キャラクターのボスも、1.2.0 から動きと位置を選べる
                Text("editor.boss.move").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                BossMoveCards(move: Binding(get: { wave.bossMove }, set: { model.draft.waves[i].bossMove = $0 }))
                if advanced {
                    Text("editor.boss.position").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    BossPositionPad(x: Binding(get: { wave.bossX }, set: { model.draft.waves[i].bossX = $0 }),
                                    y: Binding(get: { wave.bossY }, set: { model.draft.waves[i].bossY = $0 }))
                }
                SliderRow(label: "editor.boss.hp", value: Binding(get: { Double(wave.bossHp) }, set: { model.draft.waves[i].bossHp = Int($0) }),
                          range: 100...1000, step: 50) { String(Int($0)) }
                if advanced {
                    EnemyControls(showBoss: true,
                                  bossSize: Binding(get: { wave.bossSize ?? 1 }, set: { model.draft.waves[i].bossSize = $0 }),
                                  bossLook: Binding(get: { wave.bossLook ?? 0 }, set: { model.draft.waves[i].bossLook = $0 }),
                                  mooks: Binding(get: { wave.mooks }, set: { model.draft.waves[i].mooks = $0 }),
                                  mookLook: Binding(get: { wave.mookLook ?? 0 }, set: { model.draft.waves[i].mookLook = $0 }),
                                  awaken: Binding(get: { wave.awaken }, set: { model.draft.waves[i].awaken = $0 }),
                                  mooksBreakable: Binding(get: { wave.mooksBreakable == true }, set: { model.draft.waves[i].mooksBreakable = $0 }),
                                  mookHits: Binding(get: { wave.mookHits ?? DanmakuConfig.mookHp }, set: { model.draft.waves[i].mookHits = $0 }),
                                  usesCharacterPatterns: wave.emitters.contains { $0.t.bossCharacter != nil },
                                  convertCharacterPatterns: { model.convertCharacterPatterns(inWave: waveID) })
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("editor.warning").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                            Text("editor.warning.note").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        GameToggle(isOn: Binding(get: { wave.warning }, set: { model.draft.waves[i].warning = $0 }))
                    }
                    DefeatPicker(selection: Binding(get: { wave.defeat }, set: { model.draft.waves[i].defeat = $0 }))
                }
    }

    /// 耐える場面の雑魚(姿・倒せるか・回数・全部倒したら次へ)。連戦で「雑魚を倒したらボスが出る」を作れるように、かんたんでも出す
    private var mookControls: some View {
        EnemyControls(showBoss: false,
                      bossSize: .constant(1), bossLook: .constant(0),
                      mooks: Binding(get: { wave.mooks }, set: { model.draft.waves[i].mooks = $0 }),
                      mookLook: Binding(get: { wave.mookLook ?? 0 }, set: { model.draft.waves[i].mookLook = $0 }),
                      awaken: .constant(nil),
                      mooksBreakable: Binding(get: { wave.mooksBreakable == true }, set: { model.draft.waves[i].mooksBreakable = $0 }),
                      mookHits: Binding(get: { wave.mookHits ?? DanmakuConfig.mookHp }, set: { model.draft.waves[i].mookHits = $0 }),
                      mooksClear: Binding(get: { wave.mooksClear == true }, set: { model.draft.waves[i].mooksClear = $0 }),
                      inSequence: true)
    }

    private func iconButton(_ symbol: String, enabled: Bool, tint: Color = GameStyle.text, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Image(systemName: symbol).font(.system(size: 13, weight: .heavy)).foregroundStyle(tint)
                .frame(width: 32, height: 32).background(GameStyle.panelHi, in: Circle())
        }
        .buttonStyle(BounceButtonStyle())
        .opacity(enabled ? 1 : 0.3)
        .disabled(!enabled)
    }
}
