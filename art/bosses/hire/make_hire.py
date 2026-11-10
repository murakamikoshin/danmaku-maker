import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/hire_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化する
ID = 'hire'
still = make_still.make(HERE)
# 部位の地図(source/hire_parts.json → source/hire_partmap.png)で、どのドットが何かを分かったうえで動かす
base, lab, parts = from_still_parts(still, foot=23)
MOTIONS = {'ribbon_l': (1, 1, 0.0), 'ribbon_r': (1, 1, 1.6), 'ribbon_l2': (0, 1, 0.8), 'ribbon_r2': (0, 1, 2.4),
           'goldfish': (0, 2, 0.8)}        # ポイ(手に持った物)と体は動かさない。ひれ(flow)は自動でゆれる
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=2.6,
                      bubbles=[(18, 34, 2), (96, 30, 2), (100, 74, 3), (12, 80, 1), (94, 96, 1), (24, 96, 2), (88, 54, 1)])
frames = dict(idle=idle)
CORE = [(39, 33), (73, 42)]          # ポイ、金魚をのせた手
frames.update(standard(idle, dict(core=CORE, c1=(255, 110, 70), c2=(255, 236, 200), lean=1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.78, (90, 30, 140), (220, 160, 255), (180, 80, 255), (56, 52), r0=24, r1=46, sat=1.2, val=0.75)
awake_states(frames, dict(core=CORE, c1=(190, 90, 255), c2=(240, 210, 255), lean=1, scale=0.8))
NOTE = '元の絵は Canva で生成したイラスト(source/hire_source.png)を、決まった作り方(../_pipeline/README.md)でドット化したもの。待機はひれのゆれ・リボン・金魚の動き・1ドットの呼吸＋泡(体と脚の形は変えない)。覚醒は黒い出目金の紫に染まる'

if __name__ == '__main__':
    size, nc = export(ID, '金魚姫', frames, NOTE)
    print(ID, size, nc, 'colors')
