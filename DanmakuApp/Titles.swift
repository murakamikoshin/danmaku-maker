import DanmakuCore
import FirebaseFirestore
import SwiftUI

// MARK: - 称号の ID → 文字・色

/// 称号の ID。スコア達成は "score1"〜"score4"、月間は "rank1:2026-11" のように「種類:年-月」
enum TitleID {
    static let scoreIDs = ["score1", "score2", "score3", "score4"]
    /// スコア達成のしきい値(サーバーの titles.ts と同じ値)
    static let scoreMin: [String: String] = ["score1": "100000000", "score2": "1000000000000", "score3": "1000000000000000000", "score4": "10000000000000000000000000000"]
    /// 友達招待の称号(サーバーの titles.ts の INVITE_TITLES と同じ)。招待のしくみだけが付ける
    static let inviteIDs = ["invited", "inv1", "inv3", "inv5", "inv10", "founder"]
    static let monthKinds = ["rank1", "rank2", "rank3", "top10", "pct1", "pct10", "pct50"]

    struct Month: Equatable { let kind: String; let year: Int; let month: Int }

    static func month(_ id: String) -> Month? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, monthKinds.contains(String(parts[0])) else { return nil }
        let ym = parts[1].split(separator: "-")
        guard ym.count == 2, let y = Int(ym[0]), let m = Int(ym[1]), (1...12).contains(m) else { return nil }
        return Month(kind: String(parts[0]), year: y, month: m)
    }

    /// 王冠・メダルになる月間の称号か(1〜3位=金銀銅の王冠、TOP10=メダル)。サーバーの crownOfTitle と同じ
    static func crown(_ id: String) -> (crown: Int, medal: Bool)? {
        guard let m = month(id) else { return nil }
        switch m.kind {
        case "rank1": return (1, false)
        case "rank2": return (2, false)
        case "rank3": return (3, false)
        case "top10": return (0, true)
        default: return nil
        }
    }

    /// 持っている王冠・メダルを、よい順(1位が先。同じなら新しい月)に並べる
    static func crownSorted(_ ids: [String]) -> [String] {
        ids.compactMap { id -> (String, Int, Int)? in
            guard let c = crown(id), let m = month(id) else { return nil }
            return (id, c.crown > 0 ? c.crown : 4, m.year * 12 + m.month)
        }.sorted { $0.1 != $1.1 ? $0.1 < $1.1 : $0.2 > $1.2 }.map(\.0)
    }

    static func isValid(_ id: String) -> Bool { scoreIDs.contains(id) || inviteIDs.contains(id) || month(id) != nil }

    /// 画面に出す文字(例「弾幕職人」「2026年11月 1位」)
    static func text(_ id: String) -> String? {
        if scoreIDs.contains(id) || inviteIDs.contains(id) { return L("title.\(id)") }
        if let m = month(id) { return String(format: L("title.m.\(m.kind)"), m.year, m.month) }
        return nil
    }

    /// 札の色
    static func tint(_ id: String) -> Color {
        if let m = month(id) {
            switch m.kind {
            case "rank1": return CrownStyle.gold
            case "rank2": return CrownStyle.silver
            case "rank3": return CrownStyle.bronze
            case "top10": return GameStyle.pinkColor
            default: return GameStyle.yellow
            }
        }
        switch id {
        case "inv10", "founder": return CrownStyle.gold
        case "inv5": return GameStyle.pinkColor
        case "inv3": return GameStyle.yellow
        case "invited", "inv1": return GameStyle.pinkColor
        case "score4": return CrownStyle.gold
        case "score3": return GameStyle.pinkColor
        case "score2": return GameStyle.yellow
        default: return GameStyle.green
        }
    }

    /// 持っている招待の称号を、決まった順に並べる
    static func inviteSorted(_ ids: [String]) -> [String] { inviteIDs.filter { ids.contains($0) } }

    /// 持っている称号を、見せる順に並べる(スコア達成は高い順、月間は新しい月が先。同じ月は順位が上のものが先)
    static func monthSorted(_ ids: [String]) -> [String] {
        let order = Dictionary(uniqueKeysWithValues: monthKinds.enumerated().map { ($1, $0) })
        return ids.compactMap { id in month(id).map { (id, $0) } }
            .sorted { a, b in
                if a.1.year != b.1.year { return a.1.year > b.1.year }
                if a.1.month != b.1.month { return a.1.month > b.1.month }
                return (order[a.1.kind] ?? 99) < (order[b.1.kind] ?? 99)
            }.map(\.0)
    }
}

