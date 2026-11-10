import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/ice_source.png、Canvaで生成)を、色の表を使う版(pixel_pal.py)でドット化し、部位の地図で動かす
ID = 'ice'
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=10)
FLAKES = [(32, 34), (80, 34), (24, 52), (88, 52)]
CORE = [(56, 48)]
# 雪の結晶(浮いている)はひとつずつずらして上下にゆらめく。髪とドレスのすそはゆれる。手・顔・脚・ティアラは動かさない
MOTIONS = {f'flake{i}': (0, 2, i * 1.3) for i in range(4)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=1.8, bubbles=[(8, 14, 1), (104, 12, 1), (10, 96, 1), (102, 98, 1)],
                      c1=(140, 210, 255), c2=(255, 255, 255))
frames = dict(idle=idle)
def flakes(im, f, mv, c1=(140, 210, 255), c2=(255, 255, 255)):
    # 技の間、まわりの結晶が順番に光る
    for k, (x0, y0) in enumerate(FLAKES):
        if k % 4 == f:
            x, y = mv(x0, y0); star(im, x, y, 3, c1, c2)
frames.update(standard(idle, dict(core=CORE, c1=(140, 210, 255), c2=(255, 255, 255), lean=-1, attack_extra=flakes)))
frames['idle_awakened'] = awakened(idle, 0.95, (120, 30, 60), (255, 170, 200), (255, 120, 160), (56, 46))
awake_states(frames, dict(core=CORE, c1=(255, 120, 160), c2=(255, 235, 240), lean=-1,
                          attack_extra=lambda im, f, mv: flakes(im, f, mv, (255, 120, 160), (255, 235, 240))))
NOTE = '元の絵は Canva で生成したイラスト(source/ice_source.png)を、色の表を使う版でドット化したもの(高さ84)。待機は雪の結晶のゆらめきと、髪・すそのゆれ。技の中心は胸の氷の宝石。覚醒後は紅の氷に染まる'
if __name__ == '__main__':
    size, nc = export(ID, '雪の女王', frames, NOTE); print(ID, size, nc, 'colors')
