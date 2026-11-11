import DanmakuCore
import SpriteKit
import SwiftUI

/// 下のタブ「バトル」: 弾幕バトル(リアルタイム対戦)の入口と、対戦の画面。
/// 入口(ランク・レート・戦績・対戦する) → 相手を探す → 3・2・1 → 対戦 → 結果。仕様書「弾幕バトル 仕様書」
struct BattleHomeView: View {
    @StateObject private var model = BattleModel()
    @EnvironmentObject private var ads: AdsService

    var body: some View {
        ZStack {
            GameStyle.night.ignoresSafeArea()
            switch model.phase {
            case .title, .searching, .failed:
                title
            case .found, .playing, .waiting, .result:
                arena
            }
        }
        .task { await model.loadStatus() }
        .onDisappear { if case .searching = model.phase { model.cancel() } }
        // 3・2・1 から自分が落ちたあとの待ちまでは、バナーを消す(入口と結果の画面では出す)
        .onChange(of: model.phase) { p in
            switch p {
            case .found, .playing, .waiting: ads.setPlaying(tab: "battle", true)
            default: ads.setPlaying(tab: "battle", false)
            }
        }
    }

    // MARK: 入口

    private var title: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("battle.eyebrow").font(.system(size: 12, weight: .heavy)).foregroundStyle(GameStyle.cyanColor)
                    Text("battle.title").font(.display(30)).foregroundStyle(GameStyle.yellow)
                }
                rankCard
                VStack(alignment: .leading, spacing: 8) {
                    rule("scope", "battle.rule.1")
                    rule("timer", "battle.rule.2")
                    rule("bolt.fill", "battle.rule.3")
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .gamePanel(radius: 16)
                startArea
            }
            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 24)
        }
    }

    private func rule(_ icon: String, _ key: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 14, weight: .bold)).foregroundStyle(GameStyle.yellow).frame(width: 22)
            Text(key).font(.system(size: 14, weight: .bold)).foregroundStyle(GameStyle.text).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rankCard: some View {
        let s = model.status ?? BattleService.Status()
        return HStack(spacing: 14) {
            RankEmblem(rank: s.provisional ? nil : s.rank).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                if s.provisional {
                    Text(String(format: L("battle.provisional"), 10 - s.games)).font(.display(20)).foregroundStyle(GameStyle.text)
                } else {
                    Text(LocalizedStringKey("battle.rank.\(s.rank)")).font(.display(22)).foregroundStyle(RankEmblem.color(s.rank))
                }
                Text(String(format: L("battle.rating"), s.rating)).font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundStyle(GameStyle.text)
                    .accessibilityIdentifier("battle.rating")
                Text(String(format: L("battle.record"), s.wins, s.losses, s.draws)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                Text(String(format: L("battle.season"), BattleHomeView.seasonDaysLeft())).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("battle.season")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .gamePanel(radius: 18)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("battle.rank")
    }

    @ViewBuilder private var startArea: some View {
        switch model.phase {
        case .searching(let left):
            VStack(spacing: 12) {
                ProgressView().tint(GameStyle.yellow)
                Text("battle.searching").font(.display(17)).foregroundStyle(GameStyle.text)
                Text("\(left)").font(.display(34)).foregroundStyle(GameStyle.yellow).contentTransition(.numericText())
                Button { gameTap(); model.cancel() } label: {
                    Text("battle.cancel").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                        .padding(.vertical, 10).padding(.horizontal, 28)
                        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityIdentifier("battle.cancel")
            }
            .frame(maxWidth: .infinity).padding(.vertical, 18)
            .gamePanel(radius: 18)
        case .failed:
            VStack(spacing: 10) {
                Text("battle.failed").font(.system(size: 14, weight: .bold)).foregroundStyle(GameStyle.pinkColor)
                GameActionButton(title: "battle.retry", systemImage: "arrow.clockwise", fill: GameStyle.gold) { model.backToTitle(); model.start() }
            }
        default:
            GameActionButton(title: "battle.start", systemImage: "bolt.fill", fill: GameStyle.gold) { model.start() }
                .accessibilityIdentifier("battle.start")
        }
    }

    /// 今月(日本時間)の残りの日数。シーズンは月ごと
    static func seasonDaysLeft(now: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        guard let range = cal.range(of: .day, in: .month, for: now) else { return 0 }
        return range.count - cal.component(.day, from: now) + 1
    }

    // MARK: 対戦

    private var arena: some View {
        VStack(spacing: 0) {
            hud
            ZStack {
                if let scene = model.scene {
                    SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                        .aspectRatio(CGFloat(DanmakuConfig.width / DanmakuConfig.height), contentMode: .fit)
                }
                overlay
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var hud: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("battle.result.you").font(.system(size: 11, weight: .heavy)).foregroundStyle(GameStyle.cyanColor)
                Text(String(format: L("battle.time"), String(format: "%.1f", model.myTime)))
                    .font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundStyle(GameStyle.text)
            }
            Spacer()
            if model.phase == .playing {
                Button { gameTap(); model.forfeit() } label: {
                    Text("battle.forfeit").font(.system(size: 12, weight: .heavy)).foregroundStyle(GameStyle.text)
                        .padding(.vertical, 6).padding(.horizontal, 10)
                        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("battle.forfeit")
            } else {
                Text("VS").font(.display(16)).foregroundStyle(GameStyle.yellow)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.match?.opponent.name ?? "").font(.system(size: 11, weight: .heavy)).foregroundStyle(GameStyle.pinkColor).lineLimit(1)
                Group {
                    if model.opponentAlive {
                        Text(String(format: L("battle.time"), String(format: "%.1f", model.opponentTime)))
                    } else {
                        Text(String(format: L("battle.opponent.down"), String(format: "%.1f", model.opponentTime)))
                    }
                }
                .font(.system(size: 18, weight: .heavy, design: .monospaced))
                .foregroundStyle(model.opponentAlive ? GameStyle.text : GameStyle.dim)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(GameStyle.nightDeep)
    }

    @ViewBuilder private var overlay: some View {
        switch model.phase {
        case .found(let n):
            VStack(spacing: 14) {
                Text("battle.found").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text)
                if let m = model.match {
                    VStack(spacing: 4) {
                        Text(m.opponent.name).font(.system(size: 22, weight: .heavy)).foregroundStyle(GameStyle.pinkColor)
                        Text(String(format: L("battle.rating"), m.opponent.rating)).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Text("\(n)").font(.display(64)).foregroundStyle(GameStyle.yellow).contentTransition(.numericText())
            }
            .padding(24).gamePanel(radius: 20)
        case .waiting:
            VStack(spacing: 8) {
                ProgressView().tint(GameStyle.yellow)
                Text(model.opponentAlive ? "battle.waiting" : "battle.judging").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                    .multilineTextAlignment(.center)
            }
            .padding(20).gamePanel(radius: 18)
        case .result(let r):
            BattleResultCard(result: r, opponent: model.match?.opponent.name ?? "",
                             again: { model.backToTitle(); model.start() }, quit: { model.backToTitle() })
                .padding(.horizontal, 20)
        default:
            EmptyView()
        }
    }
}

/// 結果: 勝ち負け、二人の秒、レートの増減
private struct BattleResultCard: View {
    let result: BattleService.Result
    let opponent: String
    let again: () -> Void
    let quit: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(LocalizedStringKey("battle.result.\(result.outcome.rawValue)"))
                .font(.display(34))
                .foregroundStyle(result.outcome == .win ? GameStyle.yellow : result.outcome == .lose ? GameStyle.dim : GameStyle.text)
            HStack(spacing: 18) {
                side(Text("battle.result.you"), result.me.ticks, GameStyle.cyanColor)
                Text("VS").font(.display(14)).foregroundStyle(.secondary)
                side(Text(verbatim: opponent), result.opp.ticks, GameStyle.pinkColor)
            }
            let d = result.ratingAfter - result.ratingBefore
            HStack(spacing: 6) {
                Text(String(format: L("battle.rating"), result.ratingAfter)).font(.system(size: 16, weight: .heavy, design: .monospaced))
                Text(d >= 0 ? "+\(d)" : "\(d)").font(.system(size: 16, weight: .heavy, design: .monospaced))
                    .foregroundStyle(d >= 0 ? GameStyle.green : GameStyle.pinkColor)
            }
            .foregroundStyle(GameStyle.text)
            if BattleService.rankOf(result.ratingBefore) != result.rank {
                Text(LocalizedStringKey("battle.rank.\(result.rank)")).font(.display(18)).foregroundStyle(RankEmblem.color(result.rank))
            }
            HStack(spacing: 10) {
                Button { gameTap(); quit() } label: {
                    Text("battle.result.quit").font(.system(size: 15, weight: .heavy)).foregroundStyle(GameStyle.text)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityIdentifier("battle.result.quit")
                GameActionButton(title: "battle.result.again", systemImage: "bolt.fill", fill: GameStyle.gold, action: again)
                    .accessibilityIdentifier("battle.result.again")
            }
        }
        .padding(20)
        .gamePanel(radius: 20)
    }

    private func side(_ name: Text, _ ticks: Int, _ color: Color) -> some View {
        VStack(spacing: 2) {
            name.font(.system(size: 12, weight: .heavy)).foregroundStyle(color).lineLimit(1)
            Text(String(format: L("battle.time"), String(format: "%.1f", Double(ticks) / 120)))
                .font(.system(size: 20, weight: .heavy, design: .monospaced)).foregroundStyle(GameStyle.text)
        }
        .frame(maxWidth: .infinity)
    }
}

/// ランクの紋章: ランクの色のひし形に、白い弾。暫定(nil)は灰色の「?」
struct RankEmblem: View {
    let rank: String?

    static func color(_ rank: String) -> Color {
        switch rank {
        case "bronze": return Color(red: 0.80, green: 0.52, blue: 0.32)
        case "silver": return Color(red: 0.80, green: 0.82, blue: 0.88)
        case "gold": return GameStyle.yellow
        case "platinum": return GameStyle.cyanColor
        case "diamond": return GameStyle.violet
        default: return GameStyle.pinkColor
        }
    }

    var body: some View {
        ZStack {
            Rectangle().fill(rank.map(Self.color) ?? GameStyle.edge)
                .rotationEffect(.degrees(45)).padding(10)
            if rank == nil {
                Text("?").font(.display(24)).foregroundStyle(GameStyle.text)
            } else {
                Circle().fill(Color.white).frame(width: 14, height: 14)
                Circle().stroke(GameStyle.night, lineWidth: 3).frame(width: 14, height: 14)
            }
        }
    }
}
