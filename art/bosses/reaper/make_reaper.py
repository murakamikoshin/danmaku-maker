import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/reaper_source.png、Canvaで生成)を、色の表を使う版(pixel_pal.py)でドット化し、部位の地図で動かす
ID = 'reaper'
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=10)
WISPS = [(34, 47), (83, 41)]
CORE = [(66, 30)]
# 人魂(浮いている)はゆらめく。マントのすそはぼろぼろにゆれる。大鎌(手に持った物)・手・体・脚は動かさない
MOTIONS = {'wisp_l': (0, 2, 0.0), 'wisp_r': (0, 2, 2.2)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=2.4, bubbles=[(8, 20, 1), (104, 16, 1), (10, 96, 1), (104, 100, 1)],
                      c1=(80, 255, 160), c2=(210, 255, 230))
frames = dict(idle=idle)
def wisps(im, f, mv, c1=(80, 255, 160), c2=(210, 255, 230)):
    # 技の間、人魂が交互に強く光る
    for k, (x0, y0) in enumerate(WISPS):
        if (f + k) % 2 == 0:
            x, y = mv(x0, y0); star(im, x, y, 3, c1, c2)
frames.update(standard(idle, dict(core=CORE, c1=(80, 255, 160), c2=(210, 255, 230), lean=-1, attack_extra=wisps)))
frames['idle_awakened'] = awakened(idle, 0.0, (120, 10, 24), (255, 110, 120), (255, 40, 60), (60, 50), sat=1.4, thr=0.1)
awake_states(frames, dict(core=CORE, c1=(255, 40, 60), c2=(255, 190, 200), lean=-1,
                          attack_extra=lambda im, f, mv: wisps(im, f, mv, (255, 40, 60), (255, 190, 200))))
NOTE = '元の絵は Canva で生成したイラスト(source/reaper_source.png)を、色の表を使う版でドット化したもの(高さ84)。待機は人魂のゆらめきとマントのすそのゆれ。技の中心はフードのドクロ。覚醒後は緑の光が赤に変わる'
if __name__ == '__main__':
    size, nc = export(ID, '死神', frames, NOTE); print(ID, size, nc, 'colors')
