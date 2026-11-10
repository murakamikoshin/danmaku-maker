import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'reaper'
OL=(8,6,12)
C1=(18,16,28); C2=(30,27,44); C3=(46,42,64); C4=(70,64,92)
BO=(222,214,196); BO2=(150,142,128); BO3=(96,90,82)
BL=(168,178,200); BL2=(222,232,244); BL3=(92,98,122); WOOD=(58,40,34)

def pal(aw):
    if not aw:
        return dict(g1=(80,230,150), g2=(196,255,220), g3=(30,120,80), tip=C4)
    return dict(g1=(255,60,80), g2=(255,190,200), g3=(130,10,30), tip=(120,20,36))

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    aw = p.get('awake', False); c = pal(aw)
    sp = p.get('spread', 0); gl = p.get('glow', 1); t = p.get('t', 0)
    # 大鎌の柄(体のうしろ、まっすぐ)
    paint(img, line(M(), [(CX, 30), (CX, 100)], 3, sym=False), WOOD)
    paint(img, line(M(), [(CX - 1, 30), (CX - 1, 100)], 1, sym=False), (90,64,52))
    # 三日月の刃(頭の上で左右に大きく)
    cres = sub(ell(M(), CX, 40, 54, 34), ell(M(), CX, 47, 52, 33))
    cres = inter(cres, poly(M(), [(0, 0), (CX, 0), (CX, 30), (0, 46)]))
    part(img, cres, BL, shade=BL3, light=BL2, ol=OL, sw=2)
    if aw: paint(img, sub(cres, sh(cres, 0, 1)), c['g1'])
    # ぼろぼろの外套の裾(羽根のように左右へ)
    root = (52, 44)
    fan(img, root, 130 - sp, 236, 36 + sp, [C1, C2, C3, C2], OL, layers=4)
    rays(img, root, 128 - sp, 238, 14, 6, 40 + sp, C3, c['tip'], tiplen=6, wobble=[0, 7, 3, 9, 1, 6, 4, 10])
    # 外套の本体
    robe(img, dict(ol=OL, d=C1, m=C2, l=C3), top=30, bot=104, wtop=9, wbot=21)
    # フード
    hood = poly(M(), [(CX, 9), (CX - 6, 11), (CX - 11, 18), (CX - 13, 30), (CX - 11, 40), (CX, 42)])
    part(img, hood, C2, shade=C1, light=C4, ol=OL, sw=4)
    face = ell(M(), CX, 27, 7, 9); paint(img, face, OL)
    # どくろ
    sk = ell(M(), CX, 27, 5, 6); part(img, sk, BO, shade=BO2, ol=None, sw=2)
    paint(img, poly(M(), [(CX, 31), (CX - 4, 31), (CX - 3, 35), (CX, 35)]), BO2)
    for x in (CX - 2.5, CX - 0.5): px(img, x, 33, OL)
    # 目の穴と光
    paint(img, ell(M(), CX - 2.5, 26, 1.5, 1.5), OL)
    px(img, CX - 2.5, 26, c['g2'] if gl else c['g3']); px(img, CX - 3.5, 26, c['g1'])
    # 骨の手
    arm = line(M(), [(52, 38), (46, 52), (42 - sp//2, 62)], 4)
    part(img, arm, C2, shade=C1, light=C3, ol=OL, sw=2)
    for fx in (-2, 0, 2):
        paint(img, line(M(), [(41 - sp//2, 63), (41 - sp//2 + fx, 68)], 1), BO2)
    part(img, ell(M(), 41 - sp//2, 64, 2, 2), BO, shade=BO2, ol=OL, sw=1)
    # 核: 手元の魂の炎(左右)
    r = 4 + (1 if gl >= 2 else 0); ox, oy = 37 - sp//2, 74
    fl = poly(M(), [(ox, oy - 10 - r), (ox - r, oy), (ox, oy + r), (ox + r, oy)])
    part(img, fl, c['g1'] if gl else c['g3'], shade=c['g3'], light=c['g2'], ol=OL, sw=2)
    if gl: px(img, ox, oy - 1, (255, 255, 255)); px(img, ox, oy, c['g2'])
    # 胸の核(魂の結晶)
    core = ell(M(), CX, 50, 3 + (1 if gl >= 2 else 0), 3 + (1 if gl >= 2 else 0))
    part(img, core, c['g1'] if gl else c['g3'], light=c['g2'], ol=OL, sw=1)
    if gl: px(img, CX - .5, 49, (255, 255, 255))
    # 鎖
    for y in range(56, 98, 4): px(img, CX - 7, y, BO3); px(img, CX - 8, y + 2, BO3)
    # 漂う魂の粒
    for i, (x0, y0) in enumerate(((18, 96), (8, 60), (28, 112), (12, 30))):
        y = (y0 - int(t * 16) - i * 6) % 120
        px(img, x0, y, c['g1'] if i % 2 else c['g2'])
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-2*s), spread=round(2*s), glow=1)
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/re_idle0.png')
