import Foundation

/// ボスの専用の技が使う、弾の動き(印 = script)。サーバー(bossscripts.ts)にも同じ計算がある。
/// 数値は engine.js(60fps の px/フレーム)を、秒・px/秒に直したもの
extension Bullet {
    /// 待って、動き出す弾。fuse 秒までは動かず、見えず、当たらない(待機)。そのあと u0 (px/秒) で、u1 の向きへ飛ぶ。
    /// u2 == 1 のときは、動き出す瞬間の自機への向き + u1。u3 > 0 なら、動き出してから u3 秒で消える(動かない鎖など)。
    /// 動き出したあとは、ふつうの弾(重力 gravity があれば落ちる)。homeLeft は、動き出したか(0/1)
    public static let holdScript = 16
    /// 枝分かれする弾(六花)。u0 秒ごとに、±u1 ラジアンの2つに分かれる。homeLeft が、あと何回分かれるか
    public static let branchScript = 17
    /// 凍る弾(時の氷結)。u0 秒で止まって結晶になり、u1 秒で消える
    public static let freezeScript = 18
    /// 風に流される弾(吹雪)。u0 が風(px/秒。符号つき)、u1 が揺れの位相、u2 が最初に風向きが変わるまでの秒(そのあとは2秒ごとに入れ替わる)、u3 が落ちる速さ(px/秒。0 なら96)
    public static let windScript = 19
    /// 死神のまわりを回る魂。(u0, u1) を中心に、fuse 秒だけ、角度 u2 から u3 (ラジアン/秒) で回りながら広がり、そのあと自機を追う
    public static let orbitScript = 20
    /// だんだん減速して、fuse 秒で消える弾(膨らむ泡)
    public static let dragScript = 21
    /// 進む向きの横に、波打ちながら進む弾(触手)。u0 が向き、u1 が波の位相、u2 が横の速さの振れ幅(px/秒)、u3 が進む速さ(px/秒)
    public static let lateralScript = 22
    /// 一定の速さで曲がり続ける弾(渦潮)。u0 が曲がる速さ(ラジアン/秒)
    public static let curveScript = 23
    /// ミサイル。fuse 秒は待機(見えず、当たらない)。そのあと u0 秒まで減速、u0〜u2 秒の間は自機のほうへ turn (ラジアン/秒) で向きを変えながら accel (px/秒²) で加速(maxSpeed まで)、そのあとはまっすぐ
    public static let missileScript = 24
    /// 画面を暗くする印(深淵)。動かず、見えず、当たらない。fuse 秒で消える。(x, y) が提灯の位置
    public static let darkScript = 25

    /// 見えず、当たらない(待機中の弾・暗転の印)
    public var isDormant: Bool { ((script == Bullet.holdScript || script == Bullet.missileScript) && age < fuse) || script == Bullet.darkScript }
    /// 待機中でも、うっすら見せる弾か(鎖の予告線)
    public var dormantGlow: Bool { script == Bullet.holdScript && age < fuse && BulletLook.kind(of: look) == .chain }

    /// 1ステップごとの速さの倍率(1/60 秒あたりの倍率を、1/120 秒の刻みに直したもの)
    static let missileDecay = (0.95 as Double).squareRoot()
    static let dragDecay = (0.995 as Double).squareRoot()
    static let windLerp = 1 - (0.97 as Double).squareRoot()
    static let lockLerp = 1 - (0.88 as Double).squareRoot()

