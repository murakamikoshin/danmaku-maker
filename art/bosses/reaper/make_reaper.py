import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'reaper'
idle = load('reaper')
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(56, 40)], c1=(80, 255, 160), c2=(210, 255, 230), lean=-1)))
frames['idle_awakened'] = awakened(idle, 0.0, (120, 10, 24), (255, 110, 120), (255, 40, 60), (56, 60), sat=1.4, thr=0.1)
awake_states(frames, dict(core=[(56, 40)], c1=(255, 40, 60), c2=(255, 190, 200), lean=-1))
NOTE = '核は頭蓋の目。覚醒後は緑の光が赤に変わり、うしろに放射する光と、体のふちの点滅する光がつく'

if __name__ == '__main__':
    size, nc = export(ID, '死神', frames, NOTE)
    print(ID, size, nc, 'colors')
