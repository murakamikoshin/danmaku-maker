import sys, os, math
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'tools')); sys.path.insert(0, os.path.join(HERE, '..', '_pipeline'))
from bosskit import *
import make_still
# 元のイラスト(source/fallen_angel_source.png、Canvaで生成)を、決まった作り方(../_pipeline/README.md)でドット化し、部位の地図で動かす。
# 黒が多く細い金の線がある絵なので、ドット化は色の表を使う版(pixel_pal.py、設定は source/fallen_angel_settings.json)。
# 1コマは前と同じ 136×112(翼が横に広いため)
ID = 'fallen_angel'
SIZE = (136, 112)
still = make_still.make(HERE)
base, lab, parts = from_still_parts(still, foot=6, size=SIZE)
ORBS = [(47, 38), (88, 39)]
# 翼はゆっくり上下(羽ばたき)、輪っかは浮いてゆらめく、手の上の赤い球は小さく上下。髪のすそはゆれる。手・体・脚は動かさない
MOTIONS = {'wing_l': (0, 1, 0.0), 'wing_r': (0, 1, 0.0),
           'halo_t': (0, 1, 1.2), 'halo_l': (0, 1, 1.2), 'halo_r': (0, 1, 1.2),
           'orb_l': (0, 1, 2.0), 'orb_r': (0, 1, 2.8)}
idle = idle_parts_map(base, lab, parts, MOTIONS, sway_amp=2.0,
                      bubbles=[(10, 22, 1), (126, 20, 1), (12, 92, 1), (124, 94, 1)],
                      c1=(255, 60, 80), c2=(255, 210, 220))
frames = dict(idle=idle)
def orbs(im, f, mv, c1=(255, 42, 74), c2=(255, 208, 216)):
    # 技の間、両手の赤い球が交互に強く光る
    for k, (x0, y0) in enumerate(ORBS):
        if (f + k) % 2 == 0:
            x, y = mv(x0, y0); star(im, x, y, 3, c1, c2)
frames.update(standard(idle, dict(core=ORBS, c1=(255, 42, 74), c2=(255, 208, 216), lean=1, attack_extra=orbs)))
# 覚醒: 金色に染まり、うしろから金の光(前の覚醒の色と同じ系統)
frames['idle_awakened'] = awakened(idle, 0.11, (150, 100, 20), (255, 230, 140), (242, 193, 78), (68, 40), r0=30, r1=58)
awake_states(frames, dict(core=ORBS, c1=(242, 193, 78), c2=(255, 240, 200), lean=1,
                          attack_extra=lambda im, f, mv: orbs(im, f, mv, (242, 193, 78), (255, 240, 200))))
NOTE = '元の絵は Canva で生成したイラスト(source/fallen_angel_source.png)を、色の表を使う版でドット化したもの(高さ100)。待機は翼の羽ばたき、輪っかと赤い球のゆらめき、髪のすそのゆれ。覚醒は金に染まる'
if __name__ == '__main__':
    size, nc = export(ID, '堕天使', frames, NOTE); print(ID, size, nc, 'colors')