/// 王冠・メダル・名前の色(1〜3 位の単色)
enum CrownStyle {
    static let gold = Color(UIColor(hex: 0xFFD166))
    static let silver = Color(UIColor(hex: 0xD5DBE6))
    static let bronze = Color(UIColor(hex: 0xD9904F))

    static func color(_ crown: Int) -> Color? {
        switch crown {
        case 1: return gold
        case 2: return silver
        case 3: return bronze
        default: return nil
        }
    }
}

// MARK: - 名前の横に出す表示

/// 名前の横に出す称号・王冠(公開のプロフィール)
struct ProfileBadge: Equatable {
    var title: String?
    var crown = 0
    var medal = false
    static let none = ProfileBadge()
    var isEmpty: Bool { title == nil && crown == 0 && !medal }
}

/// 称号の札(小さなカプセル)
struct TitleChip: View {
    let id: String
    var size: CGFloat = 10

    var body: some View {
        if let text = TitleID.text(id) {
            let tint = TitleID.tint(id)
            Text(text)
                .font(.system(size: size, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(tint)
                .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.15)
                .background(tint.opacity(0.16), in: PixelRect(cornerRadius: 8))
                .overlay(PixelRect(cornerRadius: 8).stroke(tint.opacity(0.5), lineWidth: 0.7))
        }
    }
}

/// 名前。1〜3 位は王冠と金・銀・銅の色、4〜10 位は小さなメダル。王冠は名前の左に出す
struct BadgedName: View {
    let name: String
    let badge: ProfileBadge
    var size: CGFloat = 13
    var weight: Font.Weight = .bold
    var baseColor: Color = .white
    /// 称号の札を、名前の横に並べる(ランキングは名前の下に別に出すので false)
    var inlineChip = false

    var body: some View {
        HStack(spacing: 4) {
            if badge.crown > 0, let c = CrownStyle.color(badge.crown) {
                Image(systemName: "crown.fill").font(.system(size: size * 0.95)).foregroundStyle(c)
                    .accessibilityLabel(Text("title.crown"))
            } else if badge.medal {
                Image(systemName: "medal.fill").font(.system(size: size * 0.85)).foregroundStyle(GameStyle.pinkColor)
                    .accessibilityLabel(Text("title.medal"))
            }
            Text(name).font(.system(size: size, weight: weight)).lineLimit(1)
                .foregroundStyle(CrownStyle.color(badge.crown) ?? baseColor)
            if inlineChip, let t = badge.title { TitleChip(id: t, size: max(8, size * 0.72)) }
        }
    }
}

// MARK: - 公開のプロフィールの取得(まとめて・使い回す)

/// 世界のステージの「by ◯◯」やコメントの名前の横に出す称号・王冠を、まとめて読んで使い回す。
/// 画面ごとに 1 件ずつ読まず、集めてから 30 件ずつ 1 回で読む
@MainActor
final class ProfileBadgeStore: ObservableObject {
    static let shared = ProfileBadgeStore()
    @Published private(set) var badges: [String: ProfileBadge] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var pending = Set<String>()
    private var flushing = false
    private let ttl: TimeInterval = 600

    func badge(_ uid: String) -> ProfileBadge { badges[uid] ?? ProfileBadge.none }

    /// 読んでほしい uid を登録する(まだ読んでいない・古いものだけ)
    func request(_ uids: [String]) {
        let now = Date()
        for u in uids where !u.isEmpty {
            if let t = fetchedAt[u], now.timeIntervalSince(t) < ttl { continue }
            pending.insert(u)
        }
        guard !pending.isEmpty, !flushing else { return }
        flushing = true
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)   // 少し待って、まとめて読む
            await flush()
        }
    }

    /// 自分の表示を、すぐ入れ替える(称号を付け替えた直後など)
    func set(_ uid: String, _ badge: ProfileBadge) { badges[uid] = badge; fetchedAt[uid] = Date() }

    private func flush() async {
        defer { flushing = false }
        guard Backend.isAvailable else { pending.removeAll(); return }
        let batch = Array(pending)
        pending.removeAll()
        let now = Date()
        for start in stride(from: 0, to: batch.count, by: 30) {
            let chunk = Array(batch[start..<min(start + 30, batch.count)])
            guard let snap = try? await Firestore.firestore().collection("publicProfiles").whereField(FieldPath.documentID(), in: chunk).getDocuments() else { continue }
            var found: [String: ProfileBadge] = [:]
            for d in snap.documents {
                let x = d.data()
                found[d.documentID] = ProfileBadge(title: (x["title"] as? String).flatMap { TitleID.isValid($0) ? $0 : nil },
                                                   crown: (x["crown"] as? NSNumber)?.intValue ?? 0, medal: (x["medal"] as? Bool) ?? false)
            }
            for u in chunk { badges[u] = found[u] ?? ProfileBadge.none; fetchedAt[u] = now }
        }
        if !pending.isEmpty { request([]) }
    }
}

