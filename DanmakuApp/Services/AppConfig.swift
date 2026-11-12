import Foundation

/// 公開前に差し替える設定値（ドメイン・連絡先・App Store の URL）
enum AppConfig {
    // TODO: Firebase プロジェクト作成後に実際のドメインへ（既定は <projectId>.web.app）
    static let webHost = "danmaku-maker.web.app"
    static let supportEmail = "koshinstudio88@gmail.com"
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6824245206")!

    static var webBase: URL { URL(string: "https://\(webHost)")! }
    /// ステージの共有リンク。自分の招待コードが分かっていれば ?r=<コード> を付ける
    /// (共有ページの「App Store」ボタンが招待リンク経由になり、そこから入れた人が招待として数えられる)
    static func shareURL(_ id: String) -> URL {
        let url = webBase.appendingPathComponent("s/\(id)")
        guard let code = InviteService.cachedCode, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        c.queryItems = [URLQueryItem(name: "r", value: code)]
        return c.url ?? url
    }

    /// 端末の言語に合わせた規約ページ（ja / en）
    static var webLang: String { Locale.preferredLanguages.first?.hasPrefix("ja") == true ? "ja" : "en" }
    static var termsURL: URL { webBase.appendingPathComponent("\(webLang)/terms") }
    static var privacyURL: URL { webBase.appendingPathComponent("\(webLang)/privacy") }
    static var supportURL: URL { webBase.appendingPathComponent("\(webLang)/support") }
}
