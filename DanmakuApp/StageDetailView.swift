import DanmakuCore
import SwiftUI

struct StageDetailView: View {
    @State var remote: RemoteStage
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @Environment(\.dismiss) private var dismiss
    @State private var playing = false
    @State private var liked = false
    @State private var busy = false
    @State private var needSignIn = false
    @State private var confirmReport = false
    @State private var confirmBlock = false
    @State private var message: String?

    private var context: ShareContext { ShareContext(id: remote.id, name: remote.name, clearRatePercent: remote.clearRatePercent) }
    private var rankingContext: RankingContext? {
        remote.stage.mode == .survive ? nil : RankingContext(stageID: remote.id, stage: remote.stage)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "detail.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
            } trailing: { Color.clear.frame(width: 38, height: 38) }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    GameActionButton(title: "detail.play", systemImage: "play.fill", fill: GameStyle.accent) { playing = true }
                        .accessibilityIdentifier("detail.play")
                    actions
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    if remote.stage.mode != .survive { RankingSection(stageID: remote.id, mode: remote.stage.mode) }
                    CommentsSection(stageID: remote.id, authorUid: remote.authorUid)
                    HStack {
                        smallDanger("detail.report", "exclamationmark.bubble") { requireMember { confirmReport = true } }
                        Spacer()
                        smallDanger("detail.block", "hand.raised") { confirmBlock = true }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .sheet(isPresented: $needSignIn) { SignInSheet() }
        .confirmationDialog("detail.report.title", isPresented: $confirmReport, titleVisibility: .visible) {
            Button("report.reason.inappropriate_name") { Task { await report("inappropriate_name") } }
            Button("report.reason.impossible") { Task { await report("impossible") } }
            Button("report.reason.other") { Task { await report("other") } }
            Button("common.cancel", role: .cancel) {}
        }
        .confirmationDialog("detail.block.title", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("detail.block", role: .destructive) { blocks.block(uid: remote.authorUid, name: remote.authorName); dismiss() }
            Button("common.cancel", role: .cancel) {}
        } message: { Text("detail.block.message") }
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
                    Text(remote.name).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("by \(remote.authorName)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 10) {
                statTile(ring: remote.clearRatePercent, label: "world.clearrate")
                statTile(value: "\(remote.plays)", label: "world.plays")
                statTile(value: "\(remote.clears)", label: "world.clears")
                statTile(value: remote.id, label: "detail.id", mono: true)
            }
        }
        .padding(14)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(GameStyle.edge))
    }

    private func statTile(value: String? = nil, ring: Int? = nil, label: LocalizedStringKey, mono: Bool = false) -> some View {
        VStack(spacing: 4) {
            if value != nil {
                Text(value!).font(.system(size: mono ? 13 : 18, weight: .heavy, design: mono ? .monospaced : .rounded)).foregroundStyle(Color(Palette.gold))
                    .frame(height: 34).minimumScaleFactor(0.6).lineLimit(1)
            } else {
                PercentRing(percent: ring).scaleEffect(0.7).frame(height: 34)
            }
            Text(label).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 8)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button { gameTap(); Task { await like() } } label: {
                Label("\(remote.likes)", systemImage: liked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(liked ? Color(Palette.pink) : Color(Palette.text))
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .background((liked ? Color(Palette.pink).opacity(0.18) : Color.white.opacity(0.08)), in: Capsule())
                    .overlay(Capsule().stroke(liked ? Color(Palette.pink) : Color.white.opacity(0.15)))
            }
            .buttonStyle(BounceButtonStyle()).disabled(busy)
            ShareLink(item: ShareText.author(name: remote.name, id: remote.id)) { shareChip("detail.share", "square.and.arrow.up") }
            if let url = ShareText.xIntentURL(ShareText.author(name: remote.name, id: remote.id)) {
                Link(destination: url) { shareChip("detail.share.x", "xmark") }
            }
            Spacer(minLength: 0)
        }
    }

    private func shareChip(_ title: LocalizedStringKey, _ image: String) -> some View {
        Label(title, systemImage: image).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            .padding(.vertical, 9).padding(.horizontal, 12)
            .background(Color.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15)))
    }

    private func smallDanger(_ title: LocalizedStringKey, _ image: String, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            Label(title, systemImage: image).font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.pink).opacity(0.9))
                .padding(.vertical, 7).padding(.horizontal, 12)
                .background(Color(Palette.pink).opacity(0.1), in: Capsule())
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
