import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'kitsune'
OL=(14,6,12)
W1=(184,172,192); W2=(122,110,140); W3=(78,68,96)
R1=(122,20,44); R2=(74,12,30); R0=(196,42,66)
F1=(214,140,54); F2=(140,74,34); F3=(80,38,24); TIP=(240,222,200)
B1=(90,180,255); B2=(200,240,255)
SK=(239,224,220); SK2=(201,174,182)

def pal(aw):
    if not aw:
        return dict(f1=F1, f2=F2, f3=F3, tip=TIP, b1=B1, b2=B2, eye=R0, hair=F1, hair2=F2, hairl=TIP)
    # 覚醒: 黒い毛並み・紫の狐火
    return dict(f1=(70,40,90), f2=(40,22,56), f3=(20,10,30), tip=(200,90,255), b1=(190,80,255), b2=(240,200,255),
                eye=(200,90,255), hair=(70,40,90), hair2=(40,22,56), hairl=(130,90,160))

def tail(img, ang, L, c, fire):
    """尾: 暗い細長い面 + 毛の細い線の束(堕天使の羽根と同じ描き方)"""
    root = (CX - 2, 62)
    a = math.radians(ang)
    ex, ey = root[0] + math.cos(a)*L, root[1] + math.sin(a)*L
    pts = [root]
    for k in range(9):
        aa = math.radians(ang - 9 + 18*k/8)
        rr = L*0.92 - (3 if k % 2 else 0)
        pts.append((root[0] + math.cos(aa)*rr, root[1] + math.sin(aa)*rr))
    m = poly(M(), pts)
    part(img, m, c['f3'], shade=OL, ol=OL, sw=2)
    rays(img, root, ang - 8, ang + 8, 6, 10, L, c['f2'], c['f1'], tiplen=6, wobble=[0, 4, 1, 5, 2, 3])
    rays(img, root, ang - 4, ang + 4, 3, 22, L + 2, c['f1'], c['tip'], tiplen=4, wobble=[2, 0, 3])
    if fire:
        fl = poly(M(), [(ex, ey - 6 - fire), (ex - 3, ey - 1), (ex, ey + 2), (ex + 3, ey - 1)])
        part(img, fl, c['b1'], light=c['b2'])
        px(img, ex, ey - 1, c['b2'])

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    aw = p.get('awake', False); c = pal(aw)
    sp = p.get('spread', 0); gl = p.get('glow', 1); fire = p.get('fire', 2)
    # 九本の尾(片側4本+まんなか1本)
    for ang in (160, 188, 214, 240):
        tail(img, ang - sp, 50, c, fire)
    tail(img, 270, 46, c, fire)
    # 髪(うしろ)と顔
    head(img, dict(ol=OL, skin=SK, skin2=SK2, hair=c['hair'], hair2=c['hair2'], hairl=c['hairl'],
                   eye=c['eye'], eyel=TIP), cy=25, hair_len=58, hair_w=11)
    # 狐の耳
    ear = poly(M(), [(56, 21), (52, 7), (61, 17)])
    part(img, ear, c['f1'], shade=c['f2'], light=c['tip'], ol=OL, sw=2)
    paint(img, poly(M(), [(56, 18), (54, 11), (59, 17)]), R0 if not aw else c['f3'])
    # はかま(赤)
    robe(img, dict(ol=OL, d=R2, m=R1, l=R0), top=56, bot=100, wtop=11, wbot=18)
    # 白衣(上)
    top = poly(M(), [(CX, 34), (CX - 7, 35), (CX - 11, 40), (CX - 12, 60), (CX, 62)])
    part(img, top, W1, shade=W2, light=TIP, ol=OL, sw=4)
    paint(img, line(M(), [(CX - 6, 35), (CX, 46)], 1), R1)     # えりの赤
    paint(img, poly(M(), [(CX, 57), (CX - 12, 56), (CX - 12, 60), (CX, 61)]), R0)  # 帯
    # 大きなそで
    sl = poly(M(), [(54, 37), (43 - sp//2, 46), (38 - sp//2, 72), (48, 73), (52, 56)])
    part(img, sl, W1, shade=W2, light=TIP, ol=OL, sw=5)
    paint(img, line(M(), [(38 - sp//2, 72), (48, 73)], 1), R0)
    paint(img, inter(line(M(), [(46, 50), (43 - sp//2, 70)], 1), sl), W3)
    part(img, ell(M(), 46, 66, 2, 2), SK, shade=SK2, ol=OL, sw=1)
    # 核: 手元の狐火(左右)
    r = 4 + (1 if gl >= 2 else 0); ox = 40 - sp//2
    for i, col in enumerate((OL, c['b1'] if gl else W3, c['b2'] if gl else W2)):
        paint(img, ell(M(), ox, 66, r + 1 - i*2, r + 1 - i*2), col)
    if gl: px(img, ox, 65, (255, 255, 255))
    if gl >= 2:
        for dx_, dy_ in ((-7, -2), (5, -5), (0, -8)): px(img, ox + dx_, 66 + dy_, c['b2'])
    # 舞う火の粉
    t = p.get('t', 0)
    for i, (x0, y0) in enumerate(((24, 100), (14, 70), (34, 110), (6, 50))):
        y = (y0 - int(t * 20) - i * 5) % 118
        px(img, x0, y, c['b1'] if i % 2 else c['b2'])
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-2*s), spread=round(3*s), glow=1, fire=2 + round(2*math.sin(4*math.pi*t)))
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/ki_idle0.png')
