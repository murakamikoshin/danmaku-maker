import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'puni'
idle = load('puni', w=136)   # 覚醒後(136×112)と大きさをそろえるため、左右に透明を足して中央に置く
frames = dict(idle=idle, idle_awakened=load('puni_true'))
frames.update(standard(idle, dict(core=[(66, 88)], c1=(120, 220, 170), c2=(225, 255, 240), lean=1, scale=0.5)))
NOTE = '通常の絵(112×112)は、覚醒後の絵(136×112)と大きさをそろえるため左右に12ドットずつ透明を足した。覚醒後(idle_awakened)は元の puni_true をそのまま使っている。覚醒の秘密のため、構え・技中・硬直はザコらしく小さな動きにしている'

if __name__ == '__main__':
    size, nc = export(ID, 'ぷにまる', frames, NOTE)
    print(ID, size, nc, 'colors')
