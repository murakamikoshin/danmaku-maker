"""クリスマスの自機 3 つ(そり・トナカイに乗ったサンタ・雪の結晶)を、元絵(source/。Canva で作った絵)からドット絵にする。
art/rewards の自機と同じ決まり: 32×32・透過・機首が上・3コマ(0→1→2→1 でループ)。本体は上の 28 段、下の 4 段は尾を引く光。
黒い枠は付けない(ドット化は art/mooks/xmas/make_mooks.py と同じやり方)。
使い方: python3 make_ships.py  →  <名前>/<名前>_0〜2.png と、確認用の _preview.png"""
import os, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', '..', 'mooks', 'xmas'))
import make_mooks as mm
BODY = 28
# (名前, 元絵, x の範囲, 尾の光の色 [濃い, 明るい], 横に広げる倍率)
SHIPS = [
    ('sleigh_xmas',    'xmas_ships_source.png',    (30, 380),   ((255, 200, 60), (255, 244, 170)), 1.0),
    ('reindeer_xmas',  'xmas_reindeer_source.png', (20, 790),   ((255, 210, 80), (255, 250, 200)), 1.45),
    ('snowflake_xmas', 'xmas_ships_source.png',    (830, 1240), ((90, 190, 255), (220, 245, 255)), 1.0),
]
# 尾の光: コマごとの (dx, 段, 明るいか)。段 0 が本体のすぐ下
TRAIL = [[(0, 0, 1)], [(0, 0, 1), (0, 1, 0)], [(0, 0, 1), (0, 1, 1), (0, 2, 0), (-1, 1, 0), (1, 1, 0)]]

def body(src, x0, x1, stretch):
    # 縦に長い絵(トナカイ)は、横に少し広げてからドットにする: 32 ドットでは細すぎて角も顔も消えるので
    mm.SIZE = BODY; mm.COLORS = 16
    if stretch != 1:
        src = src.resize((int(src.width * stretch), src.height), Image.LANCZOS); x0 = int(x0 * stretch); x1 = int(x1 * stretch)
    return mm.convert(src, x0, x1)

def main():
    rows = []
    for name, fn, (x0, x1), (c_dark, c_light), stretch in SHIPS:
        src = Image.open(os.path.join(HERE, 'source', fn)).convert('RGB')
        b = body(src, x0, x1, stretch)
        bb = b.getbbox(); b = b.crop(bb)
        os.makedirs(os.path.join(HERE, name), exist_ok=True); frames = []
        for f in range(3):
            im = Image.new('RGBA', (32, 32), (0, 0, 0, 0))
            ox = (32 - b.width) // 2; im.alpha_composite(b, (ox, BODY - b.height))
            px = im.load()
            # 尾の光は、本体の一番下の段にあるドットの、左はしと右はしの列から出す(1列しかなければ1本)
            low = max(y for y in range(32) for x in range(32) if px[x, y][3])
            xs = [x for x in range(32) if px[x, low][3] or px[x, low - 1][3]]
            for cx in sorted({xs[0], xs[-1]} if xs[-1] - xs[0] > 3 else {(xs[0] + xs[-1]) // 2}):
                # 本体の一番下の段のすぐ下から出す
                base = max((y for y in range(32) if px[cx, y][3]), default=BODY - 1) + 1
                for dx, dy, light in TRAIL[f]:
                    x, y = cx + dx, base + dy
                    if 0 <= x < 32 and 0 <= y < 32 and px[x, y][3] == 0: px[x, y] = (c_light if light else c_dark) + (255,)
            im.save(os.path.join(HERE, name, f'{name}_{f}.png')); frames.append(im)
        rows.append(frames)
    k = 8; pv = Image.new('RGBA', (3 * 3 * (32 * k + 8) + 8, 32 * k + 16), (24, 22, 40, 255))
    for i, frames in enumerate(rows):
        for f, im in enumerate(frames):
            pv.alpha_composite(im.resize((32 * k, 32 * k), Image.NEAREST), (8 + (i * 3 + f) * (32 * k + 8), 8))
    pv.save(os.path.join(HERE, '_preview.png'))

if __name__ == '__main__': main()
