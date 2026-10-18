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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("settings.account") {
                    if auth.isMember {
                        Text("settings.signedin")
                        Button("settings.signout") { auth.signOut() }
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
        .preferredColorScheme(.dark)
    }
}
