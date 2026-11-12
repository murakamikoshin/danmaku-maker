import DanmakuCore
import Foundation
import SwiftUI

struct ShareContext {
    var id: String
    var name: String
    var clearRatePercent: Int?
    var url: URL { AppConfig.shareURL(id) }
}

/// シェア文言（日英は String Catalog。端末の言語で切り替わる）
enum ShareText {
    static func author(name: String, id: String) -> String {
        String(format: L("share.author"), name, AppConfig.shareURL(id).absoluteString)
    }

    /// 自分以外のステージを人に勧めるとき（「作った」とは言わない）
    static func recommend(name: String, id: String) -> String {
        String(format: L("share.recommend"), name, AppConfig.shareURL(id).absoluteString)
    }

    static func player(_ ctx: ShareContext, result: PlayResult) -> String {
        let url = ctx.url.absoluteString
        let time = String(format: "%.1f", result.time)
        switch result.outcome {
        case .cleared where result.isDamage:
            return String(format: L("share.damage"), ctx.name, result.damage, url)
        case .cleared where result.isBoss:
            return String(format: L("share.boss"), time, ctx.name, url)
        case .cleared:
            if let rate = ctx.clearRatePercent { return String(format: L("share.clear.rate"), rate, ctx.name, url) }
            return String(format: L("share.clear"), ctx.name, url)
        default:
            return String(format: L("share.fail"), ctx.name, time, url)
        }
    }

    static func xIntentURL(_ text: String) -> URL? {
        var c = URLComponents(string: "https://x.com/intent/post")
        c?.queryItems = [URLQueryItem(name: "text", value: text)]
        return c?.url
    }
}

/// 共有ボタンの下に出す案内: ステージの共有リンクから新しく入れた人も、招待として数えられる
/// (共有リンクに自分の招待コードが付くときだけ出す)
struct InviteShareHint: View {
    var body: some View {
        if InviteService.cachedCode != nil {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Image(systemName: "gift.fill").foregroundStyle(GameStyle.gold)
                Text("share.invite.hint").foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11, weight: .bold))
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier("share.invite.hint")
        }
    }
}
