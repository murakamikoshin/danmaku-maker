import DeviceCheck
import FirebaseAuth
import FirebaseFunctions
import Foundation

/// 友達招待(サーバー処理の呼び出しと、受け取ったコードの保管)。
/// - 友達のリンク(OneLink)・手入力から招待コードを受け取る → 登録(1回だけ)。ごほうびはサーバーが付ける
/// - 自分のコード・人数は、サーバーから読む
@MainActor
final class InviteService: ObservableObject {
    static let shared = InviteService()

    struct Info: Equatable { var code: String; var count: Int; var rewarded: Int; var joinedBy: Bool }

    enum RegisterResult: Equatable { case registered, already, badCode, mine, tooOld, network }

    @Published private(set) var info: Info?
    @Published private(set) var loadFailed = false

    private let defaults = UserDefaults.standard
    private static let pendingKey = "invite.pendingCode"
    private static let founderKey = "invite.founderGranted"

    /// OneLink の招待リンク。コードは、リンクの deep_link_sub1 に入れる(AppsFlyer のテンプレート F1m3)
    static func shareURL(code: String) -> URL {
        URL(string: "https://danmaku-maker.onelink.me/F1m3?deep_link_value=invite&deep_link_sub1=\(code)")!
    }

    /// リンクやコードから取り出した招待コードを、保管する(登録できる状態になったら registerPending で送る)
    func receive(code raw: String) {
        let code = Self.normalize(raw)
        guard Self.isValid(code) else { return }
        defaults.set(code, forKey: Self.pendingKey)
        Task { await registerPending() }
    }

    /// OneLink の URL(…?deep_link_sub1=<コード>)から、コードを取り出す。ほかの URL なら nil
    static func code(from url: URL) -> String? {
        guard let host = url.host, host.hasSuffix("onelink.me"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let v = items.first(where: { $0.name == "deep_link_sub1" })?.value else { return nil }
        let c = normalize(v)
        return isValid(c) ? c : nil
    }

    static func normalize(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased().filter { !$0.isWhitespace && $0 != "-" } }
    /// サーバーと同じ文字(紛らわしい 0/O/1/I を除く)・8文字
    static func isValid(_ c: String) -> Bool {
        c.count == 8 && c.allSatisfy { "ABCDEFGHJKLMNPQRSTUVWXYZ23456789".contains($0) }
    }

    /// 保管してあるコードがあれば、登録する。ネットワークの失敗なら残して、次の機会にもう一度
    func registerPending() async {
        guard Backend.isAvailable, let code = defaults.string(forKey: Self.pendingKey) else { return }
        let r = await register(code: code)
        if r != .network { defaults.removeObject(forKey: Self.pendingKey) }
        if r == .registered || r == .already { await refresh() }
    }

    /// コードを登録する(手入力・リンク共通)
    func register(code raw: String) async -> RegisterResult {
        let code = Self.normalize(raw)
        guard Self.isValid(code) else { return .badCode }
        guard Backend.isAvailable else { return .network }
        var payload: [String: Any] = ["code": code]
        if let t = await Self.deviceToken() { payload["deviceToken"] = t }
        do {
            let r = try await Backend.functions.httpsCallable("registerInvite").call(payload)
            if (r.data as? [String: Any])?["status"] as? String == "already" { return .already }
            return .registered
        } catch {
            let msg = (error as NSError).localizedDescription
            if msg == "self" { return .mine }
            if msg == "not-new" { return .tooOld }
            if msg == "code" { return .badCode }
            return .network
        }
    }

    /// 自分のコードと人数を読む(コードがなければ、サーバーが作る)
    func refresh() async {
        guard Backend.isAvailable else { return }
        do {
            let r = try await Backend.functions.httpsCallable("getInviteInfo").call()
            guard let d = r.data as? [String: Any], let code = d["code"] as? String else { loadFailed = true; return }
            CosmeticsStore.shared.setOwnedSkins(d["ships"] as? [String] ?? [])
            if let uid = Auth.auth().currentUser?.uid { await CosmeticsStore.shared.refreshBossTickets(uid: uid) }   // ボスのチケットが増えているかもしれない
            info = Info(code: code, count: (d["count"] as? NSNumber)?.intValue ?? 0, rewarded: (d["rewarded"] as? NSNumber)?.intValue ?? 0, joinedBy: d["joinedBy"] as? Bool ?? false)
            loadFailed = false
        } catch { loadFailed = true }
    }

    /// 「初期プレイヤー」の称号(締め切りより前に作ったアカウントだけ。サーバーが判定する。もらえたら、もう聞かない)
    func claimFounderIfNeeded() async {
        guard Backend.isAvailable, !defaults.bool(forKey: Self.founderKey) else { return }
        guard let r = try? await Backend.functions.httpsCallable("claimFounder").call(),
              (r.data as? [String: Any])?["granted"] as? Bool == true else { return }
        defaults.set(true, forKey: Self.founderKey)
    }

    /// この端末の DeviceCheck トークン(再インストールでの自作自演を見分けるのに、サーバーが使う)。取れなければ nil
    private static func deviceToken() async -> String? {
        guard DCDevice.current.isSupported else { return nil }
        return await withCheckedContinuation { c in
            DCDevice.current.generateToken { data, _ in c.resume(returning: data?.base64EncodedString()) }
        }
    }
}
