import Foundation

public struct Point: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

public struct Bullet: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var color: Int
    /// 追尾弾の曲がる速さ(ラジアン/秒。0 なら追尾しない)と、追尾の残り時間(秒)
    public var turn: Double = 0
    public var homeLeft: Double = 0
    /// 加速弾: 1秒あたりに速さが増える割合(0 なら加速しない)と、速さの上限(px/秒)
    public var accel: Double = 0
    public var maxSpeed: Double = 0
    /// 反射弾: 左右の壁で、あと何回はね返るか
    public var bounces: Int = 0
    /// 時間で動きが変わる弾: 1=停止弾 2=分裂弾 3=時差弾(0 なら、ふつうの弾)と、出てからの経過秒
    public var script: Int = 0
    public var age: Double = 0
    /// 弾幕作成モードで描いた軌道に沿って進む弾(nil なら、ふつうの弾)
    public var follow: PathFollow?
    /// 下向きの重力(px/秒²。重力弾)
    public var gravity: Double = 0
    /// 当たる範囲の広さ(ふつうの弾より何px広いか)と、1秒あたりに広がる量・上限(膨らむ泡)。爆風は、この広さの円
    public var radius: Double = 0
    public var grow: Double = 0
    public var growMax: Double = 0
    /// 地雷: 出てから爆発するまで(秒)。爆風: 予告の円を出している時間(秒。この間は当たらない)
    public var fuse: Double = 0
    /// すでにかすった(1 発につき 1 回だけ数える。スワイプ弾幕の点数に使う。弾の動きや当たり判定には関わらない)
    public var grazed = false
    /// 見た目だけ: 0 は標準、1 は「くの字」で描く、2 は丸で描く(発射台の sh から付く。動きや当たり判定には関わらない)
    public var look: UInt8 = 0
    /// 堕天使の技だけが使う、予備の数値(羽・破片・閉じる輪。意味は印ごとに違う)
    public var u0: Double = 0
    public var u1: Double = 0
    public var u2: Double = 0
    public var u3: Double = 0

    /// 羽の印。出てすぐ減速して止まり、そのあと揺れながら落ちる。fuse が揺れの位相、maxSpeed が落ちる速さの上限(px/秒)、u0 が落ち始めたか(0/1)
    public static let featherScript = 11
    /// 破片の印(砕けし光輪)。(u0, u1) を中心に、半径 maxSpeed の輪へ広がって回り、homeLeft 秒で自機へ突進する。
    /// u2 が最初の角度、turn が回る速さ(ラジアン/秒)、u3 が突進の速さ(px/秒)
    public static let shardScript = 12
    /// 閉じてくる輪の印(失楽園)。(u0, u1) を中心に、半径 radiusStart から u3 px/秒で縮む。u2 が最初の角度、turn が回る速さ、fuse 秒で消える
    public static let ringScript = 13
    /// 閉じてくる輪の最初の半径
    public static let ringStartRadius = 240.0
    /// 羽が減速する間(秒)と、1ステップごとの速さの倍率(1/60 秒あたり 0.93 を、1/120 秒の刻みに直したもの)
    static let featherDecelSeconds = 32.0 / 60
    static let featherDecay = (0.93 as Double).squareRoot()

    /// 御札の印(直角結界)。u0 秒で u1 ラジアン(符号つき)だけ向きを折り、速さを u3 倍にする。u2 > 0 なら u2 秒でもう一度、逆に折る。homeLeft が折った回数
    public static let foldScript = 14
    /// 揺れる弾の印(天気雨・千本鳥居の覚醒)。横の速さが sin(u0 + 経過フレーム × u1) × u2 (px/秒)。縦は変えない
    public static let swayScript = 15

    public var isRing: Bool { script == Bullet.ringScript }

    /// 画面の左右を反転する(発射の線対称)。向きの符号を持つ動き(カーブ・蛇行・光線のなぎ払い・回る破片/輪)は、回る向きも反対にする
    mutating func mirrorX() {
        let w = DanmakuConfig.width
        x = w - x; vx = -vx
        switch script {
        case Bullet.beamScript, Bullet.boomerangScript, Bullet.weaveScript, Bullet.zigzagScript: turn = -turn
        case Bullet.shardScript, Bullet.ringScript: u0 = w - u0; u2 = Double.pi - u2; turn = -turn
        case Bullet.foldScript: u1 = -u1
        case Bullet.swayScript: if u3 != 1 { u2 = -u2 }
        case Bullet.holdScript: if u2 == 1 { u1 = -u1 } else { u1 = Double.pi - u1 }
        case Bullet.windScript, Bullet.curveScript: u0 = -u0
        case Bullet.orbitScript: u0 = w - u0; u2 = Double.pi - u2; u3 = -u3
        case Bullet.lateralScript: u0 = Double.pi - u0; u2 = -u2
        default: break
        }
        if follow != nil { follow!.ox = w - follow!.ox }
    }
    /// 「くの字」で描くか。標準はどのパターンも丸。発射台で、くの字を選べる
    public var drawsAsBoomerang: Bool { look == 1 }

    /// チャージビームの印(script)。ビームは動かず、x, y が出る場所、vx, vy が向き(長さ1)、
    /// bounces が「まだ当たれるか」(1本のビームで当たるのは1回だけ)、age が出てからの経過秒。
    /// なぎ払いレーザーは、turn が撃っている間に首を振る速さ(ラジアン/秒)、homeLeft が撃つ時間(秒。0 なら標準)
    public static let beamScript = 4
    /// ブーメランの印。homeLeft 秒の間、turn(ラジアン/秒)で向きを回す(追尾ではなく、決まった弧を描く)
    public static let boomerangScript = 5
    /// 巨大弾の印。動きはふつうの弾と同じで、当たる範囲だけが広い
    public static let giantScript = 6
    /// 地雷の印。homeLeft 秒進んで止まり、出てから fuse 秒で爆発する(爆風と弾の輪になって消える)
    public static let mineScript = 7
    /// 爆風の印(隕石・地雷の爆発)。動かない。fuse 秒は予告だけで、そのあと blastActive 秒だけ、半径 radius の円が当たる。
    /// bounces が「まだ当たれるか」(1つの爆風で当たるのは1回だけ)
    public static let blastScript = 8
    /// 蛇行の印。turn(ラジアン/秒)で向きを回し続け、fuse 秒ごとに回す向きを左右に切り替える(homeLeft は次の切り替えまでの秒)
    public static let weaveScript = 9
    /// ジグザグの印。fuse 秒ごとに、向きを turn(ラジアン)だけカクッと折り、次は逆に折る(homeLeft は次に折るまでの秒)
    public static let zigzagScript = 10

    public static func blast(x: Double, y: Double, radius: Double, warn: Double, color: Int) -> Bullet {
        var b = Bullet(x: x, y: y, vx: 0, vy: 0, color: color, bounces: 1, script: blastScript)
        b.radius = radius
        b.fuse = warn
        return b
    }

    public var isBlast: Bool { script == Bullet.blastScript }
    public var isMine: Bool { script == Bullet.mineScript }
    /// 爆風が当たる(予告が終わった)ところか
    public var blastActive: Bool { isBlast && age >= fuse }
    /// 地雷が止まっているか(点滅の表示に使う)
    public var mineStopped: Bool { isMine && age >= homeLeft }

    /// 爆風が (px, py) に当たるか(1つで1回だけ)
    public func blastHits(_ px: Double, _ py: Double) -> Bool {
        guard blastActive, bounces > 0 else { return false }
        let dx = px - x, dy = py - y
        let r = radius + DanmakuConfig.hitRadius
        return dx * dx + dy * dy < r * r
    }

    /// 自機に当たる距離の2乗(弾の種類と広さで変わる)
    public var hitDistanceSquared: Double {
        if isGiant { return DanmakuConfig.giantHitRadiusSquared }
        if radius > 0 { let r = radius + DanmakuConfig.hitRadius; return r * r }
        if let r = BulletLook.hitDistance(look) { return r * r }
        return DanmakuConfig.hitRadiusSquared
    }

    /// かする距離の 2 乗。ふつうの弾は 18px。巨大弾や膨らむ泡は当たり判定が大きいので、その分だけ広げる(でないと、かする前に当たってしまう)
    public var grazeDistanceSquared: Double {
        if !isGiant && radius == 0 && look < BulletLook.firstSpecial { return DanmakuConfig.grazeRadiusSquared }
        let r = hitDistanceSquared.squareRoot() + DanmakuConfig.grazeMargin
        return r * r
    }

    /// length は光線の長さ(0 なら画面の外まで)。長さのあるビームは、maxSpeed に長さを入れる
    public static func beam(x: Double, y: Double, angle a: Double, color: Int, sweep: Double = 0, fireTime: Double = 0, length: Double = 0) -> Bullet {
        Bullet(x: x, y: y, vx: cos(a), vy: sin(a), color: color, turn: sweep, homeLeft: fireTime, maxSpeed: length, bounces: 1, script: beamScript)
    }
    /// 画面に描く光線の長さ
    public var beamLength: Double { maxSpeed > 0 ? maxSpeed : 900 }

    public var isGiant: Bool { script == Bullet.giantScript }
    /// ビームを撃っている時間(秒)
    public var beamFireTime: Double { homeLeft > 0 ? homeLeft : DanmakuConfig.beamFire }

    public var isBeam: Bool { script == Bullet.beamScript }
    /// ビームが撃たれている(当たる)ところか。ためている間は当たらない
    public var beamFiring: Bool { isBeam && age >= DanmakuConfig.beamCharge }
    /// ためている間の進み具合(0〜1)
    public var beamChargeProgress: Double { isBeam ? min(1, age / DanmakuConfig.beamCharge) : 0 }

    /// ビームが (px, py) に当たるか。光線は出る場所から向きのほうへ、画面の外まで伸びる
    public func beamHits(_ px: Double, _ py: Double) -> Bool {
        guard beamFiring, bounces > 0 else { return false }
        let rx = px - x, ry = py - y
        let along = rx * vx + ry * vy
        let d2: Double
        if along < 0 { d2 = rx * rx + ry * ry }
        else if maxSpeed > 0 && along > maxSpeed {
            // 長さのある光線は、先の端より向こうには届かない
            let ex = px - (x + vx * maxSpeed), ey = py - (y + vy * maxSpeed)
            d2 = ex * ex + ey * ey
        } else { d2 = rx * rx + ry * ry - along * along }
        return d2 < (radius > 0 ? radius * radius : DanmakuConfig.beamHitRadiusSquared)
    }

    /// 分裂弾がはじけたときに散る小さな弾(進んでいた向きから、均等な角度で)。
    /// 地雷のときは、爆風と、まわりに散る弾の輪
    public func fragments() -> [Bullet] {
        if script == Bullet.branchScript { return branchChildren() }
        if isMine {
            let speed = (vx * vx + vy * vy).squareRoot()
            let base = atan2(vy, vx)
            var out = [Bullet.blast(x: x, y: y, radius: DanmakuConfig.mineBlastRadius, warn: 0, color: color)]
            for j in 0..<DanmakuConfig.mineRing {
                let a = base + Double(j) * 2 * Double.pi / Double(DanmakuConfig.mineRing)
                out.append(Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: color))
            }
            return out
        }
        let speed = (vx * vx + vy * vy).squareRoot() * DanmakuConfig.splitSpeed
        let base = atan2(vy, vx)
        return (0..<DanmakuConfig.splitCount).map { j in
            let a = base + Double(j) * 2 * Double.pi / Double(DanmakuConfig.splitCount)
            return Bullet(x: x, y: y, vx: cos(a) * speed, vy: sin(a) * speed, color: color)
        }
    }
}

