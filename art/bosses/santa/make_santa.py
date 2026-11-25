import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
from srcpos import to_frame
# 元のイラスト(source/santa_source.png。Koshin が ChatGPT / Gemini で作った絵から prep_santa.py で作る)を、
# 色の表を使う版(pixel_pal.py、高さ84)でドット化し、部位の地図で動かす。クリスマスの期間限定で売るボス(アプリの BossCharacter.santa = 14)
ID = 'santa'; FOOT = 12
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=FOOT)
GIFT = to_frame(ID, 938, 310, FOOT); HOOK = to_frame(ID, 150, 770, FOOT); CHEST = to_frame(ID, 640, 560, FOOT)
# 待機は 16 コマ・1コマ 80ms(ふつうのボスは 8 コマ・120ms。Koshin の希望で、もっとなめらかに)。
# 体ごと上下に 2 ドットふわふわ浮く。プレゼントは手の上で上下(手のひらに近づきすぎないよう、上寄りに動かす)。横の髪・三つ編みの先・すそはゆれる。
# 杖・手・そで・脚・顔は動かさない(体ごと浮くだけ)。帽子の鈴も動かさない(帽子とのあいだに切れ目が出るため)
IDLE_N, FRAME_MS = 16, 80
SNOW = [(10, 16, 1), (100, 12, 1), (16, 60, 1), (104, 70, 1), (8, 98, 1), (96, 100, 1)]
def make_idle():
    out = []
    for i in range(IDLE_N):
        ph = i / IDLE_N * 2 * math.pi
        mv = {'gift': (0, round(-1.5 + 2.5 * math.sin(ph + 0.9)))}
        im = offset(rig_frame(base, lab, parts, mv, (ph, 2.4)), 0, round(2 * math.sin(ph)))
        for k, (x, y, r) in enumerate(SNOW):          # まわりを上へのぼる小さな光
            put(im, x, y - ((i + k * 5) % IDLE_N), (255, 255, 255))
        out.append(im)
    return out
idle = make_idle()
frames = dict(idle=idle)

# ---- 専用ポーズ(構え・技中・硬直)。元絵は、待機の元絵を参考画像にして Canva で作った「同じキャラでポーズだけ違う絵」(poses/<名前>/source/) ----
# 待機と同じ色の表でドット化し、体の大きさ(帽子の先からブーツまで 84 ドット)とベルトのバックルの位置を待機にそろえて 112×112 に置く
import json
from collections import deque
POSES = {   # height: ドット化の高さ(体の大きさを待機にそろえた値) / buckle: バックルの元絵での x / seeds: 線で囲まれた背景(元絵の座標) / tip: 杖の先(元絵の座標)
    'windup':  dict(buckle=655, seeds=[], tip=(705, 95)),
    'attack':  dict(buckle=625, seeds=[], tip=(70, 1270)),
    'recover': dict(buckle=654, seeds=[(350, 600), (380, 1100), (360, 900), (400, 1000)], tip=None),
}
BASE_BUCKLE_X = 63          # 待機の絵のバックルの x(112×112 の中)
def load_pose(name):
    cfg = POSES[name]; d = os.path.join(HERE, 'poses', name)
    still = make_still.make(d)
    im = Image.open(still).convert('RGBA'); P = im.load()
    mp = json.load(open(still + '.map.json')); bx, by, sc = mp['box'][0], mp['box'][1], mp['sc']
    if cfg['seeds']:        # 線で囲まれた背景を透明に(待機の絵の polish_santa.py と同じ考え方)
        src = Image.open(os.path.join(d, 'source', name + '_source.png')).convert('RGB'); S = src.load(); w, h = src.size
        white = lambda c: min(c) > 236 and max(c) - min(c) < 18
        M = [[0] * w for _ in range(h)]
        for sx, sy in cfg['seeds']:
            assert white(S[sx, sy]), (name, sx, sy)
            q = deque([(sx, sy)]); M[sy][sx] = 1
            while q:
                x, y = q.popleft()
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    u, v = x + dx, y + dy
                    if 0 <= u < w and 0 <= v < h and not M[v][u] and white(S[u, v]): M[v][u] = 1; q.append((u, v))
        for y in range(im.height):
            for x in range(im.width):
                if not P[x, y][3]: continue
                x0, x1, y0, y1 = int(x / sc + bx), int((x + 1) / sc + bx), int(y / sc + by), int((y + 1) / sc + by)
                t = n = 0
                for v in range(max(0, y0), min(h, y1)):
                    for u in range(max(0, x0), min(w, x1)): t += 1; n += M[v][u]
                if t and n * 2 >= t: P[x, y] = (0, 0, 0, 0)
    ox = BASE_BUCKLE_X - round((cfg['buckle'] - bx) * sc); oy = 112 - FOOT - im.height
    fr = Image.new('RGBA', (112, 112), (0, 0, 0, 0)); fr.alpha_composite(im, (ox, oy))
    tip = None if not cfg['tip'] else (ox + round((cfg['tip'][0] - bx) * sc), oy + round((cfg['tip'][1] - by) * sc))
    return fr, tip
