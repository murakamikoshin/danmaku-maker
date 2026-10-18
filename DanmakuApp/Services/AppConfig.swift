import Foundation

/// 公開前に差し替える設定値（ドメイン・連絡先・App Store の URL）
enum AppConfig {
    // TODO: Firebase プロジェクト作成後に実際のドメインへ（既定は <projectId>.web.app）
    static let webHost = "danmaku-maker.web.app"
    static let supportEmail = "support@danmaku-maker.example"
    static let appStoreURL = URL(string: "https://apps.apple.com/")!

    static var webBase: URL { URL(string: "https://\(webHost)")! }
    static func shareURL(_ id: String) -> URL { webBase.appendingPathComponent("s/\(id)") }

    /// 端末の言語に合わせた規約ページ（ja / en）
    static var webLang: String { Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en" }
    static var termsURL: URL { webBase.appendingPathComponent("\(webLang)/terms") }
    static var privacyURL: URL { webBase.appendingPathComponent("\(webLang)/privacy") }
    static var supportURL: URL { webBase.appendingPathComponent("\(webLang)/support") }
}
