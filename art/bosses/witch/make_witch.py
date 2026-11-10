import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/witch_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化し、部位の地図で動かす
ID = 'witch'
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=16)
# 触手と長い髪(flow)は自動でゆれる。提灯は竿の先で少しゆれる。体は動かさない
MOTIONS = {'lantern': (1, 1, 0.0)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=2.2, bubbles=[(12, 30, 2), (100, 46, 2), (8, 96, 1), (104, 100, 1), (96, 12, 1)],
                      c1=(120, 220, 210), c2=(230, 255, 250))
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(77, 29)], c1=(255, 214, 90), c2=(255, 250, 220), lean=-1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.97, (130, 20, 50), (255, 120, 150), (255, 70, 100), (56, 50), r0=26, r1=52)
awake_states(frames, dict(core=[(77, 29)], c1=(255, 70, 100), c2=(255, 200, 210), lean=-1, scale=0.8))
NOTE = '元の絵は Canva で生成したイラスト(source/witch_source.png)を、決まった作り方でドット化したもの(高さ80)。待機は触手と髪のゆれ、提灯のゆれ、泡。覚醒は深紅に染まる'
if __name__ == '__main__':
    size, nc = export(ID, '深海の魔女', frames, NOTE); print(ID, size, nc, 'colors')
