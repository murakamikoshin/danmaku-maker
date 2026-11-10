"""元のボスのドット絵(art/bosses/handoff/sheets)から、構え・技中・硬直・覚醒待機を描き足す共通処理。
ぼかしなし: 位置は整数ドット、色は置き換えだけ、透明度は 0 か 255 のみ。"""
from PIL import Image, ImageDraw
import colorsys, math, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # art/bosses
SHEETS = os.path.join(ROOT, 'handoff', 'sheets')
BG = (16, 12, 28)

# ---------- 読み込み ----------
def load(name, w=None):
    sh = Image.open(os.path.join(SHEETS, f'{name}_idle_sheet.png')).convert('RGBA')
    fw = sh.width // 8
    fr = [sh.crop((i * fw, 0, (i + 1) * fw, sh.height)) for i in range(8)]
    if w and w > fw:
        fr = [pad(f, w) for f in fr]
    return fr

def pad(img, w):
    o = Image.new('RGBA', (w, img.height), (0, 0, 0, 0)); o.paste(img, ((w - img.width) // 2, 0)); return o

def blank(img): return Image.new('RGBA', img.size, (0, 0, 0, 0))

# ---------- 形を動かす(整数ドットだけ) ----------
def offset(img, dx, dy):
    o = blank(img); o.paste(img, (dx, dy), img); return o

def shear(img, lean, pivot):
    """体を傾ける。pivot(足元の行)は動かさず、上に行くほど横へずらす。行ごとの整数ずらしなのでぼけない"""
    if lean == 0: return img.copy()
    o = blank(img)
    for y in range(img.height):
        dx = round(lean * max(0, pivot - y) / pivot) if pivot else 0
        row = img.crop((0, y, img.width, y + 1))
        o.paste(row, (dx, y), row)
    return o

def squash(img, n, pivot):
    """縮む(溜め)。足元(pivot)を固定して、上の部分の行を n 行ぶん間引く(最近傍)"""
    if n <= 0: return img.copy()
    o = blank(img)
    top = 0
    src_h = pivot - top; dst_h = src_h - n
    for yd in range(dst_h):
        ys = top + int(yd * src_h / dst_h)
        row = img.crop((0, ys, img.width, ys + 1))
        o.paste(row, (0, top + n + yd), row)
    below = img.crop((0, pivot, img.width, img.height)); o.paste(below, (0, pivot), below)
    return o

def bbox_bottom(img):
    b = img.getbbox(); return b[3] if b else img.height

# ---------- 色 ----------
def mapcolors(img, fn):
    o = img.copy(); p = o.load()
    cache = {}
    for y in range(o.height):
        for x in range(o.width):
            r, g, b, a = p[x, y]
            if a:
                k = (r, g, b)
                if k not in cache: cache[k] = tuple(int(max(0, min(255, v))) for v in fn(k))
                p[x, y] = cache[k] + (255,)
    return o

def mix(c, t, f): return tuple(c[i] + (t[i] - c[i]) * f for i in range(3))

def darken(img, f): return mapcolors(img, lambda c: mix(c, BG, f))
def brighten(img, f): return mapcolors(img, lambda c: mix(c, (255, 255, 255), f))

def awaken_colors(img, hue, sat=1.15, val=0.8, keep_light=0.86, thr=0.3):
    """覚醒の色: 色味の強い部分(羽根・尾・光)を hue(0〜1)へ寄せて暗めにする。
    肌は残し、白・灰色・黒は少しだけ色を差す(ベタ塗りにしない)"""
    def fn(c):
        h, s_, v = colorsys.rgb_to_hsv(*[x / 255 for x in c])
        skin = (h < 0.11 or h > 0.95) and 0.06 < s_ < 0.4 and v > 0.7
        if skin:
            return c
        if s_ >= thr:
            r, g, b = colorsys.hsv_to_rgb(hue, min(1, s_ * sat), v * val)
        else:
            r0, g0, b0 = colorsys.hsv_to_rgb(hue, 0.5, v)
            r, g, b = [(x * 0.8 + y * 0.2) * (0.92 if v < keep_light else 1) for x, y in zip((c[0]/255, c[1]/255, c[2]/255), (r0, g0, b0))]
        return (r * 255, g * 255, b * 255)
    return mapcolors(img, fn)

# ---------- 効果(光・粒・輪) ----------
def put(img, x, y, c):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < img.width and 0 <= y < img.height: img.putpixel((x, y), tuple(int(v) for v in c) + (255,))

def star(img, x, y, size, c_out, c_in, white=(255, 255, 255)):
    """光る核: 十字の光 + 真ん中を白く"""
    for k in range(1, size + 1):
        cc = c_out if k > size // 2 else c_in
        for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)): put(img, x + dx, y + dy, cc)
    if size >= 3:
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)): put(img, x + dx, y + dy, c_in)
    put(img, x, y, white)

