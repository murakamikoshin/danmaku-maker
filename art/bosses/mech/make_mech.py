import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'mech'
idle = load('mech')
def cannons(im, f, mv, c1=(255, 170, 60), c2=(255, 240, 200)):
    # 肩キャノンの砲口が交互に光る
    for i, (x0, y0) in enumerate(((19, 65), (92, 65))):
        if (f + i) % 2 == 0:
            x, y = mv(x0, y0); star(im, x, y, 3, c1, c2)
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(56, 60)], c1=(90, 220, 255), c2=(230, 250, 255), lean=1, attack_extra=cannons)))
frames['idle_awakened'] = awakened(idle, 0.0, (140, 20, 20), (255, 140, 90), (255, 60, 50), (56, 58), sat=1.3)
awake_states(frames, dict(core=[(56, 60)], c1=(255, 60, 50), c2=(255, 210, 190), lean=1, attack_extra=lambda im, f, mv: cannons(im, f, mv, (255, 60, 50), (255, 210, 190))))
NOTE = '核は胸のコアアイ。覚醒後は赤く染まり、うしろに放射する光と、体のふちの点滅する光がつく'

if __name__ == '__main__':
    size, nc = export(ID, '機神', frames, NOTE)
    print(ID, size, nc, 'colors')
