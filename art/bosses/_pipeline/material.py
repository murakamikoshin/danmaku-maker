"""素材ごとに色を決まった段にそろえる(参考のステッカーの塗り方)。
- 色相と彩度で素材に分ける(髪のオレンジ、赤、肌、白、黒っぽい物、青 など)
- 素材ごとに明るさで3段(ドットが少ない素材は2段)に分けて、その段の代表の色1つで塗る
- いちばん外のふちのドットは、その素材の「輪郭の段」(いちばん暗い段より少し明るい色)にする
使い方: python3 material.py 入力.png 出力.png [段の数=3]"""
import sys, colorsys
from collections import defaultdict
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGBA'); W, H = im.size; P = im.load()
LV = int(sys.argv[3]) if len(sys.argv) > 3 else 3
PASSES = int(sys.argv[4]) if len(sys.argv) > 4 else 3
LV_LIGHT = int(sys.argv[5]) if len(sys.argv) > 5 else 2
def hsv(c): return colorsys.rgb_to_hsv(*[t / 255 for t in c[:3]])
def rgb(h, s, v): return tuple(int(t * 255) for t in colorsys.hsv_to_rgb(h % 1, max(0, min(1, s)), max(0, min(1, v))))
def material(c):
    h, s, v = hsv(c)
    if v < 0.33: return 'dark'
    if s < 0.16: return 'white'
    if (h < 0.1 or h > 0.95) and s < 0.42 and v > 0.66: return 'skin'
    if s < 0.3 and v > 0.7: return 'white'          # ピンクがかった白(白い服の影)
    return 'h%d' % int(((h + 0.03) % 1) * 18)
groups = defaultdict(list)
for y in range(H):
    for x in range(W):
        if P[x, y][3]: groups[material(P[x, y])].append((x, y))
def kmeans1(vals, k):
    vs = sorted(vals); c = [vs[int((i + 0.5) * len(vs) / k)] for i in range(k)]
    for _ in range(12):
        b = [[] for _ in range(k)]
        for v in vals: b[min(range(k), key=lambda i: abs(v - c[i]))].append(v)
        c = [sum(x) / len(x) if x else c[i] for i, x in enumerate(b)]
    return sorted(c)
out = {}
for m, pts in groups.items():
    cols = [P[x, y][:3] for x, y in pts]
    k = (LV_LIGHT if m in ('skin', 'white', 'grey') else LV) if len(pts) >= 40 else 2 if len(pts) >= 8 else 1
    vs = [hsv(c)[2] for c in cols]; cs = kmeans1(vs, k)
    # 段ごとの代表の色: その段のドットの色相・彩度の平均 + 段の明るさ
    lv = [min(range(k), key=lambda i: abs(v - cs[i])) for v in vs]
    reps = []
    for i in range(k):
        mem = [hsv(c) for c, l in zip(cols, lv) if l == i] or [hsv(cols[0])]
        import math
        hx = sum(math.cos(h * 2 * math.pi) * s for h, s, v in mem); hy = sum(math.sin(h * 2 * math.pi) * s for h, s, v in mem)
        hh = (math.atan2(hy, hx) / (2 * math.pi)) % 1; ss = sum(s for _, s, _ in mem) / len(mem)
        reps.append(rgb(hh, ss, cs[i]))
    for (x, y), l in zip(pts, lv): out[(x, y)] = (m, reps[l], reps)
from collections import Counter
lab = {xy: (m, c) for xy, (m, c, reps) in out.items()}
for _ in range(PASSES):
    new = {}
    for (x, y), l in lab.items():
        nb = [lab.get((x + dx, y + dy)) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
        nb = [n for n in nb if n is not None]
        if not nb: new[(x, y)] = l; continue
        top, n = Counter(nb).most_common(1)[0]
        same = sum(1 for q in nb if q == l)
        new[(x, y)] = top if (same <= 1 and n >= 4) else l
    lab = new
reps_of = {m: reps for (m, c, reps) in out.values()}
out = {xy: (m, c, reps_of[m]) for xy, (m, c) in lab.items()}
for (x, y), (m, c, reps) in out.items(): P[x, y] = c + (255,)
# 外のふち: 素材の暗い段寄りの色(黒くしない)
for (x, y), (m, c, reps) in out.items():
    if any(not (0 <= x + dx < W and 0 <= y + dy < H) or not P[x + dx, y + dy][3] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
        if m == 'dark': continue
        h, s, v = hsv(reps[0])
        P[x, y] = (rgb(h, s + 0.08, max(0.58, v * 0.92)) if m not in ('white', 'grey') else (222, 182, 192)) + (255,)
im.save(sys.argv[2])
print(sys.argv[2], len(set(P[x, y][:3] for y in range(H) for x in range(W) if P[x, y][3])), 'colors', {m: len(p) for m, p in groups.items() if len(p) > 30})
