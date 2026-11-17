import numpy as np, scipy.signal as sg, wave, sys

SR = 44100; BPM = 176; STEP = 60 / BPM / 4 * SR
rng = np.random.default_rng(7)
mtof = lambda m: 440 * 2 ** ((m - 69) / 12)

def env(n, a=0.005, d=0.1, s=0.7, r=0.03):
    t = np.arange(n) / SR
    e = np.where(t < a, t / a, s + (1 - s) * np.exp(-(t - a) / d))
    rn = max(1, min(int(r * SR), n)); e[-rn:] *= np.linspace(1, 0, rn)
    return e

def filt(x, fc, kind, order=2):
    sos = sg.butter(order, fc, kind, fs=SR, output='sos')
    return sg.sosfilt(sos, x)

# ---------- drum samples ----------
def mk_kick():
    t = np.arange(int(.25 * SR)) / SR
    f = 45 + 120 * np.exp(-t / .028)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .085)
    x[:200] += rng.normal(0, .5, 200) * np.linspace(1, 0, 200)
    return np.tanh(2 * x)
def mk_snare():
    t = np.arange(int(.22 * SR)) / SR
    n = filt(rng.normal(0, 1, t.size), [900, 9000], 'bandpass') * np.exp(-t / .06)
    return n * .9 + np.sin(2 * np.pi * 195 * t) * np.exp(-t / .035) * .7
def mk_hat(dec, L):
    t = np.arange(int(L * SR)) / SR
    return filt(rng.normal(0, 1, t.size), 7500, 'highpass', 4) * np.exp(-t / dec)
def mk_crash():
    t = np.arange(int(2.0 * SR)) / SR
    return filt(rng.normal(0, 1, t.size), 3500, 'highpass') * (np.exp(-t / .45) * .7 + np.exp(-t / .06) * .5)
def mk_tom(f):
    t = np.arange(int(.3 * SR)) / SR
    ff = f * (1 + .6 * np.exp(-t / .03))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t / .11)
def mk_timp():
    t = np.arange(int(1.4 * SR)) / SR
    ff = 73.4 * (1 + .08 * np.exp(-t / .05))
    ph = 2 * np.pi * np.cumsum(ff) / SR
    x = (np.sin(ph) + .5 * np.sin(1.5 * ph) + .25 * np.sin(2 * ph)) * np.exp(-t / .38)
    return x + filt(rng.normal(0, 1, t.size), 400, 'lowpass') * np.exp(-t / .03) * 2
KICK, SNARE, HAT, OHAT, CRASH, TIMP = mk_kick(), mk_snare(), mk_hat(.012, .06), mk_hat(.08, .3), mk_crash(), mk_timp()
TOMS = [mk_tom(f) for f in (220, 165, 124, 92)]

CH = {'Dm': (50, [62, 65, 69]), 'Bb': (46, [58, 62, 65]), 'C': (48, [60, 64, 67]),
      'A': (45, [57, 61, 64]), 'Gm': (43, [55, 58, 62]), 'F': (41, [53, 57, 60])}

# ---------- score (midi, length in 16ths) ----------
MEL_A = [(74,3),(69,3),(74,2),(76,2),(77,6), (76,3),(74,3),(72,2),(74,8),
         (77,3),(74,3),(77,2),(79,2),(81,6), (79,3),(76,3),(72,2),(76,4),(79,4),
         (81,3),(79,3),(77,2),(76,2),(74,6), (77,3),(76,3),(74,2),(72,4),(69,4),
         (70,3),(74,3),(77,2),(82,8), (81,4),(79,2),(77,2),(76,4),(73,4)]
MEL_B = [(67,2),(70,2),(74,2),(79,2),(77,4),(74,4), (76,2),(73,2),(69,2),(73,2),(76,8),
         (77,2),(76,2),(74,2),(69,2),(74,4),(77,4), (81,6),(79,2),(77,4),(72,4),
         (82,2),(81,2),(79,2),(74,2),(79,4),(82,4), (81,2),(79,2),(76,2),(73,2),(76,4),(81,4),
         (82,4),(77,4),(84,4),(79,4), (85,12),(76,1),(81,1),(85,1),(88,1)]
MEL_C = [(86,6),(84,2),(82,4),(77,4), (88,6),(86,2),(84,4),(79,4), (89,8),(88,4),(86,4),
         (81,6),(86,2),(89,4),(93,4), (94,6),(93,2),(89,4),(86,4), (91,6),(88,2),(84,4),(88,4),
         (88,8),(85,4),(81,4), (85,2),(88,2),(93,4),(91,1),(89,1),(88,1),(86,1),(85,1),(82,1),(81,1),(79,1)]
