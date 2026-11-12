"""竜王の横向きに飛ぶ姿(Koshin の指示「横に飛び回る攻撃。左右とも」)。元絵は source/dragon_side_art.png(左向き)。
rig.py と同じやり方(部位に分けて骨で動かし、1コマごとにドット化)。部位は 手前の翼・奥の翼・尻尾・首と頭・体。
翼は、肩の高さを軸に上下へたたむように動かす(横から見た羽ばたき: 上に振り上げ → 体の下へ打ち下ろす)。右向きは左右を裏返す"""
import json, math, os
import numpy as np
import rig
from rig import T, R, S, ap
HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, 'source', 'dragon_side.json')))
SC = CFG['scale']; FW, FH = CFG['frame']; OFF = np.array(CFG['offset'], float); STRIDE = CFG['stride']
N_FLY = 24

def _prep():
    parts, own = rig._prepare(CFG, 'dragon_side_art.png')
    for n in ('tail', 'neck'): rig._chain_setup(n, parts=parts)
    return parts
PARTS = _prep()
PCFG = {p['name']: p for p in CFG['parts']}
BODY_C = (760, 640)

def render(i, n=N_FLY):
    """コマ i(左向き)。色の番号の絵を返す"""
    ph = 2 * math.pi * i / n; s, c = math.sin(ph), math.cos(ph)
    root = T(0, 26 * math.sin(ph - 0.6)) @ R(BODY_C, 2.0 * math.sin(ph - 1.0))
    pos = {'body': ap(root, PARTS['body']['xy'])}
    for name, lag, amp in (('wingN', 0.0, 1.0), ('wingF', 0.5, 0.92)):
        Sh = PCFG[name]['shoulder']; up = math.cos(ph - lag)                 # 1 = 振り上げ、-1 = 打ち下ろし
        sy = 0.18 + 0.82 * up if up > 0 else 0.18 + 0.75 * up                # 上では元の形、下では体の下へ(裏返る)
        if abs(sy) < 0.12: sy = 0.12 if sy >= 0 else -0.12
        M = root @ R(Sh, -10 * math.sin(ph - lag) * amp) @ S(Sh, 1.0 + 0.05 * (1 - abs(up)), sy)
        pos[name] = ap(M, PARTS[name]['xy'])
    pos['tail'] = rig.chain_pos('tail', rig.chain_mats('tail', root, [3.0 * math.sin(ph - 0.7 * k - 0.5) for k in range(5)], PARTS), PARTS)
    nm = rig.chain_mats('neck', root, [1.6 * math.sin(ph - 0.6 * k + 1.5) for k in range(4)], PARTS)
    pos['neck'] = rig.chain_pos('neck', nm, PARTS)
    out = np.zeros(FH * FW, np.uint8); per = (1 / SC / STRIDE) ** 2
    order = ['wingF', 'tail', 'body', 'neck', 'wingN']
    for name in order:
        P = PARTS[name]; d = pos[name] * SC + OFF
        ix = np.floor(d[:, 0]).astype(np.int64); iy = np.floor(d[:, 1]).astype(np.int64)
        ok = (ix >= 0) & (ix < FW) & (iy >= 0) & (iy < FH); idx = iy[ok] * FW + ix[ok]
        cnt = np.bincount(idx, minlength=FW * FH)
        votes = np.bincount(idx * rig.NL + P['lab'][ok], weights=P['w'][ok], minlength=FW * FH * rig.NL).reshape(-1, rig.NL)
        thr = 0.42 * per * (min(1.0, abs(_sy(name, ph)) + 0.25) if name.startswith('wing') else 1.0)
        cover = cnt >= thr
        out[cover] = votes.argmax(1)[cover]
    im = rig.cleanup(out.reshape(FH, FW))
    ex, ey = ap(nm[-1], np.array([CFG['eye']], float))[0] * SC + OFF; ex, ey = int(round(ex)), int(round(ey))
    for dx, dy, col in ((0, 0, 15), (1, 0, 14), (0, -1, 14), (1, -1, 14), (-1, 0, 14)):
        if 0 <= ey + dy < FH and 0 <= ex + dx < FW and im[ey + dy, ex + dx]: im[ey + dy, ex + dx] = col
    mouth = ap(nm[-1], np.array([[40, 640]], float))[0] * SC + OFF
    return im, dict(mouth=(float(mouth[0]), float(mouth[1])))

def _sy(name, ph):
    lag = 0.0 if name == 'wingN' else 0.5; up = math.cos(ph - lag)
    return 0.18 + 0.82 * up if up > 0 else 0.18 + 0.75 * up
