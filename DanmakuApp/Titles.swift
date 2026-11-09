import DanmakuCore
import FirebaseFirestore
import SwiftUI

// MARK: - 称号の ID → 文字・色

/// 称号の ID。スコア達成は "score1"〜"score4"、月間は "rank1:2026-11" のように「種類:年-月」
enum TitleID {
    static let scoreIDs = ["score1", "score2", "score3", "score4"]
    /// スコア達成のしきい値(サーバーの titles.ts と同じ値)
    static let scoreMin: [String: String] = ["score1": "100000000", "score2": "1000000000000", "score3": "1000000000000000000", "score4": "10000000000000000000000000000"]
    static let monthKinds = ["rank1", "rank2", "rank3", "top10", "pct1", "pct10", "pct50"]

    struct Month: Equatable { let kind: String; let year: Int; let month: Int }

    static func month(_ id: String) -> Month? {
        let parts = id.split(separator: ":")
        guard parts.count == 2, monthKinds.contains(String(parts[0])) else { return nil }
        let ym = parts[1].split(separator: "-")
        guard ym.count == 2, let y = Int(ym[0]), let m = Int(ym[1]), (1...12).contains(m) else { return nil }
        return Month(kind: String(parts[0]), year: y, month: m)
    }

    static func isValid(_ id: String) -> Bool { scoreIDs.contains(id) || month(id) != nil }

    /// 画面に出す文字(例「弾幕職人」「2026年11月 1位」)
    static func text(_ id: String) -> String? {
        if scoreIDs.contains(id) { return L("title.\(id)") }
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
            case "top10": return Color(Palette.pink)
            default: return Color(Palette.bullets[2])
            }
        }
        switch id {
        case "score4": return CrownStyle.gold
        case "score3": return Color(Palette.pink)
        case "score2": return Color(Palette.bullets[2])
        default: return Color(Palette.bullets[4])
        }
    }

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
                .font(.system(size: size, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(tint)
                .padding(.horizontal, size * 0.6).padding(.vertical, size * 0.15)
                .background(tint.opacity(0.16), in: Capsule())
                .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 0.7))
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
                Image(systemName: "medal.fill").font(.system(size: size * 0.85)).foregroundStyle(Color(Palette.pink))
                    .accessibilityLabel(Text("title.medal"))
            }
            Text(name).font(.system(size: size, weight: weight, design: .rounded)).lineLimit(1)
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
    @Published private(set) var loaded = false

    func load(uid: String?) async {
        guard Backend.isAvailable, let uid else { return }
        guard let snap = try? await Firestore.firestore().document("titleState/\(uid)").getDocument() else { return }
        owned = ((snap.data()?["titles"] as? [String]) ?? []).filter(TitleID.isValid)
        selected = (snap.data()?["sel"] as? String).flatMap { TitleID.isValid($0) ? $0 : nil }
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
            Color(Palette.background).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 12) {
                    HStack {
                        Text("title.button").font(.custom("DelaGothicOne-Regular", size: 22)).foregroundStyle(
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
                    GamePanel(title: "title.section.score", tint: Color(Palette.gold)) {
                        VStack(spacing: 8) {
                            ForEach(TitleID.scoreIDs, id: \.self) { id in
                                if service.owned.contains(id) {
                                    row(id)
                                } else {
                                    HStack {
                                        Text(TitleID.text(id) ?? "").font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text).opacity(0.45))
                                        Spacer()
                                        Text(String(format: L("title.need"), ScoreFormat.short(BigScore(TitleID.scoreMin[id] ?? "0") ?? .zero, SwipePalette.scoreStyle)))
                                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
                                        Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(Color(Palette.text).opacity(0.5))
                                    }
                                    .padding(.vertical, 10).padding(.horizontal, 12)
                                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    let monthly = TitleID.monthSorted(service.owned)
                    GamePanel(title: "title.section.month", tint: Color(Palette.pink)) {
                        if monthly.isEmpty {
                            Text("title.month.empty").font(.footnote).foregroundStyle(Color(Palette.text).opacity(0.6))
                        } else {
                            VStack(spacing: 8) { ForEach(monthly, id: \.self) { row($0) } }
                        }
                        Text("title.month.footer").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(Palette.text).opacity(0.5))
                    }
                    Button { gameTap(); pick(nil) } label: {
                        HStack {
                            Text("title.none").font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                            Spacer()
                            if service.selected == nil { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(Palette.pink)) }
                        }
                        .padding(14).background(GameStyle.panel, in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(service.selected == nil ? Color(Palette.pink) : GameStyle.edge, lineWidth: service.selected == nil ? 2 : 1))
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

    private func row(_ id: String) -> some View {
        let on = service.selected == id
        return Button { gameTap(); pick(id) } label: {
            HStack {
                TitleChip(id: id, size: 13)
                Spacer()
                if on { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(Palette.pink)) }
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(on ? Color(Palette.pink).opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Color(Palette.pink) : GameStyle.edge, lineWidth: on ? 1.5 : 1))
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
