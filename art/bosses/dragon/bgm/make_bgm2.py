"""竜王BGM 2曲目「怖さ・ラスボス感」: 鐘、パイプオルガン、合唱、不穏な和音(Dm→B♭m、減和音、増4度)"""
import numpy as np, scipy.signal as sg, wave, sys

SR = 44100; BPM = 144; STEP = 60 / BPM / 4 * SR
rng = np.random.default_rng(11)
mtof = lambda m: 440 * 2 ** ((m - 69) / 12)

def env(n, a=0.005, d=0.1, s=0.7, r=0.03):
    t = np.arange(n) / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / d))
    rn = max(1, min(int(r * SR), n)); e[-rn:] *= np.linspace(1, 0, rn)
    return e
def filt(x, fc, kind, order=2):
    return sg.sosfilt(sg.butter(order, fc, kind, fs=SR, output='sos'), x)

def mk_kick():
    t = np.arange(int(.28 * SR)) / SR
    f = 42 + 120 * np.exp(-t / .03)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .1)
    x[:200] += rng.normal(0, .5, 200) * np.linspace(1, 0, 200)
    return np.tanh(2 * x)
def mk_snare():
    t = np.arange(int(.3 * SR)) / SR
    n = filt(rng.normal(0, 1, t.size), [700, 8000], 'bandpass') * np.exp(-t / .08)
    return n * .9 + np.sin(2 * np.pi * 170 * t) * np.exp(-t / .045) * .8
def mk_hat(dec, L):
    t = np.arange(int(L * SR)) / SR
    return filt(rng.normal(0, 1, t.size), 7500, 'highpass', 4) * np.exp(-t / dec)
def mk_crash():
    t = np.arange(int(2.4 * SR)) / SR
    return filt(rng.normal(0, 1, t.size), 3000, 'highpass') * (np.exp(-t / .6) * .7 + np.exp(-t / .06) * .5)
def mk_tom(f):
    t = np.arange(int(.35 * SR)) / SR
    return np.sin(2 * np.pi * np.cumsum(f * (1 + .6 * np.exp(-t / .03))) / SR) * np.exp(-t / .13)
def mk_timp():
    t = np.arange(int(1.4 * SR)) / SR
    ph = 2 * np.pi * np.cumsum(73.4 * (1 + .08 * np.exp(-t / .05))) / SR
    x = (np.sin(ph) + .5 * np.sin(1.5 * ph) + .25 * np.sin(2 * ph)) * np.exp(-t / .38)
    return x + filt(rng.normal(0, 1, t.size), 400, 'lowpass') * np.exp(-t / .03) * 2
def mk_bell(m=62):
    t = np.arange(int(5 * SR)) / SR; f = mtof(m); x = np.zeros(t.size)
    for r, a, d in ((.5, .9, 2.2), (1, 1, 1.6), (1.19, .7, 1.2), (1.5, .45, .9), (2, .6, .8), (2.51, .35, .5), (2.66, .3, .45), (3.01, .25, .35), (4.1, .15, .2)):
        x += a * np.sin(2 * np.pi * f * r * t + rng.random() * 6) * np.exp(-t / d)
    x[:300] *= np.linspace(0, 1, 300)
    return x
KICK, SNARE, HAT, OHAT, CRASH, TIMP, BELL = mk_kick(), mk_snare(), mk_hat(.012, .06), mk_hat(.09, .3), mk_crash(), mk_timp(), mk_bell()
TOMS = [mk_tom(f) for f in (200, 150, 112, 84)]

CH = {'Dm': (50, [62, 65, 69]), 'Bbm': (46, [58, 61, 65]), 'Eb': (39, [63, 67, 70]), 'A': (45, [57, 61, 64]),
      'Gm': (43, [55, 58, 62]), 'Fm': (41, [53, 56, 60]), 'Edim': (40, [64, 67, 70])}

