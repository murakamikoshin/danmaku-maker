"""竜王の動き(ポーズの列)。rig.py の骨組みに、1コマごとのポーズを渡して描く。
- 待機(idle) 48コマ: 羽ばたき2回ぶん。首・尻尾のうねりは羽ばたきの半分の速さなので、48コマで1周する
- 技ごとの動き(MOVES): 構え 12コマ・技中 16コマ(ループ)・硬直 6コマ。10種類
角度の向き(度): 腕 armL は + で上がる(armR は逆)。首 neck は + で巻く / - で伸びる。尻尾 tail は + で伸びる / - で巻く。
翼 = (flap 上げ下げ, fan 指の開閉, lag 先のしなり, sx 横の伸び, sy 縦の伸び)"""
import math
from math import sin, cos, pi
N_IDLE, N_W, N_A, N_R = 48, 12, 16, 6
TAU = 2 * pi

def E(t): t = max(0.0, min(1.0, t)); return t * t * (3 - 2 * t)
def mir(a): return tuple(-x for x in a)

def fly(ph, k=1.0):
    """宙に浮いて羽ばたく基本の動き。ph: 羽ばたきの位相、k: 大きさ"""
    s, c = sin(ph), cos(ph); h = ph / 2
    w = (21 * k * s, -15 * k * (0.5 + 0.5 * c) + 3, -13 * k * c, 1 - 0.05 * k * (0.5 + 0.5 * c), 1.0)
    dy = 22 * k * sin(ph - 0.5)                                   # 打ち下ろすと体が上がる
    aL = (3 * sin(ph - 1.0), 4 * sin(ph - 1.6), 4 * sin(ph - 2.2)); lL = (4 * sin(ph - 1.3), 5 * sin(ph - 2.0))
    return dict(dx=0.0, dy=dy, rot=1.2 * sin(h + 0.4), scale=1.0, sx=1.0, sy=1.0, wingL=w, wingR=w,
                neck=tuple(1.4 * sin(h - i * 0.55 + 1.0) for i in range(7)), head=3.5 * sin(h + 2.2), head_dx=0.0, head_dy=-0.45 * dy,
                head_scale=1.4, jaw=0.32 + 0.06 * sin(h),
                tail=tuple((1.0 + 0.3 * i) * sin(h - i * 0.6) for i in range(12)),
                armL=aL, armR=mir(aL), legL=lL, legR=mir(lL))

def _mix(a, b, t):
    if isinstance(a, tuple):
        n = max(len(a), len(b)); a = a + (0.0,) * (n - len(a)); b = b + (0.0,) * (n - len(b))
        return tuple(x + (y - x) * t for x, y in zip(a, b))
    return a + (b - a) * t
def blend(p, q, t):
    """2つのポーズの間。q に書いていない項目は p のまま"""
    out = dict(p)
    for k, v in q.items(): out[k] = _mix(p[k], v, t) if k in p else v
    return out
def keys(kf, f, n):
    """コマ番号つきのポーズの列(ループ)から、コマ f のポーズ。間はなめらかにつなぐ"""
    kf = sorted(kf, key=lambda x: x[0]); f = f % n
    for i, (fa, pa) in enumerate(kf):
        fb, pb = kf[(i + 1) % len(kf)]; fb2 = fb if fb > fa else fb + n; ff = f if f >= fa else f + n
        if fa <= ff < fb2: return blend(pa, pb, E((ff - fa) / (fb2 - fa)))
    return kf[0][1]
