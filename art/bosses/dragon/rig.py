"""最強のドラゴンの骨組み(リグ)。1枚の高解像度イラストを部位に分け、骨で動かしてから、1コマごとにドット化する。
- 部位・関節・色の表は source/dragon_rig.json(座標は元絵のピクセル)
- 元絵の1ドットごとに「色の表の何番か」を先に決めておき、動かしたあとで、ドット絵の1マスに入った点の多数決でそのマスの色を決める
  (小数の位置で動かせるので、整数ドットでずらすより滑らか。色は決まった表の色だけなので、ぼけない)
- 出力は「色の番号の絵」(H×W の uint8)。色そのものは make_dragon.py が姿(通常・覚醒1〜3)ごとの色の表で塗る"""
import json, math, os
import numpy as np, cv2
from scipy import ndimage
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
CFG = json.load(open(os.path.join(HERE, 'source', 'dragon_rig.json')))
SC = CFG['scale']; FW, FH = CFG['frame']; OFF = np.array(CFG['offset'], float); STRIDE = CFG['stride']
NL = 24                                  # 色の番号の数
# 色の番号: 0 透明 / 1-3 赤(ふつう・暗い・明るい) / 4-5 黒赤(翼の膜・影) / 6-8 金(ふつう・暗い・明るい) / 9 腹のクリーム
# 10-11 口の中 / 12-13 牙 / 14-15 目(黒・赤) / 16-18 光の効果(色1・色2・白) / 19 体のふちの光 / 20-21 うしろの光 / 22 残り火
EDGE = {1: 2, 3: 2, 6: 7, 8: 7, 9: 7, 10: 11, 13: 12}    # いちばん外の1ドットに使う色

def _poly_mask(shape, poly):
    m = np.zeros(shape, np.uint8)
    if poly: cv2.fillPoly(m, [np.array(poly, np.int32)], 1)
    return m.astype(bool)

PCFG_ = {q['name']: q for q in CFG['parts']}
def _prepare(CFG=CFG, art_file='dragon_art.png'):
    """元絵を読み、部位ごとの点(位置・色の番号・重み)を作る。横向きの絵(side.py)も同じ処理を使う"""
    PCFG_ = {q['name']: q for q in CFG['parts']}; STRIDE = CFG['stride']
    art = np.array(Image.open(os.path.join(HERE, 'source', art_file)).convert('RGB')).astype(np.int32)
    H, W = art.shape[:2]
    # 背景: ふちからつながった白と、まわりを囲まれた大きな白(口のまわりの牙は残す)
    anchors = CFG.get('anchors') or globals()['CFG']['anchors']
    white = (art.min(2) > 232) & (art.max(2) - art.min(2) < 22)
    lab, n = ndimage.label(white)
    border = set(lab[0]) | set(lab[-1]) | set(lab[:, 0]) | set(lab[:, -1])
    sizes = ndimage.sum(white, lab, range(1, n + 1))
    mouth = _poly_mask((H, W), CFG['mouth_zone'])
    bg = np.zeros((H, W), bool)
    for i in range(1, n + 1):
        if i in border: bg |= lab == i
        elif sizes[i - 1] >= 500:
            m = lab == i
            if (m & mouth).sum() < 0.5 * sizes[i - 1]: bg |= m
    for poly in CFG.get('erase', []): bg |= _poly_mask((H, W), poly)
    opaque = ndimage.binary_erosion(~bg, iterations=2)      # 背景とのにじみを落とす
    # 元絵の1ドットごとの色の番号
    anc = np.array(anchors, float)
    d = ((art[:, :, None, :] - anc[None, None, :, :3]) ** 2).sum(3)
    near = d.argmin(2); label = anc[near, 3].astype(np.uint8); weight = anc[near, 4].astype(np.float32)
    # 口の中・牙の色は、口のまわりだけ(ほかの場所のにじみが化けるのを防ぐ)
    notm = ~mouth & (label >= 10)
    if notm.any():
        keep = anc[:, 3] < 10
        d2 = d[notm][:, keep]; nn = d2.argmin(1); label[notm] = anc[keep][nn, 3]; weight[notm] = anc[keep][nn, 4]
    # 部位ごとの持ち主(手前から順)。腕は、範囲の中の赤・金のかたまりだけ(後ろの翼の膜と区別する)
    own = np.full((H, W), -1, np.int16); parts = CFG['parts']
    for i, p in enumerate(parts):
        if not p['poly']: continue
        m = _poly_mask((H, W), p['poly']) & opaque
        if p.get('core'):
            c = m & np.isin(label, (1, 2, 3, 6, 7, 8, 9))
            c = ndimage.binary_opening(c, iterations=2)
            c = ndimage.binary_closing(c, structure=np.ones((3, 3)), iterations=9)
            lab2, n2 = ndimage.label(c)                                   # いちばん大きいかたまりだけ
            if n2 > 1: c = lab2 == (1 + np.argmax(ndimage.sum(c, lab2, range(1, n2 + 1))))
            m = ndimage.binary_fill_holes(ndimage.binary_dilation(c, iterations=2)) & m
        own[m & (own < 0)] = i
    body = [i for i, p in enumerate(parts) if p['name'] == 'body'][0]
    own[opaque & (own < 0)] = body
    out = {}
    yy, xx = np.mgrid[0:H:STRIDE, 0:W:STRIDE]
    for i, p in enumerate(parts):
        mine = own == i
        full = _poly_mask((H, W), p.get('full') or p['poly']) & opaque & ~mine      # ほかの部位に隠れている所
        lab_p = label.copy(); w_p = weight.copy()
        if full.any() and mine.any():
            idx = ndimage.distance_transform_edt(~mine, return_distances=False, return_indices=True)
            lab_p[full] = label[idx[0][full], idx[1][full]]; w_p[full] = weight[idx[0][full], idx[1][full]]
        sel = (mine | full)[::STRIDE, ::STRIDE]
        out[p['name']] = dict(xy=np.stack([xx[sel], yy[sel]], 1).astype(np.float32) + 0.5 * STRIDE,
                              lab=lab_p[::STRIDE, ::STRIDE][sel].astype(np.int64), w=w_p[::STRIDE, ::STRIDE][sel], cfg=p)
    return out, own