MEL_I = [(0,32),(74,4),(77,4),(82,8),(81,4),(85,4),(88,8)]
SEC = {
 'I':  dict(ch=['Dm','Dm','Bb','A'], mel=MEL_I),
 'A':  dict(ch=['Dm','Dm','Bb','C','Dm','Dm','Bb','A'], mel=MEL_A),
 'A2': dict(ch=['Dm','Dm','Bb','C','Dm','Dm','Bb','A'], mel=MEL_A),
 'B':  dict(ch=['Gm','A','Dm','F','Gm','A',('Bb','C'),'A'], mel=MEL_B),
 'C':  dict(ch=['Bb','C','Dm','Dm','Bb','C','A','A'], mel=MEL_C),
 'C2': dict(ch=['Bb','C','Dm','Dm','Bb','C','A','A'], mel=MEL_C),
}
GALLOP = [(0,2,1),(2,1,1),(3,1,1),(4,2,1),(6,1,1),(7,1,1),(8,2,1),(10,1,1),(11,1,1),(12,2,1),(14,1,1),(15,1,1)]
ACCENT = [(0,3,0),(3,3,0),(6,2,0),(8,3,0),(11,3,0),(14,2,0)]
HEAVY  = [(0,6,0),(6,2,0),(8,4,0),(12,1,1),(13,1,1),(14,1,1),(15,1,1)]
CHORUS = [(0,6,0),(6,2,0),(8,6,0),(14,2,0)]

def third(m):
    sc = [2, 4, 5, 7, 9, 10, 0]; pc = m % 12
    if pc not in sc: return m + 3
    i = sc.index(pc); up = (sc[(i + 2) % 7] - pc) % 12
    return m + up

