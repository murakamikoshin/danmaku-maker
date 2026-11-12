"""最強のドラゴン(怪獣 + ドラゴン、赤と金)を書き出す: python3 make_dragon.py
ほかのボスと作り方が違う(Koshin の指示「もっとぬるぬる、もっとかっこよく、動きの種類をめちゃくちゃ多く、覚醒は3段階」):
- 元絵(source/dragon_art.png、Canva で生成した 1456×1088)を部位に分け、骨で動かしてから1コマごとにドット化する(rig.py)
- 動きは moves.py: 待機48コマ + 技ごとの動き10種類(構え12・技中16・硬直6)。1コマ 0.04 秒
- 姿は4つ: 通常 / 覚醒1 蒼炎 / 覚醒2 紫電 / 覚醒3 白金。絵は「色の番号」で持ち、姿ごとの色の表(forms.json)で塗る
出力:
  sheets/<動き>.png   色の番号の絵を並べたもの(赤の値 = 番号×10。1行8コマ)。試射場・ボス図鑑はこれと forms.json から4つの姿を作る
  forms.json / anim.json   色の表 / コマ数・大きさ・速さ・発射位置
  dragon_<状態>_<コマ>.png  ほかのボスと同じ名前の絵(通常と覚醒1。構え・技中・硬直は「ブレス」の動き)
  gif/<姿>_idle.gif         確認用(待機だけ)"""
import sys, os, json, math
import numpy as np
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import rig, moves, side
ID = 'dragon'; FRAME_MS = 40; FW, FH = rig.FW, rig.FH; BG = (16, 12, 28)

# ---------- 姿ごとの色の表(色の番号 → 色。None は透明) ----------
FORMS = [
 dict(id='normal', name='通常', colors={1: (198, 40, 40), 2: (134, 20, 34), 3: (242, 98, 62), 4: (88, 14, 32), 5: (58, 8, 28), 6: (236, 176, 60), 7: (176, 114, 34), 8: (255, 228, 130),
      9: (246, 208, 146), 10: (190, 60, 80), 11: (96, 16, 40), 12: (255, 246, 228), 13: (220, 196, 186), 14: (24, 10, 20), 15: (255, 50, 50), 16: (255, 150, 40), 17: (255, 236, 170), 18: (255, 255, 255)}),
 dict(id='awake1', name='覚醒1 蒼炎', colors={1: (58, 48, 96), 2: (36, 30, 66), 3: (96, 88, 150), 4: (30, 24, 56), 5: (20, 16, 40), 6: (70, 190, 255), 7: (34, 110, 210), 8: (200, 244, 255),
      9: (150, 220, 255), 10: (60, 120, 220), 11: (20, 30, 90), 12: (240, 250, 255), 13: (170, 200, 230), 14: (8, 8, 24), 15: (120, 240, 255), 16: (70, 190, 255), 17: (220, 248, 255), 18: (255, 255, 255),
      19: (90, 210, 255)}),
 dict(id='awake2', name='覚醒2 紫電', colors={1: (70, 30, 100), 2: (44, 16, 70), 3: (120, 60, 160), 4: (36, 12, 58), 5: (24, 8, 40), 6: (255, 90, 220), 7: (170, 40, 160), 8: (255, 190, 250),
      9: (230, 150, 240), 10: (200, 60, 160), 11: (70, 10, 70), 12: (255, 240, 255), 13: (210, 170, 220), 14: (10, 4, 20), 15: (255, 80, 255), 16: (255, 90, 220), 17: (255, 210, 250), 18: (255, 255, 255),
      19: (255, 120, 240), 20: (110, 30, 150), 21: (255, 160, 250)}),
 dict(id='awake3', name='覚醒3 白金', colors={1: (244, 240, 236), 2: (164, 156, 190), 3: (255, 255, 255), 4: (150, 44, 58), 5: (98, 24, 46), 6: (255, 206, 80), 7: (196, 130, 30), 8: (255, 246, 176),
      9: (255, 220, 136), 10: (255, 120, 60), 11: (170, 50, 20), 12: (255, 255, 255), 13: (230, 210, 190), 14: (60, 10, 10), 15: (255, 30, 30), 16: (255, 200, 60), 17: (255, 250, 200), 18: (255, 255, 255),
      19: (255, 230, 120), 20: (200, 140, 30), 21: (255, 240, 170), 22: (255, 200, 80)}),
]
def palette(form):
    pal = np.zeros((256, 4), np.uint8)
    for k, c in form['colors'].items(): pal[k] = tuple(c) + (255,)
    return pal