MEL_I = [(0, 32), (77, 8), (73, 8), (76, 16)]
MEL_A = [(74,8),(77,4),(76,4), (75,8),(74,8), (73,8),(77,4),(70,4), (73,6),(72,2),(70,8),
         (74,4),(81,8),(80,4), (79,4),(77,4),(76,4),(74,4), (75,6),(79,2),(82,8), (81,8),(76,4),(73,4)]
MEL_B = [(79,2),(82,2),(86,2),(82,2),(79,2),(74,2),(79,4), (77,2),(80,2),(84,2),(80,2),(77,2),(72,2),(77,4),
         (76,2),(79,2),(82,2),(85,2),(88,8), (85,4),(81,4),(76,2),(79,2),(82,2),(85,2),
         (86,6),(82,2),(79,4),(82,4), (84,6),(80,2),(77,4),(80,4), (82,4),(79,4),(76,4),(73,4),
         (69,2),(73,2),(76,2),(79,2),(82,2),(85,2),(88,2),(91,2)]
MEL_C = [(81,8),(86,4),(89,4), (89,6),(85,2),(82,8), (81,4),(86,4),(89,4),(93,4), (94,8),(92,4),(89,4),
         (91,6),(89,2),(86,4),(82,4), (87,6),(86,2),(82,4),(79,4), (81,4),(85,4),(88,8), (88,4),(89,2),(88,2),(85,2),(82,2),(81,2),(76,2)]
SEC = {
 'I':  dict(ch=['Dm', 'Dm', 'Bbm', 'A'], mel=MEL_I),
 'A':  dict(ch=['Dm', 'Dm', 'Bbm', 'Bbm', 'Dm', 'Dm', 'Eb', 'A'], mel=MEL_A),
 'A2': dict(ch=['Dm', 'Dm', 'Bbm', 'Bbm', 'Dm', 'Dm', 'Eb', 'A'], mel=MEL_A),
 'B':  dict(ch=['Gm', 'Fm', 'Edim', 'A', 'Gm', 'Fm', 'Edim', 'A'], mel=MEL_B),
 'C':  dict(ch=['Dm', 'Bbm', 'Dm', 'Bbm', 'Gm', 'Eb', 'A', 'A'], mel=MEL_C),
}
GALLOP = [(0,2,1),(2,1,1),(3,1,1),(4,2,1),(6,1,1),(7,1,1),(8,2,1),(10,1,1),(11,1,1),(12,2,1),(14,1,1),(15,1,1)]
SLOW   = [(0,10,0),(10,6,0)]
CHUG   = [(0,2,0)] + [(i,1,1) for i in range(2,10)] + [(10,2,0)] + [(i,1,1) for i in range(12,16)]
CHORUS = [(0,6,0),(6,2,0),(8,6,0),(14,2,0)]

