import SwiftUI

/// 「友達を招待」。自分のコードとリンク、人数とごほうび、友達のコードの入力
struct InviteView: View {
    @ObservedObject private var service = InviteService.shared
    @EnvironmentObject private var cosmetics: CosmeticsStore
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var entered = ""
    @State private var result: InviteService.RegisterResult?
    @State private var busy = false
    @State private var copied = false
    @FocusState private var focused: Bool

    /// 人数のごほうびの段階(サーバーの INVITER_TITLES と同じ)
    /// 招待で手に入る自機の数(サーバーの MAX_REWARDED と同じ)
    private static let maxShips = 31
    /// 自機をもらう節目(サーバーの SHIP_REWARDS と同じ。1人目は1機、あとは色ごとの6機種)
    private static let shipSteps = [1, 3, 5, 10, 20, 31]
    private static let steps: [(need: Int, title: String)] = [(1, "invited"), (3, "inv3"), (5, "inv5"), (10, "inv10")]

    var body: some View {
        ZStack {
            Color(Palette.background).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    header
                    sharePanel
                    progressPanel
                    shipPanel
                    enterPanel
                }
                .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .task(id: auth.uid) { await service.refresh(); await cosmetics.refreshBossTickets(uid: auth.uid) }
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
            Text(String(format: L("invite.ship.progress"), min(cosmetics.ownedSkins.count, Self.maxShips), Self.maxShips)).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            if let nextShip = Self.shipSteps.first(where: { $0 > rewarded }) {
                Text(String(format: L("invite.ship.next"), nextShip - rewarded)).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.bullets[0]))
            }
            if let next {
                Text(String(format: L("invite.progress.next"), next.need - rewarded)).font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.pink))
            } else {
                Text("invite.progress.max").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
            }
            VStack(alignment: .leading, spacing: 2) {
                TicketCount()
                Text("ticket.where").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
            }
            Text("invite.boss.note").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.gold))
            if cosmetics.ownership.has(.puni) {
                Text("invite.boss.got").font(.system(size: 12, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.pink))
            }
            Text("invite.progress.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
        }
    }

    /// 手に入れた自機から、使うものを選ぶ(標準の自機に戻すこともできる)
    private var shipPanel: some View {
        GamePanel(title: "ship.section", tint: Color(Palette.bullets[0])) {
            Text("ship.note").font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(Color(Palette.text).opacity(0.7))
            let columns = [GridItem(.adaptive(minimum: 78), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                skinTile(id: nil)
                ForEach(cosmetics.ownedSkins, id: \.self) { skinTile(id: $0) }
            }
            if cosmetics.ownedSkins.isEmpty {
                Text("ship.empty").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
            }
        }
    }

    private func skinTile(id: String?) -> some View {
        let on = cosmetics.shipSkin == id
        return Button { gameTap(); cosmetics.selectSkin(id) } label: {
            VStack(spacing: 4) {
                if let id {
                    SkinThumb(id: id).frame(width: 56, height: 56)
                    Text(ShipSkin.name(id)).font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text)).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Image(uiImage: SpriteFactory.shipImage(.classic)).resizable().interpolation(.high).frame(width: 36, height: 43).frame(width: 56, height: 56)
                    Text("ship.default").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 8)
            .background(on ? Color(Palette.pink).opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color(Palette.pink) : GameStyle.edge, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityIdentifier("ship.\(id ?? "default")")
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

/// ドット絵の自機の見本(ゲームと同じコマ送り・同じ 0.12 秒。ぼかさずに拡大する)
struct SkinThumb: View {
    let id: String
    var body: some View {
        let frames = ShipSkin.frames(id)
        TimelineView(.animation(minimumInterval: 0.12)) { ctx in
            if frames.isEmpty { Color.clear } else {
                Image(uiImage: frames[Int(ctx.date.timeIntervalSinceReferenceDate / 0.12) % frames.count])
                    .interpolation(.none).resizable().scaledToFit()
            }
        }
    }
}

/// ボスの無料チケットの枚数(ショップ・公開・招待の画面で、同じ見た目で出す)
struct TicketCount: View {
    @EnvironmentObject private var cosmetics: CosmeticsStore
    var body: some View {
        let n = cosmetics.availableBossClaims
        HStack(spacing: 6) {
            TicketArtView(height: 20).opacity(n > 0 ? 1 : 0.45)
            Text(String(format: L("ticket.count"), n)).font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(n > 0 ? Color(Palette.bullets[4]) : Color(Palette.text).opacity(0.5))
        .accessibilityIdentifier("ticket.count")
    }
}