PARTS, OWN = _prepare()
ORDER = ['tail', 'wingL', 'wingR', 'legL', 'legR', 'body', 'armL', 'armR', 'neck', 'jaw', 'head']    # 奥 → 手前
PCFG = {p['name']: p for p in CFG['parts']}

# ---------- 2次元の変換(3×3 の行列) ----------
def T(dx, dy): return np.array([[1, 0, dx], [0, 1, dy], [0, 0, 1]], float)
def R(c, deg):
    a = math.radians(deg); s, co = math.sin(a), math.cos(a)
    return T(c[0], c[1]) @ np.array([[co, -s, 0], [s, co, 0], [0, 0, 1]], float) @ T(-c[0], -c[1])
def S(c, sx, sy=None):
    sy = sx if sy is None else sy
    return T(c[0], c[1]) @ np.array([[sx, 0, 0], [0, sy, 0], [0, 0, 1]], float) @ T(-c[0], -c[1])
def ap(M, xy): return xy @ M[:2, :2].T + M[:2, 2]

# ---------- 鎖(首・尻尾・腕・脚): 関節ごとに曲がり、関節のまわりはなめらかにつなぐ ----------
def _chain_setup(name, h=0.38, parts=None):
    P = (parts or PARTS)[name]; J = np.array(P['cfg']['joints'], float); xy = P['xy']; nb = len(J) - 1
    best = np.full(len(xy), 1e18); c = np.zeros(len(xy))
    for i in range(nb):
        a, b = J[i], J[i + 1]; ab = b - a; t = ((xy - a) @ ab) / (ab @ ab)
        tc = np.clip(t, 0, 1); d = ((xy - (a + tc[:, None] * ab)) ** 2).sum(1)
        if i == 0: tc = np.minimum(t, 1); tc = np.maximum(tc, -1)       # 付け根より手前は、最初の骨のもの
        if i == nb - 1: tc = np.maximum(np.minimum(t, 3), 0) if False else np.where(t > 1, 1.0, tc)
        m = d < best; best[m] = d[m]; c[m] = i + np.clip(tc[m], 0, 1)
    k = np.minimum(np.floor(c).astype(int), nb - 1); fr = c - k
    w_prev = np.where((fr < h) & (k > 0), 0.5 * (1 - fr / h), 0.0)
    w_next = np.where((fr > 1 - h) & (k < nb - 1), 0.5 * (fr - (1 - h)) / h, 0.0)
    P['chain'] = dict(J=J, k=k, wp=w_prev, wn=w_next, nb=nb)
for _n in ('tail', 'neck', 'armL', 'armR', 'legL', 'legR'): _chain_setup(_n)

def chain_mats(name, parent, angles, parts=None):
    """骨ごとの行列。angles[i] は関節 i での曲げ(度)。足りないぶんは 0"""
    C = (parts or PARTS)[name]['chain']; M = parent; out = []
    for i in range(C['nb']):
        M = M @ R(C['J'][i], angles[i] if i < len(angles) else 0.0); out.append(M)
    return out