/// 弾の1ステップの結果。burst は、分裂弾がはじけて消えたこと(散った小さな弾は fragments() で作る)、
/// gone は、撃ち終わったチャージビームが消えたこと
public enum BulletMotion: Sendable { case alive, burst, gone }

extension Bullet {
    /// 1ステップ分の弾の動き(時間で変わる動き・追尾・加速・移動・壁での反射)。ゲーム本体、ショップの見本、
    /// エディタのプレビューが、同じ計算を使う。画面の外に出たか、自機に当たったかは、呼ぶ側で調べる
    public mutating func advance(dt: Double, width W: Double, playerX: Double, playerY: Double) -> BulletMotion {
        if let f = follow {
            // 描いた軌道の上を、時間に沿って進む(速さや向きの変化は、軌道そのもので決まる)
            age += dt
            let p = PathData.position(f.ref.points, at: age * f.scale)
            x = f.ox + f.cosR * p.x - f.sinR * p.y
            y = f.oy + f.sinR * p.x + f.cosR * p.y
            return .alive
        }
        if isBeam {
            // チャージビームは動かない。ためて、撃って、消える。なぎ払いは、撃っている間だけ首を振る
            age += dt
            if age >= DanmakuConfig.beamCharge + beamFireTime { return .gone }
            if u0 > 0 && age < u0 {
                // 照準: ためている間、自機のほうへなめらかに向きを合わせる(u0 秒で固定)
                let want = atan2(playerY - y, playerX - x)
                let cur = atan2(vy, vx)
                var diff = want - cur
                while diff > Double.pi { diff -= 2 * Double.pi }
                while diff < -Double.pi { diff += 2 * Double.pi }
                let na = cur + diff * Bullet.lockLerp
                vx = cos(na); vy = sin(na)
            }
            if turn != 0 && age >= DanmakuConfig.beamCharge {
                let na = atan2(vy, vx) + turn * dt
                vx = cos(na); vy = sin(na)
            }
            return .alive
        }
        if isBlast {
            // 爆風: 動かない。予告(fuse 秒)のあと、少しの間だけ当たって消える
            age += dt
            return age >= fuse + DanmakuConfig.blastActive ? .gone : .alive
        }
        if isMine {
            // 地雷: 決まった時間だけ進んで止まり、時間が来たら爆発する
            age += dt
            if age >= fuse { return .burst }
            if age < homeLeft { x += vx * dt; y += vy * dt }
            return .alive
        }
        if script == Bullet.featherScript {
            // 羽: 減速して止まり、そのあと左右に揺れながら、だんだん速く落ちる
            age += dt
            if age < Bullet.featherDecelSeconds {
                vx *= Bullet.featherDecay; vy *= Bullet.featherDecay
            } else {
                if u0 == 0 { u0 = 1; vx = 0; vy = 12 }
                vy = min(vy + 180 * dt, maxSpeed)
                vx = sin((age * 60 + fuse) * 0.07) * 54
            }
            x += vx * dt; y += vy * dt
            return .alive
        }
        if script == Bullet.shardScript {
            // 破片: 光輪から輪の形に広がり、回って、時間が来た順に自機へ突進する
            age += dt
            if age >= homeLeft {
                let a = atan2(playerY - y, playerX - x)
                vx = cos(a) * u3; vy = sin(a) * u3
                script = 0; turn = 0; homeLeft = 0; maxSpeed = 0
                return .alive
            }
            let q = 1 - min(1, age / 0.4)
            let e = 1 - q * q * q
            let ang = u2 + turn * max(0, age - 0.4)
            x = u0 + cos(ang) * maxSpeed * e
            y = u1 + sin(ang) * maxSpeed * e * 0.8
            return .alive
        }
        if let m = advanceBossScript(dt: dt, playerX: playerX, playerY: playerY) { return m }
        if script == Bullet.foldScript {
            // 御札: 決まった時間で直角に折れる(覚醒すると、もう一度逆に折れてジグザグになる)
            age += dt
            if homeLeft == 0 && age >= u0 {
                let sp = (vx * vx + vy * vy).squareRoot() * u3
                let na = atan2(vy, vx) + u1
                vx = cos(na) * sp; vy = sin(na) * sp
                homeLeft = 1
            } else if homeLeft == 1 && u2 > 0 && age >= u2 {
                let sp = (vx * vx + vy * vy).squareRoot()
                let na = atan2(vy, vx) - u1
                vx = cos(na) * sp; vy = sin(na) * sp
                homeLeft = 2
            }
            x += vx * dt; y += vy * dt
            return .alive
        }
        if script == Bullet.swayScript {
            // 揺れる弾: 横に揺れながら、まっすぐ落ちる
            age += dt
            // u3: 0 = 横が sin で揺れる / 1 = 縦が cos で揺れる(横は一定) / 2 = 横が cos で揺れる(波打つ列)
            switch u3 {
            case 1: vy = cos(u0 + age * 60 * u1) * u2
            case 2: vx = cos(u0 + age * 60 * u1) * u2
            default: vx = sin(u0 + age * 60 * u1) * u2
            }
            x += vx * dt; y += vy * dt
            return .alive
        }
        if script == Bullet.ringScript {
            // 閉じてくる輪: 中心へ向かって縮む(回る輪もある)。中心に着いたら消える
            age += dt
            if age >= fuse { return .gone }
            let rad = Bullet.ringStartRadius - u3 * age
            let ang = u2 + turn * age
            x = u0 + cos(ang) * rad
            y = u1 + sin(ang) * rad
            return .alive
        }
        if script == Bullet.weaveScript || script == Bullet.zigzagScript {
            let speed = (vx * vx + vy * vy).squareRoot()
            if script == Bullet.weaveScript {
                // 蛇行: なめらかに曲がり続け、決まった時間ごとに曲がる向きを逆にする
                if homeLeft <= 0 { turn = -turn; homeLeft += fuse }
                let na = atan2(vy, vx) + turn * dt
                vx = cos(na) * speed; vy = sin(na) * speed
                homeLeft -= dt
            } else {
                // ジグザグ: 決まった時間ごとに、カクッと向きを折る(次は逆に)
                homeLeft -= dt
                if homeLeft <= 0 {
                    let na = atan2(vy, vx) + turn
                    vx = cos(na) * speed; vy = sin(na) * speed
                    turn = -turn
                    homeLeft += fuse
                }
            }
            x += vx * dt; y += vy * dt
            if bounces > 0 {
                if x < 0 { x = -x; vx = -vx; bounces -= 1 }
                else if x > W { x = 2 * W - x; vx = -vx; bounces -= 1 }
            }
            return .alive
        }
        if script == Bullet.boomerangScript {
            // ブーメラン: 決まった時間だけ、同じ速さのまま向きを回して、弧を描いて戻ってくる
            if homeLeft > 0 {
                let na = atan2(vy, vx) + turn * dt
                let speed = (vx * vx + vy * vy).squareRoot()
                vx = cos(na) * speed
                vy = sin(na) * speed
                homeLeft -= dt
            }
            x += vx * dt; y += vy * dt
            if bounces > 0 {
                if x < 0 { x = -x; vx = -vx; bounces -= 1 }
                else if x > W { x = 2 * W - x; vx = -vx; bounces -= 1 }
            }
            return .alive
        }
        var frozen = false
        if script != 0 {
            age += dt
            switch script {
            case 1:
                if age >= DanmakuConfig.stopGoMove + DanmakuConfig.stopGoHold {
                    // 止まっていた弾が、自機に向かって、少し速く飛び出す
                    let speed = (vx * vx + vy * vy).squareRoot() * DanmakuConfig.stopGoBoost
                    let a = atan2(playerY - y, playerX - x)
                    vx = cos(a) * speed; vy = sin(a) * speed
                    script = 0
                } else if age >= DanmakuConfig.stopGoMove { frozen = true }
            case 2:
                if age >= DanmakuConfig.splitAfter { return .burst }
            case 3:
                if age >= DanmakuConfig.timedHold { script = 0 } else { frozen = true }
            default:
                break   // 巨大弾など、時間で動きが変わらない印
            }
        }
        if homeLeft > 0 {
            // 追尾: 速さはそのまま、向きだけを、1ステップあたり turn*dt まで自機のほうへ回す
            let want = atan2(playerY - y, playerX - x)
            let cur = atan2(vy, vx)
            var diff = want - cur
            while diff > Double.pi { diff -= 2 * Double.pi }
            while diff < -Double.pi { diff += 2 * Double.pi }
            let maxTurn = turn * dt
            let na = cur + min(maxTurn, max(-maxTurn, diff))
            let speed = (vx * vx + vy * vy).squareRoot()
            vx = cos(na) * speed
            vy = sin(na) * speed
            homeLeft -= dt
        }
        if accel != 0 {
            let speed = (vx * vx + vy * vy).squareRoot()
            if speed < maxSpeed {
                // 上限を超えないように、増やす割合を頭打ちにする
                let g = min(1 + accel * dt, maxSpeed / speed)
                vx *= g; vy *= g
            }
        }
        if gravity != 0 { vy += gravity * dt }
        if grow != 0 { radius = min(growMax, radius + grow * dt) }
        if !frozen { x += vx * dt; y += vy * dt }
        if bounces > 0 {
            if x < 0 { x = -x; vx = -vx; bounces -= 1 }
            else if x > W { x = 2 * W - x; vx = -vx; bounces -= 1 }
        }
        return .alive
    }
}

