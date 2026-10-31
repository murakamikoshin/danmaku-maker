#!/usr/bin/env python3
"""広告で解放する30パターンと、弾幕パック2(課金)の11パターンの表から、Swift(DanmakuCore/Sources/DanmakuCore/AdPatterns.swift)と
サーバー(firebase/functions/src/adpatterns.ts)の弾の出し方を生成する。表を直したら、このスクリプトを実行し直す。
同じ式を両方に手で書くと食い違いやすいので、元の表は1つにしている。
使い方: python3 tools/gen_ad_patterns.py
"""
import os, json

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 弾の出し方の部品(すべて省略可):
#  mode: 0=輪(n個を等角度) 1=自機狙いの扇 2=真下向きの扇
#  fan: 扇の広さ(度)。0 はエディタの「角度」(r)を使う、マイナスは扇にしない(一直線)
#  spin: mode0 で 1回ごとに回す量(r に掛ける)
#  sweepAmp/sweepFreq: mode2 で、向きを左右に揺らす(振れ幅は r に掛ける)
#  layers/layerAngle/layerSpeed: 同じ形を重ねる数・重ねるごとのずれ(度)・速さの倍率
#  wobbleAmp/Freq/Phase: 弾ごとの角度のゆらぎ(度)
#  waveAmp/Freq/Phase: 弾ごとの速さの波
#  speedStep/speedCycle: j番目の弾ほど速くする(cycle>0 なら cycle ごとに戻す)
#  altSpeed: 奇数番目の弾の速さの倍率
#  speed0: 全体の速さの倍率
#  lineWidth: 発射位置を横一列に広げる幅 / scatter: 発射位置を横にばらまく幅(乱数)
#  jitter: 角度のばらつき(度、乱数)
#  turn(度/秒)/accel/maxMul/bounces/script: 追尾・加速・反射・時間で変わる動き
#  beam: 1 なら弾ではなく、ためてから撃つ光線(チャージビーム)を出す。向きは mode/fan で決まり、速さの部品は使わない
#  beamSweep/beamTime: 光線を撃っている間に、beamSweep 度だけ首を振る(なぎ払い)。撃つ時間は beamTime 秒。
#                      偶数番目と奇数番目で、振る向きが逆
#  curve/curveTime: ブーメラン。出てから curveTime 秒の間、curve 度/秒で向きを回し、弧を描いて戻ってくる。
#                   偶数番目と奇数番目で、回る向きが逆
#  giant: 1 なら巨大弾(大きく、当たる範囲も広い)
#  radius/grow/growMax: 弾の当たる範囲の広さ(ふつうの弾より何px広いか)と、1秒あたりに広がる量・上限(膨らむ泡)
#  gravity: 下向きの重力(px/秒²)。mode 3 は真上向き(投げ上げて落ちてくる)
#  mine/travel/fuse: 地雷。travel 秒進んで止まり、出てから fuse 秒で爆発する(爆風と弾の輪)
#  meteor/fuse/blastRadius/meteorGap: 隕石。自機のいる場所に予告の円を出し、fuse 秒後に半径 blastRadius の衝撃。
#                                     2つ目からは、自機から meteorGap 離れたまわりに落ちる
#  grid/gridGap: 格子レーザー。自機を通る縦と横の線から、gridGap ずつ離れた線を交互に、画面の端からためて撃つ
#  orbitRadius/curveTime: 衛星。発射口のまわりの半径 orbitRadius の円の上を curveTime 秒回ってから飛び出す
#  trail: スネーク。後ろの弾ほど trail px ずつ後ろから出て、列になって追いかける
#  pack: 2 なら、広告ではなく弾幕パック2(課金)のパターン
#
# ⚠️ id は保存データ(ステージ・解放の記録)に入るので変えない。2026-10-31 に、既存のパターンとほぼ同じ動きだった5つ
#   (swayFan≒首ふり扇、sniper≒光線、pulseRing≒時差、drizzle≒雨、twinAim≒自機狙い)を、id はそのままで別の動きに作り替えた
# defaults: エディタで選んだときの初期値 (i 間隔, c 数, v 速さ, r 角度)
P = lambda id, ja, en, defaults, **kw: dict(id=id, ja=ja, en=en, defaults=defaults, **kw)
PATTERNS = [
    P("twinRing", "二重輪", "Twin Ring", (1.0, 14, 2.4, 6), mode=0, layers=2, layerSpeed=0.6),
    P("tripleRing", "三重輪", "Triple Ring", (1.2, 12, 2.6, 4), mode=0, layers=3, layerSpeed=0.75),
    P("pinwheel", "風車", "Pinwheel", (0.5, 8, 2.4, 9), mode=0, altSpeed=0.45),
    P("ripple", "さざ波", "Ripple", (1.4, 18, 2.4, 0), mode=0, layers=4, layerAngle=5, layerSpeed=0.85, spin=0),
    P("chargeBeam", "チャージビーム", "Charge Beam", (2.4, 1, 2.0, 40), mode=1, beam=1),
    P("whirl", "渦潮", "Whirlpool", (0.12, 4, 1.6, 13), mode=0, speedStep=0.035),
    P("slither", "蛇行", "Slither", (0.6, 7, 2.2, 26), mode=2, wobbleAmp=22, wobbleFreq=1.1, wobblePhase=0.6),
    P("curtain", "カーテン", "Curtain", (0.9, 12, 1.8, 0), mode=2, fan=-1, lineWidth=330),
    P("swayFan", "跳ね返りカーテン", "Bounce Curtain", (1.3, 7, 2.0, 0), mode=2, fan=70, lineWidth=280, bounces=2),
    P("boomerang", "ブーメラン", "Boomerang", (1.2, 4, 2.4, 40), mode=1, curve=130, curveTime=1.4),
    P("drizzle", "加速する雨", "Accelerating Rain", (0.25, 2, 2.0, 0), mode=2, fan=-1, scatter=340, speed0=0.25, accel=1.0, maxMul=2.6),
    P("comet", "彗星", "Comet", (1.0, 7, 1.8, 14), mode=1, speedStep=0.15),
    P("shotgun", "散弾", "Shotgun", (0.9, 9, 2.6, 24), mode=1, jitter=10),
    P("sniper", "追尾カーテン", "Homing Curtain", (1.8, 6, 1.5, 0), mode=2, fan=-1, lineWidth=300, turn=30),
    P("giantOrb", "巨大弾", "Giant Orb", (2.0, 1, 1.6, 0), mode=1, fan=-1, giant=1, bounces=1, pack=2),
    P("twinAim", "時差扇", "Delayed Fan", (1.0, 7, 2.4, 50), mode=1, script=3, layers=2, layerSpeed=0.7),
    P("zigzagAim", "ジグザグ狙い", "Zigzag Aim", (0.7, 8, 2.3, 30), mode=1, wobbleAmp=16, wobbleFreq=2.3, wobblePhase=0.9),
    P("accelRing", "加速輪", "Accel Ring", (1.1, 16, 2.0, 7), mode=0, speed0=0.35, accel=0.8, maxMul=2.2),
    P("homingRing", "追尾の輪", "Homing Ring", (1.8, 8, 1.5, 10), mode=0, turn=40, pack=2),
    P("sweepLaser", "なぎ払いレーザー", "Sweeping Laser", (3.0, 1, 2.0, 0), mode=1, beam=1, beamSweep=90, beamTime=1.2, pack=2),
    P("bounceRing", "反射の輪", "Bounce Ring", (1.3, 10, 2.2, 8), mode=0, bounces=2),
    P("freezeRing", "停止の輪", "Freeze Ring", (1.2, 14, 2.4, 6), mode=0, script=1),
    P("shatterRing", "破裂の輪", "Shatter Ring", (1.6, 8, 2.2, 10), mode=0, script=2, pack=2),
    P("pulseRing", "止まる雨", "Pausing Rain", (0.45, 3, 2.0, 0), mode=2, fan=-1, scatter=340, script=1),
    P("freezeCurtain", "停止カーテン", "Freeze Curtain", (1.3, 9, 2.4, 0), mode=2, fan=-1, lineWidth=300, script=1),
    P("splitCurtain", "分裂カーテン", "Split Curtain", (1.5, 6, 1.8, 0), mode=2, fan=-1, lineWidth=300, script=2),
    P("wavyRing", "波紋の輪", "Wavy Ring", (1.0, 24, 2.2, 6), mode=0, waveAmp=0.35, waveFreq=3),
    P("petalFan", "花扇", "Petal Fan", (0.9, 13, 2.2, 60), mode=1, waveAmp=0.4, waveFreq=3),
    P("waveSpiral", "波渦", "Wave Spiral", (0.1, 3, 2.0, 11), mode=0, waveAmp=0.3, waveFreq=1.7, wavePhase=0.8),
    P("tide", "満ち引き", "Tide", (0.5, 9, 2.0, 70), mode=2, waveAmp=0.5, waveFreq=2, wavePhase=1.3),
    P("ladder", "はしご", "Ladder", (0.8, 10, 2.0, 0), mode=2, fan=-1, lineWidth=300, altSpeed=0.6),
    P("helix", "二重らせん", "Double Helix", (0.1, 3, 2.0, 12), mode=0, layers=2, layerAngle=8, layerSpeed=1.15),
    P("rapidFan", "連射扇", "Rapid Fan", (0.22, 6, 2.4, 36), mode=1, speedStep=0.12, speedCycle=3),
    P("lightRain", "光の雨", "Light Rain", (0.08, 2, 2.8, 0), mode=2, fan=-1, scatter=340, speed0=1.2, jitter=3),
    # ここから下は、弾幕パック2(課金)だけのパターン
    P("mine", "地雷", "Mine", (1.6, 3, 2.2, 50), mode=1, mine=1, travel=0.9, fuse=2.6, pack=2),
    P("meteor", "隕石", "Meteor", (2.0, 1, 2.0, 0), mode=0, meteor=1, fuse=1.1, blastRadius=34, meteorGap=70, pack=2),
    P("gridLaser", "格子レーザー", "Grid Laser", (3.2, 4, 2.0, 0), mode=0, grid=1, gridGap=72, pack=2),
    P("gravity", "重力弾", "Gravity Shot", (0.9, 7, 2.2, 70), mode=3, gravity=180, pack=2),
    P("orbit", "衛星", "Satellites", (1.4, 8, 1.6, 15), mode=0, orbitRadius=40, curveTime=2.0, pack=2),
    P("snake", "スネーク", "Snake", (2.2, 8, 2.0, 0), mode=1, fan=-1, turn=70, trail=11, pack=2),
    P("bubble", "膨らむ泡", "Swelling Bubble", (1.8, 2, 2.0, 40), mode=1, radius=2, grow=10, growMax=26, speed0=0.5, pack=2),
]
AD = [p for p in PATTERNS if p.get("pack") != 2]
# 弾幕パック2の並び(ショップに出す順)
PACK2_ORDER = ["mine", "meteor", "gridLaser", "sweepLaser", "giantOrb", "bubble", "gravity", "orbit", "snake", "shatterRing", "homingRing"]
PACK2 = [next(p for p in PATTERNS if p["id"] == i) for i in PACK2_ORDER]
assert len({p["id"] for p in PATTERNS}) == len(PATTERNS) == 41
assert len(AD) == 30 and len(PACK2) == 11 and {p["id"] for p in PACK2} == {p["id"] for p in PATTERNS if p.get("pack") == 2}
# 広告で解放する順番(1から数えて): チャージビーム5番目、ブーメラン10番目
assert AD[4]["id"] == "chargeBeam" and AD[9]["id"] == "boomerang"