# ---------- 光の効果(色の番号で描く。16=色1、17=色2、18=白) ----------
def put(im, x, y, c, over=True):
    x, y = int(round(x)), int(round(y))
    if 0 <= x < FW and 0 <= y < FH and (over or im[y, x] == 0): im[y, x] = c
def line(im, x0, y0, x1, y1, c, w=1, over=True):
    n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
    for k in range(n + 1):
        t = k / max(1, n); x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        for a in range(w):
            for b in range(w): put(im, x + a - w // 2, y + b - w // 2, c, over)
def star(im, x, y, size, c1=16, c2=17):
    for k in range(1, size + 1):
        cc = c1 if k > size // 2 else c2
        for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)): put(im, x + dx, y + dy, cc)
    if size >= 3:
        for dx, dy in ((1, 1), (-1, 1), (1, -1), (-1, -1)): put(im, x + dx, y + dy, c2)
    put(im, x, y, 18)
def ring(im, x, y, r, c, gap=0, over=True):
    n = max(8, int(2 * math.pi * r))
    for k in range(n):
        if gap and (k // gap) % 2: continue
        a = 2 * math.pi * k / n; put(im, x + math.cos(a) * r, y + math.sin(a) * r, c, over)
def converge(im, x, y, r, n, ph):
    for k in range(n):
        a = 2 * math.pi * k / n + ph
        put(im, x + math.cos(a) * r, y + math.sin(a) * r, 17 if k % 2 else 16); put(im, x + math.cos(a) * (r + 2), y + math.sin(a) * (r + 2), 16)
def burst(im, x, y, r0, r1, n, ph, c, a0=0.0, a1=2 * math.pi):
    for k in range(n):
        a = a0 + (a1 - a0) * (k + 0.5) / n + ph
        for rr in range(int(r0), int(r1) + 1): put(im, x + math.cos(a) * rr, y + math.sin(a) * rr, c)

def disc(im, x, y, r, c, over=True):
    yy, xx = np.ogrid[0:FH, 0:FW]; m = (xx - x) ** 2 + (yy - y) ** 2 <= r * r
    if not over: m &= im == 0
    im[m] = c
def orb(im, x, y, r, i=0):
    """光の玉: 外から 色1 → 色2 → 白。まわりに十字の光"""
    disc(im, x, y, r, 16); disc(im, x, y, max(1, r * 0.66), 17); disc(im, x, y, max(0.6, r * 0.34), 18)
    L = r * (1.7 + 0.25 * (i % 2))
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)): line(im, x + dx * r, y + dy * r, x + dx * L, y + dy * L, 17)
def flame_cone(im, x, y, ang, length, half, i):
    """口から吹き出す炎: 扇形に3色。ふちは波打つ"""
    yy, xx = np.mgrid[0:FH, 0:FW]; dx, dy = xx - x, yy - y
    d = dx * math.cos(ang) + dy * math.sin(ang); side = -dx * math.sin(ang) + dy * math.cos(ang)
    wob = 1 + 0.18 * np.sin(d * 0.55 - i * 1.3) + 0.1 * np.sin(d * 1.3 + i * 2.1)
    w = (2.5 + d * math.tan(half)) * wob
    for c, kw, kl in ((16, 1.0, 1.0), (17, 0.62, 0.8), (18, 0.3, 0.55)):
        im[(d > 0) & (d < length * kl) & (np.abs(side) < w * kw)] = c
def arc(im, x0, y0, x1, y1, bend, w, c):
    """弓なりの線(爪や尻尾の軌跡)"""
    mx, my = (x0 + x1) / 2, (y0 + y1) / 2; nx, ny = -(y1 - y0), x1 - x0; L = max(1e-6, math.hypot(nx, ny))
    cx, cy = mx + nx / L * bend, my + ny / L * bend; px, py = x0, y0
    for k in range(1, 13):
        t = k / 12; qx = (1 - t) ** 2 * x0 + 2 * t * (1 - t) * cx + t * t * x1; qy = (1 - t) ** 2 * y0 + 2 * t * (1 - t) * cy + t * t * y1
        line(im, px, py, qx, qy, c, max(1, round(w * math.sin(math.pi * t) + 0.5))); px, py = qx, qy

