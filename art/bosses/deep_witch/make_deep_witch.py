import sys, math, os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '_lib'))
from pix import *

ID = 'deep_witch'
OL=(6,10,18)
T1=(10,32,46); T2=(16,56,72); T3=(28,92,104); T4=(64,146,150); T5=(140,210,200)
P1=(28,18,48); P2=(48,32,80); P3=(78,58,122); P4=(120,96,170)
SK=(200,226,232); SK2=(138,168,188)
L1=(255,216,104); L2=(255,250,214); L3=(196,132,40)

def pal(aw):
    if not aw:
        return dict(t1=T1, t2=T2, t3=T3, t4=T4, t5=T5, l1=L1, l2=L2, l3=L3, eye=L1)
    return dict(t1=(40,8,20), t2=(76,14,36), t3=(120,24,52), t4=(180,50,80), t5=(240,130,150),
                l1=(120,255,220), l2=(230,255,250), l3=(30,150,130), eye=(120,255,220))

def draw(p):
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    aw = p.get('awake', False); c = pal(aw)
    sp = p.get('spread', 0); gl = p.get('glow', 1); t = p.get('t', 0); wv = p.get('wave', 0)
    # 大きなひれ(羽根の代わり)
    root = (52, 46)
    fan(img, root, 150 - sp, 250, 38 + sp, [c['t1'], c['t2'], c['t3'], c['t2']], OL, layers=4)
    rays(img, root, 148 - sp, 252, 12, 6, 42 + sp, c['t3'], c['t5'], tiplen=4, wobble=[0, 5, 2, 7, 1, 4])
    # 触手のすそ(片側3本)
    for k, (a0, L) in enumerate(((112, 34), (130, 38), (150, 32))):
        a = math.radians(a0); m = M()
        for i in range(31):
            s = i / 30
            ww = math.sin(s * 5 + wv + k) * 4 * s
            x = 56 + math.cos(a) * L * s + ww; y = 78 + math.sin(a) * L * s
            ell(m, x, y, 3.5 * (1 - s) + 1, 3.5 * (1 - s) + 1)
        part(img, m, c['t2'], shade=c['t1'], light=c['t4'], ol=OL, sw=2)
        for i in range(4, 28, 6):
            s = i / 30; ww = math.sin(s * 5 + wv + k) * 4 * s
            px(img, 56 + math.cos(a) * L * s + ww, 78 + math.sin(a) * L * s, c['t5'])
    # 衣
    robe(img, dict(ol=OL, d=P1, m=P2, l=P3), top=34, bot=86, wtop=7, wbot=14)
    paint(img, line(M(), [(CX, 40), (CX, 85)], 1, sym=False), c['t4'])
    # 髪と顔
    head(img, dict(ol=OL, skin=SK, skin2=SK2, hair=c['t2'], hair2=c['t1'], hairl=c['t4'], eye=c['eye'], eyel=L2),
         cy=27, hair_len=58, hair_w=11)
    # 耳ひれ
    rays(img, (56, 28), 170, 230, 5, 1, 10, c['t3'], c['t5'], tiplen=2)
    # 魔女の帽子(つばは広く、先から釣り竿の光)
    brim = ell(M(), CX, 19, 20, 4); part(img, brim, P2, shade=P1, light=P4, ol=OL, sw=2)
    cone = poly(M(), [(CX, 6), (CX - 4, 8), (CX - 10, 19), (CX, 19)])
    part(img, cone, P2, shade=P1, light=P4, ol=OL, sw=3)
    paint(img, poly(M(), [(CX, 16), (CX - 10, 16), (CX - 10, 18), (CX, 18)]), c['t3'])
    # 腕
    arm = line(M(), [(55, 38), (49, 52), (45 - sp//2, 62)], 4)
    part(img, arm, P2, shade=P1, light=P3, ol=OL, sw=2)
    part(img, ell(M(), 44 - sp//2, 64, 2, 2), SK, shade=SK2, ol=OL, sw=1)
    # 核: 帽子の先の提灯(釣り竿)
    paint(img, line(M(), [(CX, 6), (CX, 4)], 2, sym=False), OL)
    r = 4 + (1 if gl >= 2 else 0)
    paint(img, ell(M(), CX, 4, r + 1, r + 1, sym=False), OL)
    paint(img, ell(M(), CX, 4, r, r, sym=False), c['l1'] if gl else c['l3'])
    if gl:
        paint(img, ell(M(), CX, 3, r - 2, r - 2, sym=False), c['l2']); px(img, CX - .5, 3, (255, 255, 255))
    if gl >= 2:
        for dx_, dy_ in ((-8, 2), (6, -1), (-4, 8)): px(img, CX + dx_, 4 + dy_, c['l2'])
    # 手元の小さな提灯の光(左右)
    ox = 39 - sp//2
    paint(img, ell(M(), ox, 68, 3, 3), OL); paint(img, ell(M(), ox, 68, 2, 2), c['l1'] if gl else c['l3'])
    if gl: px(img, ox, 67, c['l2'])
    # 泡
    for i, (x0, y0) in enumerate(((20, 100), (10, 70), (30, 116), (6, 40), (40, 90))):
        y = (y0 - int(t * 24) - i * 7) % 120
        if i % 2: px(img, x0, y, c['t5'])
        else:
            for dx_, dy_ in ((0, -1), (-1, 0), (1, 0), (0, 1)): px(img, x0 + dx_, y + dy_, c['t4'])
    mirror_left(img)
    return offset(img, p.get('dx', 0), p.get('bob', 0))

def pose(state, f):
    if state == 'idle':
        t = f / 8; s = math.sin(2*math.pi*t)
        return dict(t=t, bob=round(-2*s), spread=round(2*s), glow=1, wave=2*math.pi*t)
    raise ValueError(state)

if __name__ == '__main__':
    draw(pose('idle', 0)).save('/tmp/dw_idle0.png')