/// 1ステップ分の自機移動量。単位は 0.25 論理px（リプレイに入れるため整数にしてある）
public struct Move: Equatable, Sendable {
    public static let unit = 0.25
    public var dx: Int8
    public var dy: Int8
    public init(dx: Int8 = 0, dy: Int8 = 0) { self.dx = dx; self.dy = dy }
    public static let zero = Move()
}

public enum Outcome: Equatable, Sendable {
    case playing, cleared, hit, timeUp
}

public enum Emit {
    /// 試作の `emit` と同じ。弾数は 1600 で頭打ち（乱数は上限でも消費する）
    /// awakened は、ボスが覚醒した状態か(堕天使の技が強くなる)。salt は、ステージごとに決まる数(失楽園の抜け道を決める)
    /// 弾を出す。mir == 1 のときは、画面の左右を反転した世界で撃って、出た弾を左右反転して戻す
    /// (自機を狙う弾は、本物の自機に向かう。回る向き・カーブの向きは反対になる)
    public static func emit(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                     rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool = false, salt: UInt32 = 0) {
        guard m.mir == 1 else {
            emitCore(m, shot: k, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
            return
        }
        let w = DanmakuConfig.width
        let before = out.count
        emitCore(m, shot: k, cx: w - cx, cy: cy, px: w - px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        for j in before..<out.count { out[j].mirrorX() }
    }

    static func emitCore(_ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,
                     rng: inout Mulberry32, into out: inout [Bullet], awakened: Bool = false, salt: UInt32 = 0) {
        let sp = m.v * 60
        let n = max(1, m.c)
        let deg = Double.pi / 180
        let off = Double(m.a) * deg   // パターン全体を回す角度
        func add(_ x: Double, _ y: Double, _ a: Double) {
            if out.count < DanmakuConfig.maxBullets {
                out.append(Bullet(x: x, y: y, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k))
            }
        }
        switch m.t {
        case .ring, .spiral:
            for j in 0..<n { add(cx, cy, Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off) }
        case .aim:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                add(cx, cy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0))
            }
        case .rain:
            for _ in 0..<n {
                let x = rng.next() * DanmakuConfig.width
                let a = Double.pi / 2 + (rng.next() - 0.5) * 0.3
                add(x, -8, a)
            }
        case .homing:
            // 最初は自機の方向へ。複数のときは少しずつ角度をずらして出す。曲がる速さは r で決める(大きいほど急に曲がる)
            let b = atan2(py - cy, px - cx) + off
            let turn = max(25.0, abs(m.r) * 2.0) * deg
            for j in 0..<n {
                let a = b + (Double(j) - Double(n - 1) / 2) * 0.35
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, turn: turn, homeLeft: DanmakuConfig.homingSeconds))
                }
            }
        case .flower, .star, .heart:
            // 輪の形の弾幕: 角度ごとに速さを変えて、花・星・ハートの輪郭をつくる(r は、1回ごとの回転)
            let rot = Double(k) * m.r * deg
            for j in 0..<n {
                let th = Double(j) * 2 * Double.pi / Double(n) + rot + off
                let rel = th - rot - off     // 形は、回転とは別に決める(回転させると、形ごと回る)
                let f: Double
                switch m.t {
                case .flower: f = 0.4 + 0.6 * abs(cos(2.5 * rel))
                case .star:
                    let u = (rel * 5 / (2 * Double.pi)).truncatingRemainder(dividingBy: 1)
                    let ph = u < 0 ? u + 1 : u
                    f = 0.45 + 0.55 * abs(ph - 0.5) * 2
                default:
                    let q = -rel
                    let sq = abs(cos(q)).squareRoot()
                    let rr = (2 - 2 * sin(q) + sin(q) * sq / (sin(q) + 1.4)) / 4
                    f = 0.15 + 0.85 * max(0, min(1, rr))
                }
                let a = th
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k))
                }
            }
        case .beam:
            // 自機に向けて、速さをずらした弾を一直線に出す(c 個)。r は、狙いのずれ(度)
            let b = atan2(py - cy, px - cx) + off + m.r * deg * 0.2
            for j in 0..<n {
                let f = 1 + Double(j) * 0.18
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(b) * sp * f, vy: sin(b) * sp * f, color: m.k))
                }
            }
        case .cross:
            // 上下左右の4方向。1方向あたり c/4 個(最低1個)が、速さをずらして列になる。r は、1回ごとの回転
            let per = max(1, n / 4)
            let rot = Double(k) * m.r * deg
            for arm in 0..<4 {
                let a = Double(arm) * Double.pi / 2 + rot + off
                for j in 0..<per {
                    let f = 1 + Double(j) * 0.25
                    if out.count < DanmakuConfig.maxBullets {
                        out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k))
                    }
                }
            }
        case .accel:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp * 0.3, vy: sin(a) * sp * 0.3, color: m.k, accel: 0.9, maxSpeed: sp * 2))
                }
            }
        case .bounce:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, bounces: 2))
                }
            }
        case .stopgo, .split:
            let b = atan2(py - cy, px - cx) + off
            for j in 0..<n {
                let a = b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0)
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, script: m.t == .stopgo ? 1 : 2))
                }
            }
        case .timed:
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: cos(a) * sp, vy: sin(a) * sp, color: m.k, script: 3))
                }
            }
        case .sideL, .sideR:
            // 左右の端から横切る。高さはばらばら(自機の初期位置より少し上まで)。r はばらつきの角度(±)
            let toRight = m.t == .sideL
            let x0 = toRight ? -8.0 : DanmakuConfig.width + 8
            let spread = abs(m.r) * deg
            for _ in 0..<n {
                let y = rng.next() * DanmakuConfig.height * 0.78
                let a = (toRight ? 0.0 : Double.pi) + (rng.next() - 0.5) * 2 * spread
                add(x0, y, a)
            }
        case .corner:
            // 四隅(下の2つは、自機に近すぎないよう画面の6割の高さ)から自機に向けて、r 度の扇状に撃つ
            let w = DanmakuConfig.width, h = DanmakuConfig.height
            let corners: [(Double, Double)] = [(-8, -8), (w + 8, -8), (-8, h * 0.6), (w + 8, h * 0.6)]
            for (ox, oy) in corners {
                let b = atan2(py - oy, px - ox)
                for j in 0..<n {
                    add(ox, oy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * m.r * deg : 0))
                }
            }
        case .sweep:
            let b = Double.pi / 2 + sin(Double(k) * 0.25) * m.r * deg
            for j in 0..<n {
                add(cx, cy, b + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * 0.5 : 0))
            }
        case .custom:
            // 弾幕作成モードで描いた軌道を、n 個、均等に回して出す。r は 1回ごとの回転、v は進む速さの倍率(2 で描いたとおり)
            guard let pts = PathData.sanitized(m.path) else { break }
            let ref = PathRef(pts)
            for j in 0..<n {
                let a = Double(j) * 2 * Double.pi / Double(n) + Double(k) * m.r * deg + off
                if out.count < DanmakuConfig.maxBullets {
                    out.append(Bullet(x: cx, y: cy, vx: 0, vy: 0, color: m.k,
                                      follow: PathFollow(ref: ref, ox: cx, oy: cy, cosR: cos(a), sinR: sin(a), scale: m.v / 2)))
                }
            }
        case .reaperScythe, .reaperSouls, .reaperChains, .reaperDeadline, .reaperRiver:
            emitReaper(m, shot: k, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        case .iceCage, .iceIcicles, .iceBlizzard, .iceFreeze, .iceMirror:
            emitIceQueen(m, shot: k, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        case .kitsuneLanterns, .kitsuneBarrier, .kitsuneSunshower, .kitsuneTorii, .kitsuneDance:
            emitKitsune(m, shot: k, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        case .angelTwin, .angelFeather, .angelHalo, .angelCross, .angelParadise:
            emitFallenAngel(m, shot: k, cx: cx, cy: cy, px: px, py: py, rng: &rng, into: &out, awakened: awakened, salt: salt)
        default:
            // 広告で解放するパターン: 弾の出し方の表に従う
            if let r = m.t.recipe { emitRecipe(r, m, shot: k, cx: cx, cy: cy, px: px, py: py, off: off, sp: sp, n: n, rng: &rng, into: &out) }
        }
    }
}

