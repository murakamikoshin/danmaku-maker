#!/usr/bin/env python3
"""広告で解放する30パターンの表から、Swift(DanmakuCore/Sources/DanmakuCore/AdPatterns.swift)と
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
# defaults: エディタで選んだときの初期値 (i 間隔, c 数, v 速さ, r 角度)
P = lambda id, ja, en, defaults, **kw: dict(id=id, ja=ja, en=en, defaults=defaults, **kw)
PATTERNS = [
    P("twinRing", "二重輪", "Twin Ring", (1.0, 14, 2.4, 6), mode=0, layers=2, layerSpeed=0.6),
    P("tripleRing", "三重輪", "Triple Ring", (1.2, 12, 2.6, 4), mode=0, layers=3, layerSpeed=0.75),
    P("pinwheel", "風車", "Pinwheel", (0.5, 8, 2.4, 9), mode=0, altSpeed=0.45),
    P("ripple", "さざ波", "Ripple", (1.4, 18, 2.4, 0), mode=0, layers=4, layerAngle=5, layerSpeed=0.85, spin=0),
    P("whirl", "渦潮", "Whirlpool", (0.12, 4, 1.6, 13), mode=0, speedStep=0.035),
    P("slither", "蛇行", "Slither", (0.6, 7, 2.2, 26), mode=2, wobbleAmp=22, wobbleFreq=1.1, wobblePhase=0.6),
    P("curtain", "カーテン", "Curtain", (0.9, 12, 1.8, 0), mode=2, fan=-1, lineWidth=330),
    P("swayFan", "ゆらぎ扇", "Swaying Fan", (0.18, 5, 2.4, 50), mode=2, fan=38, sweepAmp=1.0, sweepFreq=0.3),
    P("drizzle", "霧雨", "Drizzle", (0.12, 2, 1.6, 0), mode=2, fan=-1, scatter=340, speed0=0.7),
    P("comet", "彗星", "Comet", (1.0, 7, 1.8, 14), mode=1, speedStep=0.15),
    P("shotgun", "散弾", "Shotgun", (0.9, 9, 2.6, 24), mode=1, jitter=10),
    P("sniper", "狙撃", "Sniper", (1.1, 1, 2.4, 0), mode=1, fan=-1, layers=3, layerSpeed=1.35, speed0=0.9),
    P("twinAim", "二連狙い", "Twin Aim", (0.8, 4, 2.6, 20), mode=1, layers=2, layerAngle=9),
    P("zigzagAim", "ジグザグ狙い", "Zigzag Aim", (0.7, 8, 2.3, 30), mode=1, wobbleAmp=16, wobbleFreq=2.3, wobblePhase=0.9),
    P("accelRing", "加速輪", "Accel Ring", (1.1, 16, 2.0, 7), mode=0, speed0=0.35, accel=0.8, maxMul=2.2),
    P("homingRing", "追尾の輪", "Homing Ring", (1.8, 8, 1.5, 10), mode=0, turn=40),
    P("bounceRing", "反射の輪", "Bounce Ring", (1.3, 10, 2.2, 8), mode=0, bounces=2),
    P("freezeRing", "停止の輪", "Freeze Ring", (1.2, 14, 2.4, 6), mode=0, script=1),
    P("shatterRing", "破裂の輪", "Shatter Ring", (1.6, 8, 2.2, 10), mode=0, script=2),
    P("pulseRing", "脈動の輪", "Pulse Ring", (1.8, 12, 2.0, 8), mode=0, script=3, layers=2, layerSpeed=0.7),
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
]
assert len(PATTERNS) == 30 and len({p["id"] for p in PATTERNS}) == 30

FIELDS = [  # (名前, 型, 既定値)
    ("mode", "Int", 0), ("fan", "Double", 0.0), ("spin", "Double", 1.0), ("sweepAmp", "Double", 0.0), ("sweepFreq", "Double", 0.25),
    ("layers", "Int", 1), ("layerAngle", "Double", 0.0), ("layerSpeed", "Double", 1.0),
    ("wobbleAmp", "Double", 0.0), ("wobbleFreq", "Double", 1.0), ("wobblePhase", "Double", 0.0),
    ("waveAmp", "Double", 0.0), ("waveFreq", "Double", 1.0), ("wavePhase", "Double", 0.0),
    ("speedStep", "Double", 0.0), ("speedCycle", "Int", 0), ("altSpeed", "Double", 0.0), ("speed0", "Double", 1.0),
    ("lineWidth", "Double", 0.0), ("scatter", "Double", 0.0), ("jitter", "Double", 0.0),
    ("turn", "Double", 0.0), ("accel", "Double", 0.0), ("maxMul", "Double", 0.0), ("bounces", "Int", 0), ("script", "Int", 0),
]

def lit(t, v):
    if t == "Int":
        return str(int(v))
    return repr(float(v))

def swift():
    o = []
    o.append("// このファイルは tools/gen_ad_patterns.py が生成する。直接は編集しない(表を直してスクリプトを実行し直す)。\n")
    o.append("import Foundation\n")
    o.append("/// 広告で解放する30パターンの、弾の出し方。サーバー(adpatterns.ts)にも同じ表と計算がある\n")
    o.append("public struct PatternRecipe: Sendable {")
    for n, t, d in FIELDS:
        o.append(f"    public var {n}: {t} = {lit(t, d)}")
    o.append("}\n")
    o.append("public extension Pattern {")
    o.append("    /// 広告を見て解放する、無料のパターン(解放する順)")
    o.append("    static let ad: [Pattern] = [" + ", ".join("." + p["id"] for p in PATTERNS) + "]")
    o.append("    var isAd: Bool { Pattern.ad.contains(self) }\n")
    o.append("    /// 弾の出し方の表(広告で解放するパターンだけ)")
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
    o.append("                if out.count < DanmakuConfig.maxBullets {")
    o.append("                    out.append(Bullet(x: x, y: cy, vx: cos(a) * sp * f, vy: sin(a) * sp * f, color: m.k,")
    o.append("                                      turn: r.turn * deg, homeLeft: r.turn > 0 ? DanmakuConfig.homingSeconds : 0,")
    o.append("                                      accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces, script: r.script))")
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
    o.append("// 広告で解放する30パターンの、弾の出し方。アプリ(AdPatterns.swift)と同じ表と計算。\n")
    o.append("export interface Recipe {")
    for n, t, d in FIELDS:
        o.append(f"  {n}: number;")
    o.append("}\n")
    o.append("const BASE: Recipe = { " + ", ".join(f"{n}: {num(d)}" for n, t, d in FIELDS) + " };\n")
    o.append("export const AD_PATTERNS = [" + ", ".join(json.dumps(p["id"]) for p in PATTERNS) + "] as const;\n")
    o.append("export const RECIPES: Record<string, Recipe> = {")
    for p in PATTERNS:
        args = ", ".join(f"{n}: {num(p[n])}" for n, t, d in FIELDS if n in p)
        o.append(f"  {p['id']}: {{ ...BASE, {args} }},")
    o.append("};\n")
    o.append("/** 弾を1つ出す関数(呼ぶ側の Bullet の形に合わせる) */")
    o.append("export type AddBullet = (x: number, y: number, vx: number, vy: number, extra: { turn: number; homeLeft: number; accel: number; maxSpeed: number; bounces: number; script: number }) => void;\n")
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
    o.append("      add(x, cy, Math.cos(a) * sp * f, Math.sin(a) * sp * f, {")
    o.append("        turn: r.turn * deg, homeLeft: r.turn > 0 ? homingSeconds : 0, accel: r.accel, maxSpeed: r.maxMul > 0 ? sp * r.maxMul : 0, bounces: r.bounces, script: r.script,")
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
