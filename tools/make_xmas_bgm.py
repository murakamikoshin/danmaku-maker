"""クリスマスの BGM(bgm_xmas.caf)だけを作る。他の曲・効果音は作り直さない。完全オリジナル(既存の曲の旋律は使わない)。
使い方: python3 tools/make_xmas_bgm.py
make_audio.py の道具(Buf など)の部分だけ読み込んで使う。afconvert(macOS)が無ければ ffmpeg で書き出す。

耳にやさしい音にする決まり(Koshin の注文「人間が不快にならない周波数で」):
- 音色はサイン波と三角波だけ(矩形波・のこぎり波は使わない: 高い倍音がきつい)
- 主旋律の基音は 350〜1050 Hz、いちばん高い飾りの音でも 2.1 kHz まで
- 鈴・ハイハットの代わりの雑音は小さく、全体に 4.2 kHz のゆるいローパスをかけて、耳に刺さる 2〜5 kHz を抑える
- 低音は 87 Hz より下を鳴らさない(スマホのスピーカーで割れない)"""
import math, os, shutil, struct, subprocess, tempfile, wave
src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "make_audio.py"), encoding="utf-8").read()
exec(compile(src[:src.index("# ---------- メニュー")], "make_audio_head", "exec"))

BPM = 112
BEAT = 60.0 / BPM
BARS = 32
# ヘ長調。和音(根音の MIDI 番号, 3音)
F, Dm, Bb, C, Am = (53, [0, 4, 7]), (50, [0, 3, 7]), (58, [0, 4, 7]), (48, [0, 4, 7]), (57, [0, 3, 7])
A_CH = [F, Dm, Bb, C, F, Dm, Bb, C]
B_CH = [Bb, C, Am, Dm, Bb, C, F, F]
CHORDS = A_CH + A_CH + B_CH + A_CH
# 主旋律(小節ごと。(拍, MIDI 番号, 長さ[拍]))。A は 8 小節、終わりの 2 種類(半終止 / 終止)、B は 8 小節
A_MEL = [
    [(0, 69, 1), (1, 72, 1), (2, 77, 2)],
    [(0, 76, 1), (1, 74, 1), (2, 69, 2)],
    [(0, 70, 1), (1, 74, 1), (2, 79, 1), (3, 77, 1)],
    [(0, 76, 3)],
    [(0, 69, 1), (1, 72, 1), (2, 77, 1), (3, 81, 1)],
    [(0, 79, 1), (1, 77, 1), (2, 74, 2)],
    [(0, 74, 1), (1, 72, 1), (2, 70, 1), (3, 72, 1)],
]
A_END_HALF = [(0, 72, 3)]
A_END_FULL = [(0, 77, 3.5)]
B_MEL = [
    [(0, 74, 1), (1, 77, 1), (2, 79, 2)],
    [(0, 76, 1), (1, 79, 1), (2, 84, 2)],
    [(0, 84, 1), (1, 81, 1), (2, 76, 2)],
    [(0, 77, 1), (1, 76, 1), (2, 74, 2)],
    [(0, 74, 1), (1, 77, 1), (2, 79, 1), (3, 81, 1)],
    [(0, 79, 2), (2, 76, 2)],
    [(0, 77, 4)],
    [(2, 69, 1), (3, 72, 1)],
]
MELODY = A_MEL + [A_END_HALF] + A_MEL + [A_END_FULL] + B_MEL + A_MEL + [A_END_FULL]

def bell(b, t, dur, midi, amp):
    """オルゴール風: サイン波の基音 + 小さな 1 オクターブ上。すぐ減って、長く残らない"""
    f = hz(midi)
    b.tone(t, dur, f, amp, "sine", a=0.006, rel=0.08, decay=0.35, sus=0.18)
    if f * 2 < 2100: b.tone(t, min(dur, 0.5), f * 2, amp * 0.22, "sine", a=0.004, rel=0.05, decay=0.12, sus=0.05)

def make():
    b = Buf(BARS * 4 * BEAT)
    for bar in range(BARS):
        t0 = bar * 4 * BEAT
        root, tri = CHORDS[bar]
        sec = bar // 8                                   # 0: A / 1: A' / 2: B / 3: A''
        # パッド(三角波をやわらかく)
        for k in tri: b.tone(t0, 4 * BEAT, hz(root + 12 + k), 0.045, "tri", a=0.25, rel=0.5)
        # ベース(サイン波。87 Hz より下げない)。1拍目と3拍目、B とさいごは 4 分で歩く
        bass = root - 12 if hz(root - 12) >= 87 else root
        steps = [(0, 0), (2, 7)] if sec < 2 else [(0, 0), (1, 7), (2, 12), (3, 7)]
        for q, iv in steps: b.tone(t0 + q * BEAT, BEAT * (1.7 if sec < 2 else 0.9), hz(bass + iv), 0.2, "sine", a=0.01, rel=0.12, decay=0.6, sus=0.55)
        # 8 分のアルペジオ(A' から)
        if sec >= 1:
            for e in range(8):
                n = root + 24 + tri[[0, 1, 2, 1, 0, 2, 1, 2][e]]
                bell(b, t0 + e * BEAT / 2, BEAT / 2, n, 0.04)
        # 主旋律。さいごの A'' は 1 オクターブ上をうすく重ねる
        for bp, n, ln in MELODY[bar]:
            bell(b, t0 + bp * BEAT, ln * BEAT, n, 0.2)
            b.tone(t0 + bp * BEAT, ln * BEAT * 0.95, hz(n), 0.05, "tri", a=0.03, rel=0.12, vib=0.003)   # 伸ばす音の芯
            if sec == 3: bell(b, t0 + bp * BEAT, ln * BEAT, n + 12, 0.05)
        # そりの鈴の代わり: 小さな雑音を 8 分で(A' から)。拍の頭だけ少し大きく
        if sec >= 1:
            for e in range(8): b.noise(t0 + e * BEAT / 2, 0.05, 0.035 if e % 2 == 0 else 0.02, hp=0.7, decay=0.018, seed=bar * 8 + e)
        # やわらかいキック(B から)
        if sec >= 2:
            for q in (0, 2): b.kick(t0 + q * BEAT, 0.22)
    # 全体にゆるいローパス(4.2 kHz、1次を2回)。往復でかけて、音の出だしがずれないようにする
    al = 1 - math.exp(-2 * math.pi * 4200 / SR)
    d = b.d
    for _ in range(2):
        y = 0.0
        for i in range(b.n): y += al * (d[i] - y); d[i] = y
        y = 0.0
        for i in range(b.n - 1, -1, -1): y += al * (d[i] - y); d[i] = y
    return b

def save(b, name, peak=0.8):
    m = max(1e-9, max(abs(x) for x in b.d)); g = peak / m
    wav_path = os.path.join(tempfile.gettempdir(), name + ".wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * g)) * 32767)) for x in b.d))
    caf = os.path.join(OUT, name + ".caf")
    if shutil.which("afconvert"):
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav_path, caf], check=True)
    elif shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav_path, "-c:a", "adpcm_ima_qt", "-f", "caf", caf], check=True)
    else:
        raise SystemExit("afconvert も ffmpeg も見つからない")
    return wav_path

if __name__ == "__main__":
    print(save(make(), "bgm_xmas"))