def build(order, tail_s=4.0):
    bars = sum(len(SEC[s]['ch']) if s in SEC else 5 for s in order)
    N = int(bars * 16 * STEP + tail_s * SR)
    names = ['kick','snare','hat','crash','tom','timp','bell','gL','gR','bass','choir','trem','lead','harm','org','brass']
    T = {k: np.zeros(N) for k in names}
    P = lambda st: int(round(st * STEP))
    def add(tr, st, x, g=1.0):
        i = P(st); n = min(x.size, N - i)
        if n > 0: T[tr][i:i+n] += x[:n] * g
    def saws(m, n, cents=0.):
        f = mtof(m) * 2 ** (cents / 1200)
        return 2 * ((np.arange(n) * f / SR + rng.random()) % 1) - 1
    def gtr(st, ln, root, mute):
        n = int(ln * STEP * (0.92 if mute else 1.0))
        e = np.exp(-np.arange(n) / SR / .08) if mute else env(n, .003, .9, .55, .02)
        for tr, c in (('gL', -6), ('gR', 6)):
            add(tr, st, (saws(root, n, c) + saws(root + 7, n, c) * .8 + saws(root + 12, n, c) * .6) * e)
    def bass(st, ln, m):
        if m < 28: m += 12
        n = int(ln * STEP * .92); t = np.arange(n) / SR
        add('bass', st, (saws(m, n) * .6 + np.sin(2 * np.pi * mtof(m) * t)) * env(n, .004, .2, .65, .02))
    def padn(st, ln, notes, tr, a=.12, g=1.0, trem=False):
        n = int(ln * STEP)
        x = sum(saws(m, n, c) for m in notes for c in (-9, 9)) * env(n, a, .5, .85, .1)
        if trem: x *= .55 + .45 * np.sin(2 * np.pi * 13 * np.arange(n) / SR)
        add(tr, st, x, g)
    def organ(st, ln, m, g=1.0):
        n = int(ln * STEP * .96); t = np.arange(n) / SR; f = mtof(m); x = np.sin(np.pi * f * t) * .5
        for k, a in ((1, 1), (2, .8), (3, .5), (4, .4), (6, .25), (8, .15)):
            if f * k < 9000: x += a * np.sin(2 * np.pi * f * k * t)
        add('org', st, x * env(n, .012, .1, .95, .03), g)
    def leadn(st, ln, m, tr, vol=1.0):
        n = int(ln * STEP * .97); t = np.arange(n) / SR
        vib = 1 + .007 * np.sin(2 * np.pi * 5.2 * t) * np.clip((t - .2) / .25, 0, 1)
        f0 = mtof(m); ph = 2 * np.pi * np.cumsum(f0 * vib) / SR; x = np.zeros(n)
        for k in range(1, min(24, int(15000 / f0)) + 1):
            x += np.sin(k * ph) / k * (1.6 if k % 2 else 1.0)
        add(tr, st, x * env(n, .01, .3, .75, .05), vol)
    def mel(notes, st, shift, tr, vol=1.0):
        p = st
        for m, l in notes:
            if m:
                if tr == 'brass': padn(p, l * .95, [m + shift, m + shift - 12], 'brass', .03)
                elif tr == 'choir': padn(p, l, [m + shift], 'choir', .06, vol)
                else: leadn(p, l, m + shift, tr, vol)
            p += l

    pos = 0
    for s in order:
        if s == 'END':
            add('kick', pos, KICK); add('crash', pos, CRASH, 1.3); add('timp', pos, TIMP); add('bell', pos, BELL, 1.2)
            n = int(48 * STEP)
            for tr, c in (('gL', -6), ('gR', 6)):
                add(tr, pos, (saws(38, n, c) + saws(45, n, c) * .8 + saws(50, n, c) * .6) * np.exp(-np.arange(n) / SR / 1.8))
            bass(pos, 32, 38); padn(pos, 48, [50, 62, 65, 69, 74], 'choir', .05, 1.2)
            for m in (38, 50, 62, 65, 69): organ(pos, 44, m)
            leadn(pos, 40, 74, 'lead'); pos += 80; continue
        sec = SEC[s]; chs = sec['ch']
        if s == 'I': mel(sec['mel'], pos, 0, 'lead', .8); mel(sec['mel'], pos, -12, 'choir', 1.0)
        elif s == 'A': mel(sec['mel'], pos, 0, 'lead'); mel(sec['mel'], pos, -12, 'brass')
        elif s == 'A2': mel(sec['mel'], pos, 0, 'lead'); mel(sec['mel'], pos, -12, 'brass'); mel(sec['mel'], pos, 12, 'choir', .9); mel(sec['mel'], pos, 12, 'harm', .4)
        elif s == 'B': mel(sec['mel'], pos, 0, 'lead'); mel(sec['mel'], pos, -12, 'harm', .5)
        else: mel(sec['mel'], pos, -12, 'lead'); mel(sec['mel'], pos, -24, 'brass'); mel(sec['mel'], pos, 0, 'harm', .45); mel(sec['mel'], pos, -12, 'choir', .8)
        for b, c in enumerate(chs):
            bp = pos + b * 16; root, tri = CH[c]; last = b == len(chs) - 1
            cg = {'I': .9, 'A': .5, 'A2': .8, 'B': .7, 'C': 1.2}[s]
            padn(bp, 16, tri + [tri[0] - 12], 'choir', .15, cg)
            if s == 'I':
                padn(bp, 16, [root - 12, root - 5], 'brass', .4)
                for st in (0, 3): add('kick', bp + st, KICK, .9)          # 心臓の音
                if b in (0, 2): add('bell', bp, BELL)
                if b >= 2:
                    padn(bp, 16, [t + 12 for t in tri] + [tri[0] + 18], 'trem', .5, .5 + .5 * (b - 2), True)
                    for m in (root - 12, root, tri[0], tri[1], tri[2]): organ(bp, 16, m, .5 + .5 * (b - 2))
                if b == 3:
                    for i in range(32): add('timp', bp + i * .5, TIMP, .15 + .85 * (i / 31) ** 2)
                    for i in range(8): add('snare', bp + 12 + i * .5, SNARE, .5 + .5 * i / 7)
                continue
            # organ
            if s in ('A', 'A2'):
                seq = [tri[0], tri[2], tri[0] + 12, tri[2], tri[1] + 12, tri[2], tri[0] + 12, tri[2]]
                for i in range(8): organ(bp + i * 2, 2, seq[i] - 12); organ(bp + i * 2, 2, seq[i], .5)
            elif s == 'B':
                seq = [tri[0], tri[1], tri[2], tri[0] + 12, tri[1] + 12, tri[2] + 12, tri[1] + 12, tri[0] + 12]
                for i in range(16): organ(bp + i, 1, seq[i % 8])
            else:
                for m in (root - 12, root, tri[0], tri[1], tri[2], tri[0] + 12): organ(bp, 16, m, .65)
            if s in ('A2', 'B'): padn(bp, 16, [t + 12 for t in tri], 'trem', .2, 1.0, True)
            if s in ('A', 'A2', 'C') and b in (0, 4): add('bell', bp, BELL)
            # guitars + bass
            pat = SLOW if s == 'A' else CHUG if s == 'A2' else ([(0, 16, 0)] if last else GALLOP) if s == 'B' else CHORUS
            for st, ln, mu in pat:
                gtr(bp + st, ln, root, mu)
                if s != 'C': bass(bp + st, min(ln, 6), root - 12)
            if s == 'C':
                for st in range(0, 16, 2): bass(bp + st, 2, root - 12)
            # drums
            if b in (0, 4) or (s == 'C' and b % 2 == 0): add('crash', bp, CRASH)
            if s == 'A':
                ks = [0, 3, 10]; ss = [8]
                for i in range(0, 16, 4): add('hat', bp + i, HAT, .7)
                if last: ss = [8, 12, 14, 15]
            elif s == 'A2':
                ks = [i for i in range(16) if i != 8]; ss = [8]
                for i in range(0, 16, 2): add('hat', bp + i, HAT, 1 if i % 4 == 0 else .6)
                if last: ks = list(range(8)); ss = [8, 12, 13, 14, 15]; [add('tom', bp + 8 + i, TOMS[i]) for i in range(4)]
            elif s == 'B':
                ks = [0, 2, 3, 6, 7, 8, 10, 11, 14, 15]; ss = [4, 12]
                for i in range(0, 16, 2): add('hat', bp + i, HAT, 1 if i % 4 == 0 else .6)
                if last:
                    ks = [0]; ss = [14, 14.5, 15, 15.5]
                    for i in range(12): add('tom', bp + 2 + i, TOMS[i // 3])
            else:
                ks = list(range(16)); ss = [4, 12]
                for i in range(0, 16, 2): add('hat', bp + i, OHAT if i % 4 == 0 else HAT, .7)
                if last: ss = [4, 12, 13, 14, 15]; [add('tom', bp + 8 + i, TOMS[i]) for i in range(4)]
            for k in ks: add('kick', bp + k, KICK, 1 if k % 4 == 0 else .8)
            for k in ss: add('snare', bp + k, SNARE)
        pos += len(chs) * 16

    def rms(x):
        a = x[np.abs(x) > 1e-4]; return np.sqrt(np.mean(a ** 2)) + 1e-9 if a.size else 1.0
    norm = lambda x, tg: x * (tg / rms(x))
    drums = norm(T['kick'] + T['snare'] * .65 + T['hat'] * .12 + T['tom'] * .7 + T['timp'] * .9, .19)
    crash = norm(T['crash'], .06)
    bell = norm(T['bell'], .075)
    g = {k: norm(filt(filt(np.tanh(1.2 * T[k]), 3800, 'lowpass', 4), 85, 'highpass'), .105) for k in ('gL', 'gR')}
    bs = norm(filt(np.tanh(T['bass'] * .9), 800, 'lowpass'), .15)
    c0 = T['choir']
    choir = sum(w * filt(c0, [f * .85, f * 1.15], 'bandpass') for f, w in ((650, 1), (1080, .6), (2650, .3))) + filt(c0, 380, 'lowpass') * .25
    choir = norm(choir, .085)
    trem = norm(filt(filt(T['trem'], 5000, 'lowpass'), 500, 'highpass'), .035)
    brass = norm(filt(T['brass'], 2400, 'lowpass'), .08)
    org = norm(filt(T['org'], 6000, 'lowpass'), .095)
    lg = .12 / rms(filt(T['lead'], 6500, 'lowpass'))
    ld = filt(T['lead'], 6500, 'lowpass') * lg + filt(T['harm'], 5500, 'lowpass') * lg * .8
    common = drums + bs + choir + brass + org + ld + bell
    L = common + crash * .9 + g['gL'] + g['gR'] * .15 + trem * 1.1
    R = common + crash * 1.0 + g['gR'] + g['gL'] * .15 + trem * .9
    d = int(3 * STEP)
    for i in range(1, 5):
        (L if i % 2 else R)[i * d:] += ld[:-i * d] * (.4 ** i)
    n_ir = int(3.0 * SR); t = np.arange(n_ir) / SR
    sn = T['snare'] / (np.abs(T['snare']).max() + 1e-9) * .09
    send = ld * .9 + choir * 1.2 + brass + org * .9 + bell + trem + sn + crash * .6
    for ch, seed in ((L, 1), (R, 2)):
        ir = filt(np.random.default_rng(seed).normal(0, 1, n_ir) * np.exp(-t / .6), 300, 'highpass')
        ir /= np.sqrt(np.sum(ir ** 2))
        ch += sg.fftconvolve(send, ir)[:N] * .36
    stems = dict(drums=drums, gtr=g['gL'], bass=bs, choir=choir, org=org, lead=ld, brass=brass, bell=bell, trem=trem)
    return np.stack([L, R]), pos, stems

master = lambda x, gain: np.tanh(x * gain * .9) * .97
def save(path, x):
    y = (np.clip(x, -1, 1) * 32767).astype('<i2').T.copy()
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(y.tobytes())

out = sys.argv[1]
BODY = ['A', 'A2', 'B', 'C']
loop, steps, stems = build(BODY)
nb = int(round(steps * STEP)); tail = loop.shape[1] - nb
body = loop[:, :nb].copy(); body[:, :tail] += loop[:, nb:]
gain = 1.0 / np.percentile(np.abs(body), 99.7)
save(f'{out}/ryuou2_loop.wav', master(body, gain))
intro, isteps, _ = build(['I'])
save(f'{out}/ryuou2_intro.wav', master(intro[:, :int(round(isteps * STEP))], gain))
full, _, _ = build(['I'] + BODY + BODY + ['END'], 5.0)
save(f'{out}/ryuou2_full.wav', master(full, gain))
for name, x in (('loop', body), ('full', full)):
    m = master(x, gain)
    print(name, 'sec=%.1f' % (x.shape[1] / SR), 'peak=%.2f' % np.abs(m).max(), 'rms=%.3f' % np.sqrt(np.mean(m ** 2)), 'nan', np.isnan(m).any())
sec = nb // 4
for k, v in stems.items():
    print('%-6s' % k, ' '.join('%.3f' % np.sqrt(np.mean(v[i * sec:(i + 1) * sec] ** 2)) for i in range(4)))
print('seam', np.abs(master(body, gain)[:, 0] - master(body, gain)[:, -1]).max())
