"""イラスト → 参考のステッカーに寄せたドット絵。
測った決まりごと:
- 輪郭は黒にしない。となりの塗りの色を濃くした色(白のふちは薄いピンク灰、肌のふちは赤茶、色のふちは暗い同じ色)
- 黒いドットは、黒い物の面(太い所)にだけ残す。細い黒い線は輪郭の色に塗り替える
- 1素材3段くらいの塗り(色数は少なめ)、グラデのにじみなし
- 高さは 85〜90 ドット
使い方: python3 pixel4.py 元画像 出力.png [高さ=88] [色数=24]"""
import sys, colorsys, json
from collections import deque, Counter
from PIL import Image, ImageEnhance
src, out = sys.argv[1], sys.argv[2]
TH = int(sys.argv[3]) if len(sys.argv) > 3 else 88
NC = int(sys.argv[4]) if len(sys.argv) > 4 else 24
im = Image.open(src).convert('RGB'); w, h = im.size; p = im.load()
def white(c): return min(c) > 236 and max(c) - min(c) < 18
bg = bytearray(w * h); q = deque()
for x in range(w): q.extend(((x, 0), (x, h - 1)))
for y in range(h): q.extend(((0, y), (w - 1, y)))
while q:
    x, y = q.popleft()
    if not (0 <= x < w and 0 <= y < h) or bg[y * w + x] or not white(p[x, y]): continue
    bg[y * w + x] = 1; q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
mask = Image.frombytes('L', (w, h), bytes(0 if v else 255 for v in bg))
box = mask.getbbox(); im = im.crop(box); mask = mask.crop(box)
im = ImageEnhance.Color(im).enhance(1.15)
sc = TH / im.height; nw, nh = max(1, round(im.width * sc)), TH
small = im.resize((nw, nh), Image.BOX); a = mask.resize((nw, nh), Image.BOX)
ap = a.load(); sp = small.load()
for y in range(nh):
    for x in range(nw):
        al = ap[x, y] / 255
        if 0.2 < al < 0.98: sp[x, y] = tuple(int(max(0, min(255, (v - (1 - al) * 255) / al))) for v in sp[x, y])
q8 = small.quantize(colors=NC, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert('RGB'); qp = q8.load()
G = [[(qp[x, y] if ap[x, y] > 120 else None) for x in range(nw)] for y in range(nh)]
def hsv(c): return colorsys.rgb_to_hsv(*[t / 255 for t in c])
def rgb(h, s, v): return tuple(int(t * 255) for t in colorsys.hsv_to_rgb(h % 1, max(0, min(1, s)), max(0, min(1, v))))
def dark(c):
    h, s, v = hsv(c)
    return v < 0.36 or (v < 0.62 and s < 0.28)
def outline_of(c):
    """塗りの色 → そのふちの輪郭の色(ほんの少し濃くするだけ。黒っぽくしない)"""
    h, s, v = hsv(c)
    if s < 0.2 and v > 0.75: return (232, 208, 214)          # 白 → 薄いピンク灰(白の素材の仲間になる薄さ)
    if 0.0 <= h < 0.12 and s < 0.45 and v > 0.7: return (222, 156, 140)   # 肌 → 明るい赤茶
    return rgb(h + 0.01, s * 1.05 + 0.05, max(0.55, v * 0.82))
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1)); N8 = N4 + ((1, 1), (-1, 1), (1, -1), (-1, -1))
def at(x, y): return G[y][x] if 0 <= x < nw and 0 <= y < nh else None
# 1. 黒い線を、となりの塗りの輪郭の色にする。黒を残すのは、大きくつながった黒い面だけ
BIG = max(20, int(nw * nh * 0.006))
comp_size = {}; seen = set()
for y0 in range(nh):
    for x0 in range(nw):
        if (x0, y0) in seen or G[y0][x0] is None or not dark(G[y0][x0]): continue
        stack = [(x0, y0)]; comp = []; seen.add((x0, y0))
        while stack:
            x, y = stack.pop(); comp.append((x, y))
            for dx, dy in N4:
                q = (x + dx, y + dy)
                if q not in seen and at(*q) is not None and dark(at(*q)): seen.add(q); stack.append(q)
        # 細長い線は面ではない: ドット数に対して、太さ(2回けずって残るか)を見る
        core = [c for c in comp if all(at(c[0] + dx, c[1] + dy) is not None and dark(at(c[0] + dx, c[1] + dy)) for dx, dy in N8)]
        size = len(core) * 3 if len(core) >= 6 else 0
        for c in comp: comp_size[c] = size
newG = [row[:] for row in G]
for y in range(nh):
    for x in range(nw):
        c = G[y][x]
        if c is None or not dark(c): continue
        if comp_size.get((x, y), 0) >= BIG: continue          # 大きくつながった黒い面(帯など)は残す
        fills = [at(x + dx, y + dy) for dx, dy in N8 + ((2, 0), (-2, 0), (0, 2), (0, -2))]
        fills = [f for f in fills if f is not None and not dark(f)]
        if fills:
            # 明るいほうの塗りに合わせる(白と赤の境目なら、白のふちの色)
            f = Counter(fills).most_common(2); pick = max((k for k, _ in f), key=lambda k: hsv(k)[2])
            newG[y][x] = outline_of(pick)
G = newG
# 2. 浮いた1ドットを消す
for y in range(nh):
    for x in range(nw):
        if G[y][x] is not None and sum(1 for dx, dy in N4 if at(x + dx, y + dy) is not None) <= 1: G[y][x] = None
# 3. いちばん外の1ドットを輪郭の色にする(外に足さない)
edge = []
for y in range(nh):
    for x in range(nw):
        c = G[y][x]
        if c is None: continue
        if any(at(x + dx, y + dy) is None for dx, dy in N4):
            h_, s_, v_ = hsv(c)
            is_outline = abs(v_ - 0.6) < 0.25 and s_ > 0.3
            edge.append((x, y, c if dark(c) else outline_of(c)))
for x, y, c in edge: G[y][x] = c
res = Image.new('RGBA', (nw, nh), (0, 0, 0, 0)); rp = res.load()
for y in range(nh):
    for x in range(nw):
        if G[y][x] is not None: rp[x, y] = G[y][x] + (255,)
res.save(out)
json.dump(dict(box=list(box), sc=sc, pad=0), open(out + '.map.json', 'w'))
print(out, res.size, len(set(c[:3] for c in res.getdata() if c[3])), 'colors')
