import DanmakuCore
import SwiftUI

/// 弾幕作成モード(有料): 指で線を描くと、弾がその線の上を、描いた速さで進む弾幕になる。
/// 始めた場所が発射位置、線を描く速さが弾の速さ。作った弾幕は保存して、ステージ作りで選べる
struct PatternMakerView: View {
    @ObservedObject private var library = PatternLibrary.shared
    @Environment(\.dismiss) private var dismiss

    // 描いている途中の記録: (時刻, 位置)
    @State private var raw: [(t: TimeInterval, p: CGPoint)] = []
    @State private var drawing = false
    @State private var path: [Double] = []
    @State private var origin = CGPoint(x: 180, y: 60)   // 発射位置(論理px)
    @State private var copies = 6
    @State private var speed = 2.0
    @State private var name = ""
    @State private var editingID: UUID?
    @State private var message: LocalizedStringKey?
    @State private var engine = PatternDemoEngine(source: Point(x: 180, y: 60), player: Point(x: 180, y: 290), sweepPlayer: false)

    private let fieldW = PatternDemoEngine.fieldWidth, fieldH = PatternDemoEngine.fieldHeight
    /// 画面に出す描く範囲の大きさ(論理px)
    private var emitterForPreview: Emitter? {
        guard !path.isEmpty else { return nil }
        return Emitter(t: .custom, x: 0.5, y: 0.2, s: 0, e: 60, i: 1.2, c: copies, v: speed, r: 0, k: 0, path: path)
    }

    var body: some View {
        VStack(spacing: 0) {
            ScreenHeader(title: "maker.title") {
                RoundIconButton(systemImage: "xmark", label: "editor.close") { dismiss() }
            } trailing: { Color.clear.frame(width: 38, height: 38) }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("maker.draw.hint").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    canvas
                    controls
                    savedList
                }
                .padding(16)
            }
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: 描く場所(実際の画面と同じ比率。幅 360 を枠いっぱいに使う)

