"""Sound for the promo Reels, made here so nothing needs a licence: effects, the minds' babble, and a score
whose sections follow the story (reel.json beats mark where each one starts with "music").

Plain Python, no NumPy: everything is lists of floats at 44.1 kHz, mono, roughly within -1…1.
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 44100


def write_wav(path: Path, samples: list) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def hz(note: float) -> float:
    return 440 * 2 ** ((note - 69) / 12)


def add(buffer: list, start: float, samples: list, gain: float = 1.0) -> None:
    offset = int(start * RATE)
    end = min(len(buffer), offset + len(samples))
    for i in range(max(0, offset), end):
        buffer[i] += gain * samples[i - offset]


def normalized(samples: list, peak: float = 0.9) -> list:
    top = max((abs(s) for s in samples), default=0) or 1
    return [s * peak / top for s in samples]


# Building blocks.

def tone(freq: float, seconds: float, harmonics=(1.0,), decay: float = 0.3, attack: float = 0.004,
         glide: float = 0.0, vibrato: float = 0.0) -> list:
    """A pitched note: partials at whole multiples, a fast attack, an exponential decay; `glide` bends the
    pitch by that fraction over the note, `vibrato` wobbles it at 8 Hz."""
    out, phase = [], 0.0
    n = int(RATE * seconds)
    for i in range(n):
        t = i / RATE
        f = freq * (1 + glide * t / seconds) * (1 + vibrato * math.sin(2 * math.pi * 8 * t))
        phase += 2 * math.pi * f / RATE
        value = sum(a * math.sin(phase * (k + 1)) for k, a in enumerate(harmonics))
        out.append(value * min(1, t / attack) * math.exp(-t / decay))
    return out


def bell(freq: float, seconds: float = 0.9, decay: float = 0.35) -> list:
    """A struck bell: the note and two inharmonic partials that die away faster."""
    out = []
    for i in range(int(RATE * seconds)):
        t = i / RATE
        out.append(min(1, t / 0.002) * (math.sin(2 * math.pi * freq * t) * math.exp(-t / decay)
                                         + 0.4 * math.sin(2 * math.pi * freq * 2.76 * t) * math.exp(-t / (decay * 0.4))
                                         + 0.2 * math.sin(2 * math.pi * freq * 5.4 * t) * math.exp(-t / (decay * 0.2))))
    return out


def noise(seconds: float, seed: int, smooth: float = 1.0, high: bool = False) -> list:
    """White noise, low-passed by `smooth` (1 = none, smaller = darker), or high-passed."""
    random.seed(seed)
    out, low, last = [], 0.0, 0.0
    for _ in range(int(RATE * seconds)):
        value = random.uniform(-1, 1)
        low += smooth * (value - low)
        out.append(value - last if high else low)
        last = value
    return out


def shaped(samples: list, attack: float, decay: float) -> list:
    return [s * min(1, (i / RATE) / attack) * math.exp(-(i / RATE) / decay) for i, s in enumerate(samples)]


def pluck(note: float, seconds: float, seed: int, brightness: float = 0.5) -> list:
    """A plucked string (Karplus-Strong)."""
    random.seed(seed)
    period = max(2, int(RATE / hz(note)))
    ring = [random.uniform(-1, 1) for _ in range(period)]
    out = []
    for i in range(int(RATE * seconds)):
        value = ring[i % period]
        ring[i % period] = (0.5 - 0.004 * (1 - brightness)) * (value + ring[(i + 1) % period])
        out.append(value)
    return out


# Drums.

def kick() -> list:
    out, phase = [], 0.0
    for i in range(int(RATE * 0.3)):
        t = i / RATE
        phase += 2 * math.pi * (45 + 110 * math.exp(-t / 0.035)) / RATE
        out.append(math.sin(phase) * math.exp(-t / 0.13) + (0.3 * math.exp(-t / 0.003) if i < 200 else 0))
    return out


def snare(seed: int = 1) -> list:
    body = tone(190, 0.15, decay=0.05)
    rattle = shaped(noise(0.2, seed, high=True), 0.001, 0.07)
    return [0.6 * b + 0.7 * r for b, r in zip(body, rattle)]


def clap(seed: int = 2) -> list:
    out = [0.0] * int(RATE * 0.25)
    for k, delay in enumerate((0, 0.011, 0.022)):
        add(out, delay, shaped(noise(0.2, seed + k, smooth=0.6), 0.0005, 0.012 if k < 2 else 0.08), 0.8)
    return out


def hat(open_: bool = False, seed: int = 3) -> list:
    return shaped(noise(0.3 if open_ else 0.06, seed, high=True), 0.0005, 0.09 if open_ else 0.018)


def crash(seed: int = 4) -> list:
    return shaped(noise(1.6, seed, high=True), 0.002, 0.55)


def tick() -> list:
    return shaped(noise(0.03, 9, high=True), 0.0005, 0.004)


# Effects.

def sfx(kind: str, pitch: float = 1.0) -> list:
    if kind == "notify":
        out = [0.0] * int(RATE * 0.7)
        add(out, 0, bell(1046.5, 0.6, 0.18), 0.5)
        add(out, 0.09, bell(1568, 0.6, 0.22), 0.5)
        return out
    if kind == "hit":
        out, phase = [], 0.0
        for i in range(int(RATE * 0.8)):
            t = i / RATE
            phase += 2 * math.pi * (38 + 80 * math.exp(-t / 0.08)) / RATE
            out.append(math.sin(phase) * math.exp(-t / 0.35))
        add(out, 0, shaped(noise(0.1, 5, smooth=0.3), 0.001, 0.03), 0.6)
        return out
    if kind in ("whoosh", "door"):
        length = 0.6 if kind == "door" else 0.45
        random.seed(6)
        out, low = [], 0.0
        for i in range(int(RATE * length)):
            x = i / (RATE * length)
            coefficient = 0.02 + 0.25 * math.sin(math.pi * x) ** 2
            low += coefficient * (random.uniform(-1, 1) - low)
            out.append(low * math.sin(math.pi * x) ** 1.5 * 2.2)
        return out
    if kind == "alarm":
        out, phase = [], 0.0
        for i in range(int(RATE * 1.2)):
            t = i / RATE
            phase += 2 * math.pi * (650 + 300 * abs(math.sin(math.pi * t / 0.6))) / RATE
            out.append(0.35 * (math.sin(phase) + 0.3 * math.sin(3 * phase)) * min(1, t / 0.02) * min(1, (1.2 - t) / 0.1))
        return out
    if kind == "stamp":
        out = tone(75, 0.3, decay=0.09)
        add(out, 0, shaped(noise(0.06, 7, smooth=0.5), 0.0005, 0.015), 0.9)
        return out
    if kind == "blip":
        return [0.5 * s for s in tone(560 * pitch, 0.1, (1, 0.3), decay=0.04, glide=0.35)]
    if kind == "scratch":
        # A record dragged back and forth: noise through a resonance that whips up and down.
        random.seed(8)
        out, y1, y2 = [], 0.0, 0.0
        length = 0.42
        for i in range(int(RATE * length)):
            t = i / RATE
            centre = 250 + 2300 * abs(math.sin(2 * math.pi * 3.2 * t)) * (1 - t / length * 0.6)
            w = 2 * math.pi * centre / RATE
            r = 0.985
            y = random.uniform(-1, 1) * 0.06 + 2 * r * math.cos(w) * y1 - r * r * y2
            y2, y1 = y1, y
            out.append(y * min(1, t / 0.005) * min(1, (length - t) / 0.03))
        return normalized(out, 0.8)
    if kind == "press":
        out = tone(170, 0.12, decay=0.025)
        add(out, 0, shaped(noise(0.02, 5), 0.0005, 0.004), 0.4)
        return out
    if kind == "shimmer":
        out = [0.0] * int(RATE * 1.6)
        for k, note in enumerate((84, 88, 91, 95, 98, 100)):
            add(out, k * 0.055, bell(hz(note), 1.2, 0.5), 0.22)
        return out
    if kind == "ding":
        return [0.55 * s for s in bell(1568, 0.9, 0.3)]
    if kind == "sent":
        return [0.5 * s for s in tone(620, 0.14, (1, 0.2), decay=0.045, glide=0.7)]
    if kind == "sparkle":
        random.seed(10)
        out = [0.0] * int(RATE * 0.9)
        for k in range(7):
            add(out, k * 0.05 + random.uniform(0, 0.02), bell(hz(random.choice((96, 98, 100, 103, 105))), 0.5, 0.12), 0.18)
        return out
    if kind == "confetti":
        out = [0.0] * int(RATE * 1.0)
        for k in range(5):
            add(out, k * 0.06, shaped(noise(0.08, 20 + k, smooth=0.4), 0.0005, 0.015), 0.7)
        add(out, 0.2, tone(440, 0.5, (1, 0.6, 0.4, 0.3), decay=0.6, glide=0.2, vibrato=0.02), 0.25)
        return out
    raise ValueError(f"no sound called {kind}")


VOICES = {
    # base Hz, syllables a second, partials, pitch spread, glide, vibrato
    "impulse": (300, 15, (1, 0, 0.33, 0, 0.2), 0.25, 0.0, 0.0),
    "worry": (520, 17, (1, 0.5, 0.25), 0.12, 0.0, 0.07),
    "please": (640, 12, (1, 0.45, 0.15), 0.15, 0.18, 0.0),
    "meh": (165, 7, (1, 0.6, 0.35), 0.06, -0.2, 0.0),
    "wingman": (390, 11, (1, 0.35, 0.12), 0.08, 0.05, 0.0),
}


def babble(text: str, voice: str, seed: int = 0) -> list:
    """Animal Crossing-style chatter: one short pitched blip per character of what the mind says."""
    base, rate, partials, spread, glide, vibrato = VOICES[voice]
    random.seed(seed + len(text))
    syllables = [c for c in text if c.strip() and c not in "，。！？…「」、"]
    step = 1 / rate
    out = [0.0] * int(RATE * (len(syllables) * step + 0.2))
    for k, _ in enumerate(syllables):
        freq = base * (1 + random.uniform(-spread, spread))
        add(out, k * step, tone(freq, step * 0.95, partials, decay=step * 0.55, attack=0.006, glide=glide, vibrato=vibrato), 0.32)
    return out


# The score.

def score(sections: list, total: float) -> list:
    """`sections` is [(start seconds, name)], in order; each runs until the next one starts."""
    out = [0.0] * int(RATE * total)
    bounds = sections + [(total, None)]
    for (start, name), (end, _) in zip(bounds, bounds[1:]):
        # Each section on its own, then in at its level: quiet before the storm and as Wingman walks in,
        # loud in the argument, the party and the last chord, so the story can be heard rising and falling.
        part = [0.0] * len(out)
        {"hook": hook, "chaos": chaos, "stop": stop, "enter": enter, "groove": groove,
         "party": party, "end": ending}[name](part, start, end - start)
        level = LEVELS[name]
        for i in range(int(start * RATE), len(out)):
            out[i] += level * part[i]
    return normalized(out, 0.9)


LEVELS = {"hook": 0.55, "chaos": 1.45, "stop": 1.0, "enter": 0.65, "groove": 1.0, "party": 1.3, "end": 1.5}


def chord_pad(notes, seconds: float, swell: float = 0.3) -> list:
    out = [0.0] * int(RATE * seconds)
    for note in notes:
        step = 2 * math.pi * hz(note) / RATE
        for i in range(len(out)):
            out[i] += math.sin(step * i) + 0.2 * math.sin(2 * step * i)
    return [s * min(1, (i / RATE) / swell) * min(1, (seconds - i / RATE) / 0.15) for i, s in enumerate(out)]


def hook(out, start, seconds):
    """A held, uneasy chord, then a heartbeat once the message has landed."""
    add(out, start, chord_pad((45, 48, 52, 57), seconds, swell=0.6), 0.05)
    for beat in (0.9, 1.12, 1.55, 1.77):
        if beat < seconds:
            add(out, start + beat, kick(), 0.55)


def chaos(out, start, seconds):
    """Everyone talking at once: 150 BPM, a bass that will not sit still, and a key that climbs."""
    sixteenth = 60 / 150 / 4
    steps = int(seconds / sixteenth)
    for s in range(steps):
        at = start + s * sixteenth
        bar, pos = divmod(s, 16)
        root = 33 + bar // 2       # up a semitone every two bars
        if pos in (0, 8, 14):
            add(out, at, kick(), 0.6)
        if pos in (4, 12):
            add(out, at, snare(bar), 0.4)
        add(out, at, hat(seed=s), 0.12 if pos % 2 else 0.2)
        if pos % 2 == 0:
            note = root + (12 if pos % 4 == 2 else 0) + (10 if pos == 14 else 0)
            add(out, at, tone(hz(note), sixteenth * 1.8, (1, 0, 0.3, 0, 0.15), decay=0.08), 0.35)
        if pos in (3, 6, 11, 14):
            for interval in (12, 15, 19):
                add(out, at, tone(hz(root + 24 + interval), 0.09, (1, 0, 0.3), decay=0.04), 0.07)
    # A riser into the stop.
    rise = min(1.6, seconds)
    random.seed(12)
    low, phase = 0.0, 0.0
    begin = int((start + seconds - rise) * RATE)
    for i in range(int(rise * RATE)):
        x = i / (rise * RATE)
        low += (0.02 + 0.4 * x) * (random.uniform(-1, 1) - low)
        phase += 2 * math.pi * (200 + 1000 * x * x) / RATE
        if begin + i < len(out):
            out[begin + i] += (0.25 * low + 0.08 * math.sin(phase)) * x * x


def stop(out, start, seconds):
    """Dead quiet but for a clock."""
    k = 0
    while k * 0.5 + 0.25 < seconds:
        add(out, start + 0.25 + k * 0.5, tick(), 0.25)
        k += 1


def enter(out, start, seconds):
    """Wingman comes in: bells climbing a bright chord over a soft swell, and a cymbal drawn in reverse into the beat."""
    add(out, start, chord_pad((48, 52, 55, 59, 62), seconds, swell=0.8), 0.045)
    for k, note in enumerate((72, 76, 79, 83, 86, 88, 91, 95, 98, 100, 103, 107)):
        if k * 0.15 < seconds - 0.2:
            add(out, start + k * 0.15, bell(hz(note), 1.0, 0.4), 0.16)
    swell = min(0.8, seconds)
    reverse = list(reversed(crash(13)[: int(RATE * swell)]))
    add(out, start + seconds - swell, reverse, 0.35)


CHORDS = [(48, (60, 64, 67, 71)), (45, (57, 60, 64, 67)), (41, (57, 60, 64, 65)), (43, (59, 62, 65, 67))]   # C, Am, F, G
MOTIF = [(76, 0), (79, 2), (81, 3), (79, 4), (76, 6), (74, 8), (76, 10), (72, 12)]   # pentatonic, in sixteenths over a bar


def groove(out, start, seconds, busy=False):
    """The meeting goes well: 108 BPM, C–Am–F–G, a bass that dances, and the tune once it has settled in."""
    sixteenth = 60 / 108 / 4
    steps = int(seconds / sixteenth)
    swing = sixteenth * 0.18
    for s in range(steps):
        bar, pos = divmod(s, 16)
        at = start + s * sixteenth + (swing if pos % 2 else 0)
        root, voicing = CHORDS[bar % 4]
        if s == 0:
            add(out, at, crash(), 0.25)
        if pos in (0, 6, 10):
            add(out, at, kick(), 0.6)
        if pos in (4, 12):
            add(out, at, clap(bar), 0.45)
        if pos % 2 == 0:
            add(out, at, hat(open_=pos == 14, seed=s), 0.13)
        if busy:
            add(out, at, hat(seed=s + 500), 0.06)
        if pos in (0, 3, 6, 8, 11, 14):
            note = root - 12 + {0: 0, 3: 0, 6: 7, 8: 12, 11: 0, 14: 10}[pos]
            add(out, at, tone(hz(note), 0.3, (1, 0.5, 0.25), decay=0.16), 0.42)
        if pos in (2, 7, 10):
            for note in voicing:
                add(out, at, tone(hz(note), 0.25, (1, 0.25, 0.1), decay=0.12), 0.06)
        if (busy or bar >= 2) and bar % 2 == 0:
            for note, when in MOTIF:
                if when == pos:
                    add(out, at, pluck(note, 0.5, seed=s, brightness=0.8), 0.32)


def party(out, start, seconds):
    groove(out, start, seconds, busy=True)


def ending(out, start, seconds):
    """One last chord, all in, left to ring."""
    add(out, start, crash(), 0.35)
    add(out, start, kick(), 0.7)
    add(out, start, clap(), 0.4)
    add(out, start, tone(hz(36), seconds, (1, 0.5, 0.25), decay=1.0), 0.45)
    pad = chord_pad((48, 55, 60, 64, 67, 71, 74), seconds, swell=0.02)
    add(out, start, [s * math.exp(-(i / RATE) / 1.2) for i, s in enumerate(pad)], 0.08)
    for k, note in enumerate((79, 84, 88, 91)):
        add(out, start + 0.1 + k * 0.08, bell(hz(note), 2.0, 0.8), 0.18)
    fade = int(RATE * min(1.2, seconds))
    end = min(len(out), int((start + seconds) * RATE))
    for i in range(end - fade, end):
        out[i] *= (end - i) / fade