/// ステージのシミュレーション。計算だけを行い、描画には一切依存しない
public struct Simulation {
    public let stage: Stage
    public private(set) var tick = 0
    /// ゲーム内時間。READY 中は負。試作と同じく 1/120 を足していく
    public private(set) var t = -DanmakuConfig.readySeconds
    public private(set) var player = Point(x: DanmakuConfig.width / 2, y: DanmakuConfig.height * 0.85)
    public private(set) var bullets: [Bullet] = []
    public private(set) var shots: [PlayerShot] = []
    public let shotType: ShotType
    public private(set) var hp: Int
    /// ボスに与えたダメージの合計(ボス戦でも数える)
    public private(set) var damageDealt = 0
    public private(set) var phase = 1
    /// 「第N段階」表示の残り秒数
    public private(set) var banner = 0.0
    public private(set) var flash = 0.0
    public private(set) var outcome = Outcome.playing
    /// 被弾を無視する。UI テスト専用（アプリ側は DEBUG ビルドでしか立てない）
    public var invincible = false
    /// 復活直後の無敵が切れるステップ
    public private(set) var shieldUntilTick = 0
    /// 自機の耐久(ライフ制のときはライフの数、HP 制のときは HP)
    public let lifeMode: LifeMode
    public let lifeMax: Int
    public private(set) var lifeLeft: Int
    /// 被弾の直後に残りを数える表示用(秒)。画面のひらめきに使う
    public private(set) var hitFlash = 0.0
    /// ボスを倒した回数と、直近の撃破の場所・演出(画面の演出に使う。計算には関わらない)
    public private(set) var defeats = 0
    public private(set) var lastDefeatPosition = Point(x: 0, y: 0)
    public private(set) var lastDefeatEffect = DefeatEffect.standard
    /// スワイプ弾幕: かすった弾の数(合計)と、直前の 1 ステップでかすった弾。ビーム・爆風はかすりの対象にしない
    public private(set) var grazeCount = 0
    public private(set) var grazedThisStep: [Bullet] = []
    /// かすりを数えるか。早送りの間は止める(止まっている自機のそばを通った分は、数えない)
    public var countsGrazes = true

