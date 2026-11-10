"""ひれの仕上げ(手直し)。座標はドット絵のマス"""
import sys, colorsys, math
from PIL import Image
import os
K = float(os.environ.get('K', '1'))
im = Image.open(sys.argv[1]).convert('RGBA'); W, H = im.size; P = im.load()
def hsv(c): return colorsys.rgb_to_hsv(*[t / 255 for t in c[:3]])
def put(x, y, c):
    x, y = int(x), int(y)
    if 0 <= x < W and 0 <= y < H: P[x, y] = c + (255,)
def filled(x, y): return 0 <= x < W and 0 <= y < H and P[x, y][3] > 0
WHITE_SH = (222, 196, 204); OUT_W = (214, 170, 180)
# 1. ポイ: 白いかたまりを消して、輪と柄を描き直す
for y in range(round(7*K), round(23*K)):
    for x in range(round(5*K), round(20*K)):
        c = P[x, y]
        if c[3] and hsv(c)[1] < 0.2 and hsv(c)[2] > 0.7: P[x, y] = (0, 0, 0, 0)
cx, cy, r = 12.5 * K, 13.5 * K, round(5 * K)
RIM, RIMD, PAPER, PAPER2 = (110, 186, 240), (60, 112, 182), (238, 248, 255), (200, 226, 248)
for y in range(round(7*K), round(21*K)):
    for x in range(round(5*K), round(21*K)):
        d = math.hypot(x - cx, y - cy)
        if d <= r - 1: put(x, y, PAPER if (x + y) % 7 else PAPER2)
        elif d <= r: put(x, y, RIM)
        elif d <= r + 0.9: put(x, y, RIMD)
put(round(10*K), round(11*K), (255, 255, 255)); put(round(11*K), round(11*K), (255, 255, 255))
for i in range(7):                      # 柄(ポイの下から手へ)
    x, y = 16 * K + i * 0.5, round(18 * K) + i
    put(round(x), y, (244, 176, 64)); put(round(x) + 1, y, (200, 120, 40))
# 2. 髪のつや(上のほうに明るい帯を1列)
HAIR = None
for x in range(round(26*K), round(44*K)):
    for y in range(round(6*K), round(12*K)):
        c = P[x, y]
        if c[3] and 0.03 < hsv(c)[0] < 0.1 and hsv(c)[1] > 0.7:
            if HAIR is None: HAIR = c[:3]
            if y == round(8*K) + round(1.5 * math.sin((x - 26*K) / (17*K) * math.pi) * -1) and (x % 5) != 0: put(x, y, (255, 168, 92))
# 3. 帯に金の線
yo = round(39*K)
for x in range(round(28*K), round(41*K)):
    if P[x, yo][3] and hsv(P[x, yo])[2] < 0.4: put(x, yo, (232, 172, 70))
# 4. 袖のしわ(白い面の中に影の線)
for (x0, y0, x1, y1) in ((21, 33, 24, 45), (25, 31, 27, 37), (45, 37, 47, 47)):
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        x = round((x0 + (x1 - x0) * i / n) * K); y = round((y0 + (y1 - y0) * i / n) * K)
        c = P[x, y]
        if c[3] and hsv(c)[1] < 0.2 and hsv(c)[2] > 0.85: put(x, y, WHITE_SH)
# 5. ふちのギザギザ: へこみ(まわり3方向が埋まった空き)を埋め、飛び出た1ドットを消す
for _ in range(2):
    add, rem = [], []
    for y in range(H):
        for x in range(W):
            n4 = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            k = sum(filled(a, b) for a, b in n4)
            if not P[x, y][3] and k >= 3:
                cs = [P[a, b][:3] for a, b in n4 if filled(a, b)]
                add.append((x, y, max(set(cs), key=cs.count)))
            elif P[x, y][3] and k <= 1: rem.append((x, y))
    for x, y, c in add: put(x, y, c)
    for x, y in rem: P[x, y] = (0, 0, 0, 0)
im.save(sys.argv[2])
