import AuthenticationServices
import SwiftUI

/// Sign in with Apple のボタンとエラー表示
struct SignInButton: View {
    @EnvironmentObject private var auth: AuthService
    var onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 8) {
            SignInWithAppleButton(.signIn, onRequest: { auth.prepare($0) }, onCompletion: { result in
                Task { await auth.complete(result); if auth.isMember { onDone?() } }
            })
            .signInWithAppleButtonStyle(.white)
            .frame(height: 48)
            .accessibilityIdentifier("signin.apple")
            if let e = auth.errorMessage { Text(e).font(.footnote).foregroundStyle(Color(Palette.pink)) }
        }
    }
}

struct SignInSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("signin.title").font(.title2.bold())
            Text("signin.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
            SignInButton { dismiss() }
            Button("common.cancel") { dismiss() }
        }
        .padding(24)
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var purchases: PurchaseService
    @Environment(\.dismiss) private var dismiss
    @State private var showStore = false
    @State private var showDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section("settings.store") {
                    if purchases.isPremium {
                        Label("store.purchased", systemImage: "checkmark.seal.fill").foregroundStyle(Color(Palette.bullets[4]))
                    } else {
                        Button("revive.removeads") { showStore = true }.accessibilityIdentifier("settings.removeads")
                    }
                    Button("store.restore") { Task { await purchases.restore() } }
                    if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("settings.account") {
                    if auth.isMember {
                        Text("settings.signedin")
                        Button("settings.signout") { auth.signOut() }
                        Button("settings.delete", role: .destructive) { showDelete = true }
                            .accessibilityIdentifier("settings.delete")
                    } else {
                        Text("settings.guest").foregroundStyle(.secondary)
                        SignInButton()
                    }
                }
                Section("settings.blocked") {
                    if blocks.blocked.isEmpty { Text("settings.blocked.none").foregroundStyle(.secondary) }
                    ForEach(blocks.blocked.sorted(by: { $0.value < $1.value }), id: \.key) { uid, name in
                        HStack {
                            Text(name)
                            Spacer()
                            Button("settings.unblock") { blocks.unblock(uid: uid) }.buttonStyle(.bordered)
                        }
                    }
                }
                Section("settings.about") {
                    Link("settings.terms", destination: AppConfig.termsURL)
                    Link("settings.privacy", destination: AppConfig.privacyURL)
                    Link("settings.support", destination: AppConfig.supportURL)
                    Link(AppConfig.supportEmail, destination: URL(string: "mailto:\(AppConfig.supportEmail)")!)
                    LabeledContent("settings.version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                }
            }
            .navigationTitle("settings.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("editor.close") { dismiss() } } }
        }
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .sheet(isPresented: $showStore) { StoreView() }
        .preferredColorScheme(.dark)
    }
}

/// アカウント削除の確認と実行（Apple での再認証つき）
struct DeleteAccountSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    var body: some View {
        VStack(spacing: 16) {
            Text(done ? "delete.done.title" : "delete.title").font(.title2.bold())
            if done {
                Text("delete.done.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("editor.close") { dismiss() }.buttonStyle(.borderedProminent)
            } else {
                Text("delete.body").foregroundStyle(.secondary).multilineTextAlignment(.center)
                if auth.isBusy { ProgressView() } else {
                    SignInWithAppleButton(.continue, onRequest: { auth.prepare($0) }, onCompletion: { result in
                        Task { if await auth.deleteAccount(result) { done = true } }
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .accessibilityIdentifier("delete.apple")
                }
                if let e = auth.errorMessage { Text(e).font(.footnote).foregroundStyle(Color(Palette.pink)) }
                Button("common.cancel") { dismiss() }.disabled(auth.isBusy)
            }
        }
        .padding(24)
        .presentationDetents([.medium])
        .interactiveDismissDisabled(auth.isBusy)
        .preferredColorScheme(.dark)
    }
}
