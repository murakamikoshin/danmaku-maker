import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 最強のドラゴン(怪獣 + ドラゴン、赤と金)。元のイラスト(source/dragon_source.png。Canva の絵を source/prep_source.py で整えたもの)を、
# 色の表を使う版(pixel_pal.py)でドット化し、顔は source/polish_dragon.py で描き直している。
# ほかのボスより大きく(1コマ 168×128)、コマ数も3倍(待機24・構え12・技中12・硬直6、1コマ 0.04 秒)。Koshin の指示「めっちゃぬるぬる動くように」。
# ぬるぬる動かすために、部位をまるごと動かす共通の処理(idle_parts_map)ではなく、専用の処理を使う:
#   翼と尻尾は「列ごと」に上下へずらす(付け根は動かず、先へ行くほど大きく・遅れて動く)。となりの列との差は1ドットまでなので、穴があかない
#   頭は上へ少し動く(下の首はそのまま残すので、すき間ができない)。体全体は羽ばたきに合わせて上下に浮く
ID = 'dragon'
SIZE = (168, 128); FOOT = 6
COUNTS = dict(idle=24, windup=12, attack=12, recover=6); FRAME_MS = 40
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=FOOT, size=SIZE)
W_, H_ = SIZE; B = base.load(); Lb = lab.load()
PID = {n: p['id'] for n, p in parts.items()}
OX, OY = (W_ - Image.open(still).width) // 2, H_ - Image.open(still).height - FOOT     # ドット絵 → 1コマの中の位置
MEM = (128, 16, 28)                         # 翼の膜の色
DARKS = {(128, 16, 28), (92, 10, 24), (70, 6, 22)}
MOUTH = (83, 45); CHEST = (83, 62); HANDS = [(44, 72), (123, 72)]; WTIPS = [(7, 43), (160, 43)]

# ---------- 部位を層に分ける ----------
# 手の多角形は大まかなので、その中の「膜の色で、翼につながっているドット」は翼に戻す
def refine(wing, hand):
    todo = [(x, y) for y in range(H_) for x in range(W_) if Lb[x, y] == wing]
    seen = set(todo)
    while todo:
        x, y = todo.pop()
        for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + a, y + b)
            if q in seen or not (0 <= q[0] < W_ and 0 <= q[1] < H_): continue
            if Lb[q] == hand and B[q][3] and B[q][:3] in DARKS and B[q][:3] != (70, 6, 22):
                seen.add(q); Lb[q] = wing; todo.append(q)
refine(PID['wing_l'], PID['hand_l']); refine(PID['wing_r'], PID['hand_r'])

def columns(pid, occluder=None):
    """部位を列ごとに取り出す: {x: [(y, 色), ...]}。occluder(手)の後ろに隠れている所は膜の色で補う"""
    cols = {}
    for x in range(W_):
        ys = [y for y in range(H_) if Lb[x, y] == pid]
        if not ys: continue
        col = {y: B[x, y][:3] for y in ys}
        if occluder:
            lo, hi = min(ys), max(ys)
            for y in range(lo, min(H_, hi + 9)):
                if y not in col and Lb[x, y] in occluder and (y < hi or y <= hi + 8): col[y] = MEM
        cols[x] = sorted(col.items())
    return cols
WING_L = columns(PID['wing_l'], (PID['hand_l'], 1)); WING_R = columns(PID['wing_r'], (PID['hand_r'], 1))
TAIL = columns(PID['tail'])
ROOT_L, ROOT_R = max(WING_L), min(WING_R); TIP_L, TIP_R = min(WING_L), max(WING_R)
TAIL_X0, TAIL_X1 = min(TAIL), max(TAIL)
HEAD_KEEP = OY + 31                         # これより下の頭(あご・首のトゲ)は、下の層にも残す(頭が上がったときのすき間をふさぐ)
under = base.copy(); U = under.load()
head = blank(base); Hd = head.load()
for y in range(H_):
    for x in range(W_):
        p = Lb[x, y]
        if p in (PID['wing_l'], PID['wing_r'], PID['tail']): U[x, y] = (0, 0, 0, 0)
        elif p == PID['head']:
            Hd[x, y] = B[x, y]
            if y < HEAD_KEEP: U[x, y] = (0, 0, 0, 0)

