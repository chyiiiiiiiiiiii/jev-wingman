#!/usr/bin/env python3
"""Cut a promo Reel (1080×1920) from promo/<name>/: the app draws the screens, this strings them together.

    scripts/make-reel.py reel-01            build, draw, cut promo/reel-01/out/reel-01.mp4
    scripts/make-reel.py reel-01 --stage    run the made-up chats through Jev and the writer first

Shots to be filmed (side A, B, …) come from promo/<name>/footage/<A>.mov or .mp4 when there, cropped to
9:16 and started at the second given in footage/cuts.json ({"A": 1.5}); until then the app's drawn lead
acts them out. Their own sound (keys, a sigh) stays in, under the sound effects, over a quiet made-up
music bed; Instagram's music can go on top.
Needs ffmpeg. Every chat in it is made up.
"""
import json
import math
import random
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/Wingman.app/Contents/MacOS/Wingman"
RATE = 44100
FPS = 30


def run(*command) -> None:
    subprocess.run([str(part) for part in command], check=True)


def ffmpeg(*arguments) -> None:
    run("ffmpeg", "-loglevel", "error", "-y", *arguments)


# Sound effects for the chat itself. Wingman's own sounds come from the app (sound-inserted.wav).

def write_wav(path: Path, samples: list) -> None:
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))


def pop() -> list:
    """A message arriving: a soft bubble whose pitch drops."""
    length = int(RATE * 0.14)
    out, phase = [], 0.0
    for i in range(length):
        t = i / RATE
        phase += 2 * math.pi * (1150 - 2600 * min(t, 0.18)) / RATE
        out.append(0.32 * math.sin(phase) * min(1, t / 0.004) * math.exp(-t / 0.035))
    return out


def sent() -> list:
    """A message going out: a short rising blip."""
    length = int(RATE * 0.12)
    out, phase = [], 0.0
    for i in range(length):
        t = i / RATE
        phase += 2 * math.pi * (620 + 3800 * t) / RATE
        out.append(0.22 * math.sin(phase) * min(1, t / 0.006) * math.exp(-t / 0.04))
    return out


def sigh() -> list:
    """A long breath out: soft noise that swells and fades."""
    random.seed(3)
    out, low = [], 0.0
    for i in range(int(RATE * 0.9)):
        t = i / RATE
        low += 0.08 * (random.uniform(-1, 1) - low)      # a one-pole low-pass: hiss into breath
        out.append(1.6 * low * min(1, t / 0.22) * math.exp(-max(0, t - 0.22) / 0.22))
    return out


def press() -> list:
    """Two keys going down together: a low thock with a click on top."""
    random.seed(5)
    out = []
    for i in range(int(RATE * 0.12)):
        t = i / RATE
        out.append(0.4 * math.sin(2 * math.pi * 170 * t) * math.exp(-t / 0.025)
                   + 0.15 * random.uniform(-1, 1) * math.exp(-t / 0.004))
    return out


def typing(seconds: float) -> list:
    """Keys over most of a beat: short filtered clicks at uneven gaps."""
    random.seed(7)
    out = [0.0] * int(RATE * seconds)
    at = 0.04
    while at < seconds - 0.08:
        start, previous = int(at * RATE), 0.0
        loudness = random.uniform(0.18, 0.3)
        for i in range(int(RATE * 0.018)):
            noise = random.uniform(-1, 1)
            click = noise - previous      # a first difference: the thud goes, the click stays
            previous = noise
            if start + i < len(out):
                out[start + i] += loudness * click * math.exp(-i / (RATE * 0.004))
        at += random.uniform(0.09, 0.16)
    return out


