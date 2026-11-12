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
import rig, moves
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
 dict(id='awake3', name='覚醒3 白金', colors={1: (250, 244, 226), 2: (212, 188, 150), 3: (255, 255, 255), 4: (226, 150, 44), 5: (176, 100, 26), 6: (255, 214, 90), 7: (214, 150, 40), 8: (255, 250, 200),
      9: (255, 236, 180), 10: (255, 120, 60), 11: (170, 50, 20), 12: (255, 255, 255), 13: (230, 210, 190), 14: (60, 10, 10), 15: (255, 30, 30), 16: (255, 200, 60), 17: (255, 250, 200), 18: (255, 255, 255),
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

def effects(im, anim, i, mk, prev):
    """動きごとの光。mk: 口・手・翼の先などの位置。prev: 1つ前のコマの位置(軌跡を描く)"""
    m, _, st = anim.partition('_'); mx, my = mk['mouth']
    if st == 'windup' and m in ('breath', 'inhale', 'roar', 'wrath', 'gale', 'cyclone', 'slam'):
        t = (i + 1) / moves.N_W; cx, cy = (mx, my) if m in ('breath', 'inhale', 'roar') else mk['chest']
        converge(im, cx, cy, 30 - 22 * t, 10, i * 0.35)
        if i >= 3: converge(im, cx, cy, 40 - 26 * t, 6, -i * 0.5)
        star(im, cx, cy, max(1, round(1 + 4 * t)))
    if anim == 'breath_attack':
        burst(im, mx, my + 3, 6, 14 + i % 3 * 3, 7, 0.1 * (i % 2), 17 if i % 2 else 16, math.radians(50), math.radians(130))
        ring(im, mx, my + 2, 5 + (i % 4) * 3, 16, gap=2); star(im, mx, my + 1, 5 + i % 2)
    elif anim == 'inhale_attack':
        for k in range(3): converge(im, mx, my, 44 - ((i * 5 + k * 15) % 44), 8, i * 0.4 + k)
        star(im, mx, my, 3 + (i // 2) % 4)
    elif anim == 'roar_attack':
        for k in range(3): ring(im, mx, my, 5 + ((i * 4 + k * 12) % 36), 17 if k % 2 else 16, gap=2 if k else 0, over=False)
        star(im, mx, my, 4 + i % 2)
    elif anim == 'dive_attack':
        for h, on in (('handR', 3 <= i <= 7), ('handL', 11 <= i <= 15)):
            if on and prev:
                (x0, y0), (x1, y1) = prev[h], mk[h]
                line(im, x0, y0 + 6, x1, y1 + 6, 18, 2); line(im, x0 - 5, y0 + 9, x1 - 5, y1 + 9, 17, 2); line(im, x0 + 5, y0 + 3, x1 + 5, y1 + 3, 17, 1)
    elif anim == 'gale_attack':
        if math.sin(4 * math.pi * i / moves.N_A + 1.2) < -0.2:                          # 打ち下ろしの間、翼の下に風の筋
            for h in ('wtipL', 'wtipR', 'wristL', 'wristR'):
                x, y = mk[h]
                for k in range(3): line(im, x - 8 + k * 8, y + 10 + k * 3, x - 8 + k * 8, y + 24 + k * 5, 17 if k == 1 else 16, 1, over=False)
    elif anim == 'glide_attack':
        for h in ('wristL', 'wristR', 'wtipL', 'wtipR'):
            x, y = mk[h]; line(im, x, y - 6 - i % 3 * 2, x, y - 20 - i % 3 * 3, 17 if i % 2 else 16, 1, over=False)
        star(im, mx, my, 3)
    elif anim == 'slam_attack' and 3 <= i <= 8:
        for h in ('handL', 'handR'):
            x, y = mk[h]; r = 4 + (i - 3) * 5
            burst(im, x, y + 8, r, r + 6, 9, 0, 17 if i % 2 else 16, math.radians(200), math.radians(340)); star(im, x, y + 8, max(2, 6 - (i - 3)))
    elif anim == 'tail_attack' and prev:
        (x0, y0), (x1, y1) = prev['tailtip'], mk['tailtip']
        line(im, x0, y0, x1, y1, 18, 2); line(im, x0, y0 + 4, x1, y1 + 4, 17, 1, over=False)
    elif anim == 'cyclone_attack':
        for k, h in enumerate(('wtipL', 'wtipR')):
            x, y = mk[h]
            for j in range(10):
                a = i * 0.8 + j * 0.5 + k * 3; r = 4 + j * 1.3; put(im, x + math.cos(a) * r, y + math.sin(a) * r * 0.5, 17 if j % 2 else 16, False)
    elif anim == 'wrath_attack':
        cx, cy = mk['chest']
        burst(im, cx, cy, 60 + i % 2 * 6, 78 + i % 3 * 6, 18, i * 0.17, 17 if i % 2 else 16)
        for e in ('eyeL', 'eyeR'): star(im, *mk[e], 3)
        ring(im, cx, cy, 20 + (i * 6) % 60, 16, gap=2, over=False)

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
        f'- 動きは全部で {len(counts)} 種類・{n} コマ: 待機 {moves.N_IDLE} コマ + 技ごとの動き {len(moves.MOVES)} 種類 ×(構え {moves.N_W}・技中 {moves.N_A}・硬直 {moves.N_R})',
        '  技ごとの動き: ' + '、'.join(f"{moves.MOVE_NAMES[m]}({m})" for m in moves.MOVES),
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