    /// 自機がショットを撃つか(スワイプ弾幕では撃たない)
    private let firesShots: Bool
    private var cooldown = 0.0
    /// 失楽園の抜け道など、ステージごとに決まる数(ステージのシード)
    private let salt: UInt32
    private var rng: Mulberry32
    private var next: [Double]
    private var shotCount: [Int]
    /// 場面の一覧と、いまの場面。連戦以外は、ステージ全体が「場面1つ」
    private let specs: [WaveSpec]
    public private(set) var waveIndex = 0
    /// いまの場面が始まった時刻(t)。最初の場面は 0(ステージの開始)。連戦の途中では、切り替えの時間のあとになる
    private var waveStart = 0.0

    /// ライフ制で1つ失ったあとの無敵の長さ(秒)
    static let lifeShieldSeconds = 2.0

    static let bossMoves: [(a: Double, w: Double)] = [(0, 0), (0.25, 0.6), (0.32, 1.3)]

    /// ボスの動きの種類の数。0=止まる 1=横にゆっくり 2=横にはやい 3=上下 4=円 5=8の字 6=ワープ(決まった場所へすっと移る)
    public static let bossMoveCount = 11

    /// ワープの移動先(画面の幅・高さに対する割合)。4 秒ごとに次の場所へ、最後の 0.6 秒でなめらかに移る
    static let warpPoints: [(x: Double, y: Double)] = [(0.5, 0.18), (0.22, 0.26), (0.78, 0.16), (0.35, 0.12), (0.68, 0.30), (0.5, 0.22)]
    static let warpPeriod = 4.0
    static let warpHold = 3.4

