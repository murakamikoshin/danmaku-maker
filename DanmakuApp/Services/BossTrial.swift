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
        let emitters = Pattern.moves(of: boss).enumerated().map { i, p -> Emitter in
            var e = Emitter.make(p, end: Double(durationSec))
            e.ph = phases[min(i, phases.count - 1)]
            return e
        }
        return Stage(name: L("enemy.boss.\(boss.rawValue)"), mode: .boss, durationSec: durationSec, bossHp: bossHp, bossMove: 1,
                     emitters: emitters, lifeMode: .lives, lifeCount: lives, bossWarning: true,
                     bossLook: boss.rawValue, awaken: 3).sanitized()
    }
}
