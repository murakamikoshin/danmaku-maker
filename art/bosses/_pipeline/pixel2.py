"""イラスト → 点の少ないドット絵(平たい塗り)。
1. 白い背景を抜く  2. 元の大きさのまま少ない色に減色  3. 1マスごとに「一番多い色」を置く(線が通るマスは輪郭の色)
4. 浮いた1ドットを消す  5. 外側に1ドットの輪郭
使い方: python3 pixel2.py 元画像 出力.png 高さ 色数"""
import sys, colorsys, json
from collections import deque, Counter
from PIL import Image
src, out, TH, NC = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
im = Image.open(src).convert('RGB'); w, h = im.size
# 元が小さいときは先に4倍(最近傍)にして、マスの切り方を細かくする
UP = 4; im = im.resize((w * UP, h * UP), Image.LANCZOS); w, h = im.size; p = im.load()
def white(c): return min(c) > 228 and max(c) - min(c) < 24
bg = bytearray(w * h); q = deque()
for x in range(w): q.extend(((x, 0), (x, h - 1)))
for y in range(h): q.extend(((0, y), (w - 1, y)))
while q:
    x, y = q.popleft()
    if not (0 <= x < w and 0 <= y < h) or bg[y * w + x] or not white(p[x, y]): continue
    bg[y * w + x] = 1; q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
mask = Image.frombytes('L', (w, h), bytes(0 if v else 255 for v in bg))
box = mask.getbbox(); im = im.crop(box); mask = mask.crop(box); w, h = im.size
# 線(暗い・彩度が低めの所)
def is_line(c):
    hh, s, v = colorsys.rgb_to_hsv(*[t / 255 for t in c]); return v < 0.42
# 減色(色だけの面を代表する色を選ぶため、線と背景は除いて作る)
qimg = im.quantize(colors=NC, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
pal = qimg.getpalette()[:NC * 3]; PAL = [tuple(pal[i * 3:i * 3 + 3]) for i in range(NC)]
qp = qimg.load(); ip = im.load(); mp = mask.load()
sc = TH / h; nw = max(1, round(w * sc)); nh = TH
cell_w, cell_h = w / nw, h / nh
res = [[None] * nw for _ in range(nh)]
for j in range(nh):
    for i in range(nw):
        x0, x1 = int(i * cell_w), max(int(i * cell_w) + 1, int((i + 1) * cell_w)); y0, y1 = int(j * cell_h), max(int(j * cell_h) + 1, int((j + 1) * cell_h))
        cnt = Counter(); lines = 0; inside = 0; tot = 0
        for y in range(y0, y1, 2):
            for x in range(x0, x1, 2):
                tot += 1
                if not mp[x, y]: continue
                inside += 1
                if is_line(ip[x, y]): lines += 1
                else: cnt[qp[x, y]] += 1
        if inside < tot * 0.45: continue
        if lines > inside * 0.28 or not cnt: res[j][i] = 'L'
        else: res[j][i] = PAL[cnt.most_common(1)[0][0]]
# 浮いた点を消す(上下左右のうち3つ以上が同じ色なら、それに合わせる)
for _ in range(2):
    for j in range(1, nh - 1):
        for i in range(1, nw - 1):
            c = res[j][i]
            if c is None: continue
            nb = [res[j + dy][i + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            cc = Counter(n for n in nb if n is not None)
            if cc and cc.most_common(1)[0][1] >= 3 and c not in nb: res[j][i] = cc.most_common(1)[0][0]
            if sum(n is None for n in nb) >= 3: res[j][i] = None
pad = 1; W_, H_ = nw + pad * 2, nh + pad * 2
o = Image.new('RGBA', (W_, H_), (0, 0, 0, 0)); op = o.load()
def darker(c, f=0.36, hs=0.03):
    hh, s, v = colorsys.rgb_to_hsv(*[t / 255 for t in c]); r, g, b = colorsys.hsv_to_rgb((hh + hs) % 1, min(1, s + 0.25), v * f); return (int(r * 255), int(g * 255), int(b * 255))
for j in range(nh):
    for i in range(nw):
        c = res[j][i]
        if c is None: continue
        if c == 'L':   # 線: となりの色を暗くした色(黒一色にしない)
            nb = [res[j + dy][i + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= j + dy < nh and 0 <= i + dx < nw and res[j + dy][i + dx] not in (None, 'L')]
            c = darker(Counter(nb).most_common(1)[0][0]) if nb else (60, 30, 40)
        op[i + pad, j + pad] = c + (255,)
edge = []
for y in range(H_):
    for x in range(W_):
        if op[x, y][3]: continue
        nb = [op[x + dx, y + dy] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < W_ and 0 <= y + dy < H_ and op[x + dx, y + dy][3]]
        if nb: edge.append((x, y, darker(nb[0][:3], 0.3) + (255,)))
for x, y, c in edge: op[x, y] = c
o.save(out)
json.dump(dict(box=[b / UP for b in box], sc=sc * UP, pad=pad), open(out + '.map.json', 'w'))
print(out, o.size, len({c[:3] for c in o.getdata() if c[3]}), 'colors')