def build(order, tail_s=3.0):
    bars = sum(len(SEC[s]['ch']) if s in SEC else 4 for s in order)
    N = int(bars * 16 * STEP + tail_s * SR)
    T = {k: np.zeros(N) for k in ['kick','snare','hat','crash','tom','timp','gL','gR','bass','pad','lead','harm','arpL','arpR','brass']}
    P = lambda st: int(round(st * STEP))
    def add(tr, st, x, g=1.0):
        i = P(st); n = min(x.size, N - i)
        if n > 0: T[tr][i:i+n] += x[:n] * g
    def saws(m, n, cents=0.):
        f = mtof(m) * 2 ** (cents / 1200)
        return 2 * ((np.arange(n) * f / SR + rng.random()) % 1) - 1
    def gtr(st, ln, root, mute):
        n = int(ln * STEP * (0.92 if mute else 1.0))
        e = np.exp(-np.arange(n) / SR / .075) if mute else env(n, .003, .7, .55, .02)
        for tr, c in (('gL', -6), ('gR', 6)):
            x = saws(root, n, c) + saws(root + 7, n, c) * .8 + saws(root + 12, n, c) * .6
            add(tr, st, x * e)
    def bass(st, ln, m):
        n = int(ln * STEP * .9)
        t = np.arange(n) / SR
        x = saws(m, n) * .6 + np.sin(2 * np.pi * mtof(m) * t)
        add('bass', st, x * env(n, .004, .15, .6, .02))
    def padn(st, ln, notes, tr='pad', a=.09):
        n = int(ln * STEP)
        x = sum(saws(m, n, c) for m in notes for c in (-8, 8))
        add(tr, st, x * env(n, a, .5, .8, .08))
    def leadn(st, ln, m, tr, vol=1.0):
        n = int(ln * STEP * .97)
        t = np.arange(n) / SR
        vib = 1 + .006 * np.sin(2 * np.pi * 5.8 * t) * np.clip((t - .16) / .2, 0, 1)
        f0 = mtof(m)
        ph = 2 * np.pi * np.cumsum(f0 * vib) / SR
        x = np.zeros(n)
        for k in range(1, min(24, int(15000 / f0)) + 1):
            x += np.sin(k * ph) / k * (1.6 if k % 2 else 1.0)
        add(tr, st, x * env(n, .008, .25, .75, .04), vol)
    def mel(notes, st, shift, tr, vol=1.0, fn=None):
        p = st
        for m, l in notes:
            if m:
                mm = (fn(m) if fn else m) + shift
                if tr == 'brass': padn(p, l * .95, [mm, mm - 12], 'brass', .02)
                else: leadn(p, l, mm, tr, vol)
            p += l
    def arp(st, tri):
        seq = [tri[0], tri[1], tri[2], tri[0] + 12, tri[2], tri[1], tri[0] + 12, tri[2]]
        for i in range(8):
            n = int(STEP * .9); m = seq[i] + 12
            ph = (np.arange(n) * mtof(m) / SR) % 1
            add('arpL' if i % 2 == 0 else 'arpR', st + i, np.where(ph < .25, 1., -1.) * env(n, .002, .05, .3, .01))

    pos = 0
    for s in order:
        if s == 'END':
            add('kick', pos, KICK); add('crash', pos, CRASH, 1.3); add('timp', pos, TIMP)
            n = int(40 * STEP)
            for tr, c in (('gL', -6), ('gR', 6)):
                add(tr, pos, (saws(50, n, c) + saws(57, n, c) * .8 + saws(62, n, c) * .6) * np.exp(-np.arange(n) / SR / 1.4))
            bass(pos, 24, 38); padn(pos, 40, [62, 65, 69, 74]); leadn(pos, 36, 74, 'lead'); leadn(pos, 36, 86, 'harm', .6)
            pos += 64; continue
        sec = SEC[s]; chs = sec['ch']
        # melody
        if s == 'I':
            mel(sec['mel'], pos, 0, 'lead'); mel(sec['mel'], pos, -12, 'brass')
        elif s in ('A', 'A2', 'B'):
            mel(sec['mel'], pos, 0, 'lead')
            if s == 'A2': mel(sec['mel'], pos, 0, 'harm', .6, third)
            if s == 'B': mel(sec['mel'], pos, -12, 'harm', .5)
        else:
            mel(sec['mel'], pos, -12, 'lead'); mel(sec['mel'], pos, -24, 'brass')
            if s == 'C2': mel(sec['mel'], pos, 0, 'harm', .55)
        for b, c in enumerate(chs):
            bp = pos + b * 16
            halves = c if isinstance(c, tuple) else (c, c)
            root = lambda st: CH[halves[0 if st < 8 else 1]][0]
            last = b == len(chs) - 1
            # pad
            if halves[0] == halves[1]: padn(bp, 16, CH[c][1] + ([CH[c][1][0] + 12] if s[0] == 'C' else []))
            else:
                padn(bp, 8, CH[halves[0]][1]); padn(bp + 8, 8, CH[halves[1]][1])
            if s == 'I':
                padn(bp, 16, [CH[c][0] - 12, CH[c][0] - 5])
                if b < 2:
                    for st in ([0, 6, 8] if b == 0 else [0, 6, 8, 12, 14]): add('timp', bp + st, TIMP)
                else:
                    if b == 2: add('crash', bp, CRASH)
                    for st, ln, mu in ACCENT:
                        gtr(bp + st, ln, root(st), 0); bass(bp + st, ln, root(st) - 12); add('kick', bp + st, KICK)
                        padn(bp + st, ln * .8, [CH[c][0] + 12, CH[c][0] + 19, CH[c][0] + 24], 'brass', .015)
                    if b == 3:
                        for i in range(16): add('snare', bp + i, SNARE, .25 + .75 * i / 15)
                        for i in range(8): add('snare', bp + 12 + i * .5, SNARE, .6 + .4 * i / 7)
                continue
            # guitars + bass
            if s in ('A', 'A2'): pat = ACCENT if b in (3, 7) else GALLOP
            elif s == 'B': pat = [(0, 8, 0), (8, 8, 0)] if b == 6 else [(0, 16, 0)] if last else HEAVY
            else: pat = CHORUS
            for st, ln, mu in pat:
                gtr(bp + st, ln, root(st), mu)
                if s[0] != 'C': bass(bp + st, min(ln, 4), root(st) - 12)
            if s[0] == 'C':
                for st in range(0, 16, 2): bass(bp + st, 2, root(st) - 12)
            if s in ('A2', 'C', 'C2'):
                arp(bp, CH[halves[0]][1]); arp(bp + 8, CH[halves[1]][1])
            # drums
            if b == 0 or (b == 4) or (s[0] == 'C' and b % 2 == 0): add('crash', bp, CRASH)
            if s in ('A', 'A2'):
                ks = [0, 2, 3, 6, 7, 8, 10, 11, 14, 15]; ss = [4, 12]
                if last: ks = [0, 2, 3, 6, 7]; ss = [4, 12, 13, 14, 15]; [add('tom', bp + 8 + i, TOMS[i]) for i in range(4)]
                for i in range(0, 16, 2): add('hat', bp + i, HAT, 1 if i % 4 == 0 else .6)
            elif s == 'B':
                ks = [0, 3, 6, 10, 11]; ss = [8]
                if last:
                    ks = [0, 6]; ss = [14, 14.5, 15, 15.5]
                    for i in range(8): add('tom', bp + 6 + i, TOMS[i // 2])
                for i in range(0, 16, 4): add('hat', bp + i, OHAT, .8)
                for i in range(2, 16, 4): add('hat', bp + i, HAT, .6)
            else:
                ks = list(range(16)) if s == 'C2' else list(range(0, 16, 2)); ss = [4, 12]
                if last: ss = [4, 12, 13, 14, 15]; [add('tom', bp + 8 + i, TOMS[i]) for i in range(4)]
                for i in range(0, 16, 2): add('hat', bp + i, OHAT if i % 4 == 0 else HAT, .7)
            for k in ks: add('kick', bp + k, KICK, 1 if k % 4 == 0 else .8)
            for k in ss: add('snare', bp + k, SNARE)
        pos += len(chs) * 16

    # ---------- mix ----------
    def norm(x, target):
        a = x[np.abs(x) > 1e-4]
        return x * (target / (np.sqrt(np.mean(a ** 2)) + 1e-9)) if a.size else x
    drums = T['kick'] * 1.0 + T['snare'] * .6 + T['hat'] * .13 + T['tom'] * .7 + T['timp'] * 1.0
    drums = norm(drums, .20)
    crash = norm(T['crash'], .07)
    g = {k: norm(filt(filt(np.tanh(1.2 * T[k]), 4300, 'lowpass', 4), 95, 'highpass'), .115) for k in ('gL', 'gR')}
    bs = norm(filt(np.tanh(T['bass'] * .9), 900, 'lowpass'), .15)
    pad = norm(filt(T['pad'], 2600, 'lowpass'), .055)
    brass = norm(filt(T['brass'], 3200, 'lowpass'), .085)
    lead = norm(filt(T['lead'], 7000, 'lowpass'), .135)
    harm = filt(T['harm'], 6000, 'lowpass'); harm *= .135 / (np.sqrt(np.mean(T['lead'][np.abs(T['lead']) > 1e-4] ** 2)) + 1e-9) * .8
    aL, aR = (filt(T[k], 7000, 'lowpass') for k in ('arpL', 'arpR'))
    sc = .035 / (np.sqrt(np.mean(aL[np.abs(aL) > 1e-4] ** 2)) + 1e-9) if np.any(aL) else 0
    aL, aR = aL * sc, aR * sc
    ld = lead + harm
    L = drums + crash * .9 + g['gL'] + g['gR'] * .15 + bs + pad + brass * .9 + ld + aL + aR * .3
    R = drums + crash * 1.0 + g['gR'] + g['gL'] * .15 + bs + pad + brass * 1.0 + ld + aR + aL * .3
    d = int(3 * STEP)
    for i in range(1, 5):
        tgt = L if i % 2 else R
        tgt[i * d:] += ld[:-i * d] * (.42 ** i)
    # reverb
    n_ir = int(1.8 * SR); t = np.arange(n_ir) / SR
    send = ld * .9 + pad + brass + T['snare'] * (.2 / (np.abs(T['snare']).max() + 1e-9)) * .25 + crash * .6 + (aL + aR) * .8
    for ch, seed in ((L, 1), (R, 2)):
        ir = filt(np.random.default_rng(seed).normal(0, 1, n_ir) * np.exp(-t / .38), 350, 'highpass')
        ir /= np.sqrt(np.sum(ir ** 2))
        ch += sg.fftconvolve(send, ir)[:N] * .28
    return np.stack([L, R]), pos

def master(x, gain):
    return np.tanh(x * gain * .9) * .97

def save(path, x):
    y = (np.clip(x, -1, 1) * 32767).astype('<i2').T.copy()
    with wave.open(path, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(y.tobytes())

out = sys.argv[1]
BODY = ['A', 'A2', 'B', 'C', 'C2']
loop, steps = build(BODY)
nb = int(round(steps * STEP)); tail = loop.shape[1] - nb
body = loop[:, :nb].copy(); body[:, :tail] += loop[:, nb:]
gain = 1.0 / np.percentile(np.abs(body), 99.7)
save(f'{out}/ryuou_loop.wav', master(body, gain))
intro, isteps = build(['I'])
ni = int(round(isteps * STEP))
save(f'{out}/ryuou_intro.wav', master(intro[:, :ni], gain))  # tail of intro is dropped; fine at 176bpm into a crash
full, _ = build(['I'] + BODY + BODY + ['END'], 4.0)
save(f'{out}/ryuou_full.wav', master(full, gain))
for name, x in (('loop', body), ('full', full)):
    m = master(x, gain)
    print(name, 'sec=%.1f' % (x.shape[1] / SR), 'peak=%.2f' % np.abs(m).max(), 'rms=%.3f' % np.sqrt(np.mean(m ** 2)), 'nan', np.isnan(m).any())
