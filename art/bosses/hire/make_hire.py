import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *
HERE = os.path.dirname(os.path.abspath(__file__))
# 元のイラスト(hire_source.png、Canvaで生成)を ../_pipeline/pixel2.py(高さ64・16色)でドット化し、face3.py + source/hire_face.json で目を1色に直したのが hire_still.png
ID = 'hire'
base = from_still(os.path.join(HERE, 'source', 'hire_still.png'), foot=23)
idle = idle_from_still(base, top=62, amp=1.2, bubbles=[(16, 40, 2), (98, 34, 2), (102, 78, 3), (10, 82, 1), (94, 98, 1)])
frames = dict(idle=idle)
CORE = [(31, 27), (73, 53)]          # ポイの先、金魚をのせた手
frames.update(standard(idle, dict(core=CORE, c1=(255, 110, 70), c2=(255, 236, 200), lean=1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.78, (90, 30, 140), (220, 160, 255), (180, 80, 255), (56, 56), r0=24, r1=46, sat=1.2, val=0.75)
awake_states(frames, dict(core=CORE, c1=(190, 90, 255), c2=(240, 210, 255), lean=1, scale=0.8))
NOTE = '元の絵はCanvaで生成したイラストをドット化したもの(source/hire_source.png → source/hire_still.png)。待機はすそ・ひれのゆれと泡。覚醒は黒い出目金の紫に染まる'

if __name__ == '__main__':
    size, nc = export(ID, '金魚すくいの金魚娘 ひれ', frames, NOTE)
    print(ID, size, nc, 'colors')
