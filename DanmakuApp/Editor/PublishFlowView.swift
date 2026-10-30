import DanmakuCore
import SwiftUI

/// 投稿の流れ：利用規約への同意 → Sign in with Apple → 投稿 → 完了（シェア）
struct PublishFlowView: View {
    let stage: Stage
    let authorName: String
    /// nil のときは「URLを知っている人だけ」の投稿(まだクリアしていないステージ)
    let replay: Replay?
    let onPublished: (String) -> Void

    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var ads: AdsService
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var quota: PostQuota?
    @State private var granting = false
    @AppStorage("terms.accepted.v1") private var termsAccepted = false
    @State private var phase: Phase = .start
    @State private var error: String?

    enum Phase: Equatable { case start, publishing, done(String) }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "publish.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
                    .opacity(phase == .publishing ? 0.3 : 1).disabled(phase == .publishing)
            } trailing: { Color.clear.frame(width: 38, height: 38) }
            ScrollView {
                VStack(spacing: 16) {
                    switch phase {
                    case .start: start
                    case .publishing:
                        VStack(spacing: 12) {
                            ProgressView().tint(Color(Palette.pink)).scaleEffect(1.4)
                            Text("publish.publishing").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.secondary)
                        }.padding(.top, 50)
                    case .done(let id): done(id)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Color(Palette.pink)).multilineTextAlignment(.center) }
                }
                .padding(20)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .interactiveDismissDisabled(phase == .publishing)
        .task(id: auth.isMember) { await refreshQuota() }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var start: some View {
        if !termsAccepted {
            GamePanel(title: "publish.terms.title") {
                Text("publish.terms.body").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Link(destination: AppConfig.termsURL) { Chip(title: L("settings.terms"), selected: false) }
                    Link(destination: AppConfig.privacyURL) { Chip(title: L("settings.privacy"), selected: false) }
                }
            }
            GameActionButton(title: "publish.terms.accept", systemImage: "checkmark.circle.fill", fill: GameStyle.accent) { termsAccepted = true }
                .accessibilityIdentifier("publish.terms.accept")
        } else if !auth.isMember {
            GamePanel(title: "signin.title") {
                Text("signin.body").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                SignInButton()
            }
        } else {
            VStack(spacing: 14) {
                StageCardShell(mode: stage.mode) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(stage.name).font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).lineLimit(2)
                        Text("by \(authorName)").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                        Text(detailText(stage)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                if replay == nil {
                    Text("publish.unlisted.note").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                quotaView
                if limitReached {
                    GameActionButton(title: "publish.quota.watch", systemImage: "play.rectangle.fill", fill: GameStyle.gold) { Task { await watchForExtra() } }
                        .disabled(!ads.isReady || granting).opacity(ads.isReady && !granting ? 1 : 0.5)
                        .accessibilityIdentifier("publish.quota.watch")
                } else {
                    GameActionButton(title: replay == nil ? "publish.submit.unlisted" : "publish.submit", systemImage: "paperplane.fill", fill: GameStyle.accent) { Task { await publish() } }
                        .accessibilityIdentifier("publish.submit")
                }
            }
        }
    }

    /// 今日あと何本公開できるか(「URLを知っている人だけ」の投稿は数えないので、出さない)
    private var remaining: Int? { quota?.remaining(premium: purchases.isPremium) }
    private var limitReached: Bool { replay != nil && remaining == 0 }

    @ViewBuilder private var quotaView: some View {
        if replay != nil, quota != nil {
            if purchases.isPremium {
                Text("publish.quota.unlimited").font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(Color(Palette.bullets[4]))
            } else if let r = remaining {
                Text(r > 0 ? String(format: L("publish.quota.left"), r) : String(format: L("publish.quota.none"), PostQuota.free))
                    .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(r > 0 ? Color.secondary : Color(Palette.gold)).multilineTextAlignment(.center)
            }
        }
    }

    private func refreshQuota() async {
        guard let uid = auth.uid else { return }
        quota = await PostQuotaService.fetch(uid: uid)
    }

    private func watchForExtra() async {
        granting = true
        defer { granting = false }
        guard await ads.showRewarded(), await PostQuotaService.grantExtra() else { error = L("error.publish.generic"); return }
        error = nil
        await refreshQuota()
    }

    private func done(_ id: String) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Color(Palette.gold).opacity(0.18)).frame(width: 96, height: 96)
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(GameStyle.gold)
            }
            Text("publish.done").font(.system(size: 26, weight: .heavy, design: .rounded)).foregroundStyle(GameStyle.gold)
            Text("ID  \(id)").font(.system(size: 30, weight: .heavy, design: .monospaced)).foregroundStyle(Color(Palette.text))
                .padding(.vertical, 8).padding(.horizontal, 18).background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 14))
            let text = ShareText.author(name: stage.name, id: id)
            ShareLink(item: text) {
                Label("detail.share", systemImage: "square.and.arrow.up").font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(GameStyle.cyan, in: RoundedRectangle(cornerRadius: 16))
            }
            if let url = ShareText.xIntentURL(text) {
                Link(destination: url) { Chip(title: L("detail.share.x"), selected: false) }
            }
            Button { gameTap(); dismiss() } label: { Text("editor.close").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.secondary) }
        }
    }

    private func publish() async {
        error = nil
        phase = .publishing
        do {
            let id = try await PublishService.publish(stage: stage, authorName: authorName, replay: replay, premium: purchases.isPremium)
            phase = .done(id)
            AudioManager.shared.se(.get)
            onPublished(id)
        } catch {
            self.error = error.localizedDescription
            phase = .start
        }
    }
}
