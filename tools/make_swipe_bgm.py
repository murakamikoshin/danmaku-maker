"""スワイプ弾幕専用の BGM(bgm_swipe.caf)だけを作る。他の曲・効果音は作り直さない。
使い方: python3 tools/make_swipe_bgm.py
make_audio.py の道具(Buf・track など)の部分だけ読み込んで使う。"""
import os
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_audio.py"), encoding="utf-8").read()
exec(compile(src[:src.index("# ---------- メニュー")], "make_audio_head", "exec"))

# 緊張感 + 爽快感のあるスワイプ弾幕用(176 BPM / イ短調 / 32小節)
# 進行: Am → F → C → E。Am と E(長調の響き)でひりつかせ、F と C で明るく開ける。サビ(8小節目〜)はきらめく高音で抜ける。
# 4小節ごとに盛り上がる(0〜3: 土台 / 4〜: メロディ / 8〜: 高いトレモロ / 最後の4小節: 速いロールで駆け上がる)
def swipe_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    last = bar % 4 == 3
    for s in range(16):                                  # 16分ののこぎり波ベース(オクターブ跳ね)
        o = [0, 0, 12, 0, 0, 12, 0, 7][s % 8]
        b.tone(t0 + s * beat / 4, beat / 4 * 0.8, hz(root - 12 + o), 0.17, "saw", rel=0.01, decay=0.05, sus=0.55)
    for s in range(16):                                  # 細かいアルペジオ(休符を入れて、せかす)
        if s % 8 == 7: continue
        n = root + 24 + tri[[0, 2, 1, 2, 0, 1, 2, 1][s % 8]] + (12 if s % 8 >= 4 else 0)
        b.tone(t0 + s * beat / 4, beat / 4 * 0.7, hz(n), 0.05, "pulse", duty=0.125, rel=0.01, decay=0.04, sus=0.35)
    for q in range(4): b.kick(t0 + q * beat, 0.45)       # 四つ打ち
    if cyc >= 1:
        for q in range(4): b.kick(t0 + q * beat + beat * 0.75, 0.22)
    for q in (1, 3): b.noise(t0 + q * beat, 0.14, 0.26, hp=0.4, decay=0.05, seed=bar * 5 + q)
    for e in range(16): b.noise(t0 + e * beat / 4, 0.02, 0.05 + (0.02 if e % 4 == 2 else 0), hp=0.95, decay=0.008, seed=bar * 13 + e)
    notes = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12]
    if cyc >= 1:                                         # 鋭い主旋律
        lead = [[0, 0, 2, 0, 3, 2, 1, 0], [4, 3, 4, 2, 3, 1, 2, 0], [2, 4, 3, 2, 4, 3, 1, 2]][cyc % 3]
        for e in range(8):
            b.tone(t0 + e * beat / 2, beat / 2 * 0.9, hz(root + 24 + notes[lead[e]]), 0.15, "pulse", duty=0.5, rel=0.02, decay=0.25, sus=0.55, vib=0.004)
    if cyc >= 2:                                         # 高いトレモロ(16分の連打)で、ひりひりした感じ
        for s in range(16):
            b.tone(t0 + s * beat / 4, beat / 4 * 0.7, hz(root + 48 + tri[2]), 0.035, "pulse", duty=0.25, rel=0.01, decay=0.03, sus=0.3)
    if cyc >= 2:                                         # 爽快感: 高いベル風のきらめきが駆け上がる(基音 + 倍音)
        for e in range(8):
            n = root + 36 + tri[[0, 1, 2, 1, 2, 0, 1, 2][e]] + (12 if e >= 4 else 0)
            b.tone(t0 + e * beat / 2, beat / 2 * 0.9, hz(n), 0.05, "sine", rel=0.02, decay=0.1, sus=0.1)
            b.tone(t0 + e * beat / 2, beat / 2 * 0.9, hz(n) * 2, 0.025, "sine", rel=0.02, decay=0.05, sus=0.05)
    if cyc >= 2 and bar % 4 == 0:                        # サビの頭に、シンバル風の「ジャーン」
        b.noise(t0, 0.5, 0.2, hp=0.95, decay=0.2, seed=bar + 900)
    if last and cyc % 2 == 1:                            # 8小節ごとの終わりに、スネアのロール
        for s in range(16): b.noise(t0 + 2 * beat + s * beat / 8, 0.05, 0.12 + 0.012 * s, hp=0.4, decay=0.02, seed=bar * 77 + s)
    if bar >= 28:                                        # 最後の4小節は、音程がせり上がるサイレン風
        k = bar - 28
        b.tone(t0, 4 * beat, hz(root + 36 + 2 * k), 0.05, "saw", a=0.3, rel=0.1, slide=0.12)

track(176, 32, [(45, "min"), (41, "maj"), (48, "maj"), (40, "maj")], swipe_bar, "bgm_swipe")
print("done: bgm_swipe.caf")
