import sys, os, math
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from bosskit import *

ID = 'witch'
idle = load('witch')
frames = dict(idle=idle)
frames.update(standard(idle, dict(core=[(70, 8)], c1=(255, 214, 90), c2=(255, 250, 220), lean=-1, scale=0.8)))
frames['idle_awakened'] = awakened(idle, 0.97, (130, 20, 50), (255, 120, 150), (255, 70, 100), (56, 56))
awake_states(frames, dict(core=[(70, 8)], c1=(255, 70, 100), c2=(255, 200, 210), lean=-1, scale=0.8))
NOTE = '核は帽子の先の提灯。覚醒後は深紅に染まり、うしろに放射する光と、体のふちの点滅する光がつく'

if __name__ == '__main__':
    size, nc = export(ID, '深海の魔女', frames, NOTE)
    print(ID, size, nc, 'colors')