# 口を開けた頭(技中): 顔の左半分(ドット絵の x=66〜76)を文字の絵で書いて、左右対称に置く
FCOL = {'G': (232, 172, 56), 'g': (172, 112, 32), 'Y': (255, 224, 124), 'R': (190, 34, 32), 'r': (128, 16, 28),
        'S': (70, 6, 22), 'T': (255, 244, 224), 'F': (255, 150, 40), 'W': (255, 240, 190)}
OPEN = ["...rSTSTSTS",      # 上の牙
        "...rSSSFFFF",      # 口の中で燃える火
        "...rSSFFWWW",
        "...rSSSFFFF",
        "...rrTSTSTS",      # 下の牙
        "...rrgggGGG",      # 下あご(3ドット下がる)
        "....rrgGGGY",
        ".....rrgGGG",
        "......rrggg"]
head_open = head.copy(); Ho = head_open.load()
for j, row in enumerate(OPEN):
    for i, ch in enumerate(row):
        if ch == '.': continue
        for x in (66 + i, 153 - (66 + i)): Ho[x + OX, 33 + j + OY] = FCOL[ch] + (255,)

# ---------- 1コマを組み立てる ----------
def shift_cols(img, cols, fn):
    P = img.load()
    for x, col in cols.items():
        dy = int(round(fn(x)))
        for y, c in col:
            if 0 <= y + dy < H_: P[x, y + dy] = c + (255,)

def wing_fn(root, tip, f):
    """f(d): 付け根からの遠さ d(0〜1)→ 上下のずれ(ドット)"""
    return lambda x: f(abs(x - root) / abs(tip - root))

def pose(wing, tail=lambda t: 0, head_d=(0, 0), mouth=False, bob=0):
    """wing(d) / tail(t): 付け根からの遠さ(0〜1)→ 上下のずれ。head_d: 頭のずれ(上へは何ドットでも、左右は1ドットまで)"""
    im = blank(base)
    shift_cols(im, WING_L, wing_fn(ROOT_L, TIP_L, wing)); shift_cols(im, WING_R, wing_fn(ROOT_R, TIP_R, wing))
    shift_cols(im, TAIL, lambda x: tail((x - TAIL_X0) / (TAIL_X1 - TAIL_X0)))
    im.alpha_composite(under)
    im.alpha_composite(offset(head_open if mouth else head, *head_d))
    seal(im)
    return offset(im, 0, bob) if bob else im

def slits(im):
    """透明な切れ込み: 上下か左右を色にはさまれた透明なドット"""
    P = im.load()
    return {(x, y) for y in range(1, H_ - 1) for x in range(1, W_ - 1) if not P[x, y][3]
            and ((P[x - 1, y][3] and P[x + 1, y][3]) or (P[x, y - 1][3] and P[x, y + 1][3]))}
BASE_SLITS = slits(base)
KEEP = {(x + a, y + b) for x, y in BASE_SLITS for a in (-1, 0, 1) for b in (-1, 0, 1)}   # 元の絵にあるすき間(爪のあいだなど)は残す
def seal(im):
    """列をずらしてできた1ドットの切れ込みを、となりの色でふさぐ(元の絵にあるすき間は残す)"""
    from collections import Counter
    P = im.load()
    for x, y in sorted(slits(im) - KEEP):
        nb = [P[x + a, y + b][:3] for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)) if P[x + a, y + b][3]]
        P[x, y] = Counter(nb).most_common(1)[0][0] + (255,)