def music(seconds: float) -> list:
    """A quiet lo-fi bed so no stretch of the cut is silent: Fmaj7, Em7, Dm7, Cmaj7 at 88 BPM, with
    a warm pad, a plucked arpeggio, a soft bass and brushed drums. Made here, so nothing to license."""
    random.seed(11)
    beat = 60 / 88
    bar = beat * 4
    total = int(RATE * seconds)
    out = [0.0] * total
    chords = [(53, 57, 60, 64), (52, 55, 59, 62), (50, 53, 57, 60), (48, 52, 55, 59)]   # MIDI notes

    def hz(note):
        return 440 * 2 ** ((note - 69) / 12)

    def add(start, samples, gain):
        offset = int(start * RATE)
        for i, v in enumerate(samples):
            if offset + i < total:
                out[offset + i] += gain * v

    def pluck(note, length):
        period = max(2, int(RATE / hz(note)))
        ring = [random.uniform(-1, 1) for _ in range(period)]
        samples = []
        for i in range(int(RATE * length)):
            value = ring[i % period]
            ring[i % period] = 0.497 * (value + ring[(i + 1) % period])
            samples.append(value)
        return samples

    bars = int(seconds / bar) + 1
    for n in range(bars):
        chord = chords[n % 4]
        at = n * bar
        # Pad: the chord held through the bar, swelling in and out.
        length = int(RATE * bar)
        pad = [0.0] * length
        for note in chord:
            step = 2 * math.pi * hz(note) / RATE
            for i in range(length):
                pad[i] += math.sin(step * i) + 0.25 * math.sin(2 * step * i)
        for i in range(length):
            t = i / RATE
            pad[i] *= min(1, t / 0.35) * min(1, (bar - t) / 0.35)
        add(at, pad, 0.035)
        # Arpeggio: eighth notes up the chord, an octave higher.
        for k in range(8):
            add(at + k * beat / 2 + random.uniform(0, 0.012), pluck(chord[k % 4] + 12, 0.5), 0.12)
        # Bass on one and three; kick with it; a brushed snare on two and four; hats between.
        for k in range(4):
            start = at + k * beat
            if k in (0, 2):
                root = hz(chord[0] - 12)
                add(start, [math.sin(2 * math.pi * root * i / RATE) * math.exp(-i / (RATE * 0.35))
                            for i in range(int(RATE * 0.6))], 0.16)
                phase, kick = 0.0, []
                for i in range(int(RATE * 0.16)):
                    phase += 2 * math.pi * (50 + 70 * math.exp(-i / (RATE * 0.03))) / RATE
                    kick.append(math.sin(phase) * math.exp(-i / (RATE * 0.05)))
                add(start, kick, 0.3)
            else:
                add(start, [random.uniform(-1, 1) * math.exp(-i / (RATE * 0.06)) for i in range(int(RATE * 0.2))], 0.05)
            add(start + beat / 2, [random.uniform(-1, 1) * math.exp(-i / (RATE * 0.008)) for i in range(int(RATE * 0.03))], 0.035)
    for i in range(total):
        t = i / RATE
        out[i] *= min(1, t / 0.3) * min(1, (seconds - t) / 1.5)
    return out


# Beats into one video.

