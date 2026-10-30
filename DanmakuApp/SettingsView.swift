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
            .frame(height: 50)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .accessibilityIdentifier("signin.apple")
            if let e = auth.errorMessage { Text(e).font(.footnote).foregroundStyle(Color(Palette.pink)) }
        }
    }
}

/// 小さなシート(サインイン・削除の確認など)の共通の枠
struct MiniSheet<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 14) {
            Text(title).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).padding(.top, 8)
            content
            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(Palette.background).ignoresSafeArea())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

struct SignInSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        MiniSheet(title: "signin.title") {
            Text("signin.body").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            SignInButton { dismiss() }
            Button { gameTap(); dismiss() } label: { Text("common.cancel").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.secondary) }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthService
    @EnvironmentObject private var blocks: BlockStore
    @EnvironmentObject private var purchases: PurchaseService
    @ObservedObject private var audio = AudioManager.shared
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @ObservedObject private var handles = HandleStore.shared
    @ObservedObject private var names = DisplayNameStore.shared
    @State private var showStore = false
    @State private var showDelete = false
    @State private var showHandle = false

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "settings.title") { Color.clear.frame(width: 38, height: 38) } trailing: { Color.clear.frame(width: 38, height: 38) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    GamePanel(title: "settings.audio", tint: Color(UIColor(hex: 0x5CE1E6))) {
                        toggleRow("settings.bgm", "music.note", $audio.bgmOn)
                        toggleRow("settings.se", "speaker.wave.2.fill", $audio.seOn)
                    }

                    GamePanel(title: "settings.display", tint: Color(Palette.bullets[3])) {
                        toggleRow("settings.stagelook", "paintpalette.fill", $cosmetics.showStageLook)
                        Text("settings.stagelook.note").font(.caption).foregroundStyle(.secondary)
                        toggleRow("settings.effects", "sparkles", $cosmetics.effectsOn)
                        Text("settings.effects.note").font(.caption).foregroundStyle(.secondary)
                    }

                    GamePanel(title: "settings.store", tint: Color(Palette.pink)) {
                        if purchases.isPremium {
                            Label("store.purchased", systemImage: "checkmark.seal.fill").font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(Palette.bullets[4]))
                        } else {
                            actionRow("revive.removeads", "nosign") { showStore = true }.accessibilityIdentifier("settings.removeads")
                        }
                        actionRow("store.restore", "arrow.clockwise") { Task { await purchases.restore() } }
                        if let m = purchases.message { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    }

                    GamePanel(title: "settings.ranking.name", tint: Color(Palette.gold)) {
                        Button { gameTap(); showHandle = true } label: {
                            HStack {
                                Text(names.label(handles.handle))
                                    .font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(GameStyle.gold)
                                Spacer()
                                Image(systemName: "pencil").foregroundStyle(.secondary)
                            }
                            .padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(BounceButtonStyle())
                    }

                    GamePanel(title: "settings.account", tint: Color(UIColor(hex: 0xB28DFF))) {
                        if auth.isMember {
                            Label("settings.signedin", systemImage: "person.crop.circle.badge.checkmark").font(.system(size: 14, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(Palette.text))
                            actionRow("settings.signout", "rectangle.portrait.and.arrow.right") { auth.signOut() }
                            actionRow("settings.delete", "trash", danger: true) { showDelete = true }.accessibilityIdentifier("settings.delete")
                        } else {
                            Text("settings.guest").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                            SignInButton()
                        }
                    }

                    GamePanel(title: "settings.blocked", tint: Color(Palette.bullets[3])) {
                        if blocks.blocked.isEmpty { Text("settings.blocked.none").font(.system(size: 13)).foregroundStyle(.secondary) }
                        ForEach(blocks.blocked.sorted(by: { $0.value < $1.value }), id: \.key) { uid, name in
                            HStack {
                                Text(name).font(.system(size: 14, weight: .semibold, design: .rounded))
                                Spacer()
                                Button { gameTap(); blocks.unblock(uid: uid) } label: { Chip(title: L("settings.unblock"), selected: false) }.buttonStyle(BounceButtonStyle())
                            }
                        }
                    }

                    GamePanel(title: "settings.about", tint: Color(Palette.bullets[4])) {
                        linkRow("settings.terms", "doc.text", AppConfig.termsURL)
                        linkRow("settings.privacy", "lock.shield", AppConfig.privacyURL)
                        linkRow("settings.support", "questionmark.circle", AppConfig.supportURL)
                        linkRow(LocalizedStringKey(AppConfig.supportEmail), "envelope", URL(string: "mailto:\(AppConfig.supportEmail)")!)
                        HStack {
                            Text("settings.version").font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                            Spacer()
                            Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                                .font(.system(size: 14, weight: .heavy, design: .monospaced)).foregroundStyle(Color(Palette.text))
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .sheet(isPresented: $showDelete) { DeleteAccountSheet() }
        .sheet(isPresented: $showStore) { StoreView() }
        .sheet(isPresented: $showHandle) { HandleSheet() }
        .preferredColorScheme(.dark)
    }

    private func toggleRow(_ title: LocalizedStringKey, _ symbol: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Color(Palette.text).opacity(0.8)).frame(width: 24)
            Text(title).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            Spacer()
            GameToggle(isOn: binding)
        }
    }

    private func actionRow(_ title: LocalizedStringKey, _ symbol: String, danger: Bool = false, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).frame(width: 24)
                Text(title).font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(danger ? Color(Palette.pink) : Color(Palette.text))
            .padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(BounceButtonStyle())
    }

    private func linkRow(_ title: LocalizedStringKey, _ symbol: String, _ url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).frame(width: 24)
                Text(title).font(.system(size: 15, weight: .heavy, design: .rounded))
                Spacer()
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(Color(Palette.text))
            .padding(12).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// アカウント削除の確認と実行（Apple での再認証つき）
struct DeleteAccountSheet: View {
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var done = false

    var body: some View {
        MiniSheet(title: done ? "delete.done.title" : "delete.title") {
            if done {
                Text("delete.done.body").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                GameActionButton(title: "editor.close", systemImage: "checkmark", fill: GameStyle.accent) { dismiss() }
            } else {
                Text("delete.body").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                if auth.isBusy { ProgressView().tint(Color(Palette.pink)) } else {
                    SignInWithAppleButton(.continue, onRequest: { auth.prepare($0) }, onCompletion: { result in
                        Task { if await auth.deleteAccount(result) { done = true } }
                    })
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .accessibilityIdentifier("delete.apple")
                }
                if let e = auth.errorMessage { Text(e).font(.footnote).foregroundStyle(Color(Palette.pink)) }
                Button { gameTap(); dismiss() } label: { Text("common.cancel").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(.secondary) }
                    .disabled(auth.isBusy)
            }
        }
        .interactiveDismissDisabled(auth.isBusy)
    }
}