def ease(t): return t * t * (3 - 2 * t)
def flap(ph, amp=5.6, lag=1.2, bias=0.0):
    return lambda d: (amp * math.sin(ph - lag * d) + bias) * d ** 1.5
def tailwave(ph, amp=3.2):
    return lambda t: amp * math.sin(ph - 1.6 * t) * t ** 1.4

def sparks(im, i, n, pts, c1, c2):
    """まわりで火の粉がのぼる"""
    for k, (x, y) in enumerate(pts):
        s = (i * 2 + k * 7) % (n * 2)
        if s < n * 2 - 6: put(im, x + round(1.5 * math.sin((i + k * 5) * 2 * math.pi / n)), y - s, c1 if (i + k) % 3 else c2)
SPARKS = [(14, 100), (30, 118), (58, 124), (112, 124), (140, 116), (156, 96), (8, 30), (160, 28)]

def idle_frames(n=24):
    out = []
    for i in range(n):
        ph = 2 * math.pi * i / n
        im = pose(flap(ph), tailwave(ph + 1.0), head_d=(0, -1 if math.sin(ph - 1.2) > 0.2 else 0),
                  bob=-round(1.6 * math.sin(ph - 0.9)))      # 翼を打ち下ろすと体が少し上がる
        sparks(im, i, n, SPARKS, (255, 150, 40), (255, 224, 124))
        out.append(im)
    return out

def recolor(im, table):
    return mapcolors(im, lambda c: table.get(c, c))

def states(idle, c1, c2, fire=None):
    """構え(12)・技中(12)・硬直(6)。idle は体の絵を作る関数の入力(色を変える前)"""
    out = {}; piv = bbox_bottom(base); n = len(idle)
    # 構え: 身を沈めて翼を高く振り上げ、頭を引いて息を吸う。口に光が集まり、最後は震える
    w = []
    for f in range(12):
        t = ease(f / 11); sq = round(3 * t); ln = -round(3 * t); dx = [0, 0, 0, 0, 0, 0, 0, 0, 1, -1, 1, -1][f]
        im = pose(lambda d: (-10 * t + 1.2 * math.sin(f * 1.3) * (f > 7)) * d ** 1.3, tailwave(f * 0.5, 2 + 2 * t), head_d=(0, -round(2 * t)))
        w.append((im, sq, ln, dx, 0, f))
    out['windup'] = w
    # 技中: 口を開けて吠える。翼を速く打ち下ろし(1ループで2回)、体が反動で震える
    a = []
    for f in range(12):
        ph = 2 * math.pi * f / 6
        im = pose(flap(ph, amp=6.5, lag=1.0, bias=1.5), tailwave(ph, 4.5), head_d=(0, -1 if f % 2 else 0), mouth=True)
        a.append((im, 0, [2, 3, 3, 2, 2, 3, 3, 2, 2, 3, 3, 2][f], 0, [0, -1, -1, 0, 0, -1, -2, -1, 0, -1, -1, 0][f], f))
    out['attack'] = a
    # 硬直: 翼がだらりと下がり、体が沈んで暗くなる
    r = []
    for f in range(6):
        t = ease((f + 1) / 6)
        im = pose(lambda d: (7 * t) * d ** 1.2, lambda u: 2.5 * t * u ** 1.4)
        r.append((im, round(2 * t), -round(2 * t), 0, round(3 * t), f))
    out['recover'] = r
    return out

