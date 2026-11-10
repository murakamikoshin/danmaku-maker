import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'mech'
OL=(8,10,14)
S1=(26,30,40); S2=(46,52,66); S3=(76,84,104); S4=(120,130,152); S5=(186,194,212)
O1=(200,100,28); O2=(255,170,60); O3=(110,50,18)

def pal(aw):
    if not aw:
        return dict(c1=(255,44,64), c2=(255,150,160), c3=(130,10,30), o1=O1, o2=O2, o3=O3)
    return dict(c1=(80,220,255), c2=(220,250,255), c3=(20,80,150), o1=(200,40,60), o2=(255,90,100), o3=(90,10,24))

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    aw = p.get('awake', False); c = pal(aw)
    sp = p.get('spread', 0); gl = p.get('glow', 1)
    # 背中の装甲板(羽根の代わり)
    root = (50, 40)
    fan(img, root, 160 - sp, 250, 40 + sp, [S1, S2, S3, S2], OL, layers=4)
    rays(img, root, 158 - sp, 252, 9, 8, 42 + sp, S3, c['o2'], tiplen=3, wobble=[0, 4, 2, 6], width=2)
    # 腰の装甲
    robe(img, dict(ol=OL, d=S1, m=S2, l=S3), top=70, bot=102, wtop=12, wbot=16)
    # 胴
    tor = poly(M(), [(CX, 30), (CX - 14, 32), (CX - 20, 42), (CX - 18, 64), (CX - 11, 74), (CX, 76)])
    part(img, tor, S3, shade=S2, light=S5, ol=OL, sw=5)
    paint(img, inter(line(M(), [(CX - 16, 46), (CX - 6, 46)], 1), tor), S2)
    paint(img, inter(line(M(), [(CX - 15, 62), (CX - 6, 66)], 1), tor), S2)
    # 肩の装甲
    sh_ = ell(M(), 38 - sp//2, 38, 11, 9); part(img, sh_, S4, shade=S2, light=S5, ol=OL, sw=4)
    paint(img, inter(line(M(), [(30 - sp//2, 34), (44 - sp//2, 34)], 1), sh_), c['o1'])
    # 砲身の腕(下=プレイヤーに向く)
    gun = poly(M(), [(34 - sp//2, 44), (28 - sp//2, 48), (28 - sp//2, 86), (40 - sp//2, 86), (40 - sp//2, 48)])
    part(img, gun, S3, shade=S1, light=S4, ol=OL, sw=4)
    for y in (56, 66, 76): paint(img, line(M(), [(29 - sp//2, y), (39 - sp//2, y)], 1), S2)
    mz = ell(M(), 34 - sp//2, 87, 5, 3); part(img, mz, S2, ol=OL)
    paint(img, ell(M(), 34 - sp//2, 87, 3, 1.5), c['o2'] if gl else c['o3'])
    # 頭とV字のアンテナ
    v = poly(M(), [(CX - 1, 22), (48, 6), (51, 6), (CX, 18)])
    part(img, v, c['o1'], shade=c['o3'], light=c['o2'], ol=OL, sw=1)
    hd = poly(M(), [(CX, 16), (CX - 6, 17), (CX - 8, 24), (CX - 6, 31), (CX, 32)])
    part(img, hd, S4, shade=S2, light=S5, ol=OL, sw=3)
    paint(img, poly(M(), [(CX, 23), (CX - 6, 23), (CX - 6, 25), (CX, 25)]), OL)
    paint(img, line(M(), [(CX - 5, 24), (CX - 1, 24)], 1), c['c1'])
    # 核: 胸のコアアイ
    r = 10 + (1 if gl >= 2 else 0)
    paint(img, ell(M(), CX, 50, r + 1, r + 1, sym=False), OL)
    ring = ell(M(), CX, 50, r, r, sym=False); part(img, ring, S4, shade=S2, light=S5, sw=2)
    iris = ell(M(), CX, 50, r - 3, r - 3, sym=False)
    part(img, iris, c['c1'] if gl else c['c3'], shade=c['c3'], light=c['c2'] if gl else c['c1'], ol=OL, sw=3)
    paint(img, ell(M(), CX, 50, 1.5, 4, sym=False), OL)
    if gl:
        px(img, CX - 3.5, 46, (255, 255, 255)); px(img, CX - 2.5, 46, c['c2']); px(img, CX - 3.5, 47, c['c2'])
    if gl >= 2:
        for dx_, dy_ in ((-14, -6), (12, -10), (0, -15)): px(img, CX + dx_, 50 + dy_, c['c2'], sym=False)
    # 腰のランプ
    for x in (CX - 9, CX - 5): px(img, x, 80, c['o2'] if gl else c['o3'])
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-1.5*s), spread=round(1.5*s), glow=1)
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/me_idle0.png')
