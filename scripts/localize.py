#!/usr/bin/env python3
"""Generate Resources/<lang>.lproj/Localizable.strings from the L("…") keys in the app's sources.

    scripts/localize.py            write the tables; fail if an English translation is missing
    scripts/localize.py --keys     print every key (to translate new ones)

Keys are the Traditional Chinese originals. zh-Hant maps each to itself, zh-Hans is OpenCC's tw2sp
(Taiwan to mainland wording), English comes from Resources/i18n/en.json. Jev's option names (intents,
strategies) in ReplyQuestions.swift are keys too, since the panel shows them.
"""
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LITERAL = r'"((?:[^"\\]|\\.)*)"'


def keys() -> list[str]:
    found = []
    for path in sorted((ROOT / "Sources/Wingman").glob("*.swift")):
        found += re.findall(r'\bL\(' + LITERAL, path.read_text())
    questions = (ROOT / "Sources/WingmanCore/ReplyQuestions.swift").read_text()
    for block in ("intents", "strategies"):
        body = questions.split(f"static let {block}")[1].split("= [", 1)[1].split("\n    ]")[0]
        found += re.findall(r'\(' + LITERAL + r',', body)
    unique = []
    for key in (k.encode().decode("unicode_escape").encode("latin-1").decode("utf-8") for k in found):
        if key not in unique:
            unique.append(key)
    return unique


def strings_file(table: dict[str, str]) -> str:
    escape = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return "".join(f'"{escape(k)}" = "{escape(v)}";\n' for k, v in table.items())


def main() -> None:
    all_keys = keys()
    if "--keys" in sys.argv:
        print(json.dumps(all_keys, ensure_ascii=False, indent=1))
        return
    english = json.loads((ROOT / "Resources/i18n/en.json").read_text())
    missing = [k for k in all_keys if k not in english]
    if missing:
        sys.exit("missing English for:\n  " + "\n  ".join(missing))
    simplified = subprocess.run(["opencc", "-c", "tw2sp"], input="\n".join(all_keys), capture_output=True,
                                text=True, check=True).stdout.split("\n")
    tables = {
        "zh-Hant": {k: k for k in all_keys},
        "zh-Hans": dict(zip(all_keys, simplified)),
        "en": {k: english[k] for k in all_keys},
    }
    for language, table in tables.items():
        folder = ROOT / "Resources" / f"{language}.lproj"
        folder.mkdir(exist_ok=True)
        (folder / "Localizable.strings").write_text(strings_file(table))
    print(f"{len(all_keys)} keys → en, zh-Hant, zh-Hans")


if __name__ == "__main__":
    main()
