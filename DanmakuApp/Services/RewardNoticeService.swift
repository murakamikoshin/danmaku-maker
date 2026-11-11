import SwiftUI
import FirebaseAuth
import DanmakuCore

/// 「ごほうびが届きました」。前に見せたときから増えたもの(自機・称号と王冠・ボスのチケット・ボス)を、前に面を開いたときとくらべて見つけて、
/// 画面の上に1回だけ出す。初めて調べるときは、いまあるものを「見せたこと」にして、出さない(以前からの持ち物を、新着として出さないため)。
/// 通知(プッシュ)は、サーバーが招待の報酬・月間ランキングの報酬のときに送る(PushKind.rewards)
@MainActor
final class RewardNoticeService: ObservableObject {
    static let shared = RewardNoticeService()

    struct Item: Identifiable, Equatable {
        enum Kind: Equatable { case ship(String), title(String), ticket(Int), boss(BossCharacter), drink(Int) }
        let id = UUID()
        let kind: Kind
    }

    /// 出すもの。空でなければ、画面が開く
    @Published var pending: [Item] = []

    private let defaults = UserDefaults.standard
    private var checking = false

    private func key(_ uid: String) -> String { "rewardseen.\(uid)" }

    /// サーバーの最新を読んで、増えたものがあれば pending に入れる
    func check() async {
        guard !checking, Backend.isAvailable, let uid = Auth.auth().currentUser?.uid else { return }
        checking = true
        defer { checking = false }
        await InviteService.shared.refresh()           // 自機・チケット・ボス
        await TitleService.shared.load(uid: uid)       // 称号・王冠
        // 参加賞(月ごとの結果発表で届く回復ドリンク)。これまでにもらった数が、サーバーの gifts
        let gifts = ((try? await Backend.functions.httpsCallable("swipeGetStamina").call())?.data as? [String: Any])?["gifts"] as? NSNumber
        let giftCount = gifts?.intValue
        let store = CosmeticsStore.shared
        let ships = Set(store.ownedSkins)
        let titles = Set(TitleService.shared.owned)
        let bosses = Set(store.ownership.freeBosses.map(\.productKey))
        let tickets = store.bossTickets
        let k = key(uid)
        defer {
            var save: [String: Any] = ["ships": Array(ships), "titles": Array(titles), "bosses": Array(bosses), "tickets": tickets]
            if let giftCount { save["gifts"] = giftCount } else if let old = defaults.dictionary(forKey: k)?["gifts"] { save["gifts"] = old }   // 読めなかったときは、前の値のまま
            defaults.set(save, forKey: k)
        }
        guard let seen = defaults.dictionary(forKey: k) else { return }   // 初めて: 出さずに、いまの状態を覚える
        let seenShips = Set(seen["ships"] as? [String] ?? []), seenTitles = Set(seen["titles"] as? [String] ?? [])
        let seenBosses = Set(seen["bosses"] as? [String] ?? []), seenTickets = seen["tickets"] as? Int ?? 0
        var items: [Item] = []
        for s in ships.subtracting(seenShips).sorted() where ShipSkin.isValid(s) { items.append(Item(kind: .ship(s))) }
        for t in titles.subtracting(seenTitles).sorted() where TitleID.isValid(t) { items.append(Item(kind: .title(t))) }
        if let giftCount, let seenGifts = seen["gifts"] as? Int, giftCount > seenGifts { items.append(Item(kind: .drink(giftCount - seenGifts))) }
        if tickets > seenTickets { items.append(Item(kind: .ticket(tickets - seenTickets))) }
        for b in BossCharacter.allCases where bosses.contains(b.productKey) && !seenBosses.contains(b.productKey) { items.append(Item(kind: .boss(b))) }
        if !items.isEmpty { pending = items }
    }
}

/// 「ごほうびが届きました」の画面
struct RewardNoticeView: View {
    let items: [RewardNoticeService.Item]
    let close: () -> Void

    var body: some View {
        ZStack {
            Color(Palette.background).ignoresSafeArea()
            VStack(spacing: 14) {
                Text("reward.notice.title").font(.custom("DelaGothicOne-Regular", size: 22))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(Palette.gold)], startPoint: .top, endPoint: .bottom))
                    .padding(.top, 24)
                ScrollView {
                    VStack(spacing: 8) { ForEach(items) { row($0) } }
                }
                GameActionButton(title: "reward.notice.ok", systemImage: "checkmark", fill: GameStyle.accent) { close() }
                    .accessibilityIdentifier("reward.notice.ok")
            }
            .padding(.horizontal, 20).padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private func row(_ item: RewardNoticeService.Item) -> some View {
        HStack(spacing: 12) {
            switch item.kind {
            case .ship(let id): SkinThumb(id: id).frame(width: 48, height: 48)
            case .title: Image(systemName: "rosette").font(.system(size: 24, weight: .bold)).foregroundStyle(Color(Palette.gold)).frame(width: 48, height: 48)
            case .ticket: TicketArtView(height: 24).frame(width: 64, height: 48)
            case .drink: Image(systemName: "drop.fill").font(.system(size: 24, weight: .bold)).foregroundStyle(Color(Palette.bullets[2])).frame(width: 48, height: 48)
            case .boss(let b): Image(uiImage: BossSprites.shopArt(b, awakened: false).map { UIImage(cgImage: $0.frames[0], scale: 1, orientation: .up) } ?? UIImage()).resizable().interpolation(.none).scaledToFit().frame(width: 48, height: 48)
            }
            Text(text(item)).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GameStyle.edge))
    }

    private func text(_ item: RewardNoticeService.Item) -> String {
        switch item.kind {
        case .ship(let id): return String(format: L("reward.notice.ship"), ShipSkin.name(id))
        case .title(let id):
            if TitleID.crown(id) != nil { return String(format: L("reward.notice.crown"), TitleID.text(id) ?? "") }
            return String(format: L("reward.notice.title.item"), TitleID.text(id) ?? "")
        case .ticket(let n): return String(format: L("reward.notice.ticket"), n)
        case .boss(let b): return String(format: L("reward.notice.boss"), L("enemy.boss.\(b.rawValue)"))
        case .drink(let n): return String(format: L("reward.notice.drink"), n)
        }
    }
}
