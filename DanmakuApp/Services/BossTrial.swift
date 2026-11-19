import DanmakuCore
import Foundation

/// ショップの「広告を見て戦ってみる」で遊ぶ、キャラクターのボスのお試しステージ。
/// そのボスの専用の技5つを、HP の段階ごとに順に出す(第3段階で覚醒)。記録・ランキング・クリア確認には使わない
enum BossTrial {
    static let durationSec = 90
    static let bossHp = 400
    static let lives = 3
    /// 技ごとの段階(並びは Pattern.moves(of:) と同じ)。第1段階は1つ、第2・第3段階は2つずつ
    static let phases = [1, 2, 2, 3, 3]

    static func stage(for boss: BossCharacter) -> Stage {
        if boss == .dragon { return dragonStage() }
        let emitters = Pattern.moves(of: boss).enumerated().map { i, p -> Emitter in
            var e = Emitter.make(p, end: Double(durationSec))
            e.ph = phases[min(i, phases.count - 1)]
            return e
        }
        return Stage(name: L("enemy.boss.\(boss.rawValue)"), mode: .boss, durationSec: durationSec, bossHp: bossHp, bossMove: 1,
                     emitters: emitters, lifeMode: .lives, lifeCount: lives, bossWarning: true,
                     bossLook: boss.rawValue, awaken: 3).sanitized()
    }

    /// 竜王のお試し: 4 段階で、姿が 通常 → 蒼炎 → 紫電 → 白金 と変わる。技 15 個を段階ごとに分けて出す
    static let dragonPhases = [1, 1, 2, 2, 2, 3, 3, 3, 4, 4]
    /// 自由に決められる技 5 つ(1.4.0)も、段階ごとに 1 つずつ足す(最後の段階は 2 つ)
    static let dragonFreePhases = [1, 2, 3, 4, 4]
    private static func dragonStage() -> Stage {
        var emitters = Pattern.dragon.enumerated().map { i, p -> Emitter in
            var e = Emitter.make(p, end: 150)
            e.ph = dragonPhases[i]
            return e
        }
        emitters += Pattern.dragonFree.enumerated().map { i, p -> Emitter in
            var e = Emitter.make(p, end: 150)
            e.ph = dragonFreePhases[i]
            return e
        }
        var st = Stage(name: L("enemy.boss.13"), mode: .boss, durationSec: 150, bossHp: 900, bossMove: 1,
                       emitters: emitters, lifeMode: .lives, lifeCount: 5, bossWarning: true, bossLook: BossCharacter.dragon.rawValue)
        st.phases = 4
        st.forms = [0, 1, 2, 3]
        // 作者が置ける技は maxEmitters 個まで(sanitized がそれより後を捨てる)。お試しは技を全部見せたいので、上限ずつ整えてつなぐ
        // (上限が 8 だったころは、紅蓮の大旋回・メギドの火が捨てられて出ていなかった)
        var out = st.sanitized()
        var all: [Emitter] = []
        for c in stride(from: 0, to: emitters.count, by: DanmakuConfig.maxEmitters) {
            var part = st
            part.emitters = Array(emitters[c..<min(c + DanmakuConfig.maxEmitters, emitters.count)])
            all += part.sanitized().emitters
        }
        out.emitters = all
        return out
    }
}