def shake(p, i, ax=5.0, ay=3.0):
    q = dict(p); q['dx'] = q.get('dx', 0) + ax * (1 if i % 2 else -1); q['dy'] = q.get('dy', 0) + ay * (1 if (i // 2) % 2 else -1); return q

def W2(flap, fan, lag=0.0, sx=1.0, sy=1.0): w = (flap, fan, lag, sx, sy); return dict(wingL=w, wingR=w)
def arms(a): return dict(armL=a, armR=mir(a))
def legs(a): return dict(legL=a, legR=mir(a))

def idle(i): return fly(TAU * i / 24)

# ---------- 技ごとの動き ----------
def _std(windup_key, attack_fn, rest_key=None):
    """構え: 羽ばたきながら windup_key へ。技中: attack_fn(i)。硬直: 技中の最初のポーズから、力が抜けて待機の最初へ戻る"""
    def w(i):
        t = (i + 1) / N_W; p = blend(fly(TAU * i / 24, 1 - 0.7 * E(t)), windup_key, E(t))
        return shake(p, i, 4, 2) if t > 0.7 else p
    def r(i):
        t = (i + 1) / N_R; droop = dict(dy=30, jaw=0.5, head_dy=20, **W2(-18, -6, 8))
        a = blend(attack_fn(0), rest_key or droop, E(min(1, t * 2)))
        return blend(a, fly(TAU * (i + 1 - N_R) / 24), E(max(0, t * 2 - 1) if t > 0.5 else 0))
    return dict(windup=w, attack=attack_fn, recover=r)

def _breath():
    kw = dict(dy=-45, rot=-3, scale=0.97, neck=(2.5,) * 7, head=8, head_dy=-30, head_scale=1.3, jaw=0.5, tail=(-2,) * 12, **W2(30, -22, -6, 0.95), **arms((12, 18, 10)))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(2 * u, 0.35)); w = (-6 + 9 * sin(2 * u), 8, -6 * cos(2 * u), 1.06, 1.0)
        p.update(dy=10 + 4 * sin(2 * u), scale=1.05, wingL=w, wingR=w, neck=(-1.5,) * 7, head=3 * sin(2 * u), head_dy=55, head_scale=1.62, jaw=1.3,
                 tail=tuple((2 + 0.3 * k) * sin(2 * u - 0.6 * k) for k in range(12)), **arms((-8, -10, -12)))
        return shake(p, i, 5, 2)
    return _std(kw, a)

def _dive():
    kw = dict(dy=-70, scale=0.84, neck=(2,) * 7, jaw=0.3, head_dy=-10, **W2(36, -10, 0), **arms((45, 30, 20)), **legs((-10, 20)))
    base = dict(fly(0, 0)); base.update(scale=1.2, dy=25, head_scale=1.55, head_dy=30, jaw=1.1, neck=(-1,) * 7, tail=(3,) * 12, **W2(18, -38, 0, 0.9), **legs((-12, 15)))
    cockR = dict(base, armR=(-60, -30, -20), armL=(10, 10, 0), rot=-8, dx=18)
    hitR = dict(base, armR=(40, 28, 22), armL=(10, 10, 0), rot=10, dx=-22, scale=1.26)
    cockL = dict(base, armL=(60, 30, 20), armR=(-10, -10, 0), rot=8, dx=-18)
    hitL = dict(base, armL=(-40, -28, -22), armR=(-10, -10, 0), rot=-10, dx=22, scale=1.26)
    kf = [(0, cockR), (3, cockR), (5, hitR), (7, hitR), (8, cockL), (11, cockL), (13, hitL), (15, hitL)]
    def a(i): return keys(kf, i, N_A)
    return _std(kw, a)

def _gale():
    kw = dict(dy=-20, scale=0.95, jaw=0.3, head_dy=10, neck=(1.5,) * 7, **W2(40, -30, 0, 0.85), **arms((10, 20, 10)))
    def a(i):
        u = TAU * i / N_A; b = sin(2 * u)
        p = dict(fly(2 * u, 0.2)); w = (5 + 38 * b, -22 * max(0, b) + 10 * max(0, -b), -18 * cos(2 * u), 1.02 - 0.14 * b, 1.0)
        p.update(dy=30 * sin(2 * u - 0.6), scale=1 - 0.03 * b, wingL=w, wingR=w, jaw=0.7, head_dy=-12 * sin(2 * u - 0.6),
                 tail=tuple(-1 + (1.5 + 0.3 * k) * sin(2 * u - 0.6 * k) for k in range(12)), **arms((6 + 8 * b, 10, 6)))
        return p
    return _std(kw, a)

def _inhale():
    kw = dict(scale=1.04, jaw=1.2, head=6, head_scale=1.5, neck=(-2,) * 7, **W2(10, 10, 0, 1.04), **arms((20, 10, 0)))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(u, 0.3)); w = (10 + 5 * sin(u), 10, 0, 1.05, 1.0)
        p.update(scale=1.06 + 0.02 * sin(2 * u), sx=1 + 0.03 * sin(2 * u), wingL=w, wingR=w, jaw=1.28, head=6 + 2 * sin(2 * u), head_scale=1.52, neck=(-2,) * 7,
                 head_dy=10, **arms((22, 12, 4)), tail=tuple(-1.5 + sin(u - 0.5 * k) for k in range(12)))
        return shake(p, i, 2, 2)
    rest = dict(dy=20, scale=1.1, head_dy=60, head_scale=1.6, jaw=1.3, neck=(-1.5,) * 7, **W2(-20, 8, 6, 1.08))     # 吐き出す
    return _std(kw, a, rest)

def _glide():
    kw = dict(dy=-60, rot=-12, scale=0.9, jaw=0.4, **W2(34, -16, 0))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(0, 0)); w = (12 + 3 * sin(2 * u), -40, 0, 0.92, 1.0)
        p.update(scale=1.15, rot=6 * sin(u), dx=14 * sin(u), dy=6 * sin(2 * u), wingL=w, wingR=w, head_scale=1.5, head_dy=28, jaw=1.0, neck=(-1,) * 7, head=-4 * sin(u),
                 tail=tuple(3 + 1.2 * sin(2 * u - 0.7 * k) for k in range(12)), **arms((-15, -10, 0)), **legs((-12, 15)))
        return shake(p, i, 2, 1)
    return _std(kw, a)

