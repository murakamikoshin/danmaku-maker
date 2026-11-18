"""必殺技の効果音 5つを、コードで合成して DanmakuApp/Resources/Audio に書き出す(完全オリジナル。外部の音源は使わない)。
使い方: python3 tools/make_special_se.py

make_audio.py(BGM と基本の効果音)とは作り方が違う。あちらはピコピコ系の波形だけだが、
必殺技は金属の響き・重い衝撃・残響を重ねて、もっと厚い音にしている。そのため numpy と scipy が要る:
    pip3 install numpy scipy
音の形式は make_audio.py と同じ(22050Hz・モノラル・IMA4 の CAF)。
afconvert(macOS)があればそれを使い、無ければ ffmpeg にする。
"""
import os
import shutil
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "DanmakuApp", "Resources", "Audio")
os.makedirs(OUT, exist_ok=True)
# 同じ音になるように、乱数の種は固定
rng = np.random.default_rng(7)


def T(sec):
    return np.arange(int(sec * SR)) / SR


def place(buf, x, t0, gain=1.0):
    """buf の t0 秒の位置に、音 x を足す"""
    s = int(t0 * SR)
    n = min(len(x), len(buf) - s)
    if n > 0:
        buf[s:s + n] += x[:n] * gain


def filt(x, kind, f, order=2):
    return sosfilt(butter(order, f, kind, fs=SR, output="sos"), x)


def noise(sec):
    return rng.uniform(-1, 1, int(sec * SR))


def fade(x, a=0.003, r=0.02):
    """頭と尻を少しだけ絞って、プツッと鳴らないようにする"""
    n = len(x)
    e = np.ones(n)
    na, nr = max(1, int(a * SR)), max(1, int(r * SR))
    e[:na] = np.linspace(0, 1, na)
    e[-nr:] *= np.linspace(1, 0, nr)
    return x * e


def whoosh(sec, f0, f1, q=3.0):
    """風を切る音: ノイズに、位置が動いていく山(帯域)をかける"""
    x = noise(sec)
    n = len(x)
    y = np.zeros(n)
    lo = bp = 0.0
    fs = np.geomspace(f0, f1, n)
    for i in range(n):   # 状態変数フィルタ。山の位置を1サンプルずつ動かす
        f = 2 * np.sin(np.pi * min(fs[i], SR / 6.5) / SR)
        hp = x[i] - lo - bp / q
        bp += f * hp
        lo += f * bp
        y[i] = bp
    t = np.linspace(0, 1, n)
    return y * np.sin(np.pi * t) ** 1.5


def metal(sec, base, partials, decay, glide=0.0):
    """金属の響き: 倍音がずれた音を重ねる(高い音ほど早く消える)"""
    t = T(sec)
    y = np.zeros(len(t))
    bend = 1 - glide * np.exp(-t / 0.02)
    ph = 2 * np.pi * np.cumsum(bend) / SR
    for k, (ratio, amp) in enumerate(partials):
        y += amp * np.sin(base * ratio * ph + k * 1.7) * np.exp(-t / (decay / (1 + 0.35 * k)))
    return y


def sub(sec, f0, f1, drop, decay, drive=2.5):
    """腹に来る低い衝撃: 音程が落ちるサイン波を、少し歪ませる"""
    t = T(sec)
    f = f1 + (f0 - f1) * np.exp(-t / drop)
    y = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / decay)
    return np.tanh(y * drive) / np.tanh(drive)


def thump(sec, cutoff, decay):
    return filt(noise(sec), "low", cutoff) * np.exp(-T(sec) / decay)


def swell(sec, hp):
    """逆再生のシンバルのように、ふくらんで切れる"""
    t = T(sec)
    return filt(noise(sec), "high", hp) * (t / sec) ** 3


def bell(sec, f, ratio, index, decay):
    """FM のベル"""
    t = T(sec)
    m = np.sin(2 * np.pi * f * ratio * t) * index * np.exp(-t / (decay * 0.5))
    return np.sin(2 * np.pi * f * t + m) * np.exp(-t / decay)


def reverb(x, sec=0.7, mix=0.22, bright=6000):
    """残響。作った部屋鳴りを、元の音に混ぜる"""
    t = T(sec)
    ir = filt(rng.normal(0, 1, len(t)), "low", bright) * np.exp(-t / (sec / 5))
    ir[: int(0.012 * SR)] = 0
    wet = fftconvolve(x, ir)[: len(x)]
    wet /= max(1e-9, np.max(np.abs(wet)))
    return x + wet * mix * np.max(np.abs(x))


def lift(x, k=2.0):
    """スマホのスピーカーは低い音が出ないので、中くらいの高さを持ち上げる"""
    return filt(x, "high", 70) + k * filt(x, "high", 240)


def save(name, x, peak=0.89):
    x = fade(x, 0.001, 0.05)
    x = np.tanh(x / max(1e-9, np.max(np.abs(x))) * 1.6)   # 軽く詰めて、音を太くする
    x = x / np.max(np.abs(x)) * peak
    wav_path = os.path.join(tempfile.gettempdir(), name + ".wav")
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())
    caf = os.path.join(OUT, name + ".caf")
    # IMA4 の CAF(make_audio.py と同じ形式)
    if shutil.which("afconvert"):
        subprocess.run(["afconvert", "-f", "caff", "-d", "ima4", wav_path, caf], check=True)
    elif shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav_path,
                        "-ar", str(SR), "-ac", "1", "-c:a", "adpcm_ima_qt", "-f", "caf", caf], check=True)
    else:
        raise SystemExit("afconvert も ffmpeg も見つからない")
    os.remove(wav_path)
    print(name, round(len(x) / SR, 2), "秒")


