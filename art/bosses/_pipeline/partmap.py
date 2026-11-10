"""部位の地図: 元のイラストの上で決めた部位の形(<ID>_parts.json)を、ドット絵のマスに重ねる。
出力: <ID>_partmap.png(1ドットごとに部位の番号。0=透明、1=体、2以降=parts の順) と <ID>_partmap_view.png(確認用の色分け)
使い方: python3 partmap.py ドット.png parts.json (ドット.png.map.json が必要)"""
import sys, json
from PIL import Image, ImageDraw
still, spec = sys.argv[1], json.load(open(sys.argv[2]))
mp = json.load(open(still + '.map.json')); im = Image.open(still).convert('RGBA'); W, H = im.size
bx, by, sc, pad = mp['box'][0], mp['box'][1], mp['sc'], mp.get('pad', 0)
lab = Image.new('L', (W, H), 0); L = lab.load(); A = im.load()
for y in range(H):
    for x in range(W):
        if A[x, y][3]: L[x, y] = 1
for i, p in enumerate(spec['parts']):
    m = Image.new('L', (W, H), 0)
    ImageDraw.Draw(m).polygon([((x - bx) * sc + pad, (y - by) * sc + pad) for x, y in p['poly']], fill=255)
    M = m.load()
    for y in range(H):
        for x in range(W):
            if M[x, y] and A[x, y][3]: L[x, y] = i + 2
base = still.rsplit('_still.png', 1)[0]
lab.save(base + '_partmap.png')
COL = [(0, 0, 0), (200, 200, 200), (60, 140, 255), (255, 200, 40), (255, 80, 200), (180, 80, 255), (80, 220, 120), (60, 220, 220), (255, 120, 60), (255, 60, 60), (140, 255, 60)]
v = Image.new('RGBA', (W, H), (0, 0, 0, 0)); V = v.load()
for y in range(H):
    for x in range(W):
        if L[x, y]: V[x, y] = COL[L[x, y] % len(COL)] + (255,)
v.save(base + '_partmap_view.png')
print('parts:', ', '.join(f"{i + 2}={p['name']}({p['kind']})" for i, p in enumerate(spec['parts'])))
