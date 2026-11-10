import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'punimaru'
OL=(56,18,44)
P1=(150,50,110); P2=(214,90,150); P3=(250,140,186); P4=(255,196,222); WH=(255,250,252)
EY=(36,16,40); BL=(255,110,150)

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    sq = p.get('squash', 0)   # +でつぶれる
    rx, ry = 22 + sq, 18 - sq
    cy = 82 + sq
    # 影
    paint(img, ell(M(), CX, 101, 18 + sq, 3), (24, 16, 34))
    # 体(ぷにぷに)
    b = ell(M(), CX, cy, rx, ry, sym=False)
    poly(b, [(CX, cy - ry - 6), (CX - 3, cy - ry + 2), (CX, cy - ry + 2)])
    part(img, b, P2, shade=P1, light=P3, ol=OL, sw=5)
    paint(img, inter(sub(ell(M(), CX, cy + 2, rx - 2, ry - 2, sym=False), ell(M(), CX, cy, rx - 2, ry - 2, sym=False)), b), P1)
    # つや
    paint(img, ell(M(), CX - 12, cy - 8, 4, 2.5, sym=False), P4)
    paint(img, ell(M(), CX - 13, cy - 9, 2, 1, sym=False), WH)
    px(img, CX - 6.5, cy - 13, P4, sym=False)
    # 目(大きくてかわいい)
    for ex in (CX - 8,):
        e = ell(M(), ex, cy - 1, 3, 4); paint(img, e, EY)
        px(img, ex - 1, cy - 3, WH); px(img, ex, cy - 3, WH); px(img, ex - 1, cy - 2, WH)
        px(img, ex + 1, cy + 1, P2)
    # ほっぺ
    paint(img, ell(M(), CX - 14, cy + 4, 2, 1), BL)
    # 口
    px(img, CX - 1.5, cy + 5, EY); px(img, CX - 0.5, cy + 6, EY)
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-3*max(0, s)), squash=round(2*min(0, s)) * -1 if s < 0 else -round(1*s))
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/pu_idle0.png')
