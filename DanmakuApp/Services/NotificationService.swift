import FirebaseFirestore
import FirebaseMessaging
import SwiftUI
import UIKit
import UserNotifications

/// 通知の種類。サーバー(firebase/functions/src/notify.ts の PushKind)と同じ名前
enum PushKind: String, CaseIterable, Identifiable {
    case likes, comments, plays, rewards
    var id: String { rawValue }
    /// LocalizedStringKey("…\\(rawValue)") と書くと、キーが "settings.notify.%@" になって翻訳が引けないので、文字列をつないで作る
    var titleKey: LocalizedStringKey { LocalizedStringKey("settings.notify." + rawValue) }
    var symbol: String {
        switch self {
        case .likes: "heart.fill"
        case .comments: "text.bubble.fill"
        case .plays: "flag.checkered"
        case .rewards: "gift.fill"
        }
    }
}

/// 自分のステージへの反応(いいね・コメント・遊ばれた回数の節目)の通知。
/// 受け取るかどうかと、種類ごとのオン/オフは端末ごとに選べて、users/{uid}/pushDevices/{端末ID} に書く(送るのはサーバー)。
/// はじめは「受け取らない」。設定でオンにしたときに、通知の許可を求める。
@MainActor
final class NotificationService: NSObject, ObservableObject {
    static let shared = NotificationService()

    /// 受け取るか(全体)。オフのときは、種類ごとの設定に関係なく送られない
    @Published private(set) var enabled: Bool
    @Published private(set) var kinds: [PushKind: Bool]
    /// 端末の設定(設定アプリ)で、通知が許可されているか
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// 通知を開いたときに、そのステージを開く
    var onOpenStage: ((String) -> Void)?

    private var uid: String?
    private var token: String?
    private let defaults = UserDefaults.standard

    private static let enabledKey = "notify.enabled"
    private static func kindKey(_ k: PushKind) -> String { "notify.\(k.rawValue)" }
    /// この端末の ID(アプリを入れ直すと変わる。古い端末の登録は、送れなくなったときにサーバーが消す)
    private var deviceID: String {
        if let id = defaults.string(forKey: "notify.deviceID") { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: "notify.deviceID")
        return id
    }

    private override init() {
        enabled = defaults.bool(forKey: Self.enabledKey)
        var k: [PushKind: Bool] = [:]
        for kind in PushKind.allCases { k[kind] = defaults.object(forKey: Self.kindKey(kind)) as? Bool ?? true }
        kinds = k
        super.init()
    }

    /// 起動時に呼ぶ。許可済みなら、通知を受け取る準備をする
    func start() {
        guard Backend.isAvailable else { return }
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self
        Task { await refreshAuthorization() }
    }

    /// ログインしている人が決まったら(変わったら)呼ぶ
    func attach(uid: String?) {
        self.uid = uid
        sync()
    }

    func refreshAuthorization() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        authorization = status
        if enabled && (status == .authorized || status == .provisional || status == .ephemeral) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// 全体のオン/オフ。オンにするときは、通知の許可を求める。許可されなかったら false を返す(オフのまま)
    @discardableResult
    func setEnabled(_ on: Bool) async -> Bool {
        if on {
            let center = UNUserNotificationCenter.current()
            var status = await center.notificationSettings().authorizationStatus
            if status == .notDetermined {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
                status = await center.notificationSettings().authorizationStatus
            }
            authorization = status
            guard status == .authorized || status == .provisional || status == .ephemeral else { return false }
            UIApplication.shared.registerForRemoteNotifications()
        }
        enabled = on
        defaults.set(on, forKey: Self.enabledKey)
        sync()
        return true
    }

    func setKind(_ kind: PushKind, _ on: Bool) {
        kinds[kind] = on
        defaults.set(on, forKey: Self.kindKey(kind))
        sync()
    }

    func isOn(_ kind: PushKind) -> Bool { kinds[kind] ?? true }

    fileprivate func didReceive(token: String?) {
        self.token = token
        sync()
    }

    /// サーバーに、この端末の設定を書く(ログインしていて、トークンがあるときだけ)
    private func sync() {
        guard Backend.isAvailable, let uid, let token else { return }
        var data: [String: Any] = [
            "token": token, "lang": Locale.preferredLanguages.first ?? "en", "enabled": enabled,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        for kind in PushKind.allCases { data[kind.rawValue] = isOn(kind) }
        Firestore.firestore().collection("users").document(uid).collection("pushDevices").document(deviceID).setData(data) { _ in }
    }

    fileprivate func open(userInfo: [AnyHashable: Any]) {
        guard let id = userInfo["stageId"] as? String, !id.isEmpty else { return }
        onOpenStage?(id)
    }
}

extension NotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        Task { @MainActor in NotificationService.shared.didReceive(token: fcmToken) }
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    /// アプリを開いているときも、通知を出す
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// 通知を開いたら、そのステージを開く
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        await MainActor.run { NotificationService.shared.open(userInfo: info) }
    }
}

/// 通知(APNs)の登録結果を Firebase Messaging に渡す。広告の効果計測(AppsFlyer)の準備もここ
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        compatAssumeMainActor { AttributionService.shared.configure(launchOptions: launchOptions) }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
}
