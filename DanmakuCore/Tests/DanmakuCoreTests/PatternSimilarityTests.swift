import XCTest
@testable import DanmakuCore

final class PatternSimilarityTests: XCTestCase {
    /// 6秒間動かして、0.5秒ごとの弾の位置(40pxのマス目)を数えた分布
    private func signature(_ p: DanmakuCore.Pattern, px: Double) -> [Double] {
        let d = p.recipeDefaults ?? (i: 1.2, c: 8, v: 2.2, r: 40)
        let m = Emitter(t: p, x: 0.5, y: 0.15, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 0)
        var rng = Mulberry32(seed: 5)
        var bullets: [Bullet] = []
        let dt = DanmakuConfig.step
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        let cols = 9, rows = 14, slices = 12
        var hist = [Double](repeating: 0, count: cols * rows * slices)
        func add(_ x: Double, _ y: Double, _ s: Int) {
            guard x >= 0, x < W, y >= 0, y < H else { return }
            hist[s * cols * rows + Int(y / 40) * cols + Int(x / 40)] += 1
        }
        var nextShot = 0.0, shot = 0
        let steps = Int(6.0 / dt)
        for n in 0..<steps {
            let t = Double(n) * dt
            if t >= nextShot { Emit.emit(m, shot: shot, cx: 180, cy: 81, px: px, py: 459, rng: &rng, into: &bullets); shot += 1; nextShot += d.i }
            var born: [Bullet] = []
            var alive: [Bullet] = []
            for var b in bullets {
                if b.isBeam { b.age += dt; if b.age < 2.5 { alive.append(b) }; continue }
                switch b.advance(dt: dt, width: W, playerX: px, playerY: 459) {
                case .alive: if b.y > -60 && b.y < H + 60 && b.x > -60 && b.x < W + 60 { alive.append(b) }
                case .burst: born.append(contentsOf: b.fragments())
                case .gone: break
                }
            }
            bullets = alive + born
            if n % Int(0.5 / dt) == Int(0.5 / dt) - 1 {
                let s = min(slices - 1, n / Int(0.5 / dt))
                for b in bullets {
                    if b.isBeam { for k in 0..<20 { add(b.x + b.vx * Double(k) * 30, b.y + b.vy * Double(k) * 30, s) } }
                    else { add(b.x, b.y, s) }
                }
            }
        }
        let total = hist.reduce(0, +)
        return total > 0 ? hist.map { $0 / total } : hist
    }

    /// 広告・弾幕パック2・新しい渦巻きは、どのパターンとも、動いたあとの弾の位置の分布が十分に違う
    /// (距離は 0=同じ 〜 1=重ならない。2026-11-01 時点の最小は 0.47)。前から配信している花と星・自機狙いと反射などは対象外
    func testNewPatternsMoveDifferentlyFromEveryOther() {
        let all = DanmakuCore.Pattern.allCases.filter { $0 != .custom && $0 != .spiral }
        let fresh = Set(DanmakuCore.Pattern.ad + DanmakuCore.Pattern.pack2 + [.swirl])
        var sigs: [DanmakuCore.Pattern: [Double]] = [:]
        for p in all { sigs[p] = signature(p, px: 180) + signature(p, px: 60) }
        for i in 0..<all.count { for j in (i + 1)..<all.count where fresh.contains(all[i]) || fresh.contains(all[j]) {
            let a = sigs[all[i]]!, b = sigs[all[j]]!
            var tv = 0.0
            for k in 0..<a.count { tv += abs(a[k] - b[k]) }
            XCTAssertGreaterThan(tv / 4, 0.4, "\(all[i]) と \(all[j]) の動きが近すぎる")
        } }
    }
}
