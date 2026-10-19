"""BGM 3曲と効果音 6つを、コードで作曲・合成して DanmakuApp/Resources/Audio に書き出す(完全オリジナル。外部の音源は使わない)。
使い方: python3 tools/make_audio.py
曲はループ前提。小節の長さの整数倍で作り、音は小節の中で必ず消えるようにして、つなぎ目で途切れないようにする。"""
import array, math, os, random, struct, subprocess, tempfile, wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "DanmakuApp", "Resources", "Audio")
os.makedirs(OUT, exist_ok=True)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

class Buf:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.d = array.array("f", [0.0]) * self.n

    def tone(self, t0, dur, freq, amp, wave_="pulse", duty=0.5, a=0.004, rel=0.04, sus=0.8, decay=0.0, vib=0.0, slide=0.0):
        """音を1つ足す。wave_: pulse/tri/saw/sine"""
        s0 = int(t0 * SR)
        n = int(dur * SR)
        if s0 >= self.n or n <= 0: return
        n = min(n, self.n - s0)
        phase = 0.0
        d = self.d
        for i in range(n):
            t = i / SR
            f = freq * (1 + slide * t) * (1 + vib * math.sin(2 * math.pi * 5.5 * t))
            phase += f / SR
            p = phase - math.floor(phase)
            if wave_ == "pulse": v = 1.0 if p < duty else -1.0
            elif wave_ == "tri": v = 4 * abs(p - 0.5) - 1
            elif wave_ == "saw": v = 2 * p - 1
            else: v = math.sin(2 * math.pi * p)
            # 包絡: attack → (decay →) sustain → release
            if t < a: e = t / a
            else:
                e = sus + (1 - sus) * math.exp(-(t - a) / decay) if decay > 0 else sus
            left = dur - t
            if left < rel: e *= max(0.0, left / rel)
            d[s0 + i] += v * amp * e

    def noise(self, t0, dur, amp, hp=0.0, decay=0.05, seed=1):
        s0 = int(t0 * SR); n = min(int(dur * SR), self.n - s0)
        if n <= 0: return
        rnd = random.Random(seed + s0)
        last = 0.0
        for i in range(n):
            x = rnd.uniform(-1, 1)
            y = x - last * hp if hp else x
            last = x
            self.d[s0 + i] += y * amp * math.exp(-(i / SR) / decay)

    def kick(self, t0, amp=0.5):
        s0 = int(t0 * SR); n = min(int(0.16 * SR), self.n - s0)
        phase = 0.0
        for i in range(max(0, n)):
            t = i / SR
            f = 45 + 110 * math.exp(-t * 28)
            phase += f / SR
            self.d[s0 + i] += math.sin(2 * math.pi * phase) * amp * math.exp(-t * 14)

    def save(self, name, peak=0.85, fade=0.0):
        m = max(1e-9, max(abs(x) for x in self.d))
        g = peak / m
        if fade > 0:
            f = int(fade * SR)
            for i in range(f):
                k = i / f
                self.d[i] *= k; self.d[self.n - 1 - i] *= k
        wav_path = os.path.join(tempfile.gettempdir(), name + ".wav")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
            w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, x * g)) * 32767)) for x in self.d))
        # IMA4 の CAF: 1サンプル単位でループできる(m4a だと、つなぎ目に無音が入る)
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav_path, os.path.join(OUT, name + ".caf")], check=True)
        os.remove(wav_path)

TRIAD = {"maj": [0, 4, 7], "min": [0, 3, 7]}

def track(bpm, bars, chords, per_bar, name, fade=0.0):
    beat = 60.0 / bpm
    b = Buf(bars * 4 * beat)
    for bar in range(bars):
        root, kind = chords[bar % len(chords)]
        per_bar(b, bar, bar * 4 * beat, beat, root, TRIAD[kind])
    b.save(name, fade=fade)