def chain_pos(name, mats, parts=None):
    P = (parts or PARTS)[name]; C = P['chain']; xy = P['xy']; res = np.zeros_like(xy, dtype=float)
    k = C['k']
    for i, M in enumerate(mats):
        w = np.where(k == i, 1 - C['wp'] - C['wn'], 0.0) + np.where(k == i + 1, C['wp'], 0.0) + np.where(k == i - 1, C['wn'], 0.0)
        m = w > 0
        if m.any(): res[m] += w[m, None] * ap(M, xy[m])
    return res

# ---------- 翼: 肩で羽ばたき、手首を中心に指の骨が扇のように開閉し、先ほど遅れてしなる ----------
def _wing_setup(name):
    P = PARTS[name]; c = P['cfg']; S_, W_, tip = (np.array(c[k], float) for k in ('shoulder', 'wrist', 'tip'))
    sign = 1.0 if name == 'wingL' else -1.0            # 右の翼は左右を裏返して同じ計算をする
    v = (P['xy'] - W_) * np.array([sign, 1.0])
    phi = np.degrees(np.arctan2(v[:, 1], v[:, 0])); r = np.hypot(v[:, 0], v[:, 1])
    a0 = math.degrees(math.atan2(S_[1] - W_[1], (S_[0] - W_[0]) * sign)); a1 = math.degrees(math.atan2(tip[1] - W_[1], (tip[0] - W_[0]) * sign))
    g = np.clip((phi - a0) / (a1 - a0), 0, 1.2); g = np.where(phi < a0 - 60, 0.0, g)
    g = g * np.clip(r / 60.0, 0, 1)                   # 手首のすぐそばは動かさない
    P['wing'] = dict(S=S_, W=W_, sign=sign, g=g, r=r / r.max(), v=v)
for _n in ('wingL', 'wingR'): _wing_setup(_n)

def wing_pos(name, parent, flap=0.0, fan=0.0, lag=0.0, sx=1.0, sy=1.0):
    """flap: 肩での上げ下げ(度、+ で上)。fan: 指の開閉(度、- でたたむ)。lag: 先のしなり(度)。sx, sy: 肩を中心にした伸び縮み(前後に振る見かけ)"""
    P = PARTS[name]; Wg = P['wing']; sign = Wg['sign']
    ang = np.radians(fan * Wg['g'] + lag * Wg['r'] ** 1.5 * (Wg['g'] > 0.05))
    co, si = np.cos(ang), np.sin(ang); v = Wg['v']
    q = np.stack([co * v[:, 0] - si * v[:, 1], si * v[:, 0] + co * v[:, 1]], 1) * np.array([sign, 1.0]) + Wg['W']
    M = parent @ R(Wg['S'], flap * sign) @ S(Wg['S'], sx, sy)
    return ap(M, q)

# ---------- 1コマを描く ----------
REST = dict(dx=0, dy=0, rot=0, scale=1, sx=1, sy=1, wingL=(0, 0, 0, 1, 1), wingR=(0, 0, 0, 1, 1), neck=(), head=0, head_scale=1.4, jaw=1.0,
            tail=(), armL=(), armR=(), legL=(), legR=(), head_dx=0, head_dy=0)
BODY_C = (745, 560)

MARK = dict(mouth=('head', (800, 372)), throat=('head', (800, 330)), handL=('armL', (410, 575)), handR=('armR', (1050, 575)), tailtip=('tail', (600, 1066)),
            wtipL=('wingL', (30, 590)), wtipR=('wingR', (1425, 590)), wristL=('wingL', (386, 80)), wristR=('wingR', (1077, 80)), chest=('body', (745, 520)),
            footL=('legL', (640, 900)), footR=('legR', (860, 980)), eyeL=('head', (764, 250)), eyeR=('head', (837, 253)), crown=('head', (790, 120)))
def markers(pose):
    """口・手・翼の先・尻尾の先などの位置(ドット絵の座標)。効果を描く場所や、弾の発射位置に使う"""
    p = dict(REST); p.update(pose)
    root = T(p['dx'], p['dy']) @ R(BODY_C, p['rot']) @ S(BODY_C, p['scale'] * p['sx'], p['scale'] * p['sy'])
    nm = chain_mats('neck', root, p['neck']); piv = PCFG['head']['pivot']
    Hm = nm[-1] @ T(p['head_dx'], p['head_dy']) @ R(piv, p['head']) @ S(piv, p['head_scale'])
    out = {}
    for k, (part, xy) in MARK.items():
        q = np.array([xy], float)
        if part == 'head': r = ap(Hm, q)
        elif part == 'body': r = ap(root, q)
        elif part.startswith('wing'):
            Wg = PARTS[part]['wing']; sign = Wg['sign']; flap, fan, lag, sx, sy = p[part]
            v = (q - Wg['W']) * np.array([sign, 1.0]); a = math.radians(fan * 1.0 + lag * 1.0) if k.startswith('wtip') else 0.0
            v = np.array([[math.cos(a) * v[0, 0] - math.sin(a) * v[0, 1], math.sin(a) * v[0, 0] + math.cos(a) * v[0, 1]]])
            r = ap(root @ R(Wg['S'], flap * sign) @ S(Wg['S'], sx, sy), v * np.array([sign, 1.0]) + Wg['W'])
        else: r = ap(chain_mats(part, root, p[part])[-1], q)
        out[k] = tuple(r[0] * SC + OFF)
    return out