// MARK: - 自分の称号

/// 自分が持っている称号と、付けている称号
@MainActor
final class TitleService: ObservableObject {
    static let shared = TitleService()
    @Published private(set) var owned: [String] = []
    @Published private(set) var selected: String?
    /// 付けている王冠・メダル(月間の称号の ID)。nil で、おまかせでなければ「付けない」
    @Published private(set) var crownSel: String?
    /// おまかせ(いちばんよい王冠・メダルを自動で付ける)か
    @Published private(set) var crownAuto = true
    @Published private(set) var loaded = false

    func load(uid: String?) async {
        guard Backend.isAvailable, let uid else { return }
        guard let snap = try? await Firestore.firestore().document("titleState/\(uid)").getDocument() else { return }
        owned = ((snap.data()?["titles"] as? [String]) ?? []).filter(TitleID.isValid)
        selected = (snap.data()?["sel"] as? String).flatMap { TitleID.isValid($0) ? $0 : nil }
        if let data = snap.data(), data.keys.contains("crownSel") {
            crownAuto = false
            crownSel = (data["crownSel"] as? String).flatMap { TitleID.crown($0) != nil ? $0 : nil }
        } else {
            crownAuto = true
            crownSel = TitleID.crownSorted(owned).first
        }
        loaded = true
    }

    /// 称号を付ける(nil で外す)。成功したら true
    func select(_ id: String?, uid: String?) async -> Bool {
        guard Backend.isAvailable else { return false }
        do {
            _ = try await Backend.functions.httpsCallable("setTitle").call(["id": id as Any? ?? NSNull()])
            selected = id
            if let uid {
                var b = ProfileBadgeStore.shared.badge(uid)
                b.title = id
                ProfileBadgeStore.shared.set(uid, b)
            }
            return true
        } catch { return false }
    }

    /// 王冠・メダルを付ける。id が nil で外す。auto == true でおまかせ(いちばんよいもの)。成功したら true
    func selectCrown(_ id: String?, auto: Bool = false, uid: String?) async -> Bool {
        guard Backend.isAvailable else { return false }
        do {
            _ = try await Backend.functions.httpsCallable("setCrown").call(["id": auto ? "auto" : (id as Any? ?? NSNull())])
            crownAuto = auto
            crownSel = auto ? TitleID.crownSorted(owned).first : id
            if let uid {
                var b = ProfileBadgeStore.shared.badge(uid)
                let c = crownSel.flatMap { TitleID.crown($0) }
                b.crown = c?.crown ?? 0
                b.medal = c?.medal ?? false
                ProfileBadgeStore.shared.set(uid, b)
            }
            return true
        } catch { return false }
    }

    /// 新しくもらった称号を、持っている一覧に入れる(提出の結果から)
    func gained(_ ids: [String]) {
        for id in ids where TitleID.isValid(id) && !owned.contains(id) { owned.append(id) }
    }
}

// MARK: - 称号を選ぶ画面

struct TitlePickerView: View {
    @ObservedObject private var service = TitleService.shared
    @EnvironmentObject private var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var failed = false

