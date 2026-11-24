import XCTest
@testable import DanmakuCore

/// どの2つの弾幕(ボスの技も含む)も、同じ設定で撃ったときに、弾の出方・動きがまったく同じにならないこと(中身がかぶっていない)
final class PatternUniquenessTests: XCTestCase {
    /// 同じ設定のステージを、自機を止めたまま8秒動かし、弾の位置・速さ・種類・光線の向きなどを並べたもの
    /// ボス戦(ボスは動かない)で、look のボスを選んだ状態で撃つ(ボスの技は、そのボスのときだけ動く)
    private func fingerprint(_ t: DanmakuCore.Pattern, x: Double, look: Int?) -> [Double] {
        let m = Emitter(t: t, x: x, y: 0.2, s: 0, e: 20, i: 0.5, c: 8, v: 3, r: 60, k: 1)
        var st = Stage(name: "u", mode: .boss, durationSec: 60, bossHp: 100000, bossMove: 0, emitters: [m])
        st.bossLook = look
        st = st.sanitized()
        XCTAssertEqual(st.emitters[0].t, t, "\(t) が別の弾幕に置き換わった")
        var sim = Simulation(stage: st)
        sim.invincible = true
        var out: [Double] = []
        var step = 0
        while sim.t < 8 {
            sim.step(Move(dx: 0, dy: 0)); step += 1
            guard step % 15 == 0 else { continue }
            out.append(Double(sim.bullets.count))
            for b in sim.bullets {
                out += [b.x, b.y, b.vx, b.vy, b.u0, b.u1, b.u2, b.u3, b.radius, Double(b.script), Double(b.look)].map { ($0 * 1000).rounded() / 1000 }
            }
        }
        return out
    }

    func testNoTwoPatternsAreIdentical() {
        // spiral は、昔から ring と同じ計算(投稿済みのステージのために残しているだけで、エディタには出ない)。custom は描いた軌道しだい
        let skip: Set<DanmakuCore.Pattern> = [.spiral, .custom]
        let normal = DanmakuCore.Pattern.allCases.filter { !skip.contains($0) && $0.bossCharacter == nil }
        var dup: [String] = [], silent: [String] = []
        var compared = Set<DanmakuCore.Pattern>()
        // ボスなし(標準の見た目)と、ボスのキャラクターごとに、ふつうの弾幕+そのボスの技を、同じ条件で比べる
        let looks: [Int?] = [nil] + BossCharacter.allCases.map { $0.rawValue }
        for look in looks {
            let moves = look.flatMap { l in BossCharacter.allCases.first { $0.rawValue == l } }.map { DanmakuCore.Pattern.moves(of: $0) } ?? []
            var seen: [[Double]: DanmakuCore.Pattern] = [:]
            for t in normal + moves {
                // 発射台の位置を2か所で試す(自機狙いかどうかでも区別する)
                let a = fingerprint(t, x: 0.5, look: look), b = fingerprint(t, x: 0.2, look: look)
                // 竜王の「終焉」は弾ではなく、安全地帯だけを残す画面全体の攻撃(Dragon.swift の moveEnd だけが使う動き)なので、弾では比べない
                if a.allSatisfy({ $0 == 0 }) && t != .dragonEnd { silent.append("\(t)") }
                let f = a + [-1] + b
                if let other = seen[f] { dup.append("\(other) = \(t) (look \(String(describing: look)))") } else { seen[f] = t }
                compared.insert(t)
            }
        }
        XCTAssertEqual(Set(silent).sorted { $0 < $1 }, [], "弾を出さない弾幕がある(比べられない)")
        XCTAssertEqual(Array(Set(dup)).sorted(), [], "まったく同じ動きの弾幕がある")
        print("比べた弾幕: \(compared.count) 種類 / 全 \(DanmakuCore.Pattern.allCases.count) 種類")
    }
}
