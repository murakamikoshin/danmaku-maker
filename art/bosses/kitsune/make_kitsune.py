import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/kitsune_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化し、部位の地図で動かす
ID = 'kitsune'
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=16)
FIRES = [(24, 71), (21, 54), (26, 36), (40, 24), (72, 21), (84, 32), (91, 42), (94, 57), (89, 73)]
# 尻尾(flow)は自動でゆれる。狐火(浮いている)はひとつずつずらして上下にゆらめく。御札(手に持った物)と体は動かさない
MOTIONS = {f'fire{i}': (0, 2, i * 0.7) for i in range(9)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=2.4, bubbles=[(10, 20, 1), (102, 18, 1), (8, 90, 1), (104, 92, 1)],
                      c1=(110, 190, 255), c2=(220, 245, 255))
frames = dict(idle=idle)
def tips(im, f, mv, c1=(90, 180, 255), c2=(230, 246, 255)):
    # 技の間、尻尾の先の狐火が順番に強く光る
    for k, (x0, y0) in enumerate(FIRES):
        if k % 4 == f:
            x, y = mv(x0, y0); star(im, x, y, 2, c1, c2)
frames.update(standard(idle, dict(core=[(56, 51)], c1=(90, 180, 255), c2=(230, 246, 255), lean=1, attack_extra=tips)))
frames['idle_awakened'] = awakened(idle, 0.78, (110, 40, 170), (220, 150, 255), (200, 90, 255), (56, 48), r0=28, r1=54)
awake_states(frames, dict(core=[(56, 51)], c1=(200, 90, 255), c2=(240, 200, 255), lean=1,
                          attack_extra=lambda im, f, mv: tips(im, f, mv, (200, 90, 255), (240, 200, 255))))
NOTE = '元の絵は Canva で生成したイラスト(source/kitsune_source.png)を、決まった作り方でドット化したもの(高さ80)。待機は尻尾のゆれと狐火のゆらめき。覚醒は毛並みが紫に染まる'
if __name__ == '__main__':
    size, nc = export(ID, '九尾の巫女', frames, NOTE); print(ID, size, nc, 'colors')
