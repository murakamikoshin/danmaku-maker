import SwiftUI

/// 「友達を招待」。自分のコードとリンク、人数とごほうび、友達のコードの入力
struct InviteView: View {
    @ObservedObject private var service = InviteService.shared
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var entered = ""
    @State private var result: InviteService.RegisterResult?
    @State private var busy = false
    @State private var copied = false
    @FocusState private var focused: Bool

    /// 人数のごほうびの段階(サーバーの INVITER_TITLES と同じ)
    private static let steps: [(need: Int, title: String)] = [(1, "invited"), (3, "inv3"), (5, "inv5"), (10, "inv10")]

    var body: some View {
        ZStack {
            Color(Palette.background).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    sharePanel
                    progressPanel
                    enterPanel
                }
                .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .task(id: auth.uid) { await service.refresh() }
    }

    private var header: some View {
        HStack {
            Text("invite.title").font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(
                LinearGradient(colors: [.white, Color(Palette.gold)], startPoint: .top, endPoint: .bottom))
            Spacer()
            Button { gameTap(); dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 36, height: 36).background(Color.white.opacity(0.12), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2)))
            }
            .buttonStyle(BounceButtonStyle())
            .accessibilityLabel(Text("swipe.close"))
        }
    }

    private var sharePanel: some View {
        GamePanel(title: "invite.share.section", tint: Color(Palette.pink)) {
            Text("invite.share.body").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Color(Palette.text).opacity(0.8))
            if let info = service.info {
                Text(info.code)
                    .font(.system(size: 30, weight: .heavy, design: .monospaced)).kerning(3)
                    .foregroundStyle(Color(Palette.text))
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(GameStyle.edge))
                    .accessibilityIdentifier("invite.code")
                HStack(spacing: 10) {
                    ShareLink(item: InviteService.shareURL(code: info.code), message: Text(String(format: L("invite.share.message"), info.code))) {
                        HStack(spacing: 8) {
                            Image(systemName: "paperplane.fill").font(.system(size: 15, weight: .heavy))
                            Text("invite.share.button").font(.system(size: 15, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 13)
                        .background(GameStyle.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("invite.share")
                    Button {
                        gameTap(); UIPasteboard.general.string = info.code; copied = true
                        Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc").font(.system(size: 14, weight: .heavy))
                            Text(copied ? "invite.copied" : "invite.copy").font(.system(size: 13, weight: .heavy, design: .rounded))
                        }
                        .foregroundStyle(Color(Palette.text)).padding(.vertical, 13).padding(.horizontal, 14)
                        .background(Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GameStyle.edge))
                    }
                    .buttonStyle(BounceButtonStyle())
                    .accessibilityIdentifier("invite.copy")
                }
            } else if service.loadFailed {
                Text("invite.error.network").font(.footnote).foregroundStyle(Color(Palette.pink))
                Button { gameTap(); Task { await service.refresh() } } label: { Chip(title: L("world.retry"), selected: false) }.buttonStyle(BounceButtonStyle())
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 16)
            }
        }
    }

    private var progressPanel: some View {
        let count = service.info?.count ?? 0
        let rewarded = service.info?.rewarded ?? 0
        let next = Self.steps.first { $0.need > rewarded }
        return GamePanel(title: "invite.progress.section", tint: Color(Palette.gold)) {
            Text(String(format: L("invite.progress.count"), count)).font(.system(size: 17, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            ForEach(Self.steps, id: \.need) { step in
                let got = rewarded >= step.need
                HStack(spacing: 10) {
                    Image(systemName: got ? "checkmark.circle.fill" : "circle").foregroundStyle(got ? Color(Palette.gold) : Color(Palette.text).opacity(0.4))
                    Text(String(format: L("invite.progress.step"), step.need)).font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Color(Palette.text).opacity(got ? 1 : 0.6))
                    Spacer()
                    TitleChip(id: step.title, size: 12).opacity(got ? 1 : 0.5)
                }
            }
            if let next {
                Text(String(format: L("invite.progress.next"), next.need - rewarded)).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.pink))
            } else {
                Text("invite.progress.max").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
            }
            Text("invite.progress.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
        }
    }

    @ViewBuilder private var enterPanel: some View {
        if service.info?.joinedBy != true {
            GamePanel(title: "invite.enter.section", tint: Color(Palette.bullets[4])) {
                TextField("", text: $entered, prompt: Text("invite.enter.hint"))
                    .textFieldStyle(.plain).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .font(.system(size: 18, weight: .heavy, design: .monospaced))
                    .padding(.vertical, 11).padding(.horizontal, 12)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(GameStyle.edge))
                    .focused($focused)
                    .onChange(of: entered) { v in if v.count > 12 { entered = String(v.prefix(12)) } }
                    .accessibilityIdentifier("invite.enter")
                if let key = messageKey {
                    Text(LocalizedStringKey(key)).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(result == .registered ? Color(Palette.bullets[4]) : Color(Palette.pink))
                }
                GameActionButton(title: "invite.enter.button", systemImage: busy ? "hourglass" : "checkmark.seal.fill", fill: GameStyle.accent,
                                 enabled: InviteService.isValid(InviteService.normalize(entered)) && !busy) {
                    focused = false
                    Task {
                        busy = true; result = nil
                        result = await service.register(code: entered)
                        busy = false
                        if result == .registered || result == .already { await service.refresh() }
                    }
                }
                .accessibilityIdentifier("invite.enter.button")
            }
        } else {
            Text("invite.enter.already").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.6))
        }
    }

    private var messageKey: String? {
        switch result {
        case .registered: return "invite.enter.done"
        case .already: return "invite.enter.already"
        case .badCode: return "invite.error.code"
        case .mine: return "invite.error.self"
        case .tooOld: return "invite.error.old"
        case .network: return "invite.error.network"
        case nil: return nil
        }
    }
}