# ---------- メニュー: ゆったり(92 BPM / ハ長調 / 16小節) ----------
def menu_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    pos = bar % 4
    for k in tri:                                        # パッド
        b.tone(t0, 4 * beat, hz(root + 12 + k), 0.07, "tri", a=0.15, rel=0.3)
    for q in range(4):                                   # ベース
        b.tone(t0 + q * beat, beat * 0.9, hz(root - 12), 0.22, "tri", rel=0.05)
    for e in range(8):                                   # アルペジオ
        n = root + 24 + tri[e % 3] + (12 if e % 6 >= 3 else 0)
        b.tone(t0 + e * beat / 2, beat / 2 * 0.8, hz(n), 0.07, "pulse", duty=0.25, rel=0.03, decay=0.12, sus=0.3)
    melody = {
        0: [(0, 76, 1), (1, 79, 1), (2, 76, 1), (3, 74, 1)],
        1: [(0, 72, 1), (1, 76, 1), (2, 81, 2)],
        2: [(0, 77, 1), (1, 76, 1), (2, 74, 1), (3, 72, 1)],
        3: [(0, 74, 2), (2, 79, 1.8)],
    }[pos]
    if cyc >= 1:
        for bp, n, ln in melody:
            b.tone(t0 + bp * beat, ln * beat * 0.92, hz(n + (12 if cyc == 3 else 0)), 0.15, "pulse", duty=0.5, vib=0.004, rel=0.06, decay=0.5, sus=0.6)
    if cyc >= 2:
        for e in range(8): b.noise(t0 + e * beat / 2, 0.04, 0.05, hp=0.9, decay=0.012, seed=bar * 8 + e)
        for q in (0, 2): b.kick(t0 + q * beat, 0.3)

track(92, 16, [(48, "maj"), (45, "min"), (41, "maj"), (43, "maj")], menu_bar, "bgm_menu")

# ---------- 通常ステージ: 疾走感(150 BPM / ホ短調 / 32小節) ----------
def stage_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    for e in range(8):                                   # ベース(8分)
        b.tone(t0 + e * beat / 2, beat / 2 * 0.85, hz(root - 12 + (12 if e % 4 == 3 else 0)), 0.2, "tri", rel=0.02)
    for s in range(16):                                  # 16分のアルペジオ
        n = root + 24 + tri[[0, 1, 2, 1][s % 4]] + (12 if (s // 4) % 2 else 0)
        b.tone(t0 + s * beat / 4, beat / 4 * 0.8, hz(n), 0.06, "pulse", duty=0.125, rel=0.01, decay=0.06, sus=0.35)
    pat = [[0, 2, 1, 2, 0, 2, 3, 2], [3, 2, 1, 0, 1, 2, 3, 4], [2, 3, 4, 3, 2, 3, 1, 0]][cyc % 3]
    notes = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12]
    if cyc >= 1:
        for e in range(8):
            b.tone(t0 + e * beat / 2, beat / 2 * 0.9, hz(root + 36 + notes[pat[e]] - 12), 0.14, "pulse", duty=0.5, rel=0.03, decay=0.25, sus=0.55, vib=0.003)
    for q in range(4): b.kick(t0 + q * beat, 0.4)
    for q in (1, 3): b.noise(t0 + q * beat, 0.12, 0.22, hp=0.5, decay=0.045, seed=bar * 4 + q)
    for e in range(8): b.noise(t0 + e * beat / 2 + beat / 4 * (1 if cyc >= 4 else 0), 0.03, 0.07, hp=0.95, decay=0.01, seed=bar * 9 + e)

track(150, 32, [(40, "min"), (36, "maj"), (38, "maj"), (35, "min")], stage_bar, "bgm_stage")

# ---------- ボス戦: 緊迫(164 BPM / ニ短調 / 32小節) ----------
def boss_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    for s in range(16):                                  # 16分のベース
        o = [0, 0, 12, 0][s % 4]
        b.tone(t0 + s * beat / 4, beat / 4 * 0.8, hz(root - 12 + o), 0.17, "saw", rel=0.01, decay=0.05, sus=0.6)
    for s in range(16):                                  # のこぎり波のアルペジオ
        n = root + 24 + tri[[0, 2, 1, 2, 0, 1, 2, 1][s % 8]] + (12 if s % 8 >= 4 else 0)
        b.tone(t0 + s * beat / 4, beat / 4 * 0.75, hz(n), 0.05, "pulse", duty=0.25, rel=0.01, decay=0.05, sus=0.4)
    lead = [[0, 0, 2, 2, 3, 2, 1, 0], [4, 3, 4, 3, 2, 1, 2, 0], [2, 4, 3, 2, 1, 2, 3, 4]][cyc % 3]
    notes = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12]
    if cyc >= 1:
        for e in range(8):
            b.tone(t0 + e * beat / 2, beat / 2 * 0.92, hz(root + 24 + notes[lead[e]]), 0.15, "pulse", duty=0.5, rel=0.02, decay=0.3, sus=0.6, vib=0.005)
    for q in range(4): b.kick(t0 + q * beat, 0.42); b.kick(t0 + q * beat + beat * 0.75, 0.25)
    for q in (1, 3): b.noise(t0 + q * beat, 0.14, 0.25, hp=0.4, decay=0.05, seed=bar * 5 + q)
    if bar % 8 == 7:                                     # 8小節ごとに、スネアのロール
        for s in range(16): b.noise(t0 + 2 * beat + s * beat / 8, 0.05, 0.12 + 0.01 * s, hp=0.4, decay=0.02, seed=bar * 77 + s)
    for e in range(16): b.noise(t0 + e * beat / 4, 0.02, 0.05, hp=0.95, decay=0.008, seed=bar * 13 + e)