# 1. 一閃: 風切り → 刀の「シャキーン」→ 低い一撃
b = np.zeros(int(1.15 * SR))
place(b, whoosh(0.16, 500, 7000), 0.0, 0.9)
place(b, metal(0.95, 1900, [(1, 1), (1.47, .7), (2.09, .6), (2.56, .45), (3.31, .4), (4.12, .3), (5.4, .2)], 0.42, glide=0.25), 0.12, 0.85)
place(b, filt(noise(0.09), "high", 5000) * np.exp(-T(0.09) / 0.02), 0.12, 0.8)
place(b, sub(0.6, 240, 85, 0.05, 0.2, drive=4.0), 0.12, 0.4)
place(b, thump(0.3, 2200, 0.05), 0.12, 0.7)
save("se_special_issen", reverb(b, 0.8, 0.25))

# 2. 轟: ふくらむ → 重い「ドゥーン」→ 上できらめく
b = np.zeros(int(1.2 * SR))
place(b, swell(0.15, 3000), 0.0, 0.6)
place(b, sub(1.0, 280, 72, 0.07, 0.36, drive=6.0), 0.14, 0.7)
place(b, sub(0.5, 560, 150, 0.05, 0.18, drive=3.0), 0.14, 0.5)
place(b, thump(0.5, 1800, 0.1), 0.14, 0.9)
place(b, filt(noise(0.5), "band", [1500, 5000]) * np.exp(-T(0.5) / 0.1), 0.14, 0.6)
for i in range(9):
    place(b, bell(0.3, rng.uniform(3200, 7800), 2.01, 0.6, 0.09), 0.22 + i * 0.055 + rng.uniform(0, 0.02), 0.3)
save("se_special_todoroki", reverb(lift(b), 0.9, 0.28, 5000))

# 3. 覚醒: 駆け上がる → 「キュピーン」と光る → 余韻
b = np.zeros(int(1.15 * SR))
t = T(0.15)
f = np.geomspace(350, 3200, len(t))
place(b, np.sin(2 * np.pi * np.cumsum(f) / SR + 1.5 * np.sin(2 * np.pi * np.cumsum(f * 2.0) / SR)) * (t / 0.15) ** 1.5, 0.0, 0.5)
place(b, whoosh(0.15, 1200, 9000), 0.0, 0.45)
for f0, g, d in [(2093, .55, 0), (3136, .4, 0), (4186, .3, 0.0), (2093, .2, 0.13), (3136, .14, 0.26)]:
    place(b, bell(0.8, f0, 1.41, 2.2, 0.3), 0.14 + d, g)
place(b, sub(0.4, 220, 90, 0.04, 0.14, drive=4.0), 0.14, 0.4)
save("se_special_kakusei", reverb(b, 0.8, 0.3, 8000))

# 4. 和: 太鼓「ドドン」+ 拍子木
b = np.zeros(int(1.15 * SR))


def taiko(g):
    y = np.zeros(int(0.7 * SR))
    place(y, sub(0.7, 260, 88, 0.035, 0.28, drive=5.0), 0, 0.7 * g)
    place(y, sub(0.3, 520, 180, 0.03, 0.1, drive=2.0), 0, 0.4 * g)
    place(y, thump(0.25, 2600, 0.035), 0, 0.8 * g)
    return y


def clap():
    y = np.zeros(int(0.18 * SR))
    place(y, metal(0.18, 1150, [(1, 1), (2.27, .8), (3.6, .5), (5.1, .3)], 0.03), 0)
    place(y, filt(noise(0.02), "high", 3000) * np.exp(-T(0.02) / 0.004), 0)
    return y


place(b, clap(), 0.0, 0.9)
place(b, taiko(0.7), 0.05, 1.0)
place(b, taiko(1.0), 0.17, 1.0)
place(b, clap(), 0.17, 0.7)
place(b, whoosh(0.3, 6000, 800), 0.2, 0.25)
save("se_special_wa", reverb(lift(b), 0.9, 0.3, 4000))

# 5. 禍: 低くうなって迫る → 重い一撃 → にごった響きが残る
b = np.zeros(int(1.2 * SR))
t = T(1.05)
drone = np.zeros(len(t))
for f0 in [110, 116.6, 164.8, 221.2]:   # わざと不協和にする
    ph = 2 * np.pi * f0 * t * (1 + 0.004 * np.sin(2 * np.pi * 4.5 * t))
    drone += ((ph / (2 * np.pi)) % 1.0) * 2 - 1
drone = filt(drone, "low", 1600, 4) * np.exp(-t / 0.45)
place(b, swell(0.15, 800), 0.0, 0.5)
place(b, drone, 0.13, 0.75)
place(b, sub(1.0, 230, 62, 0.09, 0.4, drive=6.0), 0.13, 0.6)
place(b, thump(0.6, 1200, 0.13), 0.13, 0.8)
place(b, metal(0.9, 620, [(1, 1), (1.06, .9), (2.74, .5), (4.3, .3)], 0.5), 0.13, 0.45)
save("se_special_maga", reverb(lift(b), 1.0, 0.3, 3000))

print("done")
