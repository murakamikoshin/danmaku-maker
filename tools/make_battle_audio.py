"""弾幕バトル専用の BGM(bgm_battle.caf)と、相手が見つかったときの効果音(se_match.caf)だけを作る。他の曲・効果音は作り直さない。
使い方: python3 tools/make_battle_audio.py
make_audio.py の道具(Buf・track など)の部分だけ読み込んで使う。"""
import os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_audio.py"), encoding="utf-8").read()
exec(compile(src[:src.index("# ---------- メニュー")], "make_audio_head", "exec"))

# 対戦の緊張感(184 BPM / ハ短調 / 32小節)。進行: Cm → A♭ → B♭ → G(G は長調で、ひりつかせる)
# 0〜3: 低音と太鼓だけで助走 / 4〜: 刻むリフ / 8〜: 主旋律 / 16〜: 高いトレモロと8分のキック / 最後の4小節: せり上がる
def battle_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    for s in range(16):                                  # 16分ののこぎり波ベース(低く、太く)
        o = [0, 0, 0, 12, 0, 0, 7, 12][s % 8]
        b.tone(t0 + s * beat / 4, beat / 4 * 0.85, hz(root - 24 + o), 0.2, "saw", rel=0.01, decay=0.04, sus=0.6)
    for q in range(4): b.kick(t0 + q * beat, 0.5)        # 四つ打ち
    if cyc >= 4:
        for q in range(4): b.kick(t0 + q * beat + beat / 2, 0.3)
    for q in (1, 3): b.noise(t0 + q * beat, 0.16, 0.32, hp=0.35, decay=0.05, seed=bar * 7 + q)
    for e in range(16): b.noise(t0 + e * beat / 4, 0.02, 0.06 + (0.03 if e % 4 == 2 else 0), hp=0.95, decay=0.008, seed=bar * 17 + e)
    if cyc >= 1:                                         # 刻むリフ(パワーコード風: 根音と5度)
        for s in (0, 3, 6, 8, 11, 14):
            for iv in (0, 7):
                b.tone(t0 + s * beat / 4, beat / 4 * 1.6, hz(root + iv), 0.08, "saw", rel=0.02, decay=0.06, sus=0.5)
    notes = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12, tri[2] + 12]
    if cyc >= 2:                                         # 鋭い主旋律(下がって上がる、追い立てる形)
        lead = [[5, 4, 3, 4, 2, 3, 1, 2], [3, 3, 5, 4, 3, 2, 3, 4], [0, 2, 3, 5, 4, 3, 2, 1], [5, 3, 4, 2, 3, 1, 2, 0]][cyc % 4]
        for e in range(8):
            b.tone(t0 + e * beat / 2, beat / 2 * 0.85, hz(root + 24 + notes[lead[e]]), 0.16, "pulse", duty=0.25, rel=0.02, decay=0.2, sus=0.6, vib=0.005)
    if cyc >= 4:                                         # 高いトレモロ(16分の連打)
        for s in range(16):
            b.tone(t0 + s * beat / 4, beat / 4 * 0.7, hz(root + 48 + tri[s % 3]), 0.03, "pulse", duty=0.125, rel=0.01, decay=0.03, sus=0.3)
    if bar % 8 == 0 and bar > 0:                         # 8小節ごとの頭に「ジャーン」
        b.noise(t0, 0.6, 0.24, hp=0.95, decay=0.22, seed=bar + 500)
    if bar % 4 == 3:                                     # 4小節ごとの終わりに、スネアのロール
        for s in range(8): b.noise(t0 + 3 * beat + s * beat / 8, 0.05, 0.14 + 0.02 * s, hp=0.4, decay=0.02, seed=bar * 91 + s)
    if bar >= 28:                                        # 最後の4小節は、サイレン風にせり上がる
        k = bar - 28
        b.tone(t0, 4 * beat, hz(root + 36 + 3 * k), 0.05, "saw", a=0.3, rel=0.1, slide=0.15)

track(184, 32, [(48, "min"), (44, "maj"), (46, "maj"), (43, "maj")], battle_bar, "bgm_battle")

def match(b):
    # 相手が見つかった: 低い衝撃のあと、上がっていく3音と、鋭い「キン」
    b.kick(0, 0.8)
    b.noise(0, 0.25, 0.5, hp=0.3, decay=0.06)
    for i, n in enumerate([60, 67, 72]):
        b.tone(0.06 + i * 0.08, 0.18, hz(n), 0.35, "saw", decay=0.08, sus=0.4, rel=0.06)
        b.tone(0.06 + i * 0.08, 0.18, hz(n + 12), 0.2, "pulse", duty=0.25, decay=0.08, sus=0.3, rel=0.06)
    b.tone(0.32, 0.5, hz(96), 0.3, "sine", a=0.003, rel=0.2, decay=0.15, sus=0.2)
    b.tone(0.32, 0.5, hz(84), 0.25, "pulse", duty=0.5, rel=0.2, decay=0.2, sus=0.3)
se_buf = Buf(0.95); match(se_buf); se_buf.save("se_match", peak=0.9)
print("done: bgm_battle.caf, se_match.caf")