def effects(im, anim, i, mk, prev):
    """動きごとの光。mk: 口・手・翼の先などの位置。prev: 1つ前のコマの位置(軌跡を描く)"""
    m, _, st = anim.partition('_'); mx, my = mk['mouth']; cx, cy = mk['chest']
    if st == 'windup' and m in ('breath', 'inhale', 'roar', 'wrath', 'gale', 'cyclone', 'slam'):
        t = (i + 1) / moves.N_W; x, y = (mx, my) if m in ('breath', 'inhale', 'roar') else (cx, cy)
        for k in range(3): converge(im, x, y, max(3, 40 - 30 * t - k * 7 + (i % 2)), 9 + k * 2, i * 0.4 * (1 if k % 2 else -1) + k)
        orb(im, x, y, 1.5 + 5.5 * t, i)
        if t > 0.6: ring(im, x, y, 10 + (i % 3) * 5, 17, gap=2, over=False)
    if anim == 'breath_attack':
        flame_cone(im, mx, my + 2, math.pi / 2 + 0.06 * math.sin(i * 0.8), 46 + (i % 3) * 5, math.radians(17), i)
        orb(im, mx, my + 1, 5 + i % 2, i)
        for k in range(6): put(im, mx + (k - 2.5) * 5 + (i * 3 + k * 7) % 5, my + 30 + (i * 5 + k * 11) % 26, 17 if k % 2 else 18, False)
    elif anim == 'inhale_attack':
        for k in range(4): converge(im, mx, my, 54 - ((i * 5 + k * 13) % 50), 9, i * 0.45 + k * 1.1)
        for k in range(3): ring(im, mx, my, 46 - ((i * 4 + k * 15) % 42), 16, gap=3, over=False)
        orb(im, mx, my, 3 + (i % 8) * 0.7, i)
    elif anim == 'roar_attack':
        for k in range(4): ring(im, mx, my, 6 + ((i * 5 + k * 13) % 52), 17 if k % 2 else 16, gap=0 if k % 2 else 2, over=False)
        for k in range(2): ring(im, mx, my, 7 + ((i * 5 + k * 26) % 52), 18, over=False)
        burst(im, mx, my, 9, 16 + i % 3 * 3, 12, i * 0.2, 17); orb(im, mx, my, 4 + i % 2, i)
    elif anim == 'dive_attack':
        for h, f0 in (('handR', 3), ('handL', 11)):
            k = i - f0
            if 0 <= k <= 5 and prev:
                (x0, y0), (x1, y1) = prev[h], mk[h]; s_ = 1 if h == 'handR' else -1
                ax, ay = mk[h][0] + s_ * 26, mk[h][1] - 30; bx, by = mk[h][0] - s_ * 30, mk[h][1] + 34       # 爪の跡: 3本の弓なりの光
                for o_, c in ((-8, 16), (0, 18), (8, 17)):
                    arc(im, ax + o_, ay, bx + o_, by, -s_ * 12, 3 if c == 18 else 2, c)
                if k < 2: orb(im, x1, y1, 4, i)
    elif anim == 'gale_attack':
        if math.sin(4 * math.pi * i / moves.N_A + 1.2) < -0.1:                          # 打ち下ろしの間、翼の下に風の弧
            for h, s_ in (('wtipL', -1), ('wtipR', 1), ('wristL', -1), ('wristR', 1)):
                x, y = mk[h]
                for k in range(3): arc(im, x - 14, y + 12 + k * 9, x + 14, y + 12 + k * 9, 5, 2 if k == 1 else 1, 18 if k == 1 else 17)
    elif anim == 'glide_attack':
        for h in ('wristL', 'wristR', 'wtipL', 'wtipR', 'handL', 'handR'):
            x, y = mk[h]
            for k in range(2): line(im, x + k * 3 - 1, y - 6 - (i * 3 + k * 5) % 7, x + k * 3 - 1, y - 24 - (i * 4 + k * 9) % 12, 18 if k else 17, 1, over=False)
        orb(im, mx, my, 3 + i % 2, i)
    elif anim == 'slam_attack' and 3 <= i <= 9:
        k = i - 3
        for h in ('handL', 'handR'):
            x, y = mk[h]; r = 5 + k * 6
            burst(im, x, y + 8, r, r + 9 - k, 11, 0, 18 if k < 2 else (17 if i % 2 else 16), math.radians(195), math.radians(345))
            line(im, x - r * 1.3, y + 12, x + r * 1.3, y + 12, 17, 2 if k < 3 else 1)
            if k < 4: orb(im, x, y + 8, 6 - k, i)
    elif anim == 'tail_attack' and prev:
        (x0, y0), (x1, y1) = prev['tailtip'], mk['tailtip']
        arc(im, x0, y0, x1, y1, 4, 4, 18); arc(im, x0, y0 + 5, x1, y1 + 5, 4, 2, 17); arc(im, x0, y0 - 5, x1, y1 - 5, 4, 2, 16)
    elif anim == 'cyclone_attack':
        for k, h in enumerate(('wtipL', 'wtipR')):
            x, y = mk[h]
            for j in range(22):
                a = i * 0.9 + j * 0.42 + k * 3; r = 3 + j * 0.9; put(im, x + math.cos(a) * r, y - j * 0.8 + math.sin(a) * r * 0.45, (18, 17, 16)[j % 3], False)
    elif anim == 'wrath_attack':
        burst(im, cx, cy, 56 + i % 2 * 6, 84 + i % 3 * 7, 22, i * 0.17, 17 if i % 2 else 16)
        burst(im, cx, cy, 70, 96, 11, -i * 0.11, 18)
        for k in range(3): ring(im, cx, cy, 16 + ((i * 6 + k * 22) % 66), 16 if k % 2 else 17, gap=2, over=False)
        for e in ('eyeL', 'eyeR'): orb(im, *mk[e], 2.4, i)
        orb(im, mx, my, 3 + i % 2, i)