    /// 枝分かれ・ボスの専用の弾の動き。nil なら、ここでは扱わない(ふつうの動きに進む)
    mutating func advanceBossScript(dt: Double, playerX: Double, playerY: Double) -> BulletMotion? {
        switch script {
        case Bullet.holdScript:
            age += dt
            if age < fuse { return .alive }
            if homeLeft == 0 {
                homeLeft = 1
                let a = u2 == 1 ? atan2(playerY - y, playerX - x) + u1 : u1
                vx = cos(a) * u0; vy = sin(a) * u0
                if u3 <= 0 { script = 0; return nil }
            }
            if u3 > 0 && age >= fuse + u3 { return .gone }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.branchScript:
            age += dt
            if homeLeft >= 1 && age >= u0 { return .burst }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.freezeScript:
            age += dt
            if age >= u1 { return .gone }
            if age >= u0 {
                if vx != 0 || vy != 0 { vx = 0; vy = 0; look = BulletLook.code(.flake, awakened: BulletLook.isAwakened(look)) }
                return .alive
            }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.windScript:
            age += dt
            let n = age < u2 ? 0 : 1 + Int(((age - u2) / 2).rounded(.down))
            let w = n % 2 == 0 ? u0 : -u0
            vx += (w - vx) * Bullet.windLerp
            vy = (u3 > 0 ? u3 : 96) + sin(age * 60 * 0.05 + u1) * 18
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.orbitScript:
            age += dt
            if age < fuse {
                let r = 10 + 72 * age, a = u2 + u3 * age
                x = u0 + cos(a) * r; y = u1 + sin(a) * r
                return .alive
            }
            let a = atan2(playerY - y, playerX - x)
            vx = cos(a) * 84; vy = sin(a) * 84
            turn = 1.5; homeLeft = 2.0
            script = 0
            return nil
        case Bullet.dragScript:
            age += dt
            if age >= fuse { return .gone }
            vx *= Bullet.dragDecay; vy *= Bullet.dragDecay
            if grow != 0 { radius = min(growMax, radius + grow * dt) }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.lateralScript:
            age += dt
            let lat = cos(6 * age + u1) * u2
            vx = cos(u0) * u3 - sin(u0) * lat
            vy = sin(u0) * u3 + cos(u0) * lat
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.curveScript:
            age += dt
            let sp = (vx * vx + vy * vy).squareRoot()
            let na = atan2(vy, vx) + u0 * dt
            vx = cos(na) * sp; vy = sin(na) * sp
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.missileScript:
            age += dt
            if age < fuse { return .alive }   // 待機中(fuse 秒)は動かない
            let t = age - fuse
            var sp = (vx * vx + vy * vy).squareRoot()
            if t < u0 {
                vx *= Bullet.missileDecay; vy *= Bullet.missileDecay
            } else if t < u2 {
                let want = atan2(playerY - y, playerX - x)
                let cur = atan2(vy, vx)
                var diff = want - cur
                while diff > Double.pi { diff -= 2 * Double.pi }
                while diff < -Double.pi { diff += 2 * Double.pi }
                let maxTurn = turn * dt
                let na = cur + min(maxTurn, max(-maxTurn, diff))
                if u3 > 0 { sp = min(maxSpeed, sp + u3 * dt) }
                vx = cos(na) * sp; vy = sin(na) * sp
            }
            x += vx * dt; y += vy * dt
            return .alive
        case Bullet.darkScript:
            age += dt
            return age >= fuse ? .gone : .alive
        default:
            return nil
        }
    }

    /// 枝分かれ: 進んでいた向きから ±u1 の2つに分かれる。あと1回以上分かれるなら、枝分かれする弾のまま
    func branchChildren() -> [Bullet] {
        let sp = (vx * vx + vy * vy).squareRoot()
        let base = atan2(vy, vx)
        let left = homeLeft - 1
        let aw = BulletLook.isAwakened(look)
        return [-u1, u1].map { d in
            var b = Bullet(x: x, y: y, vx: cos(base + d) * sp, vy: sin(base + d) * sp, color: color)
            b.look = BulletLook.code(left >= 1 ? .shard : .flake, awakened: aw)
            if left >= 1 { b.script = Bullet.branchScript; b.homeLeft = left; b.u0 = u0; b.u1 = u1 }
            return b
        }
    }
}

extension Emit {
    /// 待機してから動き出す弾を作る(BulletLook を付ける)。aim == true なら、動き出す瞬間の自機への向き + angle
    static func holdBullet(x: Double, y: Double, delay: Double, speed: Double, angle: Double, aim: Bool = false,
                           look: UInt8, color: Int, lifetime: Double = 0, gravity: Double = 0) -> Bullet {
        var b = Bullet(x: x, y: y, vx: 0, vy: 0, color: color)
        b.look = look
        b.script = Bullet.holdScript
        b.fuse = delay; b.u0 = speed; b.u1 = angle; b.u2 = aim ? 1 : 0; b.u3 = lifetime
        b.gravity = gravity
        return b
    }
}
