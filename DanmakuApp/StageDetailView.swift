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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) { ModeBadge(mode: remote.stage.mode); Text(detailText(remote.stage)).foregroundStyle(.secondary) }
                    Text(remote.name).font(.title.bold())
                    Text("by \(remote.authorName)  ·  ID \(remote.id)").foregroundStyle(.secondary)
                    stats
                    Button { playing = true } label: { Text("detail.play").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).tint(Color(Palette.pink)).controlSize(.large)
                        .accessibilityIdentifier("detail.play")
                    HStack {
                        Button { Task { await like() } } label: { Label("\(remote.likes)", systemImage: liked ? "heart.fill" : "heart") }
                            .buttonStyle(.bordered).disabled(busy)
                        ShareLink(item: ShareText.author(name: remote.name, id: remote.id)) { Label("detail.share", systemImage: "square.and.arrow.up") }
                            .buttonStyle(.bordered)
                        if let url = ShareText.xIntentURL(ShareText.author(name: remote.name, id: remote.id)) {
                            Link("detail.share.x", destination: url).buttonStyle(.bordered)
                        }
                    }
                    if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Divider()
                    HStack {
                        Button("detail.report", role: .destructive) { requireMember { confirmReport = true } }
                        Spacer()
                        Button("detail.block", role: .destructive) { confirmBlock = true }
                    }
                    .font(.footnote)
                }
                .padding(16)
            }
            .navigationTitle("detail.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("editor.close") { dismiss() } } }
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
        }
        .fullScreenCover(isPresented: $playing) {
            PlayView(stage: remote.stage, title: remote.name, share: context,
                     onStart: { ResultsQueue.shared.recordPlay(remote.id) },
                     onResult: { r, _ in if r.outcome == .cleared { ResultsQueue.shared.recordClear(remote.id) } },
                     onExit: { playing = false; Task { await ResultsQueue.shared.flush() } })
        }
        .task {
            if let uid = auth.uid, auth.isMember { liked = await StageRepository().isLiked(id: remote.id, uid: uid) }
            if let fresh = try? await StageRepository().find(id: remote.id) { remote = fresh }
        }
    }

    private var stats: some View {
        HStack(spacing: 24) {
            stat("world.clearrate", remote.clearRatePercent.map { "\($0)%" } ?? "—")
            stat("world.plays", "\(remote.plays)")
            stat("world.clears", "\(remote.clears)")
        }
    }

    private func stat(_ key: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(key).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .monospaced)).foregroundStyle(Color(Palette.gold))
        }
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
