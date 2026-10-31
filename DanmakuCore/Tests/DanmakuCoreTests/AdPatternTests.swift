import XCTest
@testable import DanmakuCore

final class AdPatternTests: XCTestCase {
    func testThereAre30AdPatternsAndTheyAreNotPaid() {
        XCTAssertEqual(Pattern.ad.count, 30)
        XCTAssertEqual(Set(Pattern.ad).count, 30)
        XCTAssertEqual(Pattern.ad[4], .chargeBeam, "チャージビームは5番目に解放する")
        XCTAssertEqual(Pattern.ad[9], .boomerang, "ブーメランは10番目に解放する")
        XCTAssertTrue(Set(Pattern.ad).isDisjoint(with: Pattern.pack2), "弾幕パック2のパターンは、広告では手に入らない")
        for p in Pattern.ad {
            XCTAssertTrue(p.isAd)
            XCTAssertFalse(p.isPaid, "\(p)")
            XCTAssertNotNil(p.recipe, "\(p)")
            XCTAssertNotNil(p.recipeDefaults, "\(p)")
        }
        // 並びを変えない(乱数や記録に、並びの番号を使うので、新しいものは後ろに足す)
        XCTAssertEqual(Pattern.allCases.prefix(19).last, .timed)
        XCTAssertEqual(Pattern.allCases.dropFirst(49).first, .custom, "弾幕作成モードのパターンの番号は変えない")
        XCTAssertEqual(Array(Pattern.allCases.dropFirst(50)), [.chargeBeam, .boomerang, .giantOrb, .sweepLaser, .mine, .meteor, .gridLaser, .gravity, .orbit, .snake, .bubble],
                       "あとから足したパターンは、custom より後ろ")
        XCTAssertFalse(Pattern.custom.isAd)
        XCTAssertFalse(Pattern.custom.isPaid)
    }

