import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'fallen_angel'
idle = load('fallen_angel')
frames = dict(idle=idle, idle_awakened=load('fallen_angel_awakened'))
frames.update(standard(idle, dict(core=[(46, 61), (89, 61)], c1=(255, 42, 74), c2=(255, 208, 216), lean=1)))
awake_states(frames, dict(core=[(46, 61), (89, 61)], c1=(242, 193, 78), c2=(255, 240, 200), lean=1))
NOTE = '覚醒後の待機(idle_awakened)は元の覚醒の絵(fallen_angel_awakened_idle_sheet)をそのまま使っている'

if __name__ == '__main__':
    size, nc = export(ID, '堕天使', frames, NOTE)
    print(ID, size, nc, 'colors')
