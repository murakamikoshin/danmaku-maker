import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/hire_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化する
ID = 'hire'
still = make_still.make(HERE)
base = from_still(still, foot=23)
# ゆれるのは左右に広がった金魚のひれだけ(体のはば x=44〜67 の外側)。脚・体は動かさない
FINS = lambda x, y: x < 44 or x > 67
# 手・腕は動かさない(手に持っているポイも動かさない)。金魚は手の上に浮いているので、金魚だけを動かす
PARTS = [((36, 22, 43, 30), 1, 1, 0.0),          # 左のお団子のリボン
         ((69, 22, 78, 30), 1, 1, 1.6),          # 右のお団子のリボン
         ((69, 37, 80, 45), 0, 2, 0.8)]          # 手の上の金魚(上下に泳ぐ)
idle = idle_rig(base, top=52, fins=FINS, parts=PARTS, amp=2.6,
                bubbles=[(18, 34, 2), (96, 30, 2), (100, 74, 3), (12, 80, 1), (94, 96, 1), (24, 96, 2), (88, 54, 1)])
frames = dict(idle=idle)
CORE = [(39, 33), (73, 42)]          # ポイ、金魚をのせた手
frames.update(standard(idle, dict(core=CORE, c1=(255, 110, 70), c2=(255, 236, 200), lean=1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.78, (90, 30, 140), (220, 160, 255), (180, 80, 255), (56, 52), r0=24, r1=46, sat=1.2, val=0.75)
awake_states(frames, dict(core=CORE, c1=(190, 90, 255), c2=(240, 210, 255), lean=1, scale=0.8))
NOTE = '元の絵は Canva で生成したイラスト(source/hire_source.png)を、決まった作り方(../_pipeline/README.md)でドット化したもの。待機はひれのゆれ・リボン・金魚の動き・1ドットの呼吸＋泡(体と脚の形は変えない)。覚醒は黒い出目金の紫に染まる'

if __name__ == '__main__':
    size, nc = export(ID, '金魚すくいの金魚娘 ひれ', frames, NOTE)
    print(ID, size, nc, 'colors')
