"""Self-synthesized ambient / lo-fi pad bed (no samples): soft detuned chord pads, a sub bass note,
a slow filtered noise 'air' layer and a simple feedback-delay space. Output: vo/bed.wav (48 kHz stereo).
Usage: python3 music.py <seconds>"""
import sys, os, wave
import numpy as np

SR = 48000
T = float(sys.argv[1]) if len(sys.argv) > 1 else 170.0
HERE = os.path.dirname(os.path.abspath(__file__))
rng = np.random.default_rng(7)
n = int(T * SR); t = np.arange(n) / SR

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)
# Am9 - Fmaj7 - Cmaj7 - G6, 8 s per chord (MIDI notes)
CHORDS = [[57, 60, 64, 67, 71], [53, 57, 60, 64, 67], [48, 55, 59, 64, 67], [55, 59, 62, 64, 67]]
BASS = [45, 41, 36, 43]
CH = 8.0

L = np.zeros(n); R = np.zeros(n)
def env(length, a=2.5, r=3.0):
    e = np.ones(length); ai = int(a * SR); ri = int(r * SR)
    e[:ai] = np.sin(np.linspace(0, np.pi / 2, ai)) ** 2
    e[-ri:] *= np.cos(np.linspace(0, np.pi / 2, ri)) ** 2
    return e
k = 0; start = 0.0
while start < T:
    s0 = int(start * SR); length = min(int((CH + 3.0) * SR), n - s0)  # 3 s overlap = crossfade
    if length <= SR: break
    tt = np.arange(length) / SR; e = env(length)
    for j, m in enumerate(CHORDS[k % 4]):
        f = hz(m)
        for det, pan in ((-0.12, 0.3), (0.12, 0.7)):     # detuned pair, panned
            ph = rng.uniform(0, 2 * np.pi)
            v = np.sin(2 * np.pi * (f + det) * tt + ph) + 0.18 * np.sin(2 * np.pi * 2 * (f + det) * tt + ph)
            v *= 0.055 * e * (1 + 0.15 * np.sin(2 * np.pi * 0.11 * tt + j))   # slow swell
            L[s0:s0 + length] += v * (1 - pan); R[s0:s0 + length] += v * pan
    b = 0.07 * np.sin(2 * np.pi * hz(BASS[k % 4]) * tt) * e
    L[s0:s0 + length] += b; R[s0:s0 + length] += b
    start += CH; k += 1

# air: lowpassed noise with slow movement
def lp(x, a):
    y = np.empty_like(x); acc = 0.0
    # one-pole lowpass, vectorized via cumulative trick is unstable; do it in blocks
    for i in range(0, len(x), 4800):
        blk = x[i:i + 4800]
        out = np.empty_like(blk)
        for j in range(len(blk)):
            acc += a * (blk[j] - acc); out[j] = acc
        y[i:i + 4800] = out
    return y
noise = rng.standard_normal(n // 8)
noise = lp(noise, 0.02)
noise = np.interp(np.arange(n) / 8, np.arange(len(noise)), noise)
air = noise * 0.06 * (0.6 + 0.4 * np.sin(2 * np.pi * 0.05 * t))
L += air; R += np.roll(air, 2400)

# soft 'lo-fi' tick every beat (70 bpm), very quiet filtered click
beat = 60 / 70; tick = np.zeros(n)
for bt in np.arange(0, T, beat):
    i = int(bt * SR); m = min(1200, n - i)
    tick[i:i + m] += np.exp(-np.arange(m) / 180) * rng.standard_normal(m) * 0.025
L += tick; R += tick

# space: feedback delay
for d, g in ((0.37, 0.35), (0.53, 0.25)):
    D = int(d * SR)
    for ch in (L, R):
        ch[D:] += g * ch[:-D]

# master fade in / out
fi, fo = int(4 * SR), int(6 * SR)
m = np.ones(n); m[:fi] = np.linspace(0, 1, fi) ** 2; m[-fo:] = np.linspace(1, 0, fo) ** 2
L *= m; R *= m
peak = max(np.abs(L).max(), np.abs(R).max())
st = (np.stack([L, R], 1) / peak * 0.5 * 32767).astype(np.int16)
os.makedirs(os.path.join(HERE, "vo"), exist_ok=True)
with wave.open(os.path.join(HERE, "vo", "bed.wav"), "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(st.tobytes())
print("bed.wav", T)