    private var canvas: some View {
        let images = SpriteFactory.bulletImages(.classic)
        return GeometryReader { geo in
            let s = geo.size.width / fieldW
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                Canvas { ctx, size in
                    if let m = emitterForPreview {
                        engine.advance(to: tl.date, emitters: [m], key: PreviewKey(path: path, copies: copies, speed: speed, ox: origin.x, oy: origin.y))
                    }
                    // 描いた線
                    let pts = drawing ? raw.map(\.p) : (path.isEmpty ? [] : stride(from: 0, to: path.count, by: 2).map { CGPoint(x: origin.x + path[$0], y: origin.y + path[$0 + 1]) })
                    if pts.count > 1 {
                        var line = Path()
                        line.move(to: CGPoint(x: pts[0].x * s, y: pts[0].y * s))
                        for q in pts.dropFirst() { line.addLine(to: CGPoint(x: q.x * s, y: q.y * s)) }
                        ctx.stroke(line, with: .color(Color(Palette.gold).opacity(0.5)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: drawing ? [] : [4, 4]))
                    }
                    // 弾(ゲームと同じ 12×12)
                    let bs = 12 * s
                    for b in engine.bullets where !path.isEmpty {
                        ctx.draw(Image(uiImage: images[b.color % images.count]), in: CGRect(x: b.x * s - bs / 2, y: b.y * s - bs / 2, width: bs, height: bs))
                    }
                    // 発射位置
                    if !path.isEmpty || drawing {
                        let o = CGPoint(x: origin.x * s, y: origin.y * s)
                        ctx.fill(GameBossShape().path(in: CGRect(x: o.x - 14 * s * 1.6, y: o.y - 14 * s * 1.6, width: 28 * s * 1.6, height: 28 * s * 1.6)),
                                 with: .color(Color(Palette.pink).opacity(0.85)), style: FillStyle(eoFill: true))
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let p = CGPoint(x: min(fieldW, max(0, v.location.x / s)), y: min(fieldH, max(0, v.location.y / s)))
                    if !drawing { drawing = true; raw = []; path = []; origin = p }
                    raw.append((Date.timeIntervalSinceReferenceDate, p))
                }
                .onEnded { _ in finishDrawing() })
        }
        .aspectRatio(fieldW / fieldH, contentMode: .fit)
        .background(Color(Palette.background), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(GameStyle.edge))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay {
            if path.isEmpty && !drawing {
                Text("maker.draw.empty").font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
        }
        .accessibilityIdentifier("maker.canvas")
    }

    /// 描き終わり: 描いた時間の流れ(速さ)のまま、PathData.step ごとの点に並べ直す
    private func finishDrawing() {
        drawing = false
        guard let first = raw.first, let last = raw.last, last.t - first.t >= PathData.step * 2 else { raw = []; message = "maker.tooshort"; return }
        let duration = min(last.t - first.t, PathData.step * Double(PathData.pointRange.upperBound - 1))
        let n = Int(duration / PathData.step) + 1
        var out: [Double] = []
        var j = 0
        for i in 0..<n {
            let t = first.t + Double(i) * PathData.step
            while j + 1 < raw.count - 1 && raw[j + 1].t < t { j += 1 }
            let a = raw[j], b = raw[min(j + 1, raw.count - 1)]
            let u = b.t > a.t ? min(1, max(0, (t - a.t) / (b.t - a.t))) : 0
            out.append(Double(a.p.x + (b.p.x - a.p.x) * u) - Double(first.p.x))
            out.append(Double(a.p.y + (b.p.y - a.p.y) * u) - Double(first.p.y))
        }
        path = PathData.sanitized(out) ?? []
        origin = first.p
        engine.source = Point(x: Double(first.p.x), y: Double(first.p.y))
        raw = []
        message = nil
    }

    // MARK: 設定と保存

    private var controls: some View {
        GamePanel(title: "maker.settings") {
            Stepper(value: $copies, in: CustomPattern.copiesRange) {
                Text(String(format: L("maker.copies"), copies)).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            Stepper(value: $speed, in: 1...4, step: 0.5) {
                Text(String(format: L("maker.speed"), speed)).font(.system(size: 14, weight: .bold, design: .rounded))
            }
            TextField("", text: $name, prompt: Text("maker.name.placeholder"))
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .padding(.vertical, 11).padding(.horizontal, 12)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(GameStyle.edge))
                .onChange(of: name) { v in if v.count > CustomPattern.maxNameLength { name = String(v.prefix(CustomPattern.maxNameLength)) } }
                .accessibilityIdentifier("maker.name")
            if let message { Text(message).font(.caption.bold()).foregroundStyle(Color(Palette.gold)) }
            HStack(spacing: 10) {
                Button { gameTap(); clear() } label: { Chip(title: L("maker.clear"), selected: false) }.buttonStyle(BounceButtonStyle())
                GameActionButton(title: "maker.save", systemImage: "square.and.arrow.down.fill", fill: GameStyle.accent) { save() }
                    .disabled(path.isEmpty).opacity(path.isEmpty ? 0.5 : 1)
                    .accessibilityIdentifier("maker.save")
            }
        }
    }

    private func clear() {
        raw = []; path = []; drawing = false; editingID = nil; name = ""; message = nil
    }

    private func save() {
        guard !path.isEmpty else { return }
        let n = name.trimmingCharacters(in: .whitespaces)
        let p = CustomPattern(id: editingID ?? UUID(), name: n.isEmpty ? L("maker.name.default") : n, path: path, copies: copies, speed: speed)
        if library.save(p) { editingID = nil; message = "maker.saved" } else { message = "maker.limit" }
    }

    private var savedList: some View {
        GamePanel(title: "maker.saved.title") {
            if library.items.isEmpty {
                Text("maker.saved.empty").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(library.items) { item in
                HStack(spacing: 10) {
                    CustomPatternIcon(path: item.path).frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 15, weight: .heavy, design: .rounded)).foregroundStyle(Color(Palette.text))
                        Text(String(format: L("maker.item.detail"), item.copies, Double(item.path.count / 2 - 1) * PathData.step)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { gameTap(); load(item) } label: { Chip(title: L("maker.edit"), selected: false) }.buttonStyle(BounceButtonStyle())
                    Button { gameTap(); library.delete(id: item.id) } label: { Image(systemName: "trash").foregroundStyle(Color(Palette.pink)) }.buttonStyle(.plain)
                }
                .padding(10).background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func load(_ item: CustomPattern) {
        path = item.path; copies = item.copies; speed = item.speed; name = item.name; editingID = item.id
        origin = CGPoint(x: 180, y: 60)
        engine.source = Point(x: 180, y: 60)
        message = nil
    }
}

private struct PreviewKey: Hashable {
    let path: [Double]; let copies: Int; let speed: Double; let ox: CGFloat; let oy: CGFloat
}

/// 描いた軌道を小さく描いた絵(保存した弾幕の一覧とエディタの選択に使う)
struct CustomPatternIcon: View {
    let path: [Double]

    var body: some View {
        Canvas { ctx, size in
            let n = path.count / 2
            guard n > 1 else { return }
            let xs = stride(from: 0, to: path.count, by: 2).map { path[$0] }, ys = stride(from: 1, to: path.count, by: 2).map { path[$0] }
            let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
            let span = max(maxX - minX, maxY - minY, 20)
            let sc = (min(size.width, size.height) - 8) / span
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: size.width / 2 + (path[2 * i] - (minX + maxX) / 2) * sc, y: size.height / 2 + (path[2 * i + 1] - (minY + maxY) / 2) * sc)
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<n { line.addLine(to: pt(i)) }
            ctx.stroke(line, with: .color(Color(Palette.gold).opacity(0.8)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            let s = pt(0)
            ctx.fill(Path(ellipseIn: CGRect(x: s.x - 3, y: s.y - 3, width: 6, height: 6)), with: .color(Color(Palette.pink)))
        }
    }
}