    /// 動きの種類 move のボスの、場面が始まって t 秒後の位置。ゲームの計算も、エディタの見本も、サーバーの検証も、この式を使う
    public static func bossPoint(move: Int, t rawT: Double) -> Point {
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        let t = max(0, rawT)
        switch min(max(move, 0), bossMoveCount - 1) {
        case 3: return Point(x: W * 0.5, y: H * (0.2 + 0.09 * sin(t * 0.9)))
        case 4: return Point(x: W * 0.5 + 85 * cos(t * 0.7), y: H * 0.2 + 45 * sin(t * 0.7))
        case 5: return Point(x: W * 0.5 + 115 * sin(t * 0.6), y: H * 0.2 + 40 * sin(t * 1.2))
        case 6:
            let k = (t / warpPeriod).rounded(.down)
            let idx = Int(k) % warpPoints.count
            let f = t - k * warpPeriod
            let a = warpPoints[idx], b = warpPoints[(idx + 1) % warpPoints.count]
            if f <= warpHold { return Point(x: W * a.x, y: H * a.y) }
            let u = (f - warpHold) / (warpPeriod - warpHold)
            let s = u * u * (3 - 2 * u)
            return Point(x: W * (a.x + (b.x - a.x) * s), y: H * (a.y + (b.y - a.y) * s))
        // 逆向き: 円・8の字・横ゆっくり・横はやい を、反対まわり・反対側から始める
        case 7: return Point(x: W * 0.5 + 85 * cos(t * 0.7), y: H * 0.2 - 45 * sin(t * 0.7))
        case 8: return Point(x: W * 0.5 - 115 * sin(t * 0.6), y: H * 0.2 + 40 * sin(t * 1.2))
        case let m where m == 9 || m == 10:
            let mv = bossMoves[m - 8]
            return Point(x: W * (0.5 - mv.a * sin(t * mv.w)), y: H * 0.18)
        case let m:
            let mv = bossMoves[m]
            return Point(x: W * (0.5 + mv.a * sin(t * mv.w)), y: H * 0.18)
        }
    }

    /// shotType を省くと、ステージで決まっている撃ち方を使う(ふつうは、これ)
    public init(stage: Stage, shotType: ShotType? = nil) {
        self.init(stage: stage, seed: stage.seed, shotType: shotType ?? stage.shotType)
    }

    /// スワイプ弾幕用の作り方(仕様書 3.4 章)。ライフ 1、自機はショットを撃たない、ボスの場面は「ダメージ勝負」と同じ扱い
    /// (HP は無限でボスは倒れない。「第N段階」は時間の 3 分の 1 ずつで進む)。乱数の種は元のステージと同じ
    public init(swipeStage stage: Stage) {
        self.init(stage: stage, seed: stage.seed, shotType: .standard, swipe: true)
    }

    init(stage: Stage, seed: UInt32, shotType: ShotType = .standard, swipe: Bool = false) {
        self.stage = stage
        self.shotType = shotType
        firesShots = !swipe
        lifeMode = swipe ? .lives : stage.effectiveLifeMode
        lifeMax = swipe ? 1 : stage.effectiveLifeCount
        lifeLeft = swipe ? 1 : stage.effectiveLifeCount
        var specs = stage.waveSpecs
        if swipe { for i in specs.indices where specs[i].boss { specs[i].damage = true } }
        self.specs = specs
        hp = specs[0].hp
        rng = Mulberry32(seed: seed)
        salt = seed
        next = specs[0].emitters.map(\.s)
        shotCount = Array(repeating: 0, count: specs[0].emitters.count)
    }

    private var spec: WaveSpec { specs[waveIndex] }
    /// 画面に出す、ボスの大きさ(0=小 1=中 2=大)と見た目、雑魚の大きさ(nil は出さない)と見た目。いまの場面のもの
    public var bossSizeIndex: Int { spec.size }
    public var bossLookIndex: Int { spec.look }
    /// 専用の絵を持つボスか(図形のボスなら nil)
    public var bossCharacter: BossCharacter? { spec.character }
    /// 覚醒する段階(nil は覚醒しない)
    public var awakenPhase: Int? { spec.awaken }
    /// いま、覚醒した状態か(ボスの場面で、覚醒する段階に入ったあと)
    public var isAwakened: Bool { isBoss && (spec.awaken.map { phase >= $0 } ?? false) }
    public var mookSizeIndex: Int? { spec.mooks }
    public var mookLookIndex: Int { spec.mookLook }
    /// 場面の数
    public var waveCount: Int { specs.count }
    /// いまの場面の中の経過時間(秒)。切り替えの間と、READY の間は負
    public var waveT: Double { t - waveStart }
    /// 場面の切り替えの間か(2場面目以降の、開始前)
    public var isIntermission: Bool { waveIndex > 0 && waveT < 0 }
    /// いまの場面の開始前に、警告の演出を出すか
    public var warningNow: Bool { spec.warning }
    /// いまの場面の制限時間(秒)
    public var waveLimit: Double { spec.limit }
    /// いまの場面の、ボスの最大 HP
    public var waveBossHp: Int { spec.hp }
    public var currentEmitters: [Emitter] { spec.emitters }

