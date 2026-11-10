import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'ice'
idle = load('ice')
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(56, 50)], c1=(140, 210, 255), c2=(255, 255, 255), lean=-1)))
frames['idle_awakened'] = awakened(idle, 0.95, (120, 30, 60), (255, 170, 200), (255, 120, 160), (56, 56))
awake_states(frames, dict(core=[(56, 50)], c1=(255, 120, 160), c2=(255, 235, 240), lean=-1))
NOTE = '核は背後の結晶の中心。覚醒後は紅の氷に染まり、うしろに放射する光と、体のふちの点滅する光がつく'

if __name__ == '__main__':
    size, nc = export(ID, '雪の女王', frames, NOTE)
    print(ID, size, nc, 'colors')
