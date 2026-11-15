import DanmakuCore
import SwiftUI

/// ボスの段階の数(3〜5)と、段階ごとの名前・必殺技(1.3.0)。
/// 名前と必殺技は見た目だけ(段階の始めに、名前を大きく出す)。段階の数を変えると、HP の区切りと、撃つ段階の選び方が変わる
struct BossPhaseControls: View {
    /// 段階の数(nil は3段階)
    @Binding var phases: Int?
    /// 段階ごとの名前と必殺技(nil は付けない)
    @Binding var info: [PhaseInfo]?
    /// ダメージ勝負か(段階は、HP ではなく時間で進む)
    var byTime = false
    var idPrefix = "editor.phases"

    private var count: Int { phases ?? 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("editor.phases.count").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: Emitter.phaseCountRange.map { ($0, String(format: L("editor.phases.count.value"), $0)) },
                     selection: Binding(get: { count }, set: { phases = $0 == 3 ? nil : $0 }), idPrefix: idPrefix, minimum: 72)
            Text(byTime ? "editor.phases.note.time" : "editor.phases.note.hp")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            Text("editor.phases.names").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).padding(.top, 4)
            ForEach(0..<count, id: \.self) { i in row(i) }
            Text("editor.phases.names.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 1つの段階: 名前の欄と、必殺技のスイッチ
    private func row(_ i: Int) -> some View {
        HStack(spacing: 8) {
            TextField("", text: nameBinding(i), prompt: Text(String(format: L("play.phase"), i + 1)))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .padding(.vertical, 8).padding(.horizontal, 10)
                .background(GameStyle.panelHi, in: PixelRect(cornerRadius: 10))
                .overlay(PixelRect(cornerRadius: 10).stroke(item(i).sp == true ? GameStyle.pinkColor : GameStyle.edge))
                .accessibilityIdentifier("\(idPrefix).name.\(i)")
            VStack(spacing: 2) {
                Text("editor.phases.special").font(.system(size: 10, weight: .heavy)).foregroundStyle(item(i).sp == true ? GameStyle.pinkColor : .secondary)
                GameToggle(isOn: Binding(get: { item(i).sp == true }, set: { v in update(i) { $0.sp = v ? true : nil } }))
            }
            .accessibilityIdentifier("\(idPrefix).special.\(i)")
        }
    }

    private func item(_ i: Int) -> PhaseInfo {
        guard let info, i < info.count else { return PhaseInfo() }
        return info[i]
    }

    private func nameBinding(_ i: Int) -> Binding<String> {
        Binding(get: { item(i).n ?? "" }, set: { v in
            // 長さはサーバーと同じく、文字の部品(コードポイント)で数えて 16 まで。改行は入れない
            var scalars = String.UnicodeScalarView()
            scalars.append(contentsOf: v.replacingOccurrences(of: "\n", with: " ").unicodeScalars.prefix(PhaseInfo.maxName))
            let cut = String(scalars)
            update(i) { $0.n = cut.isEmpty ? nil : cut }
        })
    }

    /// i 番目を書きかえる。配列は段階の数(最大5)まで伸ばす。何も付いていなければ nil に戻す
    private func update(_ i: Int, _ change: (inout PhaseInfo) -> Void) {
        var list = info ?? []
        while list.count < Emitter.phaseCountRange.upperBound { list.append(PhaseInfo()) }
        change(&list[i])
        info = list.contains { ($0.n ?? "").isEmpty == false || $0.sp == true } ? list : nil
    }
}

/// 連戦で、次の場面があるボスを倒したときの1UP(1.3.0)。出さない / 落ちてくるのを拾う / 倒したら自動
struct OneUpPicker: View {
    @Binding var oneUp: Int?
    var idPrefix = "editor.oneup"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.oneup").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: [(0, L("editor.oneup.none")), (1, L("editor.oneup.pickup")), (2, L("editor.oneup.auto"))],
                     selection: Binding(get: { oneUp ?? 0 }, set: { oneUp = $0 == 0 ? nil : $0 }), idPrefix: idPrefix, minimum: 90)
            Text("editor.oneup.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