    func testEveryAdPatternFiresBulletsAndIsDeterministic() {
        for p in Pattern.ad + Pattern.pack2 {
            let d = p.recipeDefaults!
            let m = Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 1)
            func fire() -> [Bullet] {
                var rng = Mulberry32(seed: 7)
                var out: [Bullet] = []
                for k in 0..<5 { Emit.emit(m, shot: k, cx: 180, cy: 100, px: 180, py: 460, rng: &rng, into: &out) }
                return out
            }
            let a = fire()
            XCTAssertGreaterThanOrEqual(a.count, 5, "\(p)")
            XCTAssertLessThanOrEqual(a.count, DanmakuConfig.maxBullets)
            XCTAssertEqual(a, fire(), "\(p) は同じ入力で同じ弾になる")
            XCTAssertTrue(a.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.vx.isFinite && $0.vy.isFinite }, "\(p)")
        }
    }

    func testAdPatternsLookDifferentFromEachOther() {
        // 同じ設定で出したときの弾の並び(位置と速度)が、広告の30個と弾幕パック2の11個で、すべて違う
        var seen = Set<[Double]>()
        for p in Pattern.ad + Pattern.pack2 {
            let d = p.recipeDefaults!
            let m = Emitter(t: p, x: 0.5, y: 0.2, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 0)
            var rng = Mulberry32(seed: 3)
            var out: [Bullet] = []
            for k in 0..<3 { Emit.emit(m, shot: k, cx: 180, cy: 100, px: 120, py: 460, rng: &rng, into: &out) }
            let key = out.flatMap { [($0.x * 100).rounded(), ($0.y * 100).rounded(), ($0.vx * 100).rounded(), ($0.vy * 100).rounded(), Double($0.script), $0.turn, $0.accel, $0.gravity, $0.radius, $0.fuse] }
            XCTAssertTrue(seen.insert(key).inserted, "\(p) は他のパターンと同じ弾の並びになっている")
        }
    }

    func testOwnershipOfAdPatterns() {
        var own = Ownership()
        XCTAssertFalse(own.has(.twinRing))
        own.adPatterns = [.twinRing]
        XCTAssertTrue(own.has(.twinRing))
        XCTAssertFalse(own.has(.tripleRing))
        // 買うパターンのパックでは、広告のパターンは手に入らない。永久買い切りパックなら全部
        XCTAssertFalse(Ownership(productIDs: [Product.patternPack.id]).has(.tripleRing))
        XCTAssertTrue(Ownership(productIDs: [Product.lifetime.id]).has(.tripleRing))
    }

    func testDailyUnlockInOrderOnePerDay() {
        var s = AdPatternState()
        XCTAssertTrue(s.canClaim(today: 20000))
        XCTAssertEqual(s.next, Pattern.ad[0])
        XCTAssertEqual(s.claim(today: 20000), Pattern.ad[0])
        XCTAssertFalse(s.canClaim(today: 20000))
        XCTAssertNil(s.claim(today: 20000))
        XCTAssertNil(s.claim(today: 19990), "端末の日付を戻しても解放できない")
        XCTAssertEqual(s.claim(today: 20003), Pattern.ad[1], "休んだ日があっても、順番は飛ばない")
        XCTAssertEqual(s.unlocked, Set(Pattern.ad.prefix(2)))
        for d in 0..<40 { _ = s.claim(today: 20010 + d) }   // 30個より多く試す
        XCTAssertTrue(s.isComplete)
        XCTAssertNil(s.next)
        XCTAssertFalse(s.canClaim(today: 30000))
        XCTAssertEqual(s.claimed, 30)
    }

    func testLifetimePackUnlocksEverything() {
        let l = Ownership(productIDs: [Product.lifetime.id])
        XCTAssertTrue(l.hasLifetime)
        for t in Theme.paid { for part in ThemePart.allCases { XCTAssertTrue(l.has(part, of: t)) } }
        for s in ShotType.allCases { XCTAssertTrue(l.has(s)) }
        for p in Pattern.allCases { XCTAssertTrue(l.has(p), "\(p)") }
        XCTAssertTrue(l.hasCustomImages)
        XCTAssertTrue(l.hasPatternMaker)
        XCTAssertFalse(l.canBuy(.lifetime))
        for p in Product.all where p != .lifetime { XCTAssertFalse(l.canBuy(p), "\(p)") }
        XCTAssertFalse(Ownership().hasLifetime)
        XCTAssertTrue(Ownership().canBuy(.lifetime))
        XCTAssertEqual(Product(id: Product.lifetime.id), .lifetime)
        XCTAssertEqual(Product(id: Product.patternMaker.id), .patternMaker)
    }

    // MARK: チャージビーム

    private func beamStage(lifeMode: LifeMode = .lives, lives: Int = 1) -> Stage {
        // 真上から真下に撃つビーム(自機は画面下の中央にいるので、自機狙いでも真下を向く)
        let m = Emitter(t: .chargeBeam, x: 0.5, y: 0.1, s: 0, e: 20, i: 10, c: 1, v: 2, r: 0, k: 0)
        var st = Stage(name: "beam", mode: .survive, durationSec: 5, emitters: [m])
        st.lifeMode = lifeMode
        st.lifeCount = lives
        return st
    }

    func testChargeBeamDoesNotHitWhileCharging() {
        var sim = Simulation(stage: beamStage())
        // READY の間と、ためている間(1秒)は、光線の上にいても当たらない
        let untilFire = Int(((DanmakuConfig.readySeconds + DanmakuConfig.beamCharge) / DanmakuConfig.step).rounded()) - 2
        for _ in 0..<untilFire { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.bullets.filter(\.isBeam).count, 1)
        XCTAssertFalse(sim.bullets[0].beamFiring)
        // 撃ち始めたら当たる
        for _ in 0..<10 { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .hit)
    }

    func testChargeBeamCanBeDodgedSideways() {
        var sim = Simulation(stage: beamStage())
        // ためている間に、横へよける(光線の太さより外へ)
        for _ in 0..<Int(((DanmakuConfig.readySeconds + 0.5) / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        for _ in 0..<40 { sim.step(Move(dx: 4, dy: 0)) }   // 40 * 4 * 0.25 = 40px 右へ
        for _ in 0..<Int((1.5 / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        // 撃ち終わったビームは消える
        XCTAssertTrue(sim.bullets.filter(\.isBeam).isEmpty)
    }

    func testChargeBeamHitsOnlyOncePerBeam() {
        var sim = Simulation(stage: beamStage(lifeMode: .hp, lives: 5))
        for _ in 0..<Int(((DanmakuConfig.readySeconds + DanmakuConfig.beamCharge + DanmakuConfig.beamFire) / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .playing)
        XCTAssertEqual(sim.lifeLeft, 4, "光線の中にい続けても、1本のビームで減るのは1つだけ")
    }

    func testBeamHitGeometry() {
        var b = Bullet.beam(x: 100, y: 100, angle: Double.pi / 2, color: 0)   // 真下へ
        XCTAssertFalse(b.beamHits(100, 300), "ためている間は当たらない")
        b.age = DanmakuConfig.beamCharge
        XCTAssertTrue(b.beamHits(100, 300))
        XCTAssertTrue(b.beamHits(108, 400), "中心から8px以内は当たる")
        XCTAssertFalse(b.beamHits(110, 400), "中心から10px離れれば当たらない")
        XCTAssertFalse(b.beamHits(100, 80), "出る場所より後ろには伸びない")
        b.bounces = 0
        XCTAssertFalse(b.beamHits(100, 300), "一度当たったビームは、もう当たらない")
    }

    // MARK: ブーメラン・巨大弾・なぎ払いレーザー

    func testBoomerangComesBack() {
        let m = Emitter(t: .boomerang, x: 0.5, y: 0.2, s: 0, e: 20, i: 5, c: 2, v: 2, r: 40, k: 0)
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(m, shot: 0, cx: 180, cy: 100, px: 180, py: 460, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 2)
        XCTAssertTrue(out.allSatisfy { $0.script == Bullet.boomerangScript })
        XCTAssertEqual(out[0].turn, -out[1].turn, accuracy: 1e-12, "2つは逆向きに曲がる")
        // 弧を描いたあとは、出たときと逆(上)向きに進む
        for i in out.indices { for _ in 0..<Int((2.0 / DanmakuConfig.step).rounded()) { _ = out[i].advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 460) } }
        XCTAssertTrue(out.allSatisfy { $0.vy < 0 }, "戻ってくる")
    }

    func testGiantOrbHasWiderHitArea() {
        // 巨大弾は、ふつうの弾なら当たらない距離(15px)でも当たる
        let m = Emitter(t: .giantOrb, x: 0.5, y: 0.1, s: 0, e: 20, i: 10, c: 1, v: 1.6, r: 0, k: 0)
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(m, shot: 0, cx: 180, cy: 100, px: 180, py: 460, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].isGiant)
        XCTAssertLessThan(15.0 * 15.0, DanmakuConfig.giantHitRadiusSquared)
        XCTAssertGreaterThan(15.0 * 15.0, DanmakuConfig.hitRadiusSquared)
        let st = Stage(name: "g", mode: .survive, durationSec: 10, emitters: [m])
        var sim = Simulation(stage: st)
        // 巨大弾が出て(真下の自機に向かって)から、自機を15px横にずらして待つ
        for _ in 0..<Int(((DanmakuConfig.readySeconds + 0.1) / DanmakuConfig.step).rounded()) { sim.step(.zero) }
        XCTAssertEqual(sim.bullets.count, 1)
        for _ in 0..<15 { sim.step(Move(dx: 4, dy: 0)) }
        for _ in 0..<Int((8.0 / DanmakuConfig.step).rounded()) where sim.outcome == .playing { sim.step(.zero) }
        XCTAssertEqual(sim.outcome, .hit)
    }

    func testSweepLaserSweepsWhileFiring() {
        let m = Emitter(t: .sweepLaser, x: 0.5, y: 0.1, s: 0, e: 20, i: 10, c: 1, v: 2, r: 0, k: 0)
        var rng = Mulberry32(seed: 1)
        var out: [Bullet] = []
        Emit.emit(m, shot: 0, cx: 180, cy: 54, px: 180, py: 459, rng: &rng, into: &out)
        XCTAssertEqual(out.count, 1)
        var b = out[0]
        XCTAssertTrue(b.isBeam)
        let start = atan2(b.vy, b.vx)
        // ためている間は向きが変わらない
        for _ in 0..<Int((DanmakuConfig.beamCharge / DanmakuConfig.step).rounded()) - 1 { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 0, playerY: 0) }
        XCTAssertEqual(atan2(b.vy, b.vx), start, accuracy: 1e-9)
        // 撃っている間に、90度ぶん首を振って、撃ち終わると消える
        var gone = false
        for _ in 0..<Int(((b.beamFireTime + 0.1) / DanmakuConfig.step).rounded()) {
            if b.advance(dt: DanmakuConfig.step, width: 360, playerX: 0, playerY: 0) == .gone { gone = true; break }
        }
        XCTAssertTrue(gone)
        XCTAssertEqual(abs(atan2(b.vy, b.vx) - start), Double.pi / 2, accuracy: 0.05)
    }

    // MARK: 弾幕パック2

    func testPack2HasElevenPaidPatterns() {
        XCTAssertEqual(Pattern.pack2.count, 11)
        for p in Pattern.pack2 {
            XCTAssertTrue(p.isPaid && p.isPack2 && !p.isAd, "\(p)")
            XCTAssertNotNil(p.recipe, "\(p)")
            XCTAssertNotNil(p.recipeDefaults, "\(p)")
        }
        XCTAssertEqual(Pattern.pack2.first, .mine)
    }

    func testPack2Ownership() {
        XCTAssertFalse(Ownership().has(.mine))
        XCTAssertTrue(Ownership(productIDs: [Product.pattern(.mine).id]).has(.mine))
        XCTAssertFalse(Ownership(productIDs: [Product.pattern(.mine).id]).has(.meteor))
        // パック1ではパック2は手に入らず、パック2ではパック1は手に入らない
        XCTAssertFalse(Ownership(productIDs: [Product.patternPack.id]).has(.mine))
        let p2 = Ownership(productIDs: [Product.patternPack2.id])
        XCTAssertTrue(Pattern.pack2.allSatisfy { p2.has($0) })
        XCTAssertFalse(p2.has(.homing))
        XCTAssertFalse(p2.canBuy(.patternPack2))
        XCTAssertTrue(Pattern.pack2.allSatisfy { Ownership(productIDs: [Product.lifetime.id]).has($0) }, "永久買い切りパックなら全部")
        XCTAssertEqual(Product(id: "com.koshin.danmakumaker.patternpack2"), .patternPack2)
        XCTAssertEqual(Product(id: Product.pattern(.gridLaser).id), .pattern(.gridLaser))
        XCTAssertEqual(Product.pattern(.mine).yen, 300)
        XCTAssertEqual(Product.pattern(.orbit).yen, 100)
        XCTAssertTrue(Product.all.contains(.patternPack2))
    }

    private func fire(_ p: DanmakuCore.Pattern, shots: Int = 1, px: Double = 180, py: Double = 459) -> [Bullet] {
        let d = p.recipeDefaults!
        let m = Emitter(t: p, x: 0.5, y: 0.15, s: 0, e: 20, i: d.i, c: d.c, v: d.v, r: d.r, k: 0)
        var rng = Mulberry32(seed: 5)
        var out: [Bullet] = []
        for k in 0..<shots { Emit.emit(m, shot: k, cx: 180, cy: 81, px: px, py: py, rng: &rng, into: &out) }
        return out
    }

    func testMineStopsThenExplodesIntoBlastAndRing() {
        var b = fire(.mine)[0]
        XCTAssertTrue(b.isMine)
        var stoppedAt: (Double, Double)?
        var motion = BulletMotion.alive
        var steps = 0
        while motion == .alive && steps < 1000 {
            motion = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 459)
            if b.mineStopped && stoppedAt == nil { stoppedAt = (b.x, b.y) }
            steps += 1
        }
        XCTAssertEqual(motion, .burst)
        XCTAssertEqual(b.x, stoppedAt!.0, accuracy: 1e-9, "止まってから爆発するまで動かない")
        let frags = b.fragments()
        XCTAssertEqual(frags.count, 1 + DanmakuConfig.mineRing)
        XCTAssertTrue(frags[0].isBlast && frags[0].blastActive, "爆風は、すぐ当たる")
    }

    func testMeteorWarnsThenHitsWhereThePlayerWas() {
        let b = fire(.meteor, px: 120, py: 400)[0]
        XCTAssertTrue(b.isBlast)
        XCTAssertEqual(b.x, 120); XCTAssertEqual(b.y, 400)
        XCTAssertFalse(b.blastHits(120, 400), "予告の間は当たらない")
        var a = b; a.age = a.fuse
        XCTAssertTrue(a.blastHits(120 + 30, 400), "半径の内側は当たる")
        XCTAssertFalse(a.blastHits(120 + 45, 400))
        a.bounces = 0
        XCTAssertFalse(a.blastHits(120, 400), "1回当たったら、もう当たらない")
    }

    func testGridLaserCrossesThePlayer() {
        let beams = fire(.gridLaser, px: 150, py: 380)
        XCTAssertEqual(beams.count, 4)
        XCTAssertTrue(beams.allSatisfy { $0.isBeam })
        XCTAssertEqual(beams[0].x, 150, "1本目は自機を通る縦の線")
        XCTAssertEqual(beams[1].y, 380, "2本目は自機を通る横の線")
    }

    func testGravityShotFallsBack() {
        var b = fire(.gravity)[3]   // 真ん中の弾(真上へ)
        XCTAssertLessThan(b.vy, 0)
        for _ in 0..<Int((2.0 / DanmakuConfig.step).rounded()) { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 459) }
        XCTAssertGreaterThan(b.vy, 0, "重力で落ちてくる")
    }

    func testBubbleGrowsUpToTheLimit() {
        var b = fire(.bubble)[0]
        let start = b.hitDistanceSquared
        for _ in 0..<Int((5.0 / DanmakuConfig.step).rounded()) { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 459) }
        XCTAssertGreaterThan(b.hitDistanceSquared, start)
        XCTAssertEqual(b.radius, b.growMax, accuracy: 1e-9)
    }

    func testOrbitCirclesTheEmitter() {
        var b = fire(.orbit)[0]
        func distance(_ q: Bullet) -> Double { let dx: Double = q.x - 180, dy: Double = q.y - 81; return (dx * dx + dy * dy).squareRoot() }
        let r0 = distance(b)
        for _ in 0..<Int((1.0 / DanmakuConfig.step).rounded()) { _ = b.advance(dt: DanmakuConfig.step, width: 360, playerX: 180, playerY: 459) }
        let r1 = distance(b)
        XCTAssertEqual(r1, r0, accuracy: 2, "回っている間は、発射口からの距離がほぼ変わらない")
    }

    func testSnakeBulletsLineUpBehindTheLeader() {
        let s = fire(.snake)
        XCTAssertEqual(s.count, 8)
        XCTAssertTrue(s.allSatisfy { $0.homeLeft > 0 }, "全部が追いかける")
        XCTAssertLessThan(s[7].y, s[0].y, "後ろの弾ほど、進む向き(下)の後ろ(上)から出る")
    }
}
