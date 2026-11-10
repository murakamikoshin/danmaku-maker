import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'kitsune'
idle = load('kitsune')

TIPS = [(56 + math.cos(math.radians(-90 + k * 24)) * 46, 60 + math.sin(math.radians(-90 + k * 24)) * 46) for k in range(-4, 5)]
def tips(im, f, mv):
    # 尻尾の先に、狐火が順番に灯る
    for k, (x0, y0) in enumerate(TIPS):
        if k % 4 == f:
            x, y = mv(x0, y0); star(im, x, y, 2, (255, 150, 50), (255, 236, 190))
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(56, 60)], c1=(255, 150, 50), c2=(255, 236, 190), lean=1, attack_extra=tips)))
frames['idle_awakened'] = awakened(idle, 0.78, (120, 40, 170), (220, 150, 255), (200, 90, 255), (56, 56))
NOTE = '覚醒後は、毛並みが紫に染まり、うしろに放射する光と、体のふちの点滅する光がつく'

if __name__ == '__main__':
    size, nc = export(ID, '九尾の巫女', frames, NOTE)
    print(ID, size, nc, 'colors')