def _roar():
    kw = dict(dy=-25, neck=(3,) * 7, head=-12, head_dy=-25, head_scale=1.3, jaw=0.25, **W2(28, -14, 0), **arms((14, 14, 8)))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(u, 0.25)); w = (14 + 4 * sin(4 * u), 14, 0, 1.1, 1.0)
        p.update(scale=1.06, wingL=w, wingR=w, head_scale=1.62, head_dy=40, head=6 * sin(2 * u), jaw=1.35, neck=(-1.2,) * 7,
                 tail=tuple((2.5 + 0.3 * k) * sin(2 * u - 0.6 * k) for k in range(12)), **arms((-20, -15, -25)), **legs((8, -6)))
        return shake(p, i, 5, 3)
    return _std(kw, a)

def _slam():
    kw = dict(dy=-80, scale=0.95, jaw=0.4, **W2(34, -8, 0), **arms((50, 35, 25)), **legs((-8, 16)))
    up = dict(fly(0, 0)); up.update(dy=-60, jaw=0.5, **W2(30, -6, -6), **arms((50, 35, 25)), **legs((-8, 16)), tail=(-2,) * 12)
    down = dict(fly(0, 0)); down.update(dy=45, scale=1.06, jaw=1.2, head_dy=30, head_scale=1.5, **W2(-32, 10, 14, 1.06), **arms((-40, -20, -10)), **legs((10, -10)), tail=(3,) * 12)
    hold = dict(down, dy=38, **W2(-26, 8, 4, 1.05))
    kf = [(0, up), (3, down), (7, hold), (15, dict(up, dy=-50))]
    def a(i):
        p = keys(kf, i, N_A); return shake(p, i, 5, 3) if 3 <= i <= 8 else p
    return _std(kw, a)

def _tail():
    kw = dict(rot=-14, dx=25, tail=(-5,) * 12, jaw=0.4, wingL=(20, -8, 0, 1, 1), wingR=(-10, 0, 0, 1, 1))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(u, 0.3))
        p.update(rot=-10 * sin(u + 0.5), dx=30 * sin(u), wingL=(10 + 14 * sin(u), -6, 0, 1, 1), wingR=(10 - 14 * sin(u), -6, 0, 1, 1), jaw=0.6,
                 tail=tuple(2 + 7 * sin(u - 0.45 * k) for k in range(12)), head=6 * sin(u + 0.5), **legs((6 * sin(u), 4 * sin(u))))
        return p
    return _std(kw, a)

def _cyclone():
    kw = dict(scale=0.95, jaw=0.4, **W2(8, -25, 0, 0.72))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(u, 0.2))
        p.update(rot=12 * sin(u), dx=35 * sin(u), dy=12 * sin(2 * u), wingL=(30 * sin(u), -14 * max(0, sin(u)), -12 * cos(u), 1.04, 1.0),
                 wingR=(-30 * sin(u), -14 * max(0, -sin(u)), 12 * cos(u), 1.04, 1.0), head=-9 * sin(u), jaw=0.8,
                 tail=tuple((2 + 0.3 * k) * sin(u - 0.6 * k + 1) for k in range(12)), **arms((10, 6, 4)))
        return p
    return _std(kw, a)

def _wrath():
    kw = dict(scale=0.9, neck=(4,) * 7, head_dy=20, jaw=0.3, tail=(-5,) * 12, **W2(12, -45, 0, 0.8), **arms((-10, 40, 30)), **legs((-10, 22)))
    def a(i):
        u = TAU * i / N_A
        p = dict(fly(0, 0)); w = (16 + 8 * sin(2 * u), 16, -6 * cos(2 * u), 1.12, 1.0)
        p.update(scale=1.12 + 0.03 * sin(2 * u), wingL=w, wingR=w, head_scale=1.6, head_dy=30, head=5 * sin(2 * u), jaw=1.35, neck=(-1.5,) * 7,
                 tail=tuple(2 + (2.5 + 0.3 * k) * sin(2 * u - 0.6 * k) for k in range(12)), **arms((30, -15, -25)), **legs((12, -10)))
        return shake(p, i, 8, 5)
    return _std(kw, a)

MOVES = dict(breath=_breath(), dive=_dive(), gale=_gale(), inhale=_inhale(), glide=_glide(), roar=_roar(), slam=_slam(), tail=_tail(), cyclone=_cyclone(), wrath=_wrath())
MOVE_NAMES = dict(breath='ブレス', dive='急降下の爪', gale='羽ばたき', inhale='吸い込み', glide='滑空', roar='咆哮', slam='叩きつけ', tail='尻尾', cyclone='旋回', wrath='逆鱗')

def all_anims():
    """(名前, コマ数, コマ番号 → ポーズ) の一覧。名前は idle / <技>_windup / <技>_attack / <技>_recover"""
    out = [('idle', N_IDLE, idle)]
    for m, d in MOVES.items():
        out += [(f'{m}_windup', N_W, d['windup']), (f'{m}_attack', N_A, d['attack']), (f'{m}_recover', N_R, d['recover'])]
    return out
