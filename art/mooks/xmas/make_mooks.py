"""クリスマスの雑魚 4 体(雪だるま・プレゼント箱・ジンジャーブレッドマン・鈴)を、元絵(source/xmas_mooks_source.png。Canva で作った4体並びの絵)からドット絵にする。
雑魚は画面で 18〜36pt と小さいので、24×24 ドットの1枚絵(動かない)。黒い枠は付けない(ふちは、その場所の色の濃い段)。
使い方: python3 make_mooks.py   →  snowman.png / giftbox.png / gingerbread.png / bell.png と、確認用の _preview.png"""
import os
from collections import Counter, deque
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
SIZE = 24
COLORS = 10
# 元絵の中の範囲(x0, x1)。並び順は、ゲームの見た目の番号の順(5, 6, 7, 8)
MOOKS = [('snowman', 113, 518), ('giftbox', 662, 1129), ('gingerbread', 1244, 1725), ('bell', 1841, 2307)]

def white(c): return min(c) > 236 and max(c) - min(c) < 18
def dark(c): return max(c) < 70

def convert(src, x0, x1):
    w, h = src.size; p = src.load()
    ys = [y for y in range(h) if any(not white(p[x, y]) for x in range(x0, x1, 2))]
    y0, y1 = ys[0], ys[-1] + 1
    crop = src.crop((x0 - 4, y0 - 4, x1 + 4, y1 + 4)); cw, ch = crop.size; q = crop.load()
    # 背景: 外から続いている白だけ(雪だるまの体・目の白は、線で囲まれているので残る)
    bg = [[False] * cw for _ in range(ch)]; dq = deque()
    for x in range(cw):
        for y in (0, ch - 1): dq.append((x, y))
    for y in range(ch):
        for x in (0, cw - 1): dq.append((x, y))
    while dq:
        x, y = dq.popleft()
        if not (0 <= x < cw and 0 <= y < ch) or bg[y][x] or not white(q[x, y]): continue
        bg[y][x] = True
        dq.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    # 色を少なくまとめる(線の黒は別に数える)
    pal = crop.quantize(colors=COLORS, method=Image.MEDIANCUT, dither=Image.NONE).convert('RGB'); pq = pal.load()
    side = max(cw, ch); cell = side / SIZE; ox = (side - cw) / 2; oy = (side - ch) / 2
    out = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0)); o = out.load()
    for cy in range(SIZE):
        for cx in range(SIZE):
            n = nbg = ndark = 0; cols = Counter()
            for sy in range(int(cy * cell - oy), int((cy + 1) * cell - oy)):
                for sx in range(int(cx * cell - ox), int((cx + 1) * cell - ox)):
                    if not (0 <= sx < cw and 0 <= sy < ch): n += 1; nbg += 1; continue
                    n += 1
                    if bg[sy][sx]: nbg += 1
                    elif dark(q[sx, sy]): ndark += 1
                    else: cols[pq[sx, sy]] += 1
            if n == 0 or nbg * 2 > n: continue
            body = n - nbg
            if cols and ndark < body * 0.62: o[cx, cy] = cols.most_common(1)[0][0] + (255,)
            else: o[cx, cy] = (40, 30, 44, 255)        # 目・口・鈴の切れ込みなど、中の黒
    # ふちに残った黒(輪郭線)は、となりの色の濃い段に置きかえる: 黒い枠にしない
    src_o = out.copy(); so = src_o.load()
    for y in range(SIZE):
        for x in range(SIZE):
            if so[x, y][3] == 0 or so[x, y][:3] != (40, 30, 44): continue
            nb = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            edge = any(not (0 <= u < SIZE and 0 <= v < SIZE) or so[u, v][3] == 0 for u, v in nb)
            if not edge: continue
            near = Counter(so[u, v][:3] for u, v in nb if 0 <= u < SIZE and 0 <= v < SIZE and so[u, v][3] and so[u, v][:3] != (40, 30, 44))
            if near:
                r, g, b = near.most_common(1)[0][0]; o[x, y] = (int(r * 0.62), int(g * 0.6), int(b * 0.66), 255)
    return out

def main():
    src = Image.open(os.path.join(HERE, 'source', 'xmas_mooks_source.png')).convert('RGB')
    ims = []
    for name, x0, x1 in MOOKS:
        im = convert(src, x0, x1); im.save(os.path.join(HERE, name + '.png')); ims.append(im)
    # 確認用: 拡大(12倍)と、ゲームでの大きさ(小 18pt・中 26pt・大 36pt を 3 倍の画素で)
    k = 12; W = len(ims) * (SIZE * k + 20) + 20
    pv = Image.new('RGBA', (W, SIZE * k + 40 + 130), (24, 22, 40, 255))
    for i, im in enumerate(ims):
        x = 20 + i * (SIZE * k + 20)
        pv.alpha_composite(im.resize((SIZE * k, SIZE * k), Image.NEAREST), (x, 20))
        xx = x
        for pt in (18, 26, 36):
            s = pt * 3; pv.alpha_composite(im.resize((s, s), Image.NEAREST), (xx, SIZE * k + 40 + (108 - s))); xx += s + 14
    pv.save(os.path.join(HERE, '_preview.png'))

if __name__ == '__main__': main()
