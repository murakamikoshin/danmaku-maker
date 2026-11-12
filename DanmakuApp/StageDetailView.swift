import DanmakuCore
import SwiftUI

struct StageDetailView: View {
    @State var remote: RemoteStage
    /// 「この作者のステージを見る」を押したとき(世界のステージ一覧を、その作者だけに絞る)。nil ならボタンを出さない
    var onShowAuthor: ((RemoteStage) -> Void)? = nil
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @Environment(\.dismiss) private var dismiss
    @State private var playing = false
    @State private var liked = false
    @State private var busy = false
    @State private var needSignIn = false
    @State private var confirmReport = false
    @State private var confirmBlock = false
    @State private var confirmDelete = false
    @State private var deleteFailed = false
    @State private var message: String?

    private var context: ShareContext { ShareContext(id: remote.id, name: remote.name, clearRatePercent: remote.clearRatePercent) }
    private var rankingContext: RankingContext? {
        remote.stage.hasRanking ? RankingContext(stageID: remote.id, stage: remote.stage) : nil
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "detail.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
            } trailing: { Color.clear.frame(width: 38, height: 38) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    if remote.needsNewerApp {
                        // このアプリより新しい内容(新しいボスなど)が要るステージは、遊ばせない
                        Label("detail.needsupdate", systemImage: "arrow.down.app.fill")
                            .font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.yellow)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(GameStyle.panel, in: PixelRect(cornerRadius: 14))
                            .accessibilityIdentifier("detail.needsupdate")
                    } else {
                        GameActionButton(title: "detail.play", systemImage: "play.fill", fill: GameStyle.accent) { playing = true }
                            .accessibilityIdentifier("detail.play")
                    }
                    actions
                    InviteShareHint().frame(maxWidth: .infinity, alignment: .leading)
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if remote.stage.hasRanking { RankingSection(stageID: remote.id, mode: remote.stage.mode) }
                    CommentsSection(stageID: remote.id, authorUid: remote.authorUid)
                    if auth.uid == remote.authorUid {
                        smallDanger("detail.delete", "trash") { confirmDelete = true }
                            .accessibilityIdentifier("detail.delete")
                    }
                    HStack {
                        smallDanger("detail.report", "exclamationmark.bubble") { requireMember { confirmReport = true } }
                        Spacer()
                        smallDanger("detail.block", "hand.raised") { confirmBlock = true }
                    }
                }
                .padding(16)
            }
        }
        .background(GameStyle.night.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $needSignIn) { SignInSheet() }
        .gameDialog("detail.report.title", isPresented: $confirmReport) {
            [GameDialogAction(title: "report.reason.inappropriate_name") { Task { await report("inappropriate_name") } },
             GameDialogAction(title: "report.reason.other") { Task { await report("other") } }, .cancel()]
        }
        .gameDialog("detail.delete.title", isPresented: $confirmDelete, message: "detail.delete.message") {
            [GameDialogAction(title: "detail.delete", role: .destructive) {
                Task { if await StageRepository().deleteStage(id: remote.id) { dismiss() } else { deleteFailed = true } }
            }, .cancel()]
        }
        .gameDialog("mystage.delete.failed", isPresented: $deleteFailed) { [.ok()] }
        .gameDialog("detail.block.title", isPresented: $confirmBlock, message: "detail.block.message") {
            [GameDialogAction(title: "detail.block", role: .destructive) { blocks.block(uid: remote.authorUid, name: remote.authorName); dismiss() }, .cancel()]
        }
        .fullScreenCover(isPresented: $playing) {
            PlayView(stage: remote.stage, title: remote.name, share: context, ranking: rankingContext,
                     onStart: { ResultsQueue.shared.recordPlay(remote.id) },
                     onResult: { r, _ in if r.outcome == .cleared && !r.revived { ResultsQueue.shared.recordClear(remote.id) } },
                     onExit: { playing = false; Task { await ResultsQueue.shared.flush() } })
        }
        .task {
            if let uid = auth.uid, auth.isMember { liked = await StageRepository().isLiked(id: remote.id, uid: uid) }
            if let fresh = try? await StageRepository().find(id: remote.id) { remote = fresh }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ModeIcon(mode: remote.stage.mode, size: 54)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        ModeBadge(mode: remote.stage.mode)
                        Text(detailText(remote.stage)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Text(remote.name).font(.system(size: 24, weight: .heavy)).foregroundStyle(GameStyle.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        BadgedName(name: "by \(remote.authorName)", badge: ProfileBadgeStore.shared.badge(remote.authorUid), size: 12, weight: .semibold, baseColor: .secondary, inlineChip: true)
                        if let onShowAuthor {
                            Button { gameTap(); onShowAuthor(remote) } label: {
                                Label("detail.author.more", systemImage: "person.crop.rectangle.stack").labelStyle(.titleAndIcon)
                                    .font(.system(size: 10, weight: .heavy)).foregroundStyle(GameStyle.yellow)
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(GameStyle.yellow.opacity(0.14), in: PixelRect(cornerRadius: 8))
                            }
                            .buttonStyle(BounceButtonStyle())
                            .accessibilityIdentifier("detail.author.more")
                        }
                    }
                }
            }
            if let desc = remote.desc {
                // 作者が書いたステージの説明
                Text(desc).font(.system(size: 14, weight: .medium)).foregroundStyle(GameStyle.text.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                    .accessibilityIdentifier("detail.desc")
            }
            HStack(spacing: 10) {
                statTile(ring: remote.clearRatePercent, label: "world.clearrate")
                statTile(value: "\(remote.plays)", label: "world.plays")
                statTile(value: "\(remote.clears)", label: "world.clears")
                statTile(value: remote.id, label: "detail.id", mono: true)
            }
        }
        .padding(14)
        .background(GameStyle.panel, in: PixelRect(cornerRadius: 20))
        .overlay(PixelRect(cornerRadius: 20).stroke(GameStyle.edge))
    }

    private func statTile(value: String? = nil, ring: Int? = nil, label: LocalizedStringKey, mono: Bool = false) -> some View {
        VStack(spacing: 4) {
            if value != nil {
                Text(value!).font(.system(size: mono ? 13 : 18, weight: .heavy, design: mono ? .monospaced : .default)).foregroundStyle(GameStyle.yellow)
                    .frame(height: 34).minimumScaleFactor(0.6).lineLimit(1)
            } else {
                PercentRing(percent: ring).scaleEffect(0.7).frame(height: 34)
            }
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
    }

    /// 自分のステージなら「作った」、他人のステージなら「挑戦！」の文言
    private var stageShareText: String {
        auth.uid == remote.authorUid
            ? ShareText.author(name: remote.name, id: remote.id)
            : ShareText.recommend(name: remote.name, id: remote.id)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { gameTap(); Task { await like() } } label: {
                Label("\(remote.likes)", systemImage: liked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(liked ? GameStyle.pinkColor : GameStyle.text)
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .background((liked ? GameStyle.pinkColor.opacity(0.18) : Color.white.opacity(0.08)), in: PixelRect(cornerRadius: 8))
                    .overlay(PixelRect(cornerRadius: 8).stroke(liked ? GameStyle.pinkColor : Color.white.opacity(0.15)))
            }
            .buttonStyle(BounceButtonStyle()).disabled(busy)
            CompatShareLink(item: stageShareText) { shareChip("detail.share", "square.and.arrow.up") }
            if let url = ShareText.xIntentURL(stageShareText) {
                Link(destination: url) { shareChip("detail.share.x", "xmark") }
            }
            Spacer(minLength: 0)
        }
    }

    private func shareChip(_ title: LocalizedStringKey, _ image: String) -> some View {
        Label(title, systemImage: image).font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.text)
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 8))
            .overlay(PixelRect(cornerRadius: 8).stroke(GameStyle.edge))
    }

    private func smallDanger(_ title: LocalizedStringKey, _ image: String, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Label(title, systemImage: image).font(.system(size: 12, weight: .bold)).foregroundStyle(GameStyle.pinkColor.opacity(0.9))
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(GameStyle.pinkColor.opacity(0.1), in: PixelRect(cornerRadius: 8))
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func requireMember(_ action: () -> Void) {
        if auth.isMember { action() } else { needSignIn = true }
    }

    private func like() async {
        guard auth.isMember else { needSignIn = true; return }
        busy = true; defer { busy = false }
        if let r = try? await StageActions.toggleLike(id: remote.id) {
            liked = r.liked
            if let fresh = try? await StageRepository().find(id: remote.id) { remote = fresh }
        } else { message = L("error.network") }
    }

    private func report(_ reason: String) async {
        do { try await StageActions.report(id: remote.id, reason: reason); message = L("detail.report.done") }
        catch { message = L("error.network") }
    }
}