def aura(im, i):
    """覚醒した姿だけで見える光: 体のふちの点滅(19)、うしろの光(20・21)、のぼる火の粉(22)。通常の姿では透明"""
    a = im > 0; out = im.copy()
    near = (np.roll(a, 1, 0) | np.roll(a, -1, 0) | np.roll(a, 1, 1) | np.roll(a, -1, 1)) & ~a
    yy, xx = np.mgrid[0:FH, 0:FW]
    out[near & ((xx + yy + i) % 3 == 0)] = 19
    cx, cy = FW / 2, FH / 2 - 6
    for k in range(30):
        ang = math.radians(-205 + 230 * (k + (i % 12) / 12) / 30); L = 96 - (k * 7 % 6) * 4
        for rr in range(54 + (k % 3) * 4, L):
            x, y = int(cx + math.cos(ang) * rr), int(cy + math.sin(ang) * rr)
            if 0 <= x < FW and 0 <= y < FH and out[y, x] == 0: out[y, x] = 21 if rr > L - 5 else 20
    for k in range(14):
        x = (k * 37 + 11) % FW; y = FH - 1 - ((i * 3 + k * 29) % FH)
        if out[y, x] == 0: out[y, x] = 22
    return out

def render_all():
    frames = {}
    for name, n, fn in moves.all_anims():
        lst = []; prev = None
        for i in range(n):
            pose = fn(i); im, _ = rig.render(pose, eye_glow=name.endswith('_attack')); mk = rig.markers(pose)
            if prev is None and name.endswith('_attack'): prev = rig.markers(fn(n - 1))
            effects(im, name, i, mk, prev); prev = mk
            lst.append(aura(im, i))
        frames[name] = lst
    # 横向きに飛ぶ姿(左向きと、それを裏返した右向き)。うしろに速さの線、口に炎
    L = []
    for i in range(side.N_FLY):
        im, mk = side.render(i); mx, my = mk['mouth']
        flame_cone(im, mx - 1, my, math.pi + 0.12 * math.sin(i), 8 + i % 3 * 2, math.radians(20), i)
        for k in range(7):
            y = 70 + (k * 23 + 11) % 80; x = 60 + (k * 53 + i * 17) % 170
            line(im, x, y, x + 12 + (k % 3) * 6, y, 17 if k % 2 else 16, 1, over=False)
        L.append(aura(im, i))
    frames['side_fly_l'] = L; frames['side_fly_r'] = [np.ascontiguousarray(im[:, ::-1]) for im in L]
    return frames

def rgba(lab, pal): return Image.fromarray(pal[lab], 'RGBA')
def gif(path, labs, pal, K=3):
    fr = []
    for lab in labs:
        im = Image.new('RGBA', (FW, FH), BG + (255,)); im.alpha_composite(rgba(lab, pal))
        fr.append(im.resize((FW * K, FH * K), Image.NEAREST).convert('P', palette=Image.ADAPTIVE, colors=64))
    fr[0].save(path, save_all=True, append_images=fr[1:], duration=FRAME_MS, loop=0, disposal=2)

