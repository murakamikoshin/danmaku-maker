"""サンタ娘の元絵の下ごしらえ(届いた絵 → santa_source.png と santa_bgmask.png)。
1. プレゼントの横の「!!」の記号を消す
2. 線で囲まれているが背景の白(杖・手・すそ・脚に囲まれた三角、そでと体のすき間)を santa_bgmask.png に書き出す。
   このキャラは白いファーが多いので、閉じた白を背景にする処理(hole_min)は切ってある。代わりに polish_santa.py がこの地図を見て透明にする
使い方: python3 prep_santa.py 届いた絵.png"""
import sys, os
from collections import deque
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
im = Image.open(sys.argv[1]).convert('RGB')
ImageDraw.Draw(im).rectangle([1000, 165, 1110, 285], fill=(255, 255, 255))
im.save(os.path.join(HERE, 'santa_source.png'))
w, h = im.size; p = im.load()
def white(c): return min(c) > 236 and max(c) - min(c) < 18
SEEDS = [(480, 850), (496, 720)]   # 元絵の座標: 杖と脚のあいだの三角、そでと体のすき間
mask = Image.new('L', (w, h), 0); m = mask.load()
for sx, sy in SEEDS:
    assert white(p[sx, sy]), (sx, sy, p[sx, sy])
    q = deque([(sx, sy)]); m[sx, sy] = 255
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            u, v = x + dx, y + dy
            if 0 <= u < w and 0 <= v < h and not m[u, v] and white(p[u, v]): m[u, v] = 255; q.append((u, v))
mask.save(os.path.join(HERE, 'santa_bgmask.png'))