FIELDS = [  # (名前, 型, 既定値)
    ("mode", "Int", 0), ("fan", "Double", 0.0), ("spin", "Double", 1.0), ("sweepAmp", "Double", 0.0), ("sweepFreq", "Double", 0.25),
    ("layers", "Int", 1), ("layerAngle", "Double", 0.0), ("layerSpeed", "Double", 1.0),
    ("wobbleAmp", "Double", 0.0), ("wobbleFreq", "Double", 1.0), ("wobblePhase", "Double", 0.0),
    ("waveAmp", "Double", 0.0), ("waveFreq", "Double", 1.0), ("wavePhase", "Double", 0.0),
    ("speedStep", "Double", 0.0), ("speedCycle", "Int", 0), ("altSpeed", "Double", 0.0), ("speed0", "Double", 1.0),
    ("lineWidth", "Double", 0.0), ("scatter", "Double", 0.0), ("jitter", "Double", 0.0),
    ("turn", "Double", 0.0), ("accel", "Double", 0.0), ("maxMul", "Double", 0.0), ("bounces", "Int", 0), ("script", "Int", 0),
    ("beam", "Int", 0), ("beamSweep", "Double", 0.0), ("beamTime", "Double", 0.0),
    ("curve", "Double", 0.0), ("curveTime", "Double", 0.0), ("giant", "Int", 0),
    ("radius", "Double", 0.0), ("grow", "Double", 0.0), ("growMax", "Double", 0.0), ("gravity", "Double", 0.0),
    ("mine", "Int", 0), ("travel", "Double", 0.0), ("fuse", "Double", 0.0),
    ("meteor", "Int", 0), ("blastRadius", "Double", 0.0), ("meteorGap", "Double", 0.0),
    ("grid", "Int", 0), ("gridGap", "Double", 0.0), ("orbitRadius", "Double", 0.0), ("trail", "Double", 0.0),
]