def solve(pose):
    """ポーズ → 部位ごとの点の位置(元絵の座標)と、頭の行列"""
    p = dict(REST); p.update(pose)
    root = T(p['dx'], p['dy']) @ R(BODY_C, p['rot']) @ S(BODY_C, p['scale'] * p['sx'], p['scale'] * p['sy'])
    pos = {'body': ap(root, PARTS['body']['xy'])}
    for n in ('wingL', 'wingR'): pos[n] = wing_pos(n, root, *p[n])
    for n in ('tail', 'armL', 'armR', 'legL', 'legR'): pos[n] = chain_pos(n, chain_mats(n, root, p[n]))
    nm = chain_mats('neck', root, p['neck']); pos['neck'] = chain_pos('neck', nm)
    piv = PCFG['head']['pivot']
    Hm = nm[-1] @ T(p['head_dx'], p['head_dy']) @ R(piv, p['head']) @ S(piv, p['head_scale'])
    pos['head'] = ap(Hm, PARTS['head']['xy'])
    hy = PCFG['jaw']['hinge_y']
    pos['jaw'] = ap(Hm @ S((0, hy), 1, p['jaw']), PARTS['jaw']['xy'])       # あごは、付け根の線に向かって縦に縮めると閉じる
    scale = {n: p['scale'] for n in ORDER}; scale['head'] = scale['jaw'] = p['scale'] * p['head_scale']
    return pos, Hm, scale

def render(pose, eyes=True, eye_glow=False):
    pos, Hm, scale = solve(pose)
    out = np.zeros(FH * FW, np.uint8)
    per = (1 / SC / STRIDE) ** 2
    for n in ORDER:
        P = PARTS[n]; d = pos[n] * SC + OFF
        ix = np.floor(d[:, 0]).astype(np.int64); iy = np.floor(d[:, 1]).astype(np.int64)
        ok = (ix >= 0) & (ix < FW) & (iy >= 0) & (iy < FH)
        idx = iy[ok] * FW + ix[ok]
        cnt = np.bincount(idx, minlength=FW * FH)
        votes = np.bincount(idx * NL + P['lab'][ok], weights=P['w'][ok], minlength=FW * FH * NL).reshape(-1, NL)
        cover = cnt >= 0.42 * per / scale[n] ** 2
        out[cover] = votes.argmax(1)[cover]
    im = out.reshape(FH, FW)
    im = cleanup(im)
    if eyes:
        for ex, ey in CFG['eyes']:
            x, y = ap(Hm, np.array([[ex, ey]], float))[0] * SC + OFF; x, y = int(round(x)), int(round(y))
            s = 1 if ex < 800 else -1                          # つり目: 外側が上がる。黒い目に赤い瞳
            shape = ((-2, -1, 14), (-1, -1, 14), (0, -1, 14), (-2, 0, 14), (-1, 0, 15), (0, 0, 15 if not eye_glow else 18), (1, 0, 14), (-1, 1, 14), (0, 1, 14), (1, 1, 14))
            for dx, dy, c in shape:
                if 0 <= y + dy < FH and 0 <= x + dx * s < FW and im[y + dy, x + dx * s]: im[y + dy, x + dx * s] = c
    return im, Hm

def cleanup(im):
    a = im > 0
    nb = sum(np.roll(np.roll(a, dy, 0), dx, 1) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
    im = np.where(a & (nb <= 1), 0, im)                      # 浮いた1ドットを消す
    a = im > 0
    hole = ~a & (nb == 4)                                     # 1ドットの穴をふさぐ
    if hole.any():
        up = np.roll(im, 1, 0); im = np.where(hole, up, im); a = im > 0
    edge = a & ~(np.roll(a, 1, 0) & np.roll(a, -1, 0) & np.roll(a, 1, 1) & np.roll(a, -1, 1))
    lut = np.arange(256, dtype=np.uint8)
    for k, v in EDGE.items(): lut[k] = v
    return np.where(edge, lut[im], im).astype(np.uint8)

def head_point(Hm, src_xy):
    x, y = ap(Hm, np.array([src_xy], float))[0] * SC + OFF
    return float(x), float(y)
