import DanmakuCore
import SwiftUI

/// 結果画面の「ランキングに記録する」
struct RankingSubmitPanel: View {
    let context: RankingContext
    let result: PlayResult
    let moves: [Move]
    @ObservedObject private var handles = HandleStore.shared
    @ObservedObject private var names = DisplayNameStore.shared
    @State private var state: Phase = .idle
    @State private var editing = false

    enum Phase: Equatable { case idle, sending, done(SubmitSummary), failed(String) }
    struct SubmitSummary: Equatable { var rank: Int; var value: Int; var improved: Bool }

    private var mode: Mode { context.stage.mode }
    /// 撃ち方はステージで決まっていて全員同じなので、どの撃ち方でもランキングに送れる
    private var standard: Bool { true }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill").foregroundStyle(Color(Palette.gold))
                Text("ranking.title").font(.system(size: 14, weight: .heavy))
            }
            if !standard {
                Text("ranking.standard.only").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            } else {
                switch state {
                case .idle, .failed:
                    Button { gameTap(); editing = true } label: {
                        HStack(spacing: 6) {
                            Text(names.label(handles.handle))
                                .font(.system(size: 13, weight: .heavy)).foregroundStyle(Color(Palette.text))
                            Image(systemName: "pencil").font(.system(size: 11, weight: .bold)).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6).padding(.horizontal, 12)
                        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 8))
                    }
                    .buttonStyle(BounceButtonStyle())
                    GameActionButton(title: "ranking.submit", systemImage: "paperplane.fill", fill: GameStyle.gold) { Task { await send() } }
                        .accessibilityIdentifier("ranking.submit")
                    if case .failed(let key) = state { Text(LocalizedStringKey(key)).font(.system(size: 12)).foregroundStyle(Color(Palette.pink)) }
                case .sending:
                    ProgressView().tint(Color(Palette.gold))
                case .done(let s):
                    VStack(spacing: 2) {
                        Text(String(format: L("ranking.rank"), s.rank)).font(.display(23)).foregroundStyle(GameStyle.gold)
                        Text(s.improved ? L("ranking.improved") : String(format: L("ranking.best"), RankingService.format(s.value, mode: mode)))
                            .font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 16))
        .overlay(PixelRect(cornerRadius: 16).stroke(Color(Palette.gold).opacity(0.35)))
        .sheet(isPresented: $editing) { HandleSheet() }
    }

    private func send() async {
        state = .sending
        do {
            let o = try await RankingService.submit(stageID: context.stageID, moves: moves, handle: handles.handle, name: names.publicName, shot: context.stage.shotType)
            state = .done(SubmitSummary(rank: o.rank, value: o.value, improved: o.improved))
        } catch RankingError.tooFast { state = .failed("ranking.error.tooFast") }
        catch RankingError.notCleared { state = .failed("ranking.error.notCleared") }
        catch RankingError.badName { state = .failed("name.error.invalid") }
        catch { state = .failed("error.network") }
    }
}

/// ランキング名を選ぶ(形容詞と動物。番号は自動)
struct HandleSheet: View {
    @ObservedObject private var handles = HandleStore.shared
    @ObservedObject private var names = DisplayNameStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var authorName = AuthorName.current