    /// 次の場面へ。画面の弾と自機の弾を消し、切り替えの間(自機は動ける)のあと、新しい場面が始まる
    private mutating func advanceWave() {
        waveIndex += 1
        waveStart = t + Wave.intermissionSeconds
        bullets.removeAll(keepingCapacity: true)
        shots.removeAll(keepingCapacity: true)
        next = spec.emitters.map(\.s)
        shotCount = Array(repeating: 0, count: spec.emitters.count)
        hp = spec.hp
        phase = 1
        banner = 0
        flash = 0
        cooldown = 0
        shieldUntilTick = max(shieldUntilTick, tick + Int((Wave.intermissionSeconds / DanmakuConfig.step).rounded()))
    }

    /// いまの場面に、ボスが出る(ボス戦・ダメージ勝負・連戦のボスの場面)
    public var isBoss: Bool { spec.boss }
    /// ダメージ勝負(ボスの HP は無限。与えたダメージの合計を数える)
    public var isDamageRace: Bool { spec.damage }

    /// 復活直後で、被弾しない状態か
    public var isShielded: Bool { tick < shieldUntilTick }

    /// 被弾した場所からそのまま復活する。画面の弾を全消去し、短い間だけ無敵にする
    public mutating func revive(shieldSeconds: Double = 2) {
        guard outcome == .hit else { return }
        outcome = .playing
        // 復活のとき、ライフは1、HP は半分(最低1)まで戻す
        lifeLeft = lifeMode == .lives ? 1 : max(1, lifeMax / 2)
        bullets.removeAll(keepingCapacity: true)
        shieldUntilTick = tick + Int((shieldSeconds / DanmakuConfig.step).rounded())
    }

    // MARK: スワイプ弾幕用(仕様書 3.2 章)。本編では使わない

    /// 自機を置く(画面の端から 6px の内側に収める)
    public mutating func place(at p: Point) {
        player = Point(x: Simulation.clamp(p.x, 6, DanmakuConfig.width - 6), y: Simulation.clamp(p.y, 6, DanmakuConfig.height - 6))
    }

    /// 弾も時間も止めたまま、自機だけ動かす(クリップの「GO」の間)
    public mutating func nudgePlayer(_ move: Move) {
        place(at: Point(x: player.x + Double(move.dx) * Move.unit, y: player.y + Double(move.dy) * Move.unit))
    }

    /// 次の `steps` ステップの間、被弾しない(バリア)。当たりそうな弾は、その場で消える
    public mutating func giveShield(steps: Int) {
        shieldUntilTick = max(shieldUntilTick, tick + steps + 1)
    }

    /// 画面の弾をすべて消す(ボム)
    public mutating func clearBullets() { bullets.removeAll(keepingCapacity: true) }

    /// 自機を動かさず、無敵で、かすりも数えずに `target` ステップ目まで進める。途中でステージが終わったら、そこで止まる
    public mutating func fastForward(toTick target: Int) {
        let (wasInvincible, wasCounting) = (invincible, countsGrazes)
        invincible = true; countsGrazes = false
        while outcome == .playing && tick < target { step(.zero) }
        invincible = wasInvincible; countsGrazes = wasCounting
    }

    public var bossPosition: Point {
        if let c = spec.character { return c.position(waveT: waveT) }
        let p = Simulation.bossPoint(move: spec.move, t: waveT)
        if spec.homeDX == 0 && spec.homeDY == 0 { return p }
        // ボスの位置の指定: 動きの中心をずらす。画面の外に出ないよう、端で止める
        return Point(x: min(max(p.x + spec.homeDX, 24), DanmakuConfig.width - 24), y: min(max(p.y + spec.homeDY, 24), DanmakuConfig.height * 0.5))
    }

    private func phaseOf() -> Int {
        if isDamageRace {
            // ダメージ勝負は、HP ではなく時間の3分の1ずつで段階が進む
            let f = max(0, waveT) / spec.limit
            return f < 1.0 / 3 ? 1 : f < 2.0 / 3 ? 2 : 3
        }
        let r = Double(hp) / Double(max(1, spec.hp))
        return r > 2.0 / 3 ? 1 : r > 1.0 / 3 ? 2 : 3
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }

