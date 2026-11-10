"""縦長の目(参考のステッカーの目の作り)。顔の陰影は残して、目のドットだけ置き換える。
目 = 上にまぶたの影1列、その下に瞳 横2×縦3(上1段が濃い赤、下2段が赤)。外側の上にまつ毛1ドット
JSON: {"eyes":[[x,y],[x,y]], "iris":[r,g,b], "iris_dark":[r,g,b], "lid":[r,g,b], "mouth":[[x,y]], "mouth_color":[r,g,b]}"""
import sys, json
from PIL import Image
path, spec = sys.argv[1], json.load(open(sys.argv[2]))
import os
K = float(os.environ.get('K', '1'))
im = Image.open(path).convert('RGBA'); P = im.load()
iris, irisd, lid = (tuple(spec[k]) + (255,) for k in ('iris', 'iris_dark', 'lid'))
import colorsys
# "coords": "source" なら、座標は元のイラストのピクセル(ドット絵の .map.json で変換する)
if spec.get('coords') == 'source':
    mp = json.load(open(path + '.map.json')); bx, by, sc, pd = mp['box'][0], mp['box'][1], mp['sc'], mp.get('pad', 0)
    tr = lambda x, y: ((x - bx) * sc + pd, (y - by) * sc + pd)
    spec['eyes'] = [list(tr(x, y)) for x, y in spec['eyes']]
    spec['mouth'] = [list(tr(x, y)) for x, y in spec.get('mouth', [])]
    if 'face' in spec:
        cx, cy = tr(*spec['face']['center']); spec['face']['center'] = [cx, cy]
        spec['face']['r'] = [spec['face']['r'][0] * sc, spec['face']['r'][1] * sc]
    K = 1
# 顔の肌を塗り直す(肌が白っぽくて髪や服と同じ色にまとめられ、顔が消えたとき用)
if 'face' in spec:
    f = spec['face']; (cx, cy), (rx, ry) = f['center'], f['r']; sk = tuple(f['skin']) + (255,)
    for y in range(int(cy - ry) - 1, int(cy + ry) + 2):
        for x in range(int(cx - rx) - 1, int(cx + rx) + 2):
            if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1 and P[x, y][3]: P[x, y] = sk
    if 'chin' in f:          # あごの下のふち(影)
        ch = tuple(f['chin']) + (255,)
        for x in range(int(cx - rx * 0.7), int(cx + rx * 0.7) + 1): P[x, round(cy + ry)] = ch
def hsv(c): return colorsys.rgb_to_hsv(*[t / 255 for t in c[:3]])
# 顔のまわりに混ざった、白い服の影の色(うすいピンク灰)を肌の色に戻す
(ex0, ey0), (ex1, ey1) = [(round(x * K), round(y * K)) for x, y in spec['eyes']]
skin = P[(ex0 + ex1 + 2) // 2, ey0 + 2][:3] if 'skin' not in spec else tuple(spec['skin'])
for y in range(ey0 - 2, ey0 + 5):
    for x in range(ex0 - 3, ex1 + 5):
        c = P[x, y]
        if not c[3]: continue
        h, s_, v = hsv(c)
        pinkish = s_ < 0.3 and 0.6 < v < 0.95 and (h > 0.85 or h < 0.05)   # 白い服の影の色
        greyish = s_ < 0.14 and 0.4 < v < 0.9                              # 灰色
        if pinkish or greyish: P[x, y] = skin + (255,)
for k, (x, y) in enumerate(spec['eyes']):
    x, y = round(x * K), round(y * K)
    for i in range(2): P[x + i, y - 1] = lid
    P[x - 1 if k == 0 else x + 2, y - 1] = lid
    for j in range(3):
        for i in range(2): P[x + i, y + j] = irisd if j == 0 else iris
for (x, y) in spec.get('mouth', []): x, y = round(x * K), round(y * K); P[x, y] = tuple(spec['mouth_color']) + (255,)
im.save(path)