    var body: some View {
        VStack(spacing: 14) {
            ScreenHeader(title: "handle.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
            } trailing: { Color.clear.frame(width: 38, height: 38) }
            Text(names.useAuthorName && !authorName.trimmingCharacters(in: .whitespaces).isEmpty
                 ? authorName.trimmingCharacters(in: .whitespaces) : PlayerHandle.name(a: handles.handle.a, n: handles.handle.n, num: 1234))
                .font(.display(20)).foregroundStyle(GameStyle.gold)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GamePanel(title: "handle.mode.title") {
                        ChipGrid(items: [(false, L("handle.mode.anon")), (true, L("handle.mode.author"))],
                                 selection: Binding(get: { names.useAuthorName }, set: { names.useAuthorName = $0 }), idPrefix: "handle.mode", minimum: 120)
                        if names.useAuthorName {
                            TextField("", text: $authorName, prompt: Text("handle.author.placeholder"))
                                .textFieldStyle(.plain)
                                .font(.system(size: 16, weight: .semibold))
                                .padding(.vertical, 11).padding(.horizontal, 12)
                                .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                                .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
                                .onChange(of: authorName) { v in
                                    if v.count > DisplayNameStore.maxLength { authorName = String(v.prefix(DisplayNameStore.maxLength)) }
                                    else { AuthorName.set(v); names.objectWillChange.send() }
                                }
                                .accessibilityIdentifier("handle.author")
                            if authorName.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("handle.author.empty").font(.caption.bold()).foregroundStyle(Color(Palette.gold))
                            }
                        }
                        Text("handle.mode.note").font(.caption).foregroundStyle(.secondary)
                    }
                    GamePanel(title: "handle.adj") {
                        ChipGrid(items: (0..<PlayerHandle.choices).map { ($0, L("handle.adj.\($0)")) },
                                 selection: Binding(get: { handles.handle.a }, set: { handles.handle.a = $0 }), idPrefix: "handle.adj", minimum: 96)
                    }
                    GamePanel(title: "handle.animal") {
                        ChipGrid(items: (0..<PlayerHandle.choices).map { ($0, L("handle.animal.\($0)")) },
                                 selection: Binding(get: { handles.handle.n }, set: { handles.handle.n = $0 }), idPrefix: "handle.animal", minimum: 96)
                    }
                    Button { gameTap(); handles.handle = .random() } label: {
                        Label("handle.random", systemImage: "dice.fill").font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(Color(Palette.text)).frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 14))
                    }
                    .buttonStyle(BounceButtonStyle())
                    Text("handle.note").font(.caption).foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
    }
}

/// ステージ詳細の「世界ランキング」
struct RankingSection: View {
    let stageID: String
    let mode: Mode
    @EnvironmentObject private var auth: AuthService
    @State private var entries: [ScoreEntry] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        GamePanel(title: "ranking.title", tint: Color(Palette.gold)) {
            Text(RankingService.byTime(mode) ? "ranking.sub.boss" : "ranking.sub.damage").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if loading {
                HStack { Spacer(); ProgressView().tint(Color(Palette.gold)); Spacer() }.padding(.vertical, 10)
            } else if failed {
                Text("error.network").font(.footnote).foregroundStyle(.secondary)
            } else if entries.isEmpty {
                Text("ranking.empty").font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { idx, e in row(rank: idx + 1, e) }
                }
            }
        }
        .task { await load() }
    }

    private func row(rank: Int, _ e: ScoreEntry) -> some View {
        let mine = e.uid == auth.uid
        return HStack(spacing: 10) {
            ZStack {
                if rank <= 3 {
                    Image(systemName: "medal.fill").font(.system(size: 20))
                        .foregroundStyle([Color(Palette.gold), Color(white: 0.8), Color(UIColor(hex: 0xCD7F32))][rank - 1])
                } else {
                    Text("\(rank)").font(.system(size: 14, weight: .heavy)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 28)
            Text(e.displayName).font(.system(size: 14, weight: .bold)).foregroundStyle(Color(Palette.text)).lineLimit(1)
            Spacer()
            Text(RankingService.format(e.value, mode: mode)).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(Color(Palette.gold))
        }
        .padding(.vertical, 6).padding(.horizontal, 10)
        .background(mine ? Color(Palette.gold).opacity(0.16) : Color.white.opacity(0.05), in: PixelRect(cornerRadius: 12))
        .overlay(PixelRect(cornerRadius: 12).stroke(mine ? Color(Palette.gold) : Color.clear, lineWidth: 1.5))
    }

    private func load() async {
        loading = true; failed = false
        do { entries = try await RankingService.top(stageID: stageID, mode: mode) } catch { failed = true }
        loading = false
    }
}
