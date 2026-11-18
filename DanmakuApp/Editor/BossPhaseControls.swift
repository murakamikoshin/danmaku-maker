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
    /// 段階の名前と必殺技の欄を出すか(「くわしく」のときだけ。「かんたん」は段階の数だけ)
    var showNames = true
    /// 段階の数を変えたとき(覚醒の段階・撃つ段階を、新しい数に収めるため)。nil なら phases だけ変える
    var onCountChange: ((Int) -> Void)? = nil
    var idPrefix = "editor.phases"

    private var count: Int { phases ?? 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("editor.phases.count").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: Emitter.phaseCountRange.map { ($0, String(format: L("editor.phases.count.value"), $0)) },
                     selection: Binding(get: { count }, set: { n in if let onCountChange { onCountChange(n) } else { phases = n == 3 ? nil : n } }), idPrefix: idPrefix, minimum: 72)
            Text(byTime ? "editor.phases.note.time" : "editor.phases.note.hp")
                .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            if !showNames, info != nil {
                // 「くわしく」で付けた名前・必殺技は、「かんたん」でもゲームに出る。付いていることだけは知らせる
                Label("editor.phases.names.hidden", systemImage: "text.badge.star").font(.caption).foregroundStyle(.secondary)
            }
            if showNames {
                Text("editor.phases.names").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary).padding(.top, 4)
                ForEach(0..<count, id: \.self) { i in row(i) }
                Text("editor.phases.names.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 1つの段階: 名前の欄と、必殺技のスイッチ。必殺技にすると、その下で演出の種類を選べる(1.4.0)
    private func row(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            nameRow(i)
            if item(i).sp == true {
                Text("editor.phases.fx").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary)
                ChipGrid(items: [(0, L("editor.phases.fx.0")), (1, L("editor.phases.fx.1")), (2, L("editor.phases.fx.2"))],
                         selection: Binding(get: { item(i).fx ?? 0 }, set: { v in update(i) { $0.fx = v == 0 ? nil : v } }),
                         idPrefix: "\(idPrefix).fx.\(i)", minimum: 96)
                Text("editor.phases.se").font(.system(size: 10, weight: .heavy)).foregroundStyle(.secondary).padding(.top, 2)
                ChipGrid(items: (0...7).map { ($0, L("editor.phases.se.\($0)")) },
                         selection: Binding(get: { item(i).se ?? 0 }, set: { v in
                             update(i) { $0.se = v == 0 ? nil : v }
                             // 選んだ音をその場で聞けるように
                             if let e = AudioManager.Effect.special(v) { Task { @MainActor in AudioManager.shared.se(e) } }
                         }),
                         idPrefix: "\(idPrefix).se.\(i)", minimum: 80)
            }
        }
    }

    private func nameRow(_ i: Int) -> some View {
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
                GameToggle(isOn: Binding(get: { item(i).sp == true }, set: { v in update(i) { $0.sp = v ? true : nil; if !v { $0.fx = nil; $0.se = nil } } }))
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
    /// 最後のボスか(倒したらクリアなので1UP は付けられない。欄は消さずに、押せない形で理由を出す)
    var isLast = false
    var idPrefix = "editor.oneup"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("editor.oneup").font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            ChipGrid(items: [(0, L("editor.oneup.none")), (1, L("editor.oneup.pickup")), (2, L("editor.oneup.auto"))],
                     selection: Binding(get: { isLast ? 0 : (oneUp ?? 0) }, set: { oneUp = $0 == 0 ? nil : $0 }), idPrefix: idPrefix, minimum: 90)
                .disabled(isLast).opacity(isLast ? 0.4 : 1)
            Text(isLast ? "editor.oneup.last" : "editor.oneup.note").font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
