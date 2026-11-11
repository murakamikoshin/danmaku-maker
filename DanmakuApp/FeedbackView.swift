import FirebaseFunctions
import SwiftUI

/// 「要望を送る」。開発者に届く(サーバーが保存して、メールで転送する)
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var contact = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorKey: String?
    @FocusState private var focused: Bool

    private static let maxLength = 1000
    private static let minLength = 5
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { trimmed.count >= Self.minLength && !sending && !sent }

    var body: some View {
        ZStack {
            GameStyle.night.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("feedback.title").font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(
                            LinearGradient(colors: [.white, GameStyle.yellow], startPoint: .top, endPoint: .bottom))
                        Spacer()
                        Button { gameTap(); dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(GameStyle.panelHi, in: Circle())
                                .overlay(Circle().stroke(GameStyle.edge))
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityLabel(Text("swipe.close"))
                    }
                    if sent {
                        GamePanel(tint: Color(Palette.bullets[4])) {
                            VStack(spacing: 10) {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(Color(Palette.bullets[4]))
                                Text("feedback.sent").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text).multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                    } else {
                        GamePanel(title: "feedback.prompt", tint: GameStyle.pinkColor) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $text)
                                    .scrollContentBackground(.hidden)
                                    .font(.system(size: 15, weight: .medium))
                                    .focused($focused)
                                    .frame(minHeight: 150)
                                    .padding(6)
                                    .onChange(of: text) { v in if v.count > Self.maxLength { text = String(v.prefix(Self.maxLength)) } }
                                    .accessibilityIdentifier("feedback.text")
                                if text.isEmpty {
                                    Text("feedback.hint").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                                        .padding(.horizontal, 12).padding(.vertical, 14).allowsHitTesting(false)
                                }
                            }
                            .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                            .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
                            HStack {
                                Spacer()
                                Text("\(text.count)/\(Self.maxLength)").font(.system(size: 11, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
                            }
                            TextField("", text: $contact, prompt: Text("feedback.contact"))
                                .textFieldStyle(.plain)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.system(size: 15, weight: .semibold))
                                .padding(.vertical, 11).padding(.horizontal, 12)
                                .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                                .overlay(PixelRect(cornerRadius: 12).stroke(GameStyle.edge))
                                .onChange(of: contact) { v in if v.count > 100 { contact = String(v.prefix(100)) } }
                                .accessibilityIdentifier("feedback.contact")
                            Text("feedback.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        if let errorKey {
                            Text(LocalizedStringKey(errorKey)).font(.system(size: 12, weight: .semibold)).foregroundStyle(GameStyle.pinkColor)
                        }
                        GameActionButton(title: "feedback.send", systemImage: sending ? "hourglass" : "paperplane.fill", fill: GameStyle.accent, enabled: canSend) {
                            focused = false
                            Task { await send() }
                        }
                        .accessibilityIdentifier("feedback.send")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    @MainActor private func send() async {
        guard canSend else { return }
        sending = true; errorKey = nil
        defer { sending = false }
        guard Backend.isAvailable else { errorKey = "feedback.error.network"; return }
        let info = Bundle.main.infoDictionary
        let payload: [String: Any] = [
            "text": trimmed, "contact": contact.trimmingCharacters(in: .whitespacesAndNewlines),
            "app": info?["CFBundleShortVersionString"] as? String ?? "", "os": UIDevice.current.systemVersion,
            "lang": Locale.preferredLanguages.first ?? "",
        ]
        do {
            _ = try await Backend.functions.httpsCallable("sendFeedback").call(payload)
            sent = true
        } catch {
            let msg = (error as NSError).localizedDescription
            errorKey = msg.contains("too-fast") ? "feedback.error.fast" : msg.contains("daily-limit") ? "feedback.error.daily" : "feedback.error.network"
        }
    }
}
