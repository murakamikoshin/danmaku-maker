import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/hire_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化する
ID = 'hire'
still = make_still.make(HERE)
base = from_still(still, foot=23)
idle = idle_from_still(base, top=54, amp=1.2, bubbles=[(18, 34, 2), (96, 30, 2), (100, 74, 3), (12, 80, 1), (94, 96, 1)])
frames = dict(idle=idle)
CORE = [(39, 33), (73, 42)]          # ポイ、金魚をのせた手
frames.update(standard(idle, dict(core=CORE, c1=(255, 110, 70), c2=(255, 236, 200), lean=1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.78, (90, 30, 140), (220, 160, 255), (180, 80, 255), (56, 52), r0=24, r1=46, sat=1.2, val=0.75)
awake_states(frames, dict(core=CORE, c1=(190, 90, 255), c2=(240, 210, 255), lean=1, scale=0.8))
NOTE = '元の絵は Canva で生成したイラスト(source/hire_source.png)を、決まった作り方(../_pipeline/README.md)でドット化したもの。待機はすそ・ひれのゆれと泡。覚醒は黒い出目金の紫に染まる'

if __name__ == '__main__':
    size, nc = export(ID, '金魚すくいの金魚娘 ひれ', frames, NOTE)
    print(ID, size, nc, 'colors')
