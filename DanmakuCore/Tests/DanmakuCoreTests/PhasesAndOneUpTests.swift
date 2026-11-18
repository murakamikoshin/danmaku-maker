import XCTest
@testable import DanmakuCore

/// 1.3.0 の要望: ボスの段階を 4・5 に増やす、段階の名前と必殺技(見た目だけ)、連戦の途中のボスを倒したときの1UP
final class PhasesAndOneUpTests: XCTestCase {
    private func boss(phases: Int?, hp: Int = 500, ems: [Emitter] = [Emitter(t: .ring, i: 0.3, c: 8)]) -> Stage {
        var s = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: hp, bossMove: 0, emitters: ems)
        s.phases = phases
        return s.sanitized()
    }

    func testPhaseCodesUpToFive() {
        XCTAssertEqual(Emitter.phases(of: 135), [1, 3, 5])
        XCTAssertEqual(Emitter.phases(of: 45), [4, 5])
        XCTAssertEqual(Emitter.phases(of: 31), [], "小さい順でないものは形が正しくない")
        XCTAssertEqual(Emitter.phases(of: 16), [], "6 段階はない")
        XCTAssertEqual(Emitter.phaseCode([5, 1, 3], count: 5), 135)
        XCTAssertEqual(Emitter.phaseCode([1, 2, 3, 4], count: 4), 0, "全部は 0")
        XCTAssertEqual(Emitter.sanitizedPhase(45, count: 5), 45)
        XCTAssertEqual(Emitter.sanitizedPhase(45, count: 4), 4, "段階の数より後は外す")
        XCTAssertEqual(Emitter.sanitizedPhase(5, count: 3), 3, "残らなければ最後の段階")
        XCTAssertEqual(Emitter.sanitizedPhase(1234, count: 4), 0)
        XCTAssertTrue(Emitter(t: .ring, ph: 135).fires(inPhase: 5))
        XCTAssertFalse(Emitter(t: .ring, ph: 135).fires(inPhase: 4))
    }

    func testSanitizePhaseCountAndAwaken() {
        XCTAssertNil(boss(phases: 3).phases, "3段階は標準なので保存しない")
        XCTAssertNil(boss(phases: 7).phases)
        XCTAssertEqual(boss(phases: 5).phases, 5)
        let json = String(decoding: try! JSONEncoder().encode(boss(phases: nil)), as: UTF8.self)
        XCTAssertFalse(json.contains("phases"), "使わないときは保存しない(これまでの投稿と同じ形)")
        // 覚醒は 2〜段階の数
        var s = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 500, bossMove: 0, emitters: [Emitter(t: .ring)], bossLook: BossCharacter.firstCharacterLook, awaken: 5)
        XCTAssertNil(s.sanitized().awaken)
        s.phases = 5
        XCTAssertEqual(s.sanitized().awaken, 5)
        // 発射台の段階も、段階の数に合わせる
        let b = boss(phases: 4, ems: [Emitter(t: .ring, ph: 45)])
        XCTAssertEqual(b.emitters[0].ph, 4)
        let survive = Stage(name: "s", mode: .survive, durationSec: 20, emitters: [Emitter(t: .ring)])
        var sv = survive; sv.phases = 5
        XCTAssertNil(sv.sanitized().phases, "耐えきるステージには段階がない")
    }

    /// HP を段階の数で等分して進む。3段階は、これまでと同じ
    func testPhaseProgression() {
        func phasesSeen(_ n: Int?) -> [Int] {
            var sim = Simulation(stage: boss(phases: n, hp: 500))
            sim.invincible = true
            var seen: [Int] = []
            while sim.outcome == .playing && sim.tick < 120 * 60 {
                sim.step(.zero)
                if seen.last != sim.phase { seen.append(sim.phase) }
            }
            return seen
        }
        XCTAssertEqual(phasesSeen(nil), [1, 2, 3])
        XCTAssertEqual(phasesSeen(4), [1, 2, 3, 4])
        XCTAssertEqual(phasesSeen(5), [1, 2, 3, 4, 5])
        // ダメージ勝負は、時間を等分
        var d = Stage(name: "d", mode: .damage, durationSec: 30, emitters: [Emitter(t: .ring)])
        d.phases = 5
        var sim = Simulation(stage: d.sanitized())
        sim.invincible = true
        var seen: [Int] = []
        while sim.outcome == .playing && sim.tick < 120 * 40 { sim.step(.zero); if seen.last != sim.phase { seen.append(sim.phase) } }
        XCTAssertEqual(seen, [1, 2, 3, 4, 5])
    }

    func testPhaseInfoIsDecorOnly() {
        var s = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 500, bossMove: 0, emitters: [Emitter(t: .ring, i: 0.3, c: 8)])
        s.phases = 4
        s.phaseInfo = [PhaseInfo(n: "  開幕\n"), PhaseInfo(), PhaseInfo(n: "とても長い必殺技の名前ですよ本当に長い", sp: true), PhaseInfo(), PhaseInfo(n: "捨てる")]
        let clean = s.sanitized()
        XCTAssertEqual(clean.phaseInfo?.count, 4, "段階の数にそろえる")
        XCTAssertEqual(clean.phaseInfo?[0].n, "開幕")
        XCTAssertEqual(clean.phaseInfo?[2].n?.unicodeScalars.count, PhaseInfo.maxName)
        XCTAssertEqual(clean.phaseInfo?[2].sp, true)
        var empty = s; empty.phaseInfo = [PhaseInfo(n: " "), PhaseInfo()]
        XCTAssertNil(empty.sanitized().phaseInfo, "何も付いていなければ保存しない")
        // 名前は計算に関わらない: 同じ結果・同じ乱数の種
        var plain = s; plain.phaseInfo = nil
        XCTAssertEqual(Simulation.run(stage: clean, moves: []), Simulation.run(stage: plain.sanitized(), moves: []))
        XCTAssertEqual(clean.seed, plain.sanitized().seed)
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(clean))
        XCTAssertEqual(back.phaseInfo, clean.phaseInfo)
    }

    /// 必殺技の演出の種類と効果音(1.4.0): 必殺技だけに付く。範囲の外は入れない。計算には関わらない
    func testPhaseFxIsDecorOnly() {
        var s = Stage(name: "b", mode: .boss, durationSec: 60, bossHp: 500, bossMove: 0, emitters: [Emitter(t: .ring, i: 0.3, c: 8)])
        s.phaseInfo = [PhaseInfo(n: "奥義", sp: true, fx: 2, se: 5), PhaseInfo(sp: true, fx: 0, se: 0), PhaseInfo(n: "ふつう", fx: 1, se: 3)]
        let clean = s.sanitized()
        XCTAssertEqual(clean.phaseInfo, [PhaseInfo(n: "奥義", sp: true, fx: 2, se: 5), PhaseInfo(sp: true), PhaseInfo(n: "ふつう")])
        var wild = s; wild.phaseInfo = [PhaseInfo(sp: true, fx: 9, se: 8), PhaseInfo(sp: true, se: -1), PhaseInfo()]
        XCTAssertEqual(wild.sanitized().phaseInfo, [PhaseInfo(sp: true), PhaseInfo(sp: true), PhaseInfo()])
        var plain = s; plain.phaseInfo = nil
        XCTAssertEqual(Simulation.run(stage: clean, moves: []), Simulation.run(stage: plain.sanitized(), moves: []))
        XCTAssertEqual(clean.seed, plain.sanitized().seed)
        let back = try! JSONDecoder().decode(Stage.self, from: JSONEncoder().encode(clean))
        XCTAssertEqual(back.phaseInfo, clean.phaseInfo)
        // 1.3.x が保存した形(fx なし)も、そのまま読める
        let old = try! JSONDecoder().decode([PhaseInfo].self, from: Data(#"[{"n":"a","sp":true},{}]"#.utf8))
        XCTAssertEqual(old, [PhaseInfo(n: "a", sp: true), PhaseInfo()])
        // 効果音は 1〜7。演出とは別々に選べる
        XCTAssertEqual(PhaseInfo.seRange, 1...7)
    }

    private func sequence(oneUp: Int?, last: Int? = 2, lives: Int = 2, mode: LifeMode = .lives) -> Stage {
        var w1 = Wave(kind: .boss, durationSec: 60, bossHp: 100, bossMove: 0, emitters: [Emitter(t: .ring, i: 2, c: 2)])
        w1.oneUp = oneUp
        var w2 = Wave(kind: .boss, durationSec: 60, bossHp: 1000, bossMove: 0, emitters: [Emitter(t: .ring, i: 2, c: 2)])
        w2.oneUp = last
        return Stage(name: "q", mode: .sequence, durationSec: 0, emitters: [], lifeMode: mode, lifeCount: lives, waves: [w1, w2]).sanitized()
    }

    func testOneUpSanitize() {
        let s = sequence(oneUp: 1)
        XCTAssertEqual(s.waves?[0].oneUp, 1)
        XCTAssertNil(s.waves?[1].oneUp, "最後のボスには付けない")
        XCTAssertNil(sequence(oneUp: 9).waves?[0].oneUp)
    }

    /// 自動: 1つ目のボスを倒したら、その場でライフ+1
    func testOneUpAuto() {
        var sim = Simulation(stage: sequence(oneUp: 2, lives: 2))
        sim.invincible = true
        while sim.waveIndex == 0 && sim.tick < 120 * 70 { sim.step(.zero) }
        XCTAssertEqual(sim.waveIndex, 1)
        XCTAssertEqual(sim.lifeLeft, 3)
        XCTAssertEqual(sim.oneUpsTaken, 1)
        // 付けていなければ増えない
        var none = Simulation(stage: sequence(oneUp: nil, lives: 2))
        none.invincible = true
        while none.waveIndex == 0 && none.tick < 120 * 70 { none.step(.zero) }
        XCTAssertEqual(none.lifeLeft, 2)
    }

    /// 拾う: ボスの位置から落ちてくる。自機が真下にいれば拾える。よければ取らずに消える
    func testOneUpPickup() {
        func play(follow: Bool) -> Simulation {
            var sim = Simulation(stage: sequence(oneUp: 1, lives: 2))
            sim.invincible = true
            for _ in 0..<(120 * 75) {
                var mv = Move.zero
                if follow, let item = sim.oneUpItem {
                    mv.dx = item.x > sim.player.x + 1 ? 4 : item.x < sim.player.x - 1 ? -4 : 0
                } else if !follow, sim.oneUpItem != nil {
                    mv.dx = sim.oneUpItem!.x < 100 ? 4 : -4
                }
                sim.step(mv)
                if sim.outcome != .playing { break }
            }
            return sim
        }
        let got = play(follow: true)
        XCTAssertEqual(got.oneUpsTaken, 1)
        XCTAssertEqual(got.lifeLeft, 3)
        XCTAssertNil(got.oneUpItem)
        let missed = play(follow: false)
        XCTAssertEqual(missed.oneUpsTaken, 0)
        XCTAssertEqual(missed.lifeLeft, 2)
        XCTAssertNil(missed.oneUpItem, "画面の下へ出たら消える")
    }

    /// ライフは最大5まで。HP 制は3回復(最大まで)
    func testOneUpCaps() {
        var full = Simulation(stage: sequence(oneUp: 2, lives: 5))
        full.invincible = true
        while full.waveIndex == 0 && full.tick < 120 * 70 { full.step(.zero) }
        XCTAssertEqual(full.lifeLeft, 5)
        var hp = Simulation(stage: sequence(oneUp: 2, lives: 10, mode: .hp))
        hp.invincible = true
        while hp.waveIndex == 0 && hp.tick < 120 * 70 { hp.step(.zero) }
        XCTAssertEqual(hp.lifeLeft, 10, "減っていなければ最大のまま")
    }
}
