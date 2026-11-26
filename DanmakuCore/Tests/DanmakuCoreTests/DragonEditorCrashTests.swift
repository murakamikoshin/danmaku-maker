import XCTest
@testable import DanmakuCore

/// レビュー(1.4.2): ボスの見た目を竜王にしてから発射台のパターンを変えると落ちる。
/// エディタがパターンを変えたときに動かす計算(技の絵・見本)を、竜王の全部の技と段階の数・姿で回して、落ちないことを確かめる
final class DragonEditorCrashTests: XCTestCase {
    func testIconAndPreviewSimulationsForEveryDragonPatternDoNotCrash() {
        let pats = Pattern.allCases.filter { $0.bossCharacter == .dragon } + [.ring, .aim, .custom, .sideL, .radialLaser, .lightning]
        for p in pats {
            for phases in [1, 2, 3, 4, 5] {
                for form in 0...3 {
                    var m = Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 60, i: 1.5, c: 6, v: 2, r: 0, k: 0)
                    m.k = 0; m.s = 0; m.ph = 0
                    var st = Stage(name: "", mode: .boss, durationSec: 60, bossHp: 9999, emitters: [m], lifeMode: .lives, lifeCount: 9, bossLook: BossCharacter.dragon.rawValue)
                    st.phases = phases
                    st.forms = [form, form, form]
                    st = st.sanitized()
                    var sim = Simulation(stage: st)
                    sim.invincible = true
                    for _ in 0..<Int(6.0 / DanmakuConfig.step) { sim.step(.zero) }
                    _ = sim.dragon.zones
                }
            }
        }
    }
}