def lit(t, v):
    if t == "Int":
        return str(int(v))
    return repr(float(v))

def swift():
    o = []
    o.append("// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。\n")
    o.append("import Foundation\n")
    o.append("/// 広告で解放するパターンと、弾幕パック2のパターンの、弾の出し方。サーバー(adpatterns.ts)にも同じ表と計算がある\n")
    o.append("public struct PatternRecipe: Sendable {")
    for n, t, d in FIELDS:
        o.append(f"    public var {n}: {t} = {lit(t, d)}")
    o.append("}\n")
    o.append("public extension Pattern {")
    o.append("    /// 広告を見て解放する、無料のパターン(解放する順)。表の pack=2 のものは入らない")
    o.append("    static let ad: [Pattern] = [" + ", ".join("." + p["id"] for p in AD) + "]")
    o.append("    var isAd: Bool { Pattern.ad.contains(self) }\n")
    o.append("    /// 弾幕パック2(課金)のパターン(ショップに出す順)")
    o.append("    static let pack2: [Pattern] = [" + ", ".join("." + p["id"] for p in PACK2) + "]\n")
    o.append("    /// 弾の出し方の表(広告で解放するパターンと、弾幕パック2のパターン)")
    o.append("    var recipe: PatternRecipe? {")
    o.append("        switch self {")
    for p in PATTERNS:
        args = ", ".join(f"{n}: {lit(t, p[n])}" for n, t, d in FIELDS if n in p)
        o.append(f"        case .{p['id']}: return PatternRecipe({args})")
    o.append("        default: return nil")
    o.append("        }")
    o.append("    }\n")
    o.append("    /// エディタで選んだときの初期値(間隔・数・速さ・角度)")
    o.append("    var recipeDefaults: (i: Double, c: Int, v: Double, r: Double)? {")
    o.append("        switch self {")
    for p in PATTERNS:
        i, c, v, r = p["defaults"]
        o.append(f"        case .{p['id']}: return ({float(i)!r}, {c}, {float(v)!r}, {float(r)!r})")
    o.append("        default: return nil")
    o.append("        }")
    o.append("    }")
    o.append("}\n")
    o.append("extension Emit {")
    o.append("    /// 表(PatternRecipe)に従って弾を出す。部品の意味は tools/gen_ad_patterns.py を参照")
    o.append("    static func emitRecipe(_ r: PatternRecipe, _ m: Emitter, shot k: Int, cx: Double, cy: Double, px: Double, py: Double,")
    o.append("                           off: Double, sp: Double, n: Int, rng: inout Mulberry32, into out: inout [Bullet]) {")
    o.append("        let deg = Double.pi / 180")
    o.append("        let fanDeg = r.fan < 0 ? 0 : (r.fan > 0 ? r.fan : m.r)")
    o.append("        var layerSpeed = 1.0")
    o.append("        for layer in 0..<max(1, r.layers) {")
    o.append("            let layerShift = Double(layer) * r.layerAngle * deg")
    o.append("            let base: Double")
    o.append("            switch r.mode {")
    o.append("            case 0: base = Double(k) * m.r * deg * r.spin + off")
    o.append("            case 1: base = atan2(py - cy, px - cx) + off")
    o.append("            case 3: base = -Double.pi / 2 + off")
    o.append("            default: base = Double.pi / 2 + off + sin(Double(k) * r.sweepFreq) * m.r * deg * r.sweepAmp")
    o.append("            }")
    o.append("            for j in 0..<n {")
    o.append("                var a: Double")
    o.append("                if r.mode == 0 { a = base + Double(j) * 2 * Double.pi / Double(n) }")
    o.append("                else { a = base + (n > 1 ? (Double(j) / Double(n - 1) - 0.5) * fanDeg * deg : 0) }")
    o.append("                a += layerShift")
    o.append("                if r.wobbleAmp != 0 { a += r.wobbleAmp * deg * sin(Double(j) * r.wobbleFreq + Double(k) * r.wobblePhase) }")
    o.append("                if r.jitter != 0 { a += (rng.next() - 0.5) * 2 * r.jitter * deg }")
    o.append("                var f = r.speed0 * layerSpeed")
    o.append("                if r.speedStep != 0 { let jj = r.speedCycle > 0 ? j % r.speedCycle : j; f *= 1 + Double(jj) * r.speedStep }")
    o.append("                if r.altSpeed != 0 && j % 2 == 1 { f *= r.altSpeed }")
    o.append("                if r.waveAmp != 0 { f *= 1 + r.waveAmp * sin(Double(j) * r.waveFreq + Double(k) * r.wavePhase) }")
    o.append("                var x = cx")
    o.append("                if r.lineWidth != 0 { x += (n > 1 ? Double(j) / Double(n - 1) - 0.5 : 0) * r.lineWidth }")
    o.append("                if r.scatter != 0 { x += (rng.next() - 0.5) * r.scatter }")
    o.append("                guard out.count < DanmakuConfig.maxBullets else { continue }")
    o.append("                let side = j % 2 == 0 ? 1.0 : -1.0")
    o.append("                if r.meteor != 0 {")
    o.append("                    // 隕石: 自機のいる場所(2つ目からは、そのまわり)に、予告の円を出してから衝撃を落とす")
    o.append("                    let mx = j == 0 ? px : px + cos(a) * r.meteorGap, my = j == 0 ? py : py + sin(a) * r.meteorGap")
    o.append("                    out.append(Bullet.blast(x: mx, y: my, radius: r.blastRadius, warn: r.fuse, color: m.k))")
    o.append("                } else if r.grid != 0 {")
    o.append("                    // 格子レーザー: 自機を通る縦と横の線から、間をあけて交互に。画面の端から反対の端まで")
    o.append("                    let idx = j / 2")
    o.append("                    let gap = idx == 0 ? 0 : Double(idx % 2 == 1 ? 1 : -1) * Double((idx + 1) / 2) * r.gridGap")
    o.append("                    if j % 2 == 0 { out.append(Bullet.beam(x: px + gap, y: -10, angle: Double.pi / 2, color: m.k)) }")
    o.append("                    else { out.append(Bullet.beam(x: -10, y: py + gap, angle: 0, color: m.k)) }")
    o.append("                } else if r.beam != 0 {")
    o.append("                    // チャージビーム: その場に止まったまま、向き(長さ1)だけを持つ。なぎ払いは、振る分の半分だけ戻した向きから始める")
    o.append("                    if r.beamSweep != 0 {")
    o.append("                        out.append(Bullet.beam(x: x, y: cy, angle: a - side * r.beamSweep * deg / 2, color: m.k,")
    o.append("                                               sweep: side * r.beamSweep * deg / r.beamTime, fireTime: r.beamTime))")
    o.append("                    } else {")
    o.append("                        out.append(Bullet.beam(x: x, y: cy, angle: a, color: m.k))")
    o.append("                    }")
    o.append("                } else if r.orbitRadius != 0 {")
    o.append("                    // 衛星: 発射口のまわりの円の上から、円に沿う向きに出て、curveTime 秒だけ回ってから飛び出す")
    o.append("                    let speed = sp * f")
    o.append("                    out.append(Bullet(x: cx + cos(a) * r.orbitRadius, y: cy + sin(a) * r.orbitRadius,")
    o.append("                                      vx: cos(a + Double.pi / 2) * speed, vy: sin(a + Double.pi / 2) * speed, color: m.k,")
    o.append("                                      turn: speed / r.orbitRadius, homeLeft: r.curveTime, script: Bullet.boomerangScript))")
    o.append("                } else if r.curve != 0 {")
    o.append("                    // ブーメラン: 決まった時間だけ向きを回す(追尾ではない)")
    o.append("                    out.append(Bullet(x: x, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k,")
    o.append("                                      turn: side * r.curve * deg, homeLeft: r.curveTime, bounces: r.bounces, script: Bullet.boomerangScript))")
    o.append("                } else {")
    o.append("                    // スネーク: 後ろの弾ほど、進む向きの後ろから出る(同じように曲がるので、列になって追いかける)")
    o.append("                    let bx = x - cos(a) * r.trail * Double(j), by = cy - sin(a) * r.trail * Double(j)")
    o.append("                    var b = Bullet(x: bx, y: by, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k,")
    o.append("                                   turn: r.turn * deg, homeLeft: r.turn > 0 ? DanmakuConfig.homingSeconds : 0,")
    o.append("                                   accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces,")
    o.append("                                   script: r.giant != 0 ? Bullet.giantScript : r.script)")
    o.append("                    if r.mine != 0 {")
    o.append("                        // 地雷: travel 秒進んで止まり、出てから fuse 秒で爆発する")
    o.append("                        b.script = Bullet.mineScript; b.homeLeft = r.travel; b.fuse = r.fuse")
    o.append("                    }")
    o.append("                    b.gravity = r.gravity")
    o.append("                    b.radius = r.radius; b.grow = r.grow; b.growMax = r.growMax")
    o.append("                    out.append(b)")
    o.append("                }")
    o.append("            }")
    o.append("            layerSpeed *= r.layerSpeed")
    o.append("        }")
    o.append("    }")
    o.append("}")
    return "\n".join(o) + "\n"