def finish(raw, table, c1, c2):
    """色を変え(覚醒)、傾き・沈みをつけ、光の効果を足す"""
    res = {}
    piv = bbox_bottom(base)
    for st, lst in raw.items():
        fr = []
        for im, sq, ln, dx, dy, f in lst:
            if table: im = recolor(im, table)
            im = offset(shear(squash(im, sq, piv), ln, piv), dx, dy)
            mv = lambda x0, y0: moved(x0, y0, sq, ln, piv, dx, dy)
            mx, my = mv(*MOUTH)
            if st == 'windup':
                t = f / 11
                converge(im, mx, my, 26 - 20 * t, 10, f * 0.35, c1, c2)
                if f >= 3: converge(im, mx, my, 34 - 22 * t, 6, -f * 0.5, c2, c1)
                star(im, mx, my, max(1, round(1 + 4 * t)), c1, c2)
                if f >= 8: ring(im, mx, my, [9, 7, 5, 3][f - 8], c2)
            elif st == 'attack':
                ring(im, mx, my + 2, 5 + (f % 6) * 4, c1, gap=2 if f % 6 >= 3 else 0)
                ring(im, mx, my + 2, 5 + ((f + 3) % 6) * 4, c2, gap=2)
                burst(im, mx, my + 2, 5, 9 + f % 3 * 2, 10, f * math.pi / 12, c2)
                star(im, mx, my + 2, 4 + f % 2, c1, c2)
                for k, (hx, hy) in enumerate(HANDS + WTIPS):       # 爪と翼の先が順に光る
                    if (f + k * 3) % 6 < 2: x, y = mv(hx, hy); star(im, x, y, 2 + (k < 2), c1, c2)
            else:
                im = darken(im, 0.18 + 0.04 * f)
                put(im, mx, my + 1 - f, mix(c1, BG, 0.4)); put(im, mx + 2, my - 2 - f, mix(c1, BG, 0.6))   # 口から残り火
            fr.append(im)
        res[st] = fr
    return res

# 覚醒: 黒曜の体に蒼い炎。赤 → 黒紫、金 → 蒼白い光
AWAKE = {(190, 34, 32): (58, 48, 96), (128, 16, 28): (36, 30, 66), (236, 84, 52): (96, 88, 150),
         (92, 10, 24): (26, 22, 50), (70, 6, 22): (20, 16, 40),
         (232, 172, 56): (70, 190, 255), (172, 112, 32): (34, 110, 210), (255, 224, 124): (200, 244, 255),
         (255, 150, 40): (90, 210, 255), (255, 240, 190): (235, 252, 255), (255, 255, 236): (160, 240, 255)}
C1, C2 = (255, 150, 40), (255, 236, 170)             # 通常の光: 炎の橙
A1, A2 = (70, 190, 255), (220, 248, 255)             # 覚醒の光: 蒼

idle = idle_frames(COUNTS['idle'])
frames = dict(idle=idle)
raw = states(idle, C1, C2)
frames.update(finish(raw, None, C1, C2))
aw = []
for i, im in enumerate(idle_frames(COUNTS['idle'])):
    im = recolor(im, AWAKE)
    im = rays_behind(im, 84, 58, 44, 66, 26, (i % 12) / 12, (30, 90, 200), (160, 235, 255))
    aw.append(aura(im, (90, 210, 255), phase=i % 3, every=2))
frames['idle_awakened'] = aw
for k, v in finish(raw, AWAKE, A1, A2).items():
    frames[k + '_awakened'] = [aura(im, (90, 210, 255), phase=i % 3, every=2) for i, im in enumerate(v)]
NOTE = ('元の絵は Canva で生成したイラストを source/prep_source.py で整え(翼の先を描き足し、頭を1.6倍にした)、色の表を使う版でドット化したもの(高さ112)。'
        '顔は source/polish_dragon.py で描き直した。ほかのボスより大きく(168×128)、コマ数が3倍(待機24・構え12・技中12・硬直6)で、1コマ 0.04 秒。'
        '待機は翼の羽ばたき(先へ行くほど遅れて動く)・尻尾のうねり・体の上下。技中は口を開けて吠える。覚醒は黒い体に蒼い炎')
if __name__ == '__main__':
    size, nc = export(ID, '最強のドラゴン', frames, NOTE, counts=COUNTS, frame_ms=FRAME_MS); print(ID, size, nc, 'colors')