    var body: some View {
        ZStack {
            GameStyle.night.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("title.button").font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(GameStyle.yellow)
                        Spacer()
                        Button { gameTap(); dismiss() } label: {
                            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundStyle(.white)
                                .frame(width: 36, height: 36).background(GameStyle.panelHi, in: Circle())
                                .overlay(Circle().stroke(GameStyle.edge))
                        }
                        .buttonStyle(BounceButtonStyle())
                        .accessibilityIdentifier("titles.close")
                        .accessibilityLabel(Text("swipe.close"))
                    }
                    GamePanel(title: "title.section.score", tint: GameStyle.yellow) {
                        VStack(spacing: 8) {
                            ForEach(TitleID.scoreIDs, id: \.self) { id in
                                if service.owned.contains(id) {
                                    row(id)
                                } else {
                                    HStack {
                                        Text(TitleID.text(id) ?? "").font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.text.opacity(0.45))
                                        Spacer()
                                        Text(String(format: L("title.need"), ScoreFormat.short(BigScore(TitleID.scoreMin[id] ?? "0") ?? .zero, SwipePalette.scoreStyle)))
                                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.5))
                                        Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(GameStyle.text.opacity(0.5))
                                    }
                                    .padding(.vertical, 10).padding(.horizontal, 12)
                                    .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    let monthly = TitleID.monthSorted(service.owned)
                    GamePanel(title: "title.section.month", tint: GameStyle.pinkColor) {
                        if monthly.isEmpty {
                            Text("title.month.empty").font(.footnote).foregroundStyle(GameStyle.text.opacity(0.6))
                        } else {
                            VStack(spacing: 8) { ForEach(monthly, id: \.self) { row($0) } }
                        }
                        Text("title.month.footer").font(.system(size: 11, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.5))
                    }
                    GamePanel(title: "title.section.crown", tint: CrownStyle.gold) {
                        let crowns = TitleID.crownSorted(service.owned)
                        VStack(spacing: 8) {
                            crownRow(title: L("title.crown.auto"), on: service.crownAuto, id: "auto", icon: "wand.and.stars", color: GameStyle.text) { pickCrown(nil, auto: true) }
                            ForEach(crowns, id: \.self) { id in
                                let c = TitleID.crown(id)
                                crownRow(title: TitleID.text(id) ?? "", on: !service.crownAuto && service.crownSel == id, id: id,
                                         icon: (c?.crown ?? 0) > 0 ? "crown.fill" : "medal.fill",
                                         color: CrownStyle.color(c?.crown ?? 0) ?? GameStyle.pinkColor) { pickCrown(id, auto: false) }
                            }
                            crownRow(title: L("title.crown.none"), on: !service.crownAuto && service.crownSel == nil, id: "none", icon: "nosign", color: GameStyle.text.opacity(0.6)) { pickCrown(nil, auto: false) }
                        }
                        if crowns.isEmpty { Text("title.crown.empty").font(.footnote).foregroundStyle(GameStyle.text.opacity(0.6)) }
                        Text("title.crown.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.5))
                    }
                    let invites = TitleID.inviteSorted(service.owned)
                    if !invites.isEmpty {
                        GamePanel(title: "title.section.invite", tint: GameStyle.pinkColor) {
                            VStack(spacing: 8) { ForEach(invites, id: \.self) { row($0) } }
                        }
                    }
                    Button { gameTap(); pick(nil) } label: {
                        HStack {
                            Text("title.none").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                            Spacer()
                            if service.selected == nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(GameStyle.pinkColor) }
                        }
                        .padding(14).background(GameStyle.panel, in: PixelRect(cornerRadius: 16))
                        .overlay(PixelRect(cornerRadius: 16).stroke(service.selected == nil ? GameStyle.pinkColor : GameStyle.edge, lineWidth: service.selected == nil ? 2 : 1))
                    }
                    .buttonStyle(BounceButtonStyle())
                    if failed { Text("swipe.error.network").font(.footnote).foregroundStyle(.secondary) }
                }
                .padding(.horizontal, 16).padding(.bottom, 28).padding(.top, 8)
            }
        }
        .preferredColorScheme(.dark)
        .task { await service.load(uid: auth.uid) }
    }

    private func crownRow(title: String, on: Bool, id: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button { gameTap(); action() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(color).frame(width: 24)
                Text(title).font(.system(size: 13, weight: .heavy)).foregroundStyle(GameStyle.text)
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(GameStyle.pinkColor) }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(on ? GameStyle.pinkColor.opacity(0.16) : Color.white.opacity(0.06), in: PixelRect(cornerRadius: 12))
            .overlay(PixelRect(cornerRadius: 12).strokeBorder(on ? GameStyle.yellow : GameStyle.edge, lineWidth: 2))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityIdentifier("crown.row.\(id)")
    }

    private func pickCrown(_ id: String?, auto: Bool) {
        Task { failed = !(await service.selectCrown(id, auto: auto, uid: auth.uid)) }
    }

    private func row(_ id: String) -> some View {
        let on = service.selected == id
        return Button { gameTap(); pick(id) } label: {
            HStack {
                TitleChip(id: id, size: 13)
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(GameStyle.pinkColor) }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(on ? GameStyle.pinkColor.opacity(0.16) : Color.white.opacity(0.06), in: PixelRect(cornerRadius: 12))
            .overlay(PixelRect(cornerRadius: 12).strokeBorder(on ? GameStyle.yellow : GameStyle.edge, lineWidth: 2))
        }
        .buttonStyle(BounceButtonStyle())
        .accessibilityIdentifier("title.row.\(id)")
    }

    private func pick(_ id: String?) {
        Task {
            failed = false
            if await !service.select(id, uid: auth.uid) { failed = true }
        }
    }
}
