#!/usr/bin/env python3
"""Draw the README's demo with the app itself and string the frames into docs/demo-<language>.gif.

    scripts/make-demo.py        build, render the English and Traditional Chinese frames, write both GIFs

Needs ffmpeg (brew install ffmpeg). The chat in it is made up; nothing is read from screen.
"""
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "build/Wingman.app/Contents/MacOS/Wingman"
FADE = 0.25      # seconds each frame takes to dissolve into the next
WIDTH = 900      # pixels; the frames are drawn at twice that
FPS = 15


def gif(frames: Path, out: Path) -> None:
    beats = [line.split() for line in (frames / "frames.txt").read_text().splitlines() if line.strip()]
    inputs, chain, offset = [], "", 0.0
    for name, seconds in beats:
        inputs += ["-loop", "1", "-t", str(float(seconds) + FADE), "-i", str(frames / name)]
    previous = "[0]"
    for index, (_, seconds) in enumerate(beats[:-1], start=1):
        offset += float(seconds)
        chain += f"{previous}[{index}]xfade=transition=fade:duration={FADE}:offset={offset:.2f}[v{index}];"
        previous = f"[v{index}]"
    chain += (f"{previous}fps={FPS},scale={WIDTH}:-1:flags=lanczos,split[a][b];"
              "[a]palettegen=max_colors=192:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", *inputs, "-filter_complex", chain, "-loop", "0", str(out)],
                   check=True)
    print(f"{out.relative_to(ROOT)} {out.stat().st_size // 1024} KB")


def main() -> None:
    subprocess.run([ROOT / "scripts/build-app.sh"], check=True, stdout=subprocess.DEVNULL)
    for language in ("en", "zh-Hant"):
        with tempfile.TemporaryDirectory() as folder:
            subprocess.run([APP, "--render-demo", folder, "-AppleLanguages", f"({language})"], check=True,
                           stdout=subprocess.DEVNULL)
            gif(Path(folder), ROOT / f"docs/demo-{language}.gif")


if __name__ == "__main__":
    sys.exit(main())
