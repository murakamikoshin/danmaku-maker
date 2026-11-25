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
    if name == 'recover':   # 顔は手で描き直す(自動だと、閉じた目が出ず、口が大きすぎた。Koshin の指摘 2026-11-25)。座標は、高さ84でドット化した絵のマス
        SK, LID, IR, IRD, MO, SW = (255, 234, 220, 255), (28, 62, 56, 255), (246, 198, 70, 255), (190, 126, 38, 255), (214, 84, 96, 255), (150, 214, 250, 255)
        SK2, MOD = (238, 196, 184, 255), (150, 40, 60, 255)
        for y in range(19, 25):                      # 顔の幅を待機の絵と同じ(11ドット)に取り直す。前髪が顔にかぶりすぎて、顔が細く見えていた
            for x in range(21, 32):
                if P[x, y][3]: P[x, y] = SK2 if (x in (21, 31) or y == 24) else SK
        for x in (22, 23): P[x, 19] = LID; P[x, 20] = IR; P[x, 21] = IR; P[x, 22] = IRD                # 開いている目(縦長 2×3、上にまぶたの線)
        P[24, 19] = LID
        for x, y in ((31, 20), (30, 20), (29, 21), (28, 21), (30, 22), (31, 22)): P[x, y] = (30, 24, 36, 255)   # ぎゅっとつぶった目。向かって右の目なので「<」の形(とがった先が鼻のほう)。はっきり見えるよう、濃い色で横に長く
        for x in (25, 26, 27): P[x, 23] = MOD; P[x, 24] = MO                                            # 「いてっ」と開いた口
        P[32, 18] = SW; P[32, 19] = SW                                                                  # こめかみの汗
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
    """構え 8 コマ(1回)・技中 16 コマ(ループ: 1周に1回、振りかぶって振り下ろす)・硬直 4 コマ(1回)。pose: {名前: (絵, 杖の先)}"""
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
    # 技中(ループ、16 コマ = 約1.3秒で1周): 1周に1回だけ、振りかぶって(2コマ)→ 振り下ろす。当たった瞬間に小さな光の輪が2コマだけ出て、
    # あとは振り下ろした姿でゆっくり上下しながら、杖の先の光がまたたく。
    # (1回目は 0.64 秒ごとに振り続けて大きな輪も出し「やかましい」、2回目は振らずに上下だけで「大人しすぎ」。その中間。Koshin の指摘 2026-11-25)
    a = []
    SEQ = [('W', 0, 0), ('W', 0, -1), ('A', 1, 2), ('A', 0, 1)] + [('A', 0, dy) for dy in (0, 0, -1, -1, -1, 0, 0, 1, 1, 0, 0, 0)]
    for f, (src, dx, dy) in enumerate(SEQ):
        base_im, tip = (W, wt) if src == 'W' else (A, at)
        im = offset(base_im, dx, dy); x, y = tip[0] + dx, tip[1] + dy
        if f == 2: ring(im, x, y, 5, c1); burst(im, x, y, 3, 7, 8, 0, c2); star(im, x, y, 4, c1, c2)
        elif f == 3: ring(im, x, y, 10, c1, gap=2); star(im, x, y, 3, c1, c2)
        elif src == 'W': star(im, x, y, 3, c1, c2)
        else: star(im, x, y, [2, 3, 2, 1][f % 4], c1, c2)
        a.append(im)
    out['attack'] = a
    out['recover'] = [darken(offset(R, dx, dy), d) for dx, dy, d in [(1, 1, 0.12), (0, 2, 0.28), (0, 2, 0.3), (0, 1, 0.18)]]
    return out
frames.update(make_states(idle, POSE, (255, 204, 80), (255, 250, 220)))
CHEST = to_frame(ID, 640, 560, FOOT)
# 覚醒のうしろ: ほかのボスの「放射する線」は使わない(Koshin の判断、2026-11-25。棒が刺さっているように見えるため。既存のボスは変えない)。
# ノエルは、深紅の三日月を背負い、火の粉がゆっくり舞い上がる。月は動かない(体だけがふわふわ浮くので、奥行きが出る)
MOON_C, MOON_R = (58, 46), 31
MOON_COL = [(96, 14, 38), (168, 26, 52), (232, 62, 78), (255, 150, 150)]     # 影 → 本体 → 明るい縁 → いちばん外の光
EMBERS = [(14, 92, 0), (30, 104, 5), (47, 98, 11), (72, 106, 3), (90, 96, 8), (102, 88, 13), (22, 70, 9), (96, 66, 2), (60, 110, 14), (8, 50, 6)]
def moon_layer():
    im = Image.new('RGBA', (112, 112), (0, 0, 0, 0)); P = im.load(); (cx, cy), R = MOON_C, MOON_R
    for y in range(112):
        for x in range(112):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d > R: continue
            d2 = math.hypot(x + 0.5 - (cx + 11), y + 0.5 - (cy - 9))      # 右上をえぐって三日月に
            if d2 < R - 5: continue
            c = MOON_COL[3] if d > R - 1.2 else MOON_COL[2] if d > R - 3.2 else MOON_COL[1]
            if d2 < R - 3: c = MOON_COL[0]                                 # 内側のふちは影
            P[x, y] = c + (255,)
    return im
MOON = moon_layer()
def behind_moon(im, i, n=16):
    out = MOON.copy(); P = out.load()
    for k, (x, y0, ph) in enumerate(EMBERS):                               # 火の粉: n コマで上へ 1 周。ゆらゆら横にずれ、消える前に暗くなる
        t = (i + ph) % n; y = y0 - t * 2; x2 = x + round(math.sin((t + k) * 0.8) * 1.5)
        if 0 <= x2 < 112 and 0 <= y < 112 and not P[x2, y][3]:
            P[x2, y] = ((255, 190, 160) if t < 4 else (236, 70, 84) if t < 11 else (130, 22, 46)) + (255,)
    out.alpha_composite(im)
    return out
frames['idle_awakened'] = [behind_moon(black_santa(f), i) for i, f in enumerate(idle)]
aw_pose = {n: (black_santa(im), tip) for n, (im, tip) in POSE.items()}
for k, v in make_states([black_santa(f) for f in idle], aw_pose, (255, 70, 80), (255, 220, 220)).items():
    frames[k + '_awakened'] = [behind_moon(f, i) for i, f in enumerate(v)]
NOTE = ('元の絵は Koshin が画像生成で作ったイラスト(source/santa_source.png)を、色の表を使う版でドット化したもの(高さ84)。'
        '杖は、元絵では脚を横切っていたのを、手の先で止めて脚を描き直した(source/polish_santa.py。Koshin の判断)。'
        '待機は16コマ(1コマ80ms): 体ごとふわふわ浮き、プレゼントの上下、横の髪・三つ編みの先・すそのゆれ。'
        '構え・技中・硬直は専用ポーズの絵(poses/。待機の元絵を参考画像にして Canva で作った)。構え8コマ(杖を振りかぶる)・技中16コマ(1周に1回、振りかぶって振り下ろす。あとは振り下ろした姿でゆっくり上下)・硬直4コマ。'
        '覚醒は黒サンタ: 赤い服としま模様が黒に、目が赤に。うしろに深紅の三日月と舞う火の粉(ほかのボスの放射する線は使わない)')
if __name__ == '__main__':
    size, nc = export(ID, 'ノエル(クリスマス娘)', frames, NOTE, counts={'idle': IDLE_N, 'windup': 8, 'attack': 16, 'recover': 4}, frame_ms=FRAME_MS); print(ID, size, nc, 'colors')
