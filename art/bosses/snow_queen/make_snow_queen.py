import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'snow_queen'
OL=(10,10,24); D=(22,30,58); Mi=(36,52,92); L=(62,88,140)
I1=(90,170,220); I2=(170,230,255); WH=(240,248,255)
SK=(239,224,220); SK2=(201,174,182)
HA=(196,208,232); HA2=(120,134,170)
EYE=(80,220,255)

def pal(aw):
    if not aw:
        return dict(ol=OL, d=D, m=Mi, l=L, i1=I1, i2=I2, eye=EYE, hair=HA, hair2=HA2, hairl=WH)
    # 覚醒: 赤い氷・黒髪
    return dict(ol=(14,4,12), d=(40,10,26), m=(70,18,40), l=(110,30,56), i1=(230,50,80), i2=(255,170,180),
                eye=(255,60,80), hair=(40,30,52), hair2=(20,14,30), hairl=(90,70,110))

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    aw = p.get('awake', False); c = pal(aw)
    sp = p.get('spread', 0); gl = p.get('glow', 1); t = p.get('t', 0)
    # 雪の結晶の光輪(頭のうしろ)
    hl = 15 + p.get('halo', 0)
    for ang in (-90, -150, 150, -30, 30, 90):
        a = math.radians(ang); x1, y1 = CX + math.cos(a)*hl, 20 + math.sin(a)*hl
        paint(img, line(M(), [(CX, 20), (x1, y1)], 1, sym=False), c['i1'])
        bx, by = CX + math.cos(a)*hl*.6, 20 + math.sin(a)*hl*.6
        for s_ in (0.5, -0.5):
            paint(img, line(M(), [(bx, by), (bx + math.cos(a+s_)*4, by + math.sin(a+s_)*4)], 1, sym=False), c['i2'])
        px(img, x1, y1, WH, sym=False)
    # 氷の翼: 暗い帯の扇 + 結晶の細い線
    root = (54, 42)
    fan(img, root, 150 - sp, 272, 40 + sp, [c['d'], c['m'], c['l']], c['ol'])
    rays(img, root, 146 - sp, 276, 17, 8, 46 + sp, c['l'], c['i2'], tiplen=5, wobble=[0, 6, 2, 9, 4, 7, 1, 10, 3])
    rays(img, root, 160 - sp, 262, 9, 6, 32 + sp, c['i1'], c['i2'], tiplen=3, wobble=[0, 4, 2])
    # 髪と顔
    head(img, dict(ol=c['ol'], skin=SK, skin2=SK2, hair=c['hair'], hair2=c['hair2'], hairl=c['hairl'],
                   eye=c['eye'], eyel=WH), cy=25, hair_len=60, hair_w=11)
    # ローブ
    m = robe(img, dict(ol=c['ol'], d=c['d'], m=c['m'], l=c['l']), top=34, bot=100, wtop=7, wbot=18)
    paint(img, line(M(), [(CX, 46), (CX, 99)], 2, sym=False), c['i1'])
    paint(img, line(M(), [(CX - .5, 50), (CX - .5, 99)], 1, sym=False), c['i2'])
    # 毛皮のえり
    fur = poly(M(), [(CX, 37), (CX - 6, 34), (CX - 10, 37), (CX - 8, 40), (CX - 3, 40)])
    part(img, fur, c['hair2'], shade=c['l'], light=c['hair'], ol=c['ol'], sw=1)
    # 腕
    arm = line(M(), [(54, 38), (49, 50), (46 - sp//2, 59)], 4)
    part(img, arm, c['m'], shade=c['d'], light=c['l'], ol=c['ol'], sw=2)
    part(img, ell(M(), 45 - sp//2, 61, 2, 2), SK, shade=SK2, ol=c['ol'], sw=1)
    # 冠(細い氷のとげ)
    for x0, h in ((58, 6), (60.5, 9), (CX, 12)):
        paint(img, line(M(), [(x0, 17), (x0, 17 - h)], 1), c['i2'])
        px(img, x0, 17 - h, WH)
    paint(img, line(M(), [(57, 17), (CX, 17)], 1), c['i1'])
    # 手元に浮かぶ氷の結晶(左右)
    for cx_, cy_ in ((40 - sp//2, 64),):
        r = 4 + (1 if gl >= 2 else 0)
        dm = poly(M(), [(cx_, cy_ - r - 2), (cx_ - r, cy_), (cx_, cy_ + r + 2), (cx_ + r, cy_)])
        part(img, dm, c['i1'] if gl else c['l'], shade=c['m'], light=c['i2'], ol=c['ol'], sw=2)
        if gl: px(img, cx_, cy_ - 1, WH); px(img, cx_ - 1, cy_, c['i2'])
    # 核: 胸の雪結晶のブローチ
    r = 3 + (1 if gl >= 2 else 0)
    core = poly(M(), [(CX, 41 - r), (CX - r, 44), (CX, 47 + r), (CX + r, 44)], sym=False)
    part(img, core, c['i1'] if gl else c['m'], light=c['i2'], ol=c['ol'], sw=1)
    if gl: px(img, CX, 43, WH)
    if gl >= 2:
        for dx_, dy_ in ((0, -9), (7, 0), (5, -6)): px(img, CX - dx_, 44 + dy_, WH)
    # 雪の粒
    for i, (x0, y0) in enumerate(((22, 12), (30, 96), (12, 80), (44, 108), (8, 40), (36, 6))):
        y = (y0 + int(t * 16) + i * 5) % 118
        px(img, x0, y, c['i2'] if i % 2 else WH)
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-2*s), spread=round(2*s), halo=round(s), glow=1)
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/sq_idle0.png')
