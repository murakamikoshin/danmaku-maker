import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/mech_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化し、部位の地図で動かす
ID = 'mech'
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=23)
# 翼は少し上下(羽ばたき)、噴射の炎はゆらめく(浮いている扱い: 動いたあとは透明)。胴体・大砲・単眼は動かさない
MOTIONS = {'wing_ul': (0, 1, 0.0), 'wing_ur': (0, 1, 0.0), 'wing_ll': (0, -1, 0.0), 'wing_lr': (0, -1, 0.0),
           'flame_c': (0, 2, 1.0), 'flame_l': (0, 1, 2.0), 'flame_r': (0, 1, 2.6)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=0, bubbles=[(10, 30, 1), (102, 30, 1), (14, 92, 1), (98, 96, 1)],
                      c1=(255, 170, 60), c2=(255, 240, 200))
frames = dict(idle=idle)
def cannons(im, f, mv, c1=(255, 170, 60), c2=(255, 240, 200)):
    for i, (x0, y0) in enumerate(((25, 46), (86, 46))):
        if (f + i) % 2 == 0:
            x, y = mv(x0, y0); star(im, x, y, 3, c1, c2)
frames.update(standard(idle, dict(core=[(56, 49)], c1=(90, 200, 255), c2=(230, 250, 255), lean=1, attack_extra=cannons)))
frames['idle_awakened'] = awakened(idle, 0.0, (140, 20, 20), (255, 140, 90), (255, 60, 50), (56, 46), r0=26, r1=52, sat=1.3)
awake_states(frames, dict(core=[(56, 49)], c1=(255, 60, 50), c2=(255, 210, 190), lean=1,
                          attack_extra=lambda im, f, mv: cannons(im, f, mv, (255, 60, 50), (255, 210, 190))))
NOTE = '元の絵は Canva で生成したイラスト(source/mech_source.png)を、決まった作り方でドット化したもの(高さ66)。待機は翼の羽ばたきと噴射のゆらめき。覚醒は赤く染まる'
if __name__ == '__main__':
    size, nc = export(ID, '機神', frames, NOTE); print(ID, size, nc, 'colors')