    /// 1ステップ（1/120 秒）進める。終了後は何もしない
    public mutating func step(_ move: Move) {
        guard outcome == .playing else { return }
        grazedThisStep.removeAll(keepingCapacity: true)
        let dt = DanmakuConfig.step
        let W = DanmakuConfig.width, H = DanmakuConfig.height
        tick += 1
        t += dt
        if hitFlash > 0 { hitFlash = max(0, hitFlash - dt) }
        player.x = Simulation.clamp(player.x + Double(move.dx) * Move.unit, 6, W - 6)
        player.y = Simulation.clamp(player.y + Double(move.dy) * Move.unit, 6, H - 6)

        let bp = isBoss ? bossPosition : Point(x: 0, y: 0)
        if isBoss {
            let ph = phaseOf()
            if ph != phase {
                phase = ph
                if ph > 1 { bullets.removeAll(keepingCapacity: true); banner = 1.2 }
            }
            if banner > 0 { banner -= dt }
            cooldown -= dt
            if firesShots && waveT >= 0 && cooldown <= 0 {
                cooldown = shotType.interval
                for spec in shotType.volley {
                    shots.append(PlayerShot(x: player.x + spec.dx, y: player.y - 10, vx: spec.vx, damage: spec.damage))
                }
            }
            var w = 0
            for var s in shots {
                s.x += s.vx * dt
                s.y -= 600 * dt
                if s.y < -10 || s.x < -10 || s.x > W + 10 { continue }
                let dx = s.x - bp.x, dy = s.y - bp.y
                let br = spec.character?.hitRadius ?? DanmakuConfig.bossRadii[min(max(spec.size, 0), 2)]
                if dx * dx + dy * dy < br * br {
                    damageDealt += s.damage
                    if !isDamageRace { hp -= s.damage }
                    flash = 0.06; continue
                }
                shots[w] = s; w += 1
            }
            shots.removeSubrange(w...)
            if flash > 0 { flash -= dt }
            if !isDamageRace && hp <= 0 {
                defeats += 1
                lastDefeatPosition = bp
                lastDefeatEffect = spec.defeat
                if waveIndex + 1 < specs.count { advanceWave() } else { outcome = .cleared }
                return
            }
        }

        if waveT >= 0 {
            for (idx, m) in spec.emitters.enumerated() {
                if isBoss {
                    if !(m.ph == 0 || m.ph == phase) || banner > 0 { next[idx] = waveT; continue }
                    while waveT >= next[idx] {
                        // ボス戦でも、好きな場所から出せる(p == 1)。雨は、これまでどおり位置を使わない
                        let fx = m.firesFromPoint ? m.x * W : bp.x
                        let fy = m.firesFromPoint ? m.y * H : bp.y
                        let before = bullets.count
                        Emit.emit(m, shot: shotCount[idx], cx: m.t == .rain ? 0 : fx, cy: fy,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets, awakened: isAwakened, salt: salt)
                        if let sh = m.sh { for j in before..<bullets.count { bullets[j].look = UInt8(sh) } }
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                } else {
                    let end = min(m.e, spec.limit)
                    while waveT >= next[idx] && next[idx] < end {
                        let before = bullets.count
                        Emit.emit(m, shot: shotCount[idx], cx: m.x * W, cy: m.y * H,
                                  px: player.x, py: player.y, rng: &rng, into: &bullets)
                        if let sh = m.sh { for j in before..<bullets.count { bullets[j].look = UInt8(sh) } }
                        shotCount[idx] += 1
                        next[idx] += max(0.05, m.i)
                    }
                }
            }
        }

        var w = 0
        var born: [Bullet] = []
        for i in 0..<bullets.count {
            var b = bullets[i]
            let motion = b.advance(dt: dt, width: W, playerX: player.x, playerY: player.y)
            if motion == .burst {
                let room = max(0, DanmakuConfig.maxBullets - (w + born.count + (bullets.count - i - 1)))
                born.append(contentsOf: b.fragments().prefix(room))
                continue
            }
            if motion == .gone { continue }
            if b.isDormant {
                // 待機中の弾・暗転の印: 見えず、当たらない
                bullets[w] = b; w += 1
                continue
            }
            if b.isBeam || b.isBlast {
                // チャージビーム・爆風: 当たる間だけ、触れると当たる。当たっても消えない(同じものでは1回だけ)
                let touched = b.isBeam ? b.beamHits(player.x, player.y) : b.blastHits(player.x, player.y)
                if touched && !(invincible || tick < shieldUntilTick) {
                    b.bounces = 0
                    lifeLeft -= 1
                    if lifeLeft <= 0 { outcome = .hit; return }
                    if lifeMode == .lives {
                        shieldUntilTick = tick + Int((Simulation.lifeShieldSeconds / dt).rounded())
                        hitFlash = 0.5
                    } else {
                        hitFlash = 0.15
                    }
                }
                bullets[w] = b; w += 1
                continue
            }
            if !b.isRing && (b.x < -20 || b.x > W + 20 || b.y < -20 || b.y > H + 20) { continue }
            let dx = b.x - player.x, dy = b.y - player.y
            let d2 = dx * dx + dy * dy
            if d2 < b.hitDistanceSquared {
                if invincible || tick < shieldUntilTick { continue }
                lifeLeft -= 1
                if lifeLeft <= 0 { outcome = .hit; return }   // ライフ1・HP が尽きたとき: 以前と同じく、その場で終了
                if lifeMode == .lives {
                    shieldUntilTick = tick + Int((Simulation.lifeShieldSeconds / dt).rounded())
                    hitFlash = 0.5
                } else {
                    hitFlash = 0.15
                }
                continue   // 当たった弾は消える
            }
            if countsGrazes && !b.grazed && d2 < b.grazeDistanceSquared {
                b.grazed = true
                grazeCount += 1
                grazedThisStep.append(b)
            }
            bullets[w] = b; w += 1
        }
        bullets.removeSubrange(w...)
        bullets.append(contentsOf: born)
        if waveT >= spec.limit {
            if waveIndex + 1 < specs.count {
                // 連戦の途中: ボスの場面は、時間切れで失敗。生き残る場面は、クリアして次へ
                if spec.boss && !spec.damage { outcome = .timeUp } else { advanceWave() }
            } else {
                outcome = (isBoss && !isDamageRace) ? .timeUp : .cleared
            }
        }
    }
}

extension Simulation {
    public struct Result: Equatable, Sendable {
        public var outcome: Outcome
        /// 終了時のステップ数
        public var steps: Int
        public var bulletCount: Int
        public var hp: Int
        /// 終了時の弾の位置から作ったハッシュ（完全一致の確認用）
        public var bulletHash: UInt32
        /// 弾の位置を、小数第3位に丸めて作ったハッシュ(sin/cos の最後の桁の違いに左右されない。サーバーとの一致の確認用)
        public var bulletHashCoarse: UInt32
    }

    /// 入力列を再生して結果を返す。入力が尽きたら動かさずに続ける
    public static func run(stage: Stage, moves: [Move]) -> Result {
        var sim = Simulation(stage: stage)
        let limit = (stage.timeLimitSec + 3) * 120 + 144
        while sim.outcome == .playing && sim.tick < limit {
            sim.step(sim.tick < moves.count ? moves[sim.tick] : .zero)
        }
        return sim.result
    }

    public var result: Result {
        var h = FNV1a()
        for b in bullets {
            for q in [b.x, b.y] {
                let bits = q.bitPattern
                for shift in stride(from: 0, to: 64, by: 8) { h.add(UInt8((bits >> UInt64(shift)) & 0xFF)) }
            }
        }
        var c = FNV1a()
        for b in bullets { for q in [b.x, b.y] { c.add(Int32((q * 1000).rounded())) } }
        return Result(outcome: outcome, steps: tick, bulletCount: bullets.count, hp: hp, bulletHash: h.value, bulletHashCoarse: c.value)
    }
}
