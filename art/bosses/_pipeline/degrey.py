"""灰色のドットを消す。灰色(彩度が低い中くらいの明るさ)は、まわり5×5で一番多い灰色でない色にする。
黒い物(帯・下駄など、とても暗い色)と、白はそのまま。
使い方: python3 degrey.py 入力.png 出力.png"""
import sys, colorsys
from collections import Counter
from PIL import Image
im = Image.open(sys.argv[1]).convert('RGBA'); W, H = im.size; P = im.load()
def hsv(c): return colorsys.rgb_to_hsv(*[t / 255 for t in c[:3]])
def grey(c):
    h, s, v = hsv(c); return s < 0.16 and 0.45 < v < 0.9
for _ in range(3):
    ch = []
    for y in range(H):
        for x in range(W):
            c = P[x, y]
            if not c[3] or not grey(c): continue
            nb = [P[x + dx, y + dy][:3] for dx in range(-2, 3) for dy in range(-2, 3)
                  if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H and P[x + dx, y + dy][3] and not grey(P[x + dx, y + dy])]
            ch.append((x, y, Counter(nb).most_common(1)[0][0] if nb else (222, 196, 204)))
    for x, y, c in ch: P[x, y] = c + (255,)
# 白い面に混ざった茶色(肌の影として塗られた着物のしわ)を、白い服の影の色にする
WSH = (232, 208, 214)
def whiteish(c):
    h, s, v = hsv(c); return s < 0.16 and v > 0.8
for _ in range(2):
    ch = []
    for y in range(H):
        for x in range(W):
            c = P[x, y]
            if not c[3]: continue
            h, s, v = hsv(c)
            if not (0.0 <= h < 0.12 and s > 0.3 and v < 0.78): continue
            nb = [P[x + dx, y + dy] for dx in (-1, 0, 1) for dy in (-1, 0, 1) if (dx or dy) and 0 <= x + dx < W and 0 <= y + dy < H]
            if sum(1 for n in nb if n[3] and (whiteish(n) or n[:3] == WSH)) >= 3: ch.append((x, y))
    for x, y in ch: P[x, y] = WSH + (255,)
im.save(sys.argv[2])
n = sum(1 for y in range(H) for x in range(W) if P[x, y][3] and grey(P[x, y]))
print(sys.argv[2], 'grey left:', n)