track(164, 32, [(38, "min"), (34, "maj"), (36, "maj"), (33, "maj")], boss_bar, "bgm_boss")

# ---------- キラキラ: 明るく軽快(138 BPM / ト長調 / 32小節) ----------
def bright_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    for e in range(8):                                   # はずむベース
        b.tone(t0 + e * beat / 2, beat / 2 * 0.7, hz(root - 12 + (7 if e % 4 == 2 else 0)), 0.2, "tri", rel=0.02)
    for s in range(16):                                  # 高い音のきらめくアルペジオ(ベル風: 基音 + 倍音)
        n = root + 36 + tri[[0, 1, 2, 1][s % 4]] + (12 if (s // 4) % 2 else 0)
        b.tone(t0 + s * beat / 4, beat / 4 * 0.9, hz(n), 0.05, "sine", rel=0.02, decay=0.07, sus=0.1)
        b.tone(t0 + s * beat / 4, beat / 4 * 0.9, hz(n) * 2, 0.025, "sine", rel=0.02, decay=0.04, sus=0.05)
    pat = [[0, 1, 2, 1, 3, 2, 1, 0], [2, 3, 4, 3, 2, 1, 2, 0], [0, 2, 4, 3, 4, 2, 3, 1]][cyc % 3]
    notes = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12]
    if cyc >= 1:
        for e in range(8):
            b.tone(t0 + e * beat / 2, beat / 2 * 0.85, hz(root + 24 + notes[pat[e]]), 0.15, "pulse", duty=0.25, rel=0.03, decay=0.2, sus=0.5, vib=0.003)
    for q in range(4): b.kick(t0 + q * beat, 0.32)
    for q in (1, 3): b.noise(t0 + q * beat, 0.1, 0.18, hp=0.5, decay=0.04, seed=bar * 3 + q)
    for e in range(8): b.noise(t0 + e * beat / 2 + beat / 4, 0.025, 0.07, hp=0.95, decay=0.009, seed=bar * 11 + e)

track(138, 32, [(43, "maj"), (40, "min"), (36, "maj"), (38, "maj")], bright_bar, "bgm_bright")

# ---------- ミステリアス: ふしぎで少し不気味(104 BPM / イ短調 / 24小節) ----------
def mystery_bar(b, bar, t0, beat, root, tri):
    cyc = bar // 4
    for k in tri:                                        # ゆらぐパッド
        b.tone(t0, 4 * beat, hz(root + 12 + k), 0.06, "tri", a=0.25, rel=0.4, vib=0.01)
    b.tone(t0, 4 * beat, hz(root - 12), 0.2, "tri", a=0.05, rel=0.2)
    for e in range(8):                                   # ゆっくり上り下りするアルペジオ
        n = root + 24 + tri[[0, 1, 2, 1, 0, 2, 1, 2][e]] + (12 if e in (3, 6) else 0)
        b.tone(t0 + e * beat / 2, beat * 0.9, hz(n), 0.07, "pulse", duty=0.125, rel=0.05, decay=0.4, sus=0.2)
    if cyc >= 1:                                         # 間のあるメロディ
        m = [(0, 0, 2), (2, 2, 1), (3, 1, 1)] if bar % 2 == 0 else [(0, 2, 1.5), (2, 1, 1), (3, 0, 1)]
        for bp, idx, ln in m:
            b.tone(t0 + bp * beat, ln * beat * 0.95, hz(root + 36 + tri[idx]), 0.12, "sine", a=0.02, rel=0.1, vib=0.008, decay=0.7, sus=0.5)
    if cyc >= 2:
        b.kick(t0, 0.3); b.kick(t0 + 2.5 * beat, 0.22)
        for q in (1, 3): b.noise(t0 + q * beat, 0.2, 0.08, hp=0.5, decay=0.08, seed=bar * 4 + q)

track(104, 24, [(45, "min"), (41, "maj"), (36, "maj"), (40, "maj")], mystery_bar, "bgm_mystery")

# ---------- 効果音 ----------
def se(name, seconds, fn):
    b = Buf(seconds); fn(b); b.save(name, peak=0.9)

se("se_tap", 0.09, lambda b: (b.tone(0, 0.07, 1320, 0.5, "pulse", duty=0.25, rel=0.03, decay=0.03, sus=0.3), b.tone(0.02, 0.06, 1760, 0.3, "pulse", duty=0.25, rel=0.03)))
se("se_hit", 0.45, lambda b: (b.noise(0, 0.4, 0.9, hp=0.2, decay=0.09), b.tone(0, 0.35, 140, 0.6, "saw", decay=0.1, sus=0.1, rel=0.1, slide=-1.4), b.kick(0, 0.8)))
se("se_life", 0.4, lambda b: (b.tone(0, 0.3, 420, 0.5, "pulse", duty=0.5, decay=0.1, sus=0.2, rel=0.08, slide=-1.8), b.noise(0, 0.15, 0.4, hp=0.3, decay=0.04)))
se("se_get", 0.55, lambda b: [b.tone(i * 0.07, 0.2, hz(n), 0.35, "pulse", duty=0.25, decay=0.08, sus=0.3, rel=0.06) for i, n in enumerate([76, 79, 84, 88])])
def clear(b):
    for i, n in enumerate([72, 76, 79, 84, 79, 84, 88]):
        b.tone(i * 0.11, 0.2 if i < 6 else 0.6, hz(n), 0.35, "pulse", duty=0.5, decay=0.3, sus=0.5, rel=0.1)
        b.tone(i * 0.11, 0.2 if i < 6 else 0.6, hz(n - 12), 0.2, "tri", rel=0.1)
se("se_clear", 1.5, clear)
def fail(b):
    for i, n in enumerate([67, 64, 60, 55]):
        b.tone(i * 0.16, 0.3, hz(n), 0.4, "pulse", duty=0.5, decay=0.2, sus=0.4, rel=0.1)
        b.tone(i * 0.16, 0.3, hz(n - 12), 0.25, "tri", rel=0.1)
se("se_fail", 1.0, fail)
print("done")
