import SwiftUI

/// スワイプ弾幕の今月の賞品: 月末の順位ごとにもらえる称号・王冠・金の自機と、参加賞(回復ドリンク)。
/// 中身はサーバーの titles.ts(awardsFor・goldShipsFor)と、titlesfns.ts の参加賞と同じ
struct SeasonPrizesView: View {
    let openRanking: () -> Void
    @Environment(\.dismiss) private var dismiss

    /// 金の自機は、上の順位ほど多い(上の順位は、下の順位のぶんも全部もらえる)。サーバーの GOLD_SHIP_ORDER の後ろから
    private static let goldOrder = ["ace_gold", "bastion_gold", "gemini_gold", "lancer_gold", "phantom_gold"]
    private struct Row: Identifiable {
        let id: String
        let label: String
        let kind: String
        let crown: Int      // 1〜3 = 金・銀・銅の王冠、4 = メダル、0 = なし
        let ships: Int
    }
    private var rows: [Row] {
        [Row(id: "r1", label: L("season.rank.1"), kind: "rank1", crown: 1, ships: 5),
         Row(id: "r2", label: L("season.rank.2"), kind: "rank2", crown: 2, ships: 4),
         Row(id: "r3", label: L("season.rank.3"), kind: "rank3", crown: 3, ships: 3),
         Row(id: "r10", label: L("season.rank.top10"), kind: "top10", crown: 4, ships: 2),
         Row(id: "p1", label: L("season.rank.pct1"), kind: "pct1", crown: 0, ships: 1),
         Row(id: "p10", label: L("season.rank.pct10"), kind: "pct10", crown: 0, ships: 1),
         Row(id: "p50", label: L("season.rank.pct50"), kind: "pct50", crown: 0, ships: 0)]
    }

    /// スワイプ弾幕でいつでも取れる称号(スコア達成)と、その条件(サーバーの SCORE_TITLES と同じ)。招待の称号は、ともだち招待の画面に出す
    private static let always: [(String, String)] = [
        ("score1", "season.always.score1"), ("score2", "season.always.score2"), ("score3", "season.always.score3"), ("score4", "season.always.score4"),
    ]

    /// 今月(日本時間)の称号の ID(見本の札に使う)
    private var month: String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = Date()
        return String(format: "%04d-%02d", cal.component(.year, from: now), cal.component(.month, from: now))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("season.prizes.note").font(.system(size: 13, weight: .semibold)).foregroundStyle(GameStyle.text.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                    ForEach(rows) { r in row(r) }
                    // 参加賞
                    HStack(spacing: 12) {
                        Text("season.rank.all").font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text).frame(width: 84, alignment: .leading)
                        DrinkArtView(size: 34)
                        Text("season.prize.drink").font(.system(size: 13, weight: .bold)).foregroundStyle(GameStyle.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(12).background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                    Text("season.prizes.footer").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    // いつでも取れる称号(期間なし。一度もらったらずっと使える)
                    Text("season.always.title").font(.display(17)).foregroundStyle(GameStyle.text).padding(.top, 8)
                    Text("season.always.note").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    ForEach(Self.always, id: \.0) { item in
                        HStack(spacing: 10) {
                            TitleChip(id: item.0, size: 11)
                            Spacer(minLength: 6)
                            Text(LocalizedStringKey(item.1)).font(.system(size: 12, weight: .bold)).foregroundStyle(GameStyle.text)
                                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
                        .accessibilityElement(children: .combine)
                    }
                    GameActionButton(title: "swipe.ranking", systemImage: "trophy.fill", fill: GameStyle.gold) {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openRanking() }
                    }
                    .accessibilityIdentifier("season.prizes.ranking")
                }
                .padding(16)
            }
            .background(GameStyle.night.ignoresSafeArea())
            .navigationTitle(Text("season.prizes.sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityIdentifier("season.prizes.close")
                }
            }
        }
    }

    private func row(_ r: Row) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(r.label).font(.system(size: 14, weight: .heavy)).foregroundStyle(GameStyle.text).frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if r.crown >= 1 && r.crown <= 3 {
                        Image(systemName: "crown.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(CrownStyle.color(r.crown) ?? GameStyle.yellow)
                    } else if r.crown == 4 {
                        Image(systemName: "medal.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(GameStyle.pinkColor)
                    }
                    TitleChip(id: "\(r.kind):\(month)", size: 11)
                }
                if r.ships > 0 {
                    HStack(spacing: 4) {
                        ForEach(Self.goldOrder.suffix(r.ships), id: \.self) { SkinThumb(id: $0).frame(width: 26, height: 26) }
                    }
                    .accessibilityLabel(Text(String(format: L("season.prize.ships"), r.ships)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).background(GameStyle.panelHi, in: PixelRect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
