#!/usr/bin/env python3
"""Cut a promo Reel (1080×1920) from promo/<name>/: the app draws the screens, this strings them together.

    scripts/make-reel.py reel-01            build, draw, cut promo/reel-01/out/reel-01.mp4
    scripts/make-reel.py reel-01 --stage    run the made-up chats through Jev and the writer first

Shots to be filmed (side A, B, …) come from promo/<name>/footage/<A>.mov or .mp4 when there, cropped to
9:16 and started at the second given in footage/cuts.json ({"A": 1.5}); until then a card says what to
film. Their own sound (keys, a sigh) stays in, under the sound effects. Music is left to Instagram.
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
        sounds = {"pop": work / "pop.wav", "sent": work / "sent.wav", "inserted": frames / "sound-inserted.wav",
                  "ready": frames / "sound-ready.wav"}
        write_wav(sounds["pop"], pop())
        write_wav(sounds["sent"], sent())
        inputs, chain, labels, start = ["-i", joined], "", ["[0:a]"], 0.0
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
                chain += f"[{n}:a]volume={gain},adelay={int(start * 1000)}:all=1[s{n}];"
                labels.append(f"[s{n}]")
            start += beat["seconds"]
        chain += f"{''.join(labels)}amix=inputs={len(labels)}:duration=first:normalize=0,alimiter=limit=0.9[a]"
        out = promo / "out" / f"{name}.mp4"
        out.parent.mkdir(exist_ok=True)
        ffmpeg(*inputs, "-filter_complex", chain, "-map", "0:v", "-map", "[a]", "-c:v", "copy", "-c:a", "aac",
               "-b:a", "192k", "-movflags", "+faststart", out)
        filmed = sorted({b["side"] for b in beats if "side" in b} - {p.stem for p in footage.glob("*.*")})
        print(f"{out.relative_to(ROOT)} · {start:.1f} s" + (f" · still to film: {', '.join(filmed)}" if filmed else ""))


if __name__ == "__main__":
    main()
