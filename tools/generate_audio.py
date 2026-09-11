"""Original, deterministic quiet foley. Regenerate with Python's standard library."""
from pathlib import Path
import math, random, struct, wave
out = Path(__file__).resolve().parents[1] / 'game/assets/audio'
out.mkdir(exist_ok=True)
rate = 22050
for name, duration in [('step', .16), ('plug', .11), ('ui', .055), ('fan', 4.)]:
    rng = random.Random(41)
    samples = []
    low = 0.
    for i in range(int(rate * duration)):
        t = i / rate
        low = .88 * low + .12 * rng.uniform(-1, 1)
        if name == 'fan':
            v = .25 * low + .015 * math.sin(2 * math.pi * 100 * t) + .008 * math.sin(2 * math.pi * 150 * t)
        elif name == 'step':
            v = (low * 2 + .2 * math.sin(2 * math.pi * 95 * t)) * math.exp(-t * 35) * min(t * 700, 1)
        else:
            freq = 1300 if name == 'plug' else 800
            v = (.3 * math.sin(2 * math.pi * freq * t) + low) * math.exp(-t * 75) * min(t * 1800, 1)
        samples.append(int(max(-1, min(1, v)) * 32767))
    if name == 'fan':
        # Smooth periodic seam, no click at loop boundary.
        seam = 512
        for i in range(seam):
            blend = i / seam
            samples[-seam+i] = int(samples[-seam+i] * (1-blend) + samples[i] * blend)
        samples = samples[seam:]
    with wave.open(str(out / (name + '.wav')), 'wb') as f:
        f.setparams((1, 2, rate, 0, 'NONE', 'not compressed'))
        f.writeframes(struct.pack('<' + 'h' * len(samples), *samples))
