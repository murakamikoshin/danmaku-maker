"""イラスト → ドット絵(決まった色の表を使う版)。pixel4 + material + degrey の代わり。
黒が多くて細い金の線がある絵(堕天使など)は、平均を取ると色が濁るので、こちらを使う。
- 元絵の1ドットごとに「どの素材の何段目か」を、色の表のいちばん近い見本で決める
- ドット絵の1マスは、そのマスに入る元絵のドットの多数決(素材ごとの重み付き。細い金の線や光る球を残しやすくする)
- 散った点を、まわりの多数決で1回ならす
- いちばん外の1ドットは、その素材の濃い段にする(黒い線は使わない)
設定(source/<ID>_settings.json の "palette"):
  {"素材名": {"tones": [[ふつう], [暗い(ふちにも使う)], [明るい]], "anchors": [[元絵の色 r,g,b, 段の番号], ...], "weight": 1.0, "edge": ふちに使う段(書かなければ1)}, ...、"_fringe": [にじみが化けやすい素材]}
使い方: python3 pixel_pal.py 元画像 出力.png 高さ 設定.json"""
import sys, json
from collections import deque, Counter, defaultdict
from PIL import Image
src, out, TH, cfgp = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4]
PAL = json.load(open(cfgp))['palette']
FRINGE = PAL.pop('_fringe', None)
im = Image.open(src).convert('RGB'); w, h = im.size; p = im.load()
def white(c): return min(c) > 236 and max(c) - min(c) < 18
bg = bytearray(w * h); q = deque()
for x in range(w): q.extend(((x, 0), (x, h - 1)))
for y in range(h): q.extend(((0, y), (w - 1, y)))
while q:
    x, y = q.popleft()
    if not (0 <= x < w and 0 <= y < h) or bg[y * w + x] or not white(p[x, y]): continue
    bg[y * w + x] = 1; q.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
# 輪っかの内側など、まわりから閉じた白い所も背景にする(大きい白の塊だけ。髪の小さな光は残す)
seen = bytearray(w * h)
for y0 in range(h):
    for x0 in range(w):
        i0 = y0 * w + x0
        if bg[i0] or seen[i0] or not (min(p[x0, y0]) > 244 and max(p[x0, y0]) - min(p[x0, y0]) < 10): continue
        comp = []; st = [(x0, y0)]; seen[i0] = 1
        while st:
            x, y = st.pop(); comp.append((x, y))
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                u, v = x + dx, y + dy
                if 0 <= u < w and 0 <= v < h and not seen[v * w + u] and not bg[v * w + u] and min(p[u, v]) > 244 and max(p[u, v]) - min(p[u, v]) < 10:
                    seen[v * w + u] = 1; st.append((u, v))
        if len(comp) >= 60:
            for x, y in comp: bg[y * w + x] = 1
xs = [x for y in range(h) for x in range(w) if not bg[y * w + x]]; ys = [y for y in range(h) for x in range(w) if not bg[y * w + x]]
box = (min(xs), min(ys), max(xs) + 1, max(ys) + 1)
sc = TH / (box[3] - box[1]); nw = max(1, round((box[2] - box[0]) * sc)); nh = TH
anchors = [(tuple(a[:3]), m, a[3]) for m, d in PAL.items() for a in d['anchors']]
def classify(c):
    return min(anchors, key=lambda a: sum((u - v) ** 2 for u, v in zip(a[0], c)))[1:]
lab = [[None] * nw for _ in range(nh)]
for gy in range(nh):
    for gx in range(nw):
        x0 = box[0] + gx / sc; x1 = box[0] + (gx + 1) / sc; y0 = box[1] + gy / sc; y1 = box[1] + (gy + 1) / sc
        votes = defaultdict(float); tones = defaultdict(Counter); n = inside = 0
        for y in range(int(y0), max(int(y0) + 1, int(y1 + 0.999))):
            for x in range(int(x0), max(int(x0) + 1, int(x1 + 0.999))):
                if not (0 <= x < w and 0 <= y < h): continue
                n += 1
                if bg[y * w + x]: continue
                inside += 1; m, t = classify(p[x, y]); votes[m] += PAL[m].get('weight', 1.0); tones[m][t] += 1
        if n == 0 or inside * 2 < n: continue
        m = max(votes, key=votes.get); lab[gy][gx] = (m, tones[m].most_common(1)[0][0])
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1)); N8 = N4 + ((1, 1), (-1, 1), (1, -1), (-1, -1))
def at(x, y): return lab[y][x] if 0 <= x < nw and 0 <= y < nh else None
# 散った点をならす(となり8マスのうち、同じ素材が1つもなく、ほかの素材が5つ以上なら、その素材にする)
new = [r[:] for r in lab]
for y in range(nh):
    for x in range(nw):
        c = lab[y][x]
        if c is None: continue
        ns = [at(x + dx, y + dy) for dx, dy in N8]; ns = [k for k in ns if k is not None]
        if not any(k[0] == c[0] for k in ns) and ns:
            m, cnt = Counter(k[0] for k in ns).most_common(1)[0]
            if cnt >= 5: new[y][x] = Counter(k for k in ns if k[0] == m).most_common(1)[0][0]
lab = new
# 背景とのさかい目のにじみ(白と黒が混ざった灰色など)が、別の素材(髪など)に化けたものを、となりの素材に直す
FR = set(FRINGE or [])
for _ in range(2):
    new = [r[:] for r in lab]
    for y in range(nh):
        for x in range(nw):
            c = lab[y][x]
            if c is None or c[0] not in FR or not any(at(x + dx, y + dy) is None for dx, dy in N8): continue
            ns = [at(x + dx, y + dy) for dx, dy in N8]; same = sum(1 for k in ns if k and k[0] == c[0])
            other = [k for k in ns if k and k[0] != c[0]]
            if other and len(other) >= same: new[y][x] = Counter(other).most_common(1)[0][0]
    lab = new
# 浮いた1ドットを消す
for y in range(nh):
    for x in range(nw):
        if lab[y][x] is not None and sum(1 for dx, dy in N4 if at(x + dx, y + dy) is not None) <= 1: lab[y][x] = None
# いちばん外の1ドットは、その素材の暗い段(tones の2つ目)にする
edge = [(x, y) for y in range(nh) for x in range(nw) if lab[y][x] is not None and any(at(x + dx, y + dy) is None for dx, dy in N4)]
for x, y in edge:
    m, t = lab[y][x]; lab[y][x] = (m, PAL[m].get('edge', 1 if len(PAL[m]['tones']) > 1 else 0))
res = Image.new('RGBA', (nw, nh), (0, 0, 0, 0)); rp = res.load()
for y in range(nh):
    for x in range(nw):
        if lab[y][x] is not None:
            m, t = lab[y][x]; rp[x, y] = tuple(PAL[m]['tones'][t]) + (255,)
res.save(out)
json.dump(dict(box=list(box), sc=sc, pad=0), open(out + '.map.json', 'w'))
print(out, res.size)
