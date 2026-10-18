import DanmakuCore
import SwiftUI

/// 投稿の流れ：利用規約への同意 → Sign in with Apple → 投稿 → 完了（シェア）
struct PublishFlowView: View {
    let stage: Stage
    let authorName: String
    let replay: Replay
    let onPublished: () -> Void

    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @AppStorage("terms.accepted.v1") private var termsAccepted = false
    @State private var phase: Phase = .start
    @State private var error: String?

    enum Phase: Equatable { case start, publishing, done(String) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                switch phase {
                case .start: start
                case .publishing: ProgressView("publish.publishing").padding(.top, 40)
                case .done(let id): done(id)
                }
                if let error { Text(error).font(.footnote).foregroundStyle(Color(Palette.pink)).multilineTextAlignment(.center) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("publish.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("editor.close") { dismiss() } } }
        }
        .interactiveDismissDisabled(phase == .publishing)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var start: some View {
        if !termsAccepted {
            VStack(alignment: .leading, spacing: 12) {
                Text("publish.terms.title").font(.title3.bold())
                Text("publish.terms.body").foregroundStyle(.secondary)
                Link("settings.terms", destination: AppConfig.termsURL)
                Link("settings.privacy", destination: AppConfig.privacyURL)
                Button { termsAccepted = true } label: { Text("publish.terms.accept").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Color(Palette.pink)).controlSize(.large)
                    .accessibilityIdentifier("publish.terms.accept")
            }
        } else if !auth.isMember {
            VStack(spacing: 12) {
                Text("signin.title").font(.title3.bold())
                Text("signin.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
                SignInButton()
            }
        } else {
            VStack(spacing: 12) {
                Text(stage.name).font(.title2.bold())
                Text("by \(authorName)").foregroundStyle(.secondary)
                Button { Task { await publish() } } label: { Text("publish.submit").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(Color(Palette.pink)).controlSize(.large)
                    .accessibilityIdentifier("publish.submit")
            }
        }
    }

    private func done(_ id: String) -> some View {
        VStack(spacing: 14) {
            Text("publish.done").font(.title2.bold()).foregroundStyle(Color(Palette.gold))
            Text("ID  \(id)").font(.system(.title, design: .monospaced))
            let text = ShareText.author(name: stage.name, id: id)
            ShareLink(item: text) { Label("detail.share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(Color(Palette.bullets[1])).controlSize(.large)
            if let url = ShareText.xIntentURL(text) { Link("detail.share.x", destination: url).buttonStyle(.bordered) }
            Button("editor.close") { dismiss() }
        }
    }

    private func publish() async {
        error = nil
        phase = .publishing
        do {
            let id = try await PublishService.publish(stage: stage, authorName: authorName, replay: replay)
            phase = .done(id)
            onPublished()
        } catch {
            self.error = error.localizedDescription
            phase = .start
        }
    }
}