def export():
    frames = render_all()
    for sub in ('sheets', 'gif'):
        os.makedirs(os.path.join(HERE, sub), exist_ok=True)
        for f in os.listdir(os.path.join(HERE, sub)): os.remove(os.path.join(HERE, sub, f))
    for f in os.listdir(HERE):
        if f.startswith('dragon_') and f.endswith(('.png', '.gif')): os.remove(os.path.join(HERE, f))
    # 色の番号の絵(1行8コマ)
    counts = {}
    for name, lst in frames.items():
        n = len(lst); counts[name] = n; cols = 8; rows = (n + cols - 1) // cols
        sh = np.zeros((rows * FH, cols * FW, 4), np.uint8)
        for k, lab in enumerate(lst):
            y, x = (k // cols) * FH, (k % cols) * FW
            sh[y:y + FH, x:x + FW, 0] = lab * 10; sh[y:y + FH, x:x + FW, 3] = np.where(lab > 0, 255, 0)
        Image.fromarray(sh, 'RGBA').save(os.path.join(HERE, 'sheets', name + '.png'), optimize=True)
    json.dump(dict(forms=[dict(id=f['id'], name=f['name'], colors={str(k): list(v) for k, v in f['colors'].items()}) for f in FORMS]),
              open(os.path.join(HERE, 'forms.json'), 'w'), ensure_ascii=False, indent=1)
    rest = rig.markers(moves.idle(0))
    json.dump(dict(frame_ms=FRAME_MS, w=FW, h=FH, cols=8, counts=dict(idle=moves.N_IDLE, windup=moves.N_W, attack=moves.N_A, recover=moves.N_R),
                   moves=[dict(id=m, name=moves.MOVE_NAMES[m]) for m in moves.MOVES], anims=counts,
                   extras=[dict(id='side_fly_l', name='横に飛ぶ(左向き)'), dict(id='side_fly_r', name='横に飛ぶ(右向き)')],
                   origins={k: [round(v[0]), round(v[1])] for k, v in rest.items()}, label_step=10),
              open(os.path.join(HERE, 'anim.json'), 'w'), ensure_ascii=False, indent=1)
    # ほかのボスと同じ名前の絵(通常・覚醒1。構え・技中・硬直はブレス)
    std = dict(idle='idle', windup='breath_windup', attack='breath_attack', recover='breath_recover')
    for suf, form in (('', FORMS[0]), ('_awakened', FORMS[1])):
        pal = palette(form)
        for st, an in std.items():
            for k, lab in enumerate(frames[an]): rgba(lab, pal).save(os.path.join(HERE, f'{ID}_{st}{suf}_{k}.png'))
    # 確認用のGIF: 待機だけ(4つの姿)。ほかの動きは、試射場・ボス図鑑で見る
    for f in FORMS: gif(os.path.join(HERE, 'gif', f"{f['id']}_idle.gif"), frames['idle'], palette(f), K=2)
    n = sum(counts.values())
    open(os.path.join(HERE, 'README.txt'), 'w').write('\n'.join([
        '最強のドラゴン(dragon) のドット絵', '',
        f'- 1コマ {FW}×{FH} ピクセル(ほかのボスは 112×112)、背景は透明。1コマ {FRAME_MS / 1000:g} 秒(25コマ/秒)。拡大は必ず最近傍補間',
        f'- 動きは全部で {len(counts)} 種類・{n} コマ: 待機 {moves.N_IDLE} コマ + 技ごとの動き {len(moves.MOVES)} 種類 ×(構え {moves.N_W}・技中 {moves.N_A}・硬直 {moves.N_R})+ 横向きに飛ぶ姿(左右)',
        '  技ごとの動き: ' + '、'.join(f"{moves.MOVE_NAMES[m]}({m})" for m in moves.MOVES),
        '  ほかに、横向きに飛ぶ姿(side_fly_l 左向き / side_fly_r 右向き、各24コマのループ。元絵は source/dragon_side_art.png、骨組みは side.py)',
        '- 姿は4つ: ' + ' / '.join(f['name'] for f in FORMS) + '。絵は1組だけで、姿ごとの色の表(forms.json)で塗り分ける',
        '- sheets/<動き>.png: 色の番号の絵を1行8コマで並べたもの(赤の値 ÷ 10 = 色の番号、透明 = 0)。番号の意味は rig.py の先頭',
        '  覚醒の姿だけで見える光(体のふちの点滅 19、うしろの光 20・21、火の粉 22)も同じ絵に入っていて、通常の色の表では透明になる',
        f'- {ID}_<状態>_<コマ>.png: ほかのボスと同じ名前の絵(通常と、_awakened = 覚醒1)。構え・技中・硬直は「ブレス」の動き',
        '- anim.json: コマ数・大きさ・速さ・発射位置(origins。待機の最初のコマでの、口・手・翼の先などの位置)',
        '- gif/: 確認用(4つの姿の待機)', '',
        '描き直すとき: python3 make_dragon.py(骨組みは rig.py と source/dragon_rig.json、動きは moves.py)']) + '\n')
    return frames, counts

if __name__ == '__main__':
    frames, counts = export(); print(ID, (FW, FH), len(counts), 'anims', sum(counts.values()), 'frames')
