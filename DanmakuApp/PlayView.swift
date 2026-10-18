import SwiftUI
import SpriteKit
import DanmakuCore

struct PlayResult {
    var outcome: Outcome
    var time: Double
    var hp: Int
    var duration: Int
    var isBoss: Bool
}

@MainActor
final class PlayModel: ObservableObject {
    let stage: Stage
    @Published private(set) var scene: GameScene
    @Published private(set) var generation = 0
    @Published private(set) var remaining: Double
    @Published private(set) var result: PlayResult?

    init(stage: Stage) {
        self.stage = stage
        remaining = Double(stage.durationSec)
        scene = GameScene(stage: stage)
        wire()
    }

    private func wire() {
        scene.onTime = { [weak self] t in
            guard let self else { return }
            let rounded = (t * 10).rounded() / 10
            if rounded != self.remaining { self.remaining = rounded }
        }
        scene.onFinish = { [weak self] sim, _ in
            guard let self else { return }
            self.result = PlayResult(outcome: sim.outcome, time: max(0, sim.t), hp: sim.hp,
                                     duration: sim.stage.durationSec, isBoss: sim.isBoss)
        }
    }

    func restart() {
        result = nil
        remaining = Double(stage.durationSec)
        scene = GameScene(stage: stage)
        generation += 1
        wire()
    }
}

struct PlayView: View {
    let title: String
    let onExit: () -> Void
    @StateObject private var model: PlayModel

    init(stage: Stage, title: String, onExit: @escaping () -> Void) {
        self.title = title
        self.onExit = onExit
        _model = StateObject(wrappedValue: PlayModel(stage: stage))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("play.quit", action: onExit)
                    .buttonStyle(.bordered)
                    .tint(.white)
                Text(title).font(.headline).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Text(String(format: "%.1f", model.remaining))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(Color(Palette.gold))
            }
            .foregroundStyle(Color(Palette.text))
            .padding(.horizontal, 16).padding(.vertical, 10)

            SpriteView(scene: model.scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder],
                       debugOptions: Self.debugOptions)
                .id(model.generation)
                .aspectRatio(CGFloat(DanmakuConfig.width / DanmakuConfig.height), contentMode: .fit)
                .overlay { if let r = model.result { ResultView(result: r, retry: { model.restart() }, back: onExit) } }
                .frame(maxHeight: .infinity)

            Text("play.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        }
        .background(Color(Palette.background).ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private static var debugOptions: SpriteView.DebugOptions {
        #if DEBUG
        [.showsFPS, .showsNodeCount]
        #else
        []
        #endif
    }
}

struct ResultView: View {
    let result: PlayResult
    let retry: () -> Void
    let back: () -> Void

    private var win: Bool { result.outcome == .cleared }
    private var timeText: String { String(format: "%.1f", result.time) }

    private var headline: String {
        switch result.outcome {
        case .cleared: return L(result.isBoss ? "result.boss.win" : "result.clear")
        case .timeUp: return L("result.timeup")
        default: return L("result.hit")
        }
    }

    private var message: String {
        switch result.outcome {
        case .cleared:
            return result.isBoss ? String(format: L("result.msg.boss"), timeText)
                                 : String(format: L("result.msg.survive"), result.duration)
        case .timeUp: return String(format: L("result.msg.timeup"), result.hp)
        default: return String(format: L("result.msg.hit"), timeText)
        }
    }

    var body: some View {
        ZStack {
            Color(Palette.background).opacity(0.72)
            VStack(spacing: 14) {
                Text(headline)
                    .font(.system(size: 34, weight: .heavy))
                    .foregroundStyle(win ? Color(Palette.gold) : Color(Palette.pink))
                Text(message).font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("result.retry", action: retry).buttonStyle(.borderedProminent).tint(Color(Palette.pink))
                    Button("result.back", action: back).buttonStyle(.bordered).tint(.white)
                }
            }
            .padding(22)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(red: 0.11, green: 0.09, blue: 0.25)))
            .padding(30)
        }
    }
}