def num(v):
    return repr(float(v)) if not float(v).is_integer() else str(int(v))

def ts():
    o = []
    o.append("// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。")
    o.append("// 広告で解放するパターンと、弾幕パック2のパターンの、弾の出し方。アプリ(AdPatterns.swift)と同じ表と計算。\n")
    o.append("export interface Recipe {")
    for n, t, d in FIELDS:
        o.append(f"  {n}: number;")
    o.append("}\n")
    o.append("const BASE: Recipe = { " + ", ".join(f"{n}: {num(d)}" for n, t, d in FIELDS) + " };\n")
    o.append("export const AD_PATTERNS = [" + ", ".join(json.dumps(p["id"]) for p in AD) + "] as const;")
    o.append("export const PACK2_PATTERNS = [" + ", ".join(json.dumps(p["id"]) for p in PACK2) + "] as const;\n")
    o.append("export const RECIPES: Record<string, Recipe> = {")
    for p in PATTERNS:
        args = ", ".join(f"{n}: {num(p[n])}" for n, t, d in FIELDS if n in p)
        o.append(f"  {p['id']}: {{ ...BASE, {args} }},")
    o.append("};\n")
    o.append("/** チャージビームの印(弾の script)。アプリの Bullet.beamScript と同じ */")
    o.append("export const BEAM_SCRIPT = 4;")
    o.append("/** ブーメランと巨大弾の印。アプリの Bullet.boomerangScript / giantScript と同じ */")
    o.append("export const BOOMERANG_SCRIPT = 5, GIANT_SCRIPT = 6;")
    o.append("/** 地雷と爆風(隕石・地雷の爆発)の印。アプリの Bullet.mineScript / blastScript と同じ */")
    o.append("export const MINE_SCRIPT = 7, BLAST_SCRIPT = 8;\n")
    o.append("/** 弾を1つ出す関数(呼ぶ側の Bullet の形に合わせる) */")
    o.append("export interface BulletExtra { turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number; gravity: number; radius: number; grow: number; growMax: number; fuse: number }")
    o.append("const NONE: BulletExtra = { turn: 0, homeLeft: 0, accel: 0, maxSpeed: 0, bounces: 0, script: 0, gravity: 0, radius: 0, grow: 0, growMax: 0, fuse: 0 };")
    o.append("export type AddBullet = (x: number, y: number, vx: number, vy: number, extra: BulletExtra) => void;\n")
    o.append("export function emitRecipe(r: Recipe, m: { c: number; r: number; k: number }, k: number, cx: number, cy: number, px: number, py: number,")
    o.append("  off: number, sp: number, n: number, rng: () => number, homingSeconds: number, add: AddBullet): void {")
    o.append("  const deg = Math.PI / 180;")
    o.append("  const fanDeg = r.fan < 0 ? 0 : (r.fan > 0 ? r.fan : m.r);")
    o.append("  let layerSpeed = 1;")
    o.append("  for (let layer = 0; layer < Math.max(1, r.layers); layer++) {")
    o.append("    const layerShift = layer * r.layerAngle * deg;")
    o.append("    let base: number;")
    o.append("    if (r.mode === 0) base = k * m.r * deg * r.spin + off;")
    o.append("    else if (r.mode === 1) base = Math.atan2(py - cy, px - cx) + off;")
    o.append("    else if (r.mode === 3) base = -Math.PI / 2 + off;")
    o.append("    else base = Math.PI / 2 + off + Math.sin(k * r.sweepFreq) * m.r * deg * r.sweepAmp;")
    o.append("    for (let j = 0; j < n; j++) {")
    o.append("      let a: number;")
    o.append("      if (r.mode === 0) a = base + (j * 2 * Math.PI) / n;")
    o.append("      else a = base + (n > 1 ? (j / (n - 1) - 0.5) * fanDeg * deg : 0);")
    o.append("      a += layerShift;")
    o.append("      if (r.wobbleAmp !== 0) a += r.wobbleAmp * deg * Math.sin(j * r.wobbleFreq + k * r.wobblePhase);")
    o.append("      if (r.jitter !== 0) a += (rng() - 0.5) * 2 * r.jitter * deg;")
    o.append("      let f = r.speed0 * layerSpeed;")
    o.append("      if (r.speedStep !== 0) { const jj = r.speedCycle > 0 ? j % r.speedCycle : j; f *= 1 + jj * r.speedStep; }")
    o.append("      if (r.altSpeed !== 0 && j % 2 === 1) f *= r.altSpeed;")
    o.append("      if (r.waveAmp !== 0) f *= 1 + r.waveAmp * Math.sin(j * r.waveFreq + k * r.wavePhase);")
    o.append("      let x = cx;")
    o.append("      if (r.lineWidth !== 0) x += (n > 1 ? j / (n - 1) - 0.5 : 0) * r.lineWidth;")
    o.append("      if (r.scatter !== 0) x += (rng() - 0.5) * r.scatter;")
    o.append("      const side = j % 2 === 0 ? 1 : -1;")
    o.append("      if (r.meteor !== 0) {")
    o.append("        // 隕石: 自機のいる場所(2つ目からは、そのまわり)に、予告の円を出してから衝撃を落とす。アプリの Bullet.blast と同じ")
    o.append("        const mx = j === 0 ? px : px + Math.cos(a) * r.meteorGap, my = j === 0 ? py : py + Math.sin(a) * r.meteorGap;")
    o.append("        add(mx, my, 0, 0, { ...NONE, bounces: 1, script: BLAST_SCRIPT, radius: r.blastRadius, fuse: r.fuse });")
    o.append("        continue;")
    o.append("      }")
    o.append("      if (r.grid !== 0) {")
    o.append("        // 格子レーザー: 自機を通る縦と横の線から、間をあけて交互に。画面の端から反対の端まで")
    o.append("        const idx = Math.trunc(j / 2);")
    o.append("        const gap = idx === 0 ? 0 : (idx % 2 === 1 ? 1 : -1) * Math.trunc((idx + 1) / 2) * r.gridGap;")
    o.append("        if (j % 2 === 0) add(px + gap, -10, Math.cos(Math.PI / 2), Math.sin(Math.PI / 2), { ...NONE, bounces: 1, script: BEAM_SCRIPT });")
    o.append("        else add(-10, py + gap, Math.cos(0), Math.sin(0), { ...NONE, bounces: 1, script: BEAM_SCRIPT });")
    o.append("        continue;")
    o.append("      }")
    o.append("      if (r.beam !== 0) {")
    o.append("        // チャージビーム: その場に止まったまま、向き(長さ1)だけを持つ。アプリの Bullet.beam と同じ")
    o.append("        if (r.beamSweep !== 0) {")
    o.append("          const a0 = a - side * r.beamSweep * deg / 2;")
    o.append("          add(x, cy, Math.cos(a0), Math.sin(a0), { ...NONE, turn: side * r.beamSweep * deg / r.beamTime, homeLeft: r.beamTime, bounces: 1, script: BEAM_SCRIPT });")
    o.append("        } else {")
    o.append("          add(x, cy, Math.cos(a), Math.sin(a), { ...NONE, bounces: 1, script: BEAM_SCRIPT });")
    o.append("        }")
    o.append("        continue;")
    o.append("      }")
    o.append("      if (r.orbitRadius !== 0) {")
    o.append("        // 衛星: 発射口のまわりの円の上から、円に沿う向きに出て、curveTime 秒だけ回ってから飛び出す")
    o.append("        const speed = sp * f;")
    o.append("        add(cx + Math.cos(a) * r.orbitRadius, cy + Math.sin(a) * r.orbitRadius, Math.cos(a + Math.PI / 2) * speed, Math.sin(a + Math.PI / 2) * speed,")
    o.append("          { ...NONE, turn: speed / r.orbitRadius, homeLeft: r.curveTime, script: BOOMERANG_SCRIPT });")
    o.append("        continue;")
    o.append("      }")
    o.append("      if (r.curve !== 0) {")
    o.append("        // ブーメラン: 決まった時間だけ向きを回す(追尾ではない)")
    o.append("        add(x, cy, Math.cos(a) * sp * f, Math.sin(a) * sp * f, { ...NONE, turn: side * r.curve * deg, homeLeft: r.curveTime, bounces: r.bounces, script: BOOMERANG_SCRIPT });")
    o.append("        continue;")
    o.append("      }")
    o.append("      // スネーク: 後ろの弾ほど、進む向きの後ろから出る(同じように曲がるので、列になって追いかける)")
    o.append("      const bx = x - Math.cos(a) * r.trail * j, by = cy - Math.sin(a) * r.trail * j;")
    o.append("      add(bx, by, Math.cos(a) * sp * f, Math.sin(a) * sp * f, {")
    o.append("        turn: r.turn * deg, homeLeft: r.mine !== 0 ? r.travel : r.turn > 0 ? homingSeconds : 0, accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces,")
    o.append("        script: r.mine !== 0 ? MINE_SCRIPT : r.giant !== 0 ? GIANT_SCRIPT : r.script,")
    o.append("        gravity: r.gravity, radius: r.radius, grow: r.grow, growMax: r.growMax, fuse: r.mine !== 0 ? r.fuse : 0,")
    o.append("      });")
    o.append("    }")
    o.append("    layerSpeed *= r.layerSpeed;")
    o.append("  }")
    o.append("}")
    return "\n".join(o) + "\n"

def names():
    return {p["id"]: (p["ja"], p["en"]) for p in PATTERNS}

if __name__ == "__main__":
    open(os.path.join(ROOT, "DanmakuCore/Sources/DanmakuCore/AdPatterns.swift"), "w").write(swift())
    open(os.path.join(ROOT, "firebase/functions/src/adpatterns.ts"), "w").write(ts())
    print("generated", len(PATTERNS), "patterns")