POSE = {n: load_pose(n) for n in POSES}

# ---- 覚醒: 黒サンタ(Koshin の OK、2026-11-25)。赤い服・帽子・しま模様が黒に、目は金から赤に。髪・肌・白いファー・金はそのまま ----
BLACK_SANTA = {(208, 54, 60): (58, 48, 72), (148, 30, 48): (32, 26, 44), (238, 96, 92): (98, 84, 116),
               (246, 198, 70): (255, 70, 70), (190, 126, 38): (170, 20, 44)}
def black_santa(im):
    im = im.copy(); P = im.load()
    for y in range(im.height):
        for x in range(im.width):
            c = P[x, y]
            if c[3] and c[:3] in BLACK_SANTA: P[x, y] = BLACK_SANTA[c[:3]] + (255,)
    return im

def make_states(idle_fr, pose, c1, c2):
    """構え 8 コマ(1回)・技中 8 コマ(ループ: 振りかぶる → 振り下ろす)・硬直 4 コマ(1回)。pose: {名前: (絵, 杖の先)}"""
    (W, wt), (A, at), (R, _) = pose['windup'], pose['attack'], pose['recover']
    piv = bbox_bottom(idle_fr[0]); out = {}
    w = [squash(idle_fr[0], 1, piv), squash(idle_fr[0], 2, piv)]          # しずむ → 杖を振り上げる → 力をためて震える
    for f, (dx, dy) in enumerate([(0, 2), (0, 0), (0, -1), (1, -1), (-1, -1), (0, -1)]):
        im = offset(W, dx, dy); x, y = wt[0] + dx, wt[1] + dy
        converge(im, x, y, [14, 12, 10, 8, 6, 4][f], 8, f * 0.4, c1, c2)
        star(im, x, y, [1, 1, 2, 2, 3, 3][f], c1, c2)
        if f >= 4: ring(im, x, y, [0, 0, 0, 0, 6, 4][f], c2)
        w.append(im)
    out['windup'] = w
    a = []
    for f, (src, dx, dy) in enumerate([('W', 0, -1), ('W', 0, -2), ('A', 1, 2), ('A', 0, 1), ('A', 0, 0), ('A', 0, 0), ('A', 0, -1), ('W', 0, 1)]):
        base_im, tip = (W, wt) if src == 'W' else (A, at)
        im = offset(base_im, dx, dy); x, y = tip[0] + dx, tip[1] + dy
        if src == 'A':
            k = f - 2
            ring(im, x, y, [4, 9, 14, 18, 21][k], c1, gap=2 if k >= 2 else 0)
            if k < 3: burst(im, x, y, 3, 7 + k * 2, 8, k * math.pi / 8, c2)
            star(im, x, y, [4, 4, 3, 2, 2][k], c1, c2)
        else:
            star(im, x, y, 3, c1, c2)
        a.append(im)
    out['attack'] = a
    out['recover'] = [darken(offset(R, dx, dy), d) for dx, dy, d in [(1, 1, 0.12), (0, 2, 0.28), (0, 2, 0.3), (0, 1, 0.18)]]
    return out
frames.update(make_states(idle, POSE, (255, 204, 80), (255, 250, 220)))
CHEST = to_frame(ID, 640, 560, FOOT)
def awaken_frame(im, i):
    im = rays_behind(black_santa(im), CHEST[0], CHEST[1], 26, 50, 22, (i % 8) / 8, (150, 20, 40), (255, 90, 90))
    return aura(im, (255, 80, 90), phase=i % 3, every=2)
frames['idle_awakened'] = [awaken_frame(f, i) for i, f in enumerate(idle)]
aw_pose = {n: (black_santa(im), tip) for n, (im, tip) in POSE.items()}
for k, v in make_states([black_santa(f) for f in idle], aw_pose, (255, 70, 80), (255, 220, 220)).items():
    frames[k + '_awakened'] = [aura(f, (255, 80, 90), phase=i % 3, every=2) for i, f in enumerate(v)]
NOTE = ('元の絵は Koshin が画像生成で作ったイラスト(source/santa_source.png)を、色の表を使う版でドット化したもの(高さ84)。'
        '杖は、元絵では脚を横切っていたのを、手の先で止めて脚を描き直した(source/polish_santa.py。Koshin の判断)。'
        '待機は16コマ(1コマ80ms): 体ごとふわふわ浮き、プレゼントの上下、横の髪・三つ編みの先・すそのゆれ。'
        '構え・技中・硬直は専用ポーズの絵(poses/。待機の元絵を参考画像にして Canva で作った)。構え8コマ・技中8コマ(杖を振りかぶる→振り下ろす)・硬直4コマ。'
        '覚醒は黒サンタ: 赤い服としま模様が黒に、目が赤に。うしろに深紅の光')
if __name__ == '__main__':
    size, nc = export(ID, 'ノエル(クリスマス娘)', frames, NOTE, counts={'idle': IDLE_N, 'windup': 8, 'attack': 8, 'recover': 4}, frame_ms=FRAME_MS); print(ID, size, nc, 'colors')
