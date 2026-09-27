#!/usr/bin/env python3
"""Generate Resources/<lang>.lproj/Localizable.strings from the L("…") keys in the app's sources.

    scripts/localize.py            write the tables; fail if an English translation is missing
    scripts/localize.py --keys     print every key (to translate new ones)

Keys are the Traditional Chinese originals. zh-Hant maps each to itself, zh-Hans is OpenCC's tw2sp
(Taiwan to mainland wording), every other language comes from Resources/i18n/<language>.json. Jev's
option names (intents, strategies) in ReplyQuestions.swift are keys too, since the panel shows them.
A translation must keep the key's %@ and %% placeholders.
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


# OpenCC converts wording, not Apple's own names for macOS settings in mainland China.
APPLE_ZH_HANS = {"辅助使用": "辅助功能", "屏幕与系统录音": "录屏与系统录音", "钥匙圈": "钥匙串", "菜单列": "菜单栏",
                 "「": "“", "」": "”", "『": "‘", "』": "’"}


def apple_mainland_terms(text: str) -> str:
    for taiwan, mainland in APPLE_ZH_HANS.items():
        text = text.replace(taiwan, mainland)
    return text


def strings_file(table: dict[str, str]) -> str:
    escape = lambda s: s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return "".join(f'"{escape(k)}" = "{escape(v)}";\n' for k, v in table.items())


def main() -> None:
    all_keys = keys()
    if "--keys" in sys.argv:
        print(json.dumps(all_keys, ensure_ascii=False, indent=1))
        return
    translated = {path.stem: json.loads(path.read_text()) for path in sorted((ROOT / "Resources/i18n").glob("*.json"))}
    problems = []
    for language, table in translated.items():
        problems += [f"{language}: missing {k!r}" for k in all_keys if k not in table]
        problems += [f"{language}: placeholders differ in {k!r}" for k in all_keys
                     if k in table and (k.count("%@"), k.count("%%")) != (table[k].count("%@"), table[k].count("%%"))]
    if problems:
        sys.exit("\n".join(problems))
    simplified = subprocess.run(["opencc", "-c", "tw2sp"], input="\n".join(all_keys), capture_output=True,
                                text=True, check=True).stdout.split("\n")
    simplified = [apple_mainland_terms(line) for line in simplified]
    tables = {
        "zh-Hant": {k: k for k in all_keys},
        "zh-Hans": dict(zip(all_keys, simplified)),
        **{language: {k: table[k] for k in all_keys} for language, table in translated.items()},
    }
    for language, table in tables.items():
        folder = ROOT / "Resources" / f"{language}.lproj"
        folder.mkdir(exist_ok=True)
        (folder / "Localizable.strings").write_text(strings_file(table))
    print(f"{len(all_keys)} keys → " + ", ".join(tables))


if __name__ == "__main__":
    main()
