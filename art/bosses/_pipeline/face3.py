"""ドット絵の目を1色に描き直す(座標はドット絵のマス)。顔の設定は JSON:
{"skin":[x,y], "eyes":[{"clear":[x0,y0,x1,y1], "lash":[x0,x1,y], "iris":[x0,y0,x1,y1]}, ...], "iris_color":[r,g,b]}"""
import sys, json
from PIL import Image
path, spec = sys.argv[1], json.load(open(sys.argv[2]))
im = Image.open(path).convert('RGBA'); P = im.load()
skin = P[tuple(spec['skin'])]; ic = tuple(spec['iris_color']) + (255,); lash = tuple(spec.get('lash_color', [60, 22, 28])) + (255,)
for e in spec['eyes']:
    x0, y0, x1, y1 = e['clear']
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1): P[x, y] = skin
    a, b, y = e['lash']
    for x in range(a, b + 1): P[x, y] = lash
    x0, y0, x1, y1 = e['iris']
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1): P[x, y] = ic
im.save(path)
