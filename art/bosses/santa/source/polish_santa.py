"""サンタ娘の仕上げ(手直し)。
1. 線で囲まれた背景(santa_bgmask.png。prep_santa.py が作る)を透明にする"""
import sys, os, json
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
path = sys.argv[1]
im = Image.open(path).convert('RGBA'); W, H = im.size; P = im.load()
mp = json.load(open(path + '.map.json')); bx, by, sc, pd = mp['box'][0], mp['box'][1], mp['sc'], mp.get('pad', 0)
mask = Image.open(os.path.join(HERE, 'santa_bgmask.png')).convert('L'); M = mask.load(); mw, mh = mask.size
for y in range(H):
    for x in range(W):
        if not P[x, y][3]: continue
        x0, x1 = int((x - pd) / sc + bx), int((x + 1 - pd) / sc + bx); y0, y1 = int((y - pd) / sc + by), int((y + 1 - pd) / sc + by)
        n = t = 0
        for v in range(max(0, y0), min(mh, y1)):
            for u in range(max(0, x0), min(mw, x1)):
                t += 1; n += M[u, v] > 0
        if t and n * 2 >= t: P[x, y] = (0, 0, 0, 0)
im.save(path)

# ---- ここからは、ドット絵のマスの座標(高さ84で作ったときのマス)。Koshin の判断(2026-11-25): 杖が脚を横切ってごちゃつくので、杖を手の先で止める ----
import math
im = Image.open(path).convert('RGBA'); P = im.load()
RED, RED_D, WHITE, WHITE_D = (208, 54, 60, 255), (148, 30, 48, 255), (255, 250, 244, 255), (236, 204, 208, 255)
def seg_dist(x, y, a, b):
    (ax, ay), (bx_, by_) = a, b; dx, dy = bx_ - ax, by_ - ay; L2 = dx * dx + dy * dy
    t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L2))
    return math.hypot(x - (ax + t * dx), y - (ay + t * dy)), t * math.sqrt(L2)
def is_candy(c): return c[3] and (c[0] > 140 and c[1] < 110 or min(c[:3]) > 190) or (c[3] and max(c[:3]) < 110)   # 赤・白・線の暗い色
# 2. 杖: 手の先 2 マスより先(脚を横切って足元まで)を消す
CANE_A, CANE_B = (23.6, 58.0), (38.2, 71.2)
for y in range(56, 73):
    for x in range(20, 41):
        if not P[x, y][3]: continue
        d, _ = seg_dist(x + 0.5, y + 0.5, CANE_A, CANE_B)
        if d <= 2.6 and is_candy(P[x, y]): P[x, y] = (0, 0, 0, 0)
# 杖の先を丸く閉じる(白の先に赤い帯、いちばん先は濃い赤)
for (x, y), c in {(22, 56): WHITE, (23, 56): RED, (22, 57): RED, (23, 57): RED_D, (24, 57): (0, 0, 0, 0), (21, 57): WHITE_D, (24, 56): RED_D, (21, 58): (0, 0, 0, 0), (22, 58): (0, 0, 0, 0), (23, 58): (0, 0, 0, 0)}.items(): P[x, y] = c
# 3. 左脚(向かって左)を描き直す: すその下からブーツの上まで、赤と白のしま
LEG_A, LEG_B = (34.6, 54.5), (28.6, 67.6)
for y in range(56, 68):
    for x in range(24, 40):
        d, t = seg_dist(x + 0.5, y + 0.5, LEG_A, LEG_B)
        if d > 2.45: continue
        c = P[x, y]
        if c[3] and not is_candy(c): continue          # すそ・ブーツ・髪には手を付けない
        white = int(t / 2.3) % 2 == 1
        edge = d > 1.55
        P[x, y] = (WHITE_D if edge else WHITE) if white else (RED_D if edge else RED)
# 4. そで口の内側(暗い茶のかたまり)を、服の濃い赤にそろえる
for y in range(33, 38):
    for x in range(51, 55):
        c = P[x, y]
        if c[3] and max(c[:3]) < 200 and not (c[0] > 180 and c[1] < 90): P[x, y] = RED_D
im.save(path)
