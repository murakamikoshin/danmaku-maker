import DanmakuCore

/// 試作の公式サンプル（フェーズ9で JSON 30本に置き換える）
struct SampleStage: Identifiable {
    let id: String
    let nameKey: String
    let stage: Stage
}

enum SampleStages {
    private static func em(_ t: Pattern, x: Double = 0.5, y: Double = 0.2, s: Double = 0, e: Double = 20, i: Double,
                           c: Int, v: Double, r: Double = 0, k: Int, ph: Int = 0) -> Emitter {
        Emitter(t: t, x: x, y: y, s: s, e: e, i: i, c: c, v: v, r: r, k: k, ph: ph)
    }

    static let all: [SampleStage] = [
        SampleStage(id: "s1", nameKey: "sample.s1", stage: Stage(name: "s1", mode: .survive, durationSec: 20, emitters: [
            em(.spiral, y: 0.25, i: 0.12, c: 3, v: 1.8, r: 11, k: 1)])),
        SampleStage(id: "s2", nameKey: "sample.s2", stage: Stage(name: "s2", mode: .survive, durationSec: 20, emitters: [
            em(.rain, y: 0, i: 0.18, c: 2, v: 2.2, k: 1),
            em(.aim, y: 0.15, s: 5, i: 1.5, c: 3, v: 2.5, r: 30, k: 2)])),
        SampleStage(id: "s3", nameKey: "sample.s3", stage: Stage(name: "s3", mode: .survive, durationSec: 20, emitters: [
            em(.aim, x: 0.2, y: 0.15, i: 0.9, c: 5, v: 3, r: 40, k: 0),
            em(.aim, x: 0.8, y: 0.15, s: 0.45, i: 0.9, c: 5, v: 3, r: 40, k: 3)])),
        SampleStage(id: "s5", nameKey: "sample.s5", stage: Stage(name: "s5", mode: .boss, durationSec: 60, bossHp: 400, bossMove: 1, emitters: [
            em(.aim, e: 30, i: 0.6, c: 5, v: 2.6, r: 50, k: 2, ph: 1),
            em(.ring, e: 30, i: 0.55, c: 18, v: 2, r: 9, k: 0, ph: 2),
            em(.spiral, e: 30, i: 0.09, c: 4, v: 2.1, r: 13, k: 3, ph: 3),
            em(.aim, e: 30, i: 1.4, c: 3, v: 3.2, r: 20, k: 1, ph: 3)])),
        SampleStage(id: "s4", nameKey: "sample.s4", stage: Stage(name: "s4", mode: .survive, durationSec: 20, emitters: [
            em(.ring, x: 0.3, i: 0.7, c: 20, v: 2.2, r: 7, k: 0),
            em(.ring, x: 0.7, s: 0.35, i: 0.7, c: 20, v: 2.2, r: -7, k: 2),
            em(.sweep, y: 0.1, s: 6, i: 0.2, c: 3, v: 3, r: 70, k: 1)])),
    ].map { SampleStage(id: $0.id, nameKey: $0.nameKey, stage: $0.stage.sanitized()) }
}
