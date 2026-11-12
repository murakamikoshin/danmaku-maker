"""Canva の絵(dragon_source_raw.png)を、ドット化の元絵(dragon_source.png)に整える。使い方: python3 prep_source.py
1. 翼の先が絵の左右の端で切れていたので、左右に余白を足して翼の先を描き足す
2. 頭が小さくてドットにすると顔がつぶれるので、頭(角・首のトゲごと)を首の付け根を軸に大きくする(Koshin の指示「顔小さくない?」)"""
import os
from PIL import Image, ImageDraw
H = os.path.dirname(os.path.abspath(__file__))
raw = Image.open(os.path.join(H, 'dragon_source_raw.png')).convert('RGB'); w, h = raw.size
PAD, S = 18, 4          # 足す余白(片側)、描くときの倍率(あとで縮めて線をなめらかにする)
MEM, GOLD, GOLD_D, LINE = (107, 18, 18), (219, 153, 47), (150, 98, 20), (50, 6, 6)
big = Image.new('RGB', ((w + PAD * 2) * S, h * S), (255, 255, 255)); d = ImageDraw.Draw(big)
def wing(side):
    # 元絵の端(x=0)で切れている範囲: 上の骨 y=20〜27、まん中の骨 y=46〜51、膜の下の端 y=79
    X = lambda x: ((PAD - x) if side < 0 else (PAD + w - 1 + x)) * S     # x = 端から外へ何ドットか
    Y = lambda y: y * S
    tip = (X(16), Y(31))
    d.polygon([(X(-1), Y(20)), tip, (X(9), Y(52)), (X(4), Y(66)), (X(-1), Y(80))], fill=MEM)            # 膜
    d.line([(X(-1), Y(80)), (X(4), Y(66)), (X(9), Y(52)), tip], fill=LINE, width=S * 2, joint='curve')   # 膜の外のふち
    for y0, wd in ((23.5, 7), (48.5, 5)):                                                                # 骨(先へ行くほど細い)
        d.line([(X(-1), Y(y0)), tip], fill=LINE, width=S * (wd + 2))
        d.line([(X(-1), Y(y0)), tip], fill=GOLD, width=S * wd)
        d.line([(X(-1), Y(y0 + wd / 2 - 0.5)), tip], fill=GOLD_D, width=S)
wing(-1); wing(1)
out = big.resize((w + PAD * 2, h), Image.LANCZOS)
out.paste(raw, (PAD, 0))
# 2. 頭を大きくする
HEAD = [(100, 0), (133, 0), (138, 12), (142, 20), (140, 30), (128, 35), (105, 35), (93, 30), (92, 20), (97, 12)]   # 頭のまわり(余白を足したあとの座標)。首は入れない
PIV, K, TOP = (116, 35), 1.6, 22            # 軸(あごの下)、倍率、上に足す余白
W2, H2 = out.size
def white(c): return min(c) > 236 and max(c) - min(c) < 18
m = Image.new('L', (W2, H2), 0); ImageDraw.Draw(m).polygon(HEAD, fill=255)
op = out.load(); mp = m.load()
for y in range(H2):
    for x in range(W2):
        if mp[x, y] and white(op[x, y]): mp[x, y] = 0
head = out.copy(); head.putalpha(m)
canvas = Image.new('RGB', (W2, H2 + TOP), (255, 255, 255)); canvas.paste(out, (0, TOP))
ImageDraw.Draw(canvas).polygon([(x, y + TOP) for x, y in HEAD], fill=(255, 255, 255))      # 元の頭を消す
x0, y0, x1, y1 = m.getbbox(); hc = head.crop((x0, y0, x1, y1))
nw, nh = round(hc.width * K), round(hc.height * K); hb = hc.resize((nw, nh), Image.LANCZOS)
a = hb.split()[3].point(lambda v: 255 if v > 110 else 0); hb.putalpha(a)
px, py = round(PIV[0] - (PIV[0] - x0) * K), round(PIV[1] - (PIV[1] - y0) * K) + TOP
canvas.paste(hb, (px, py), hb)
canvas.save(os.path.join(H, 'dragon_source.png'))