def ring(img, x, y, r, c, gap=0):
    """1ドット幅の輪(gap>0 なら点線)"""
    n = max(8, int(2 * math.pi * r))
    for i in range(n):
        if gap and (i // gap) % 2: continue
        a = 2 * math.pi * i / n
        put(img, x + math.cos(a) * r, y + math.sin(a) * r, c)

def converge(img, x, y, r, n, phase, c1, c2):
    """溜め: まわりから粒が集まってくる"""
    for i in range(n):
        a = 2 * math.pi * i / n + phase
        px_, py_ = x + math.cos(a) * r, y + math.sin(a) * r
        put(img, px_, py_, c1 if i % 2 else c2)
        put(img, x + math.cos(a) * (r + 2), y + math.sin(a) * (r + 2), c1)

def burst(img, x, y, r0, r1, n, phase, c):
    """技: 核から放射する短い光の線"""
    for i in range(n):
        a = 2 * math.pi * i / n + phase
        for rr in range(int(r0), int(r1) + 1):
            put(img, x + math.cos(a) * rr, y + math.sin(a) * rr, c)

def aura(img, c, phase=0, every=1):
    """シルエットの外側1ドットに光のふち(覚醒)。phase で点滅させる"""
    a = img.split()[3]; W_, H_ = img.size; p = a.load()
    o = img.copy()
    for y in range(H_):
        for x in range(W_):
            if p[x, y]: continue
            near = any(0 <= x + dx < W_ and 0 <= y + dy < H_ and p[x + dx, y + dy] for dx, dy in ((1,0),(-1,0),(0,1),(0,-1)))
            if near and ((x + y + phase) % (every + 1) == 0):
                o.putpixel((x, y), c + (255,))
    return o

def rays_behind(img, cx, cy, r0, r1, n, phase, c1, c2):
    """体のうしろ(上半分の扇)に放射する光の線。長さをばらつかせ、先だけ明るい(堕天使の覚醒と同じ雰囲気)"""
    layer = blank(img)
    for i in range(n):
        a = math.radians(-200 + 220 * (i + phase) / n)
        L = r1 - (i * 7 % 6) * 2
        for rr in range(int(r0 + (i % 3) * 3), int(L) + 1):
            put(layer, cx + math.cos(a) * rr, cy + math.sin(a) * rr, c2 if rr > L - 4 else c1)
    layer.alpha_composite(img)
    return layer

# ---------- 書き出し ----------
STATES = [('idle', 8, '0→1→…→7 でループ'), ('windup', 4, '0→3 の順に1回'), ('attack', 4, '0→3 でループ'),
          ('recover', 2, '0→1 の順に1回(そのあと待機へ)'), ('idle_awakened', 8, '0→1→…→7 でループ'),
          ('windup_awakened', 4, '0→3 の順に1回(覚醒後)'), ('attack_awakened', 4, '0→3 でループ(覚醒後)'),
          ('recover_awakened', 2, '0→1 の順に1回(そのあと覚醒後の待機へ)')]

def export(boss_id, title, frames, note=''):
    out = os.path.join(ROOT, boss_id); os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        if f.endswith('.png') or f.endswith('.gif'): os.remove(os.path.join(out, f))
    size = None; allc = set()
    for st, n, _ in STATES:
        assert len(frames[st]) == n, (boss_id, st, len(frames[st]))
        for i, im in enumerate(frames[st]):
            if size is None: size = im.size
            assert im.size == size, (boss_id, st, i, im.size)
            al = {p[3] for p in im.getdata()}; assert al <= {0, 255}, (boss_id, st, i, al)
            allc |= {p[:3] for p in im.getdata() if p[3]}
            im.save(os.path.join(out, f'{boss_id}_{st}_{i}.png'))
        # 状態ごとのGIF(4倍・0.12秒/コマ)
        g = [Image.alpha_composite(Image.new('RGBA', size, BG + (255,)), im).resize((size[0] * 4, size[1] * 4), Image.NEAREST)
             for im in frames[st]]
        g = [x.convert('P', palette=Image.ADAPTIVE, colors=255) for x in g]
        g[0].save(os.path.join(out, f'{boss_id}_{st}.gif'), save_all=True, append_images=g[1:], duration=120, loop=0, disposal=2)
    # 一覧画像(4倍・暗い背景): 1行=1状態
    S = 4; cw, ch = size[0] * S, size[1] * S
    sheet = Image.new('RGBA', (cw * 8 + 9 * 8, (ch + 8) * len(STATES) + 8), BG + (255,))
    for r, (st, n, _) in enumerate(STATES):
        for i, im in enumerate(frames[st]):
            sheet.alpha_composite(im.resize((cw, ch), Image.NEAREST), (8 + i * (cw + 8), 8 + r * (ch + 8)))
    sheet.save(os.path.join(out, 'preview_sheet.png'))
    # README
    lines = [f'{title}({boss_id}) のドット絵', '',
             f'- 1コマの大きさ: 全コマ {size[0]}×{size[1]} ピクセル、背景は透明(PNG・RGBA、透明度は0か255だけ)',
             '- 向き: 正面(下向き)。体の中心は全コマ同じ位置。拡大は必ず最近傍補間(.nearest)',
             '- ファイル名: ' + f'{boss_id}_<状態>_<コマ番号>.png', '',
             '状態ごとのコマ数とループの順番:']
    for st, n, order in STATES: lines.append(f'- {st}: {n}コマ。{order}')
    lines += ['', '- 待機(idle)は元の絵(handoff/sheets)をそのまま1コマずつに分けたもの。〇〇_awakened は覚醒後の姿の同じ動き']
    if note: lines.append('- ' + note)
    lines += ['- 構え・技中・硬直では、体を少し傾けて真正面一辺倒にならないようにしている(行ごとの整数ずらしなので、ぼけない)',
              '- 再生の目安: 1コマ 0.12 秒(状態ごとのGIFと同じ)', '',
              f'使った色({len(allc)}色):']
    lines += ['  ' + ' '.join('#%02X%02X%02X' % c for c in sorted(allc)[i:i + 8]) for i in range(0, len(allc), 8)]
    lines += ['', f'描き直すとき: python3 make_{boss_id}.py(共通処理は ../tools/bosskit.py)']
    open(os.path.join(out, 'README.txt'), 'w').write('\n'.join(lines) + '\n')
    return size, len(allc)

def moved(x, y, sq, lean, piv, dx=0, dy=0):
    """squash → shear → offset したあとで、元の (x, y) がどこへ動いたか"""
    if sq and y < piv: y = sq + y * (piv - sq) / piv
    if lean and y < piv: x += round(lean * (piv - y) / piv)
    return x + dx, y + dy

# ---------- 標準の動き(各ボスの設定で呼ぶ) ----------
def standard(idle, cfg):
    """cfg: core=[(x,y),...] 効果の中心、c1/c2 効果の色、lean 傾ける向き(+1 右 / -1 左)、scale 効果の大きさ"""
    base = idle[0]; piv = bbox_bottom(base); L = cfg.get('lean', 1); s = cfg.get('scale', 1.0)
    c1, c2 = cfg['c1'], cfg['c2']; cores = cfg['core']
    out = {}
    # 構え: 縮む → 反対側へ振りかぶる → 震える。核に光が集まる
    w = []
    for f in range(4):
        im = squash(base, [0, 1, 2, 3][f], piv)
        im = shear(im, -L * [0, 1, 2, 3][f], piv)
        im = offset(im, [0, 0, 1, -1][f], 0)
        for (x0, y0) in cores:
            x, y = moved(x0, y0, [0, 1, 2, 3][f], -L * [0, 1, 2, 3][f], piv, [0, 0, 1, -1][f], 0)
            converge(im, x, y, [16, 12, 8, 5][f] * s, 8, f * 0.4, c1, c2)
            star(im, x, y, max(1, round([1, 2, 3, 4][f] * s)), c1, c2)
            if f >= 2: ring(im, x, y, [0, 0, 7, 4][f] * s, c2)
        w.append(im)
    out['windup'] = w
    # 技中: 前へ傾いて反動。核から光が放たれる(待機の絵を使うので羽根・尾も動き続ける)
    a = []
    for f in range(4):
        im = idle[[0, 2, 4, 6][f]]
        im = shear(im, L * [2, 3, 3, 2][f], piv)
        im = offset(im, 0, [0, -1, -1, 0][f])
        for (x0, y0) in cores:
            x, y = moved(x0, y0, 0, L * [2, 3, 3, 2][f], piv, 0, [0, -1, -1, 0][f])
            ring(im, x, y, ([4, 9, 14, 19][f]) * s, c1, gap=2 if f >= 2 else 0)
            burst(im, x, y, 3 * s, (6 + f % 2 * 2) * s, 8, f * math.pi / 8, c2)
            star(im, x, y, max(2, round((4 + f % 2) * s)), c1, c2)
        extra = cfg.get('attack_extra')
        if extra: extra(im, f, lambda x0, y0: moved(x0, y0, 0, L * [2, 3, 3, 2][f], piv, 0, [0, -1, -1, 0][f]))
        a.append(im)
    out['attack'] = a
    # 硬直: ぐったり下がって首をかしげる。全体が暗く、核の光が消える
    r = []
    for f in range(2):
        im = squash(base, [1, 2][f], piv)
        im = shear(im, L * [-1, -2][f], piv)
        im = offset(im, 0, [2, 3][f])
        im = darken(im, [0.3, 0.38][f])
        for (x0, y0) in cores:
            x, y = moved(x0, y0, [1, 2][f], L * [-1, -2][f], piv, 0, [2, 3][f])
            put(im, x, y, mix(c1, BG, 0.5))
        r.append(im)
    out['recover'] = r
    return out

def awake_states(frames, cfg):
    """覚醒後の構え・技中・硬直(覚醒後の待機の絵を土台にする)"""
    for k, v in standard(frames['idle_awakened'], cfg).items():
        frames[k + '_awakened'] = v

def awakened(idle, hue, ray1, ray2, aura_c, center, r0=30, r1=54, n=22, sat=1.15, val=0.8, thr=0.3):
    """覚醒後の待機: 色を変え、うしろに放射する光、体のふちに点滅する光"""
    out = []
    for i, f in enumerate(idle):
        im = awaken_colors(f, hue, sat=sat, val=val, thr=thr)
        im = rays_behind(im, center[0], center[1], r0, r1, n, (i % 8) / 8, ray1, ray2)
        im = aura(im, aura_c, phase=i % 3, every=2)
        out.append(im)
    return out

# ---------- イラストからドット化したボス(1枚の絵から待機8コマを作る) ----------
def from_still(path, size=(112, 112), foot=2):
    """1枚の絵を 112×112 の中央・足元をそろえて置く"""
    st = Image.open(path).convert('RGBA'); c = Image.new('RGBA', size, (0, 0, 0, 0))
    c.paste(st, ((size[0] - st.width) // 2, size[1] - st.height - foot), st)
    return c

def sway(img, phase, top, amp=1.5, freq=0.16):
    """すそ・ひれ・髪がゆれる: top より下の行を、下に行くほど大きく左右へずらす(整数ドット)"""
    o = blank(img)
    for y in range(img.height):
        row = img.crop((0, y, img.width, y + 1))
        dx = 0
        if y > top:
            k = (y - top) / max(1, img.height - top)
            dx = round(amp * k * math.sin(phase + y * freq))
        o.paste(row, (dx, y), row)
    return o

def idle_from_still(base, top, bubbles=(), amp=1.5, c1=(150, 214, 250), c2=(255, 255, 255)):
    """待機8コマ: ゆれ + まわりで小さな粒がのぼる"""
    out = []
    for i in range(8):
        ph = i / 8 * 2 * math.pi
        im = sway(base, ph, top, amp)
        for k, (x, y, r) in enumerate(bubbles):
            yy = y - ((i + k * 3) % 8) * 2
            if r > 1: ring(im, x, yy, r, c1)
            put(im, x - (r > 1), yy - (r > 1), c2)
        out.append(im)
    return out

def sway_region(img, phase, top, region, amp=1.5, freq=0.16):
    """region(x, y) が True のドットだけをゆらす(体・脚は動かさない)。下に行くほど大きく、整数ドットで左右へ"""
    o = img.copy(); P = img.load(); O = o.load(); W_, H_ = img.size
    moved = []
    for y in range(top, H_):
        k = (y - top) / max(1, H_ - top); dx = round(amp * k * math.sin(phase + y * freq))
        if not dx: continue
        for x in range(W_):
            if P[x, y][3] and region(x, y):
                moved.append((x + dx, y, P[x, y])); O[x, y] = (0, 0, 0, 0)
    for x, y, c in moved:
        if 0 <= x < W_: O[x, y] = c
    return o

def idle_parts(base, top, region, bubbles=(), amp=1.5, c1=(150, 214, 250), c2=(255, 255, 255)):
    """待機8コマ: 決めた部分(ひれ・リボンなど)だけゆれる + まわりで小さな粒がのぼる"""
    out = []
    for i in range(8):
        ph = i / 8 * 2 * math.pi
        im = sway_region(base, ph, top, region, amp)
        for k, (x, y, r) in enumerate(bubbles):
            yy = y - ((i + k * 3) % 8) * 2
            if r > 1: ring(im, x, yy, r, c1)
            put(im, x - (r > 1), yy - (r > 1), c2)
        out.append(im)
    return out

def move_parts(img, parts):
    """決めた四角の中のドットを、それぞれ (dx, dy) だけ動かす。parts: [((x0, y0, x1, y1), dx, dy), ...]
    先に全部消してから置くので、部品どうしが重なっても形は崩れない"""
    o = img.copy(); P = img.load(); O = o.load(); W_, H_ = img.size
    moved = []
    for (x0, y0, x1, y1), dx, dy in parts:
        if not (dx or dy): continue
        for y in range(max(0, y0), min(H_, y1 + 1)):
            for x in range(max(0, x0), min(W_, x1 + 1)):
                if P[x, y][3]: moved.append((x + dx, y + dy, P[x, y])); O[x, y] = (0, 0, 0, 0)
    for x, y, c in moved:
        if 0 <= x < W_ and 0 <= y < H_: O[x, y] = c
    return o

def idle_rig(base, top, fins, parts, breathe=1, bubbles=(), amp=2.5, c1=(150, 214, 250), c2=(255, 255, 255)):
    """待機8コマ: ひれのゆれ + 部品(リボン・持ち物など)の動き + 全体の呼吸 + 粒。体と脚の形は変えない
    parts: [((x0, y0, x1, y1), ax, ay, 位相のずれ[, すき間を埋めるか]), ...]  ax, ay はゆれ幅(ドット)
    すき間を埋めるか: 体にくっついた部品は True(省略時)、手の上に浮いている物などは False"""
    out = []
    for i in range(8):
        ph = i / 8 * 2 * math.pi
        im = fill_gaps(sway_region(base, ph, top, fins, amp), base)
        # 体にくっついた部品(リボンなど)は、動いたあとのすき間を埋める。浮いている物(金魚など)は埋めない(影が残るので)
        def mv(p): return (p[0], round(p[1] * math.sin(ph + p[3])), round(p[2] * math.sin(ph + p[3])))
        stuck = [mv(p) for p in parts if (p[4] if len(p) > 4 else True)]
        floating = [mv(p) for p in parts if not (p[4] if len(p) > 4 else True)]
        before = im.copy(); im = fill_gaps(move_parts(im, stuck), before)
        im = move_parts(im, floating)
        if breathe: im = offset(im, 0, -1 if math.sin(ph) > 0.35 else 0)
        for k, (x, y, r) in enumerate(bubbles):
            yy = y - ((i + k * 3) % 8) * 2
            if r > 1: ring(im, x, yy, r, c1)
            put(im, x - (r > 1), yy - (r > 1), c2)
        out.append(im)
    return out

def fill_gaps(im, base):
    """部品を動かしたあとのすき間を埋める: 元の絵では色があったのに透明になったドットを、となりの色で埋める"""
    from collections import Counter
    P = im.load(); Bp = base.load(); W_, H_ = im.size
    for _ in range(3):
        add = []
        for y in range(H_):
            for x in range(W_):
                if P[x, y][3] or not Bp[x, y][3]: continue
                nb = [P[x + dx, y + dy][:3] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if 0 <= x + dx < W_ and 0 <= y + dy < H_ and P[x + dx, y + dy][3]]
                if nb: add.append((x, y, Counter(nb).most_common(1)[0][0]))
        for x, y, c in add: P[x, y] = c + (255,)
    return im

def count_gaps(im, base):
    P = im.load(); Bp = base.load(); W_, H_ = im.size
    return sum(1 for y in range(H_) for x in range(W_) if Bp[x, y][3] and not P[x, y][3])