def segment(beat: dict, frames: Path, footage: Path, cuts: dict, out: Path) -> None:
    seconds = str(beat["seconds"])
    overlay = frames / beat["overlay"]
    shot = next((footage / f"{beat['side']}{ext}" for ext in (".mov", ".mp4", ".MOV", ".MP4")
                 if "side" in beat and (footage / f"{beat['side']}{ext}").exists()), None)
    encode = ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p", "-r", str(FPS),
              "-c:a", "aac", "-ar", str(RATE), "-ac", "2", "-t", seconds]
    if shot:
        voiced = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "a", "-show_entries", "stream=index",
                                 "-of", "csv=p=0", str(shot)], capture_output=True, text=True).stdout.strip()
        sound = "[0:a]volume=0.7[a0];[a0][2]amix=inputs=2:duration=longest:normalize=0[aout]" if voiced else "[2]anull[aout]"
        # A take shorter than its beat holds its last frame rather than leaving the cut short.
        ffmpeg("-ss", str(cuts.get(beat["side"], 0)), "-t", seconds, "-i", shot, "-loop", "1", "-t", seconds, "-i", overlay,
               "-f", "lavfi", "-t", seconds, "-i", f"anullsrc=r={RATE}:cl=stereo",
               "-filter_complex",
               "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1,"
               f"tpad=stop_mode=clone:stop_duration={seconds}[v];[v][1]overlay[out];{sound}",
               "-map", "[out]", "-map", "[aout]", *encode, out)
    elif "sequence" in beat:
        ffmpeg("-framerate", str(FPS), "-start_number", "0", "-i", frames / beat["sequence"], "-loop", "1", "-t", seconds,
               "-i", overlay, "-f", "lavfi", "-t", seconds, "-i", f"anullsrc=r={RATE}:cl=stereo",
               "-filter_complex", "[0][1]overlay,setsar=1[out]", "-map", "[out]", "-map", "2:a", *encode, out)
    else:
        ffmpeg("-loop", "1", "-t", seconds, "-i", frames / beat["frame"], "-loop", "1", "-t", seconds, "-i", overlay,
               "-f", "lavfi", "-t", seconds, "-i", f"anullsrc=r={RATE}:cl=stereo",
               "-filter_complex", "[0][1]overlay,setsar=1[out]", "-map", "[out]", "-map", "2:a", *encode, out)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    name = sys.argv[1]
    promo = ROOT / "promo" / name
    footage = promo / "footage"
    cuts = json.loads((footage / "cuts.json").read_text()) if (footage / "cuts.json").exists() else {}
    run(ROOT / "scripts/build-app.sh")
    if "--stage" in sys.argv:
        run(APP, "--stage", promo, "-AppleLanguages", "(zh-Hant)")
    with tempfile.TemporaryDirectory() as folder:
        work = Path(folder)
        frames = work / "frames"
        run(APP, "--render-reel", promo, frames, "-AppleLanguages", "(zh-Hant)")
        beats = json.loads((frames / "beats.json").read_text())

        parts = []
        for index, beat in enumerate(beats):
            part = work / f"part-{index:02d}.mp4"
            segment(beat, frames, footage, cuts, part)
            parts.append(part)
        (work / "parts.txt").write_text("".join(f"file '{part}'\n" for part in parts))
        joined = work / "joined.mp4"
        ffmpeg("-f", "concat", "-safe", "0", "-i", work / "parts.txt", "-c", "copy", joined)

        # Each beat's sound, placed where the beat starts.
        sounds = {"inserted": frames / "sound-inserted.wav", "ready": frames / "sound-ready.wav"}
        for kind, samples in (("pop", pop()), ("sent", sent()), ("sigh", sigh()), ("press", press())):
            sounds[kind] = work / f"{kind}.wav"
            write_wav(sounds[kind], samples)
        length = sum(beat["seconds"] for beat in beats)
        write_wav(work / "music.wav", music(length))
        inputs, chain, labels, start = ["-i", joined, "-i", work / "music.wav"], "", ["[0:a]", "[1:a]"], 0.0
        for index, beat in enumerate(beats):
            kind = beat.get("sound")
            if kind == "type":
                path = work / f"type-{index}.wav"
                write_wav(path, typing(beat["seconds"]))
            else:
                path = sounds.get(kind)
            if path:
                inputs += ["-i", path]
                n = len(labels)
                gain = 1.6 if kind in ("inserted", "ready") else 1.0
                chain += f"[{n}:a]volume={gain},adelay={int((start + beat.get('soundAt', 0)) * 1000)}:all=1[s{n}];"
                labels.append(f"[s{n}]")
            start += beat["seconds"]
        chain += f"{''.join(labels)}amix=inputs={len(labels)}:duration=first:normalize=0,alimiter=limit=0.9[a]"
        out = promo / "out" / f"{name}.mp4"
        out.parent.mkdir(exist_ok=True)
        # The first beat, caption and all, is the cover.
        ffmpeg("-i", frames / beats[0]["frame"], "-i", frames / beats[0]["overlay"], "-filter_complex", "overlay",
               "-q:v", "2", out.with_name("cover.jpg"))
        ffmpeg(*inputs, "-filter_complex", chain, "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac",
               "-b:a", "192k", "-movflags", "+faststart", out)
        drawn = sorted({b["side"] for b in beats if "side" in b} - {p.stem for p in footage.glob("*.*")})
        print(f"{out.relative_to(ROOT)} · {start:.1f} s" + (f" · drawn, not filmed: {', '.join(drawn)}" if drawn else ""))


if __name__ == "__main__":
    main()
