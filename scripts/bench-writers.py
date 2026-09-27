#!/usr/bin/env python3
"""Compare reply-writing models on the same synthetic Slack threads.

    scripts/bench-writers.py [model ...]

Uses OPENROUTER_API_KEY, or the key Wingman stored in the Keychain (macOS asks once).
Prints a summary table and writes every draft to build/bench-writers.md.
"Non-Taiwan" counts the spots OpenCC's s2twp rewrites: simplified glyphs and mainland
wording (視頻→影片, 數據→資料). It over-reaches on a few words (權限→許可權), so read the drafts.
"""
from __future__ import annotations

import difflib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MODELS = [
    "anthropic/claude-haiku-4.5",
    "google/gemini-3.1-flash-lite",
    "google/gemini-3.5-flash-lite",
    "openai/gpt-5.4-nano",
    "deepseek/deepseek-v4-flash",
    "z-ai/glm-5.3-flash",
    "qwen/qwen3.8-flash",
    "minimax/minimax-m3",
]

# Mirrors Brain.writerRules.
RULES = """你替使用者（「我」）起草要在 Slack 回給同事的訊息。
- 每則回覆就是我會直接送出的原文：不加引號、不加說明、不署名。
- 用對方使用的語言回覆；中文一律用臺灣繁體中文與臺灣用語。
- 語氣像真人同事：自然、簡潔、有禮，不要客服腔，不要過度客套或堆砌表情符號。
- 一則只寫一段，不換行，通常一到兩句。
- 不要編造對話裡沒有的事實、數字、日期或承諾；需要但不知道時，留下像 [時間] 這樣的空格讓我自己填。
- 只輸出 JSON 陣列，不要其他文字：[{"strategy": "<回法>", "text": "<回覆>"}]"""

SCENARIOS = {
    "催發版": (["Mia：Android 那個跳頁的 bug 修好了嗎？客戶今天又來問了", "Leo（我）：修好了，在跑測試",
              "Mia：那今天下班前可以發版嗎？我要回覆客戶時間"],
             ["給進度和時間：說明目前狀態並給出預估時間", "答應但附條件：可以，但說明前提、風險或需要的東西",
              "直接答應：同意並給出明確承諾"]),
    "客訴": (["Kevin：上次那份月報的營收數字又錯了，客戶很不爽", "Kevin：到底是誰負責的？這已經第二次了"],
            ["先問清楚：資訊不足，先反問釐清", "給進度和時間：說明目前狀態並給出預估時間",
             "婉拒或延後：做不到或現在不行，有禮貌地拒絕或改期"]),
    "請幫忙": (["Amy：可以幫我看一下 #482 這個 PR 嗎？我明天早上要 demo 給客戶看", "Amy：主要是登入那段我不太確定"],
             ["直接答應：同意並給出明確承諾", "答應但附條件：可以，但說明前提、風險或需要的東西",
              "婉拒或延後：做不到或現在不行，有禮貌地拒絕或改期"]),
    "英文道謝": (["Mark: Thanks for the quick fix on the export bug! The client is happy now 🙌"],
              ["表達感謝：道謝或肯定對方", "簡短回應：一兩個字表示收到或認同即可", "給進度和時間：說明目前狀態並給出預估時間"]),
}


def api_key() -> str:
    if key := os.environ.get("OPENROUTER_API_KEY"):
        return key
    out = subprocess.run(["security", "find-generic-password", "-s", "com.moniit.wingman", "-a", "openrouter", "-w"],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        sys.exit("No OpenRouter key: set OPENROUTER_API_KEY or save it in Wingman's settings.")
    return out.stdout.strip()


def prompt(lines: list[str], strategies: list[str]) -> str:
    asks = "\n".join(f"- {s}" for s in strategies)
    return (f"Slack 頻道 #開發\n我的名字：Leo\n最近的對話（由舊到新）：\n" + "\n".join(lines)
            + f"\n\n請依照下面每一種回法各寫一則回覆，順序不變：\n{asks}")


def call(key: str, model: str, user: str) -> dict:
    body = {"model": model, "temperature": 0.7, "max_tokens": 700, "usage": {"include": True},
            "reasoning": {"enabled": False},
            "provider": {"order": ["Fireworks", "Together", "BaseTen", "DeepInfra"],
                         "ignore": ["DeepSeek", "StreamLake", "Alibaba", "SiliconFlow", "Baidu"]},  # as Brain.swift
            "messages": [{"role": "system", "content": RULES}, {"role": "user", "content": user}]}
    request = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions", data=json.dumps(body).encode(),
                                     headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json",
                                              "X-Title": "Wingman bench"})
    started = time.time()
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            data = json.load(response)
    except urllib.error.HTTPError as error:
        return {"error": f"HTTP {error.code} {error.read()[:160].decode(errors='replace')}", "seconds": time.time() - started}
    data["seconds"] = time.time() - started
    return data


def drafts(content: str) -> list[str] | None:
    for pattern in (r"\[.*\]", r"\{.*\}"):
        match = re.search(pattern, content, re.S)
        if not match:
            continue
        try:
            value = json.loads(match.group(0))
        except json.JSONDecodeError:
            continue
        items = value if isinstance(value, list) else value.get("candidates", [])
        texts = [i.get("text", "").strip() for i in items if isinstance(i, dict) and i.get("text", "").strip()]
        if texts:
            return texts
    return None


def non_taiwan(text: str) -> int:
    """Number of spots OpenCC rewrites; counted as edits so one changed word counts once."""
    converted = subprocess.run(["opencc", "-c", "s2twp"], input=text, capture_output=True, text=True).stdout
    return sum(op != "equal" for op, *_ in difflib.SequenceMatcher(None, text, converted).get_opcodes())


def main() -> None:
    key = api_key()
    models = sys.argv[1:] or MODELS
    report = ["# Writer bench\n"]
    print(f"{'model':32s} {'ok':>5s} {'avg s':>6s} {'max s':>6s} {'$/call':>9s} {'non-TW':>6s}")
    for model in models:
        seconds, costs, oks, off = [], [], 0, 0
        report.append(f"\n## {model}\n")
        for name, (lines, strategies) in SCENARIOS.items():
            result = call(key, model, prompt(lines, strategies))
            seconds.append(result["seconds"])
            if "error" in result:
                report.append(f"- **{name}**: {result['error']}\n")
                continue
            costs.append((result.get("usage") or {}).get("cost") or 0)
            content = result["choices"][0]["message"].get("content") or ""
            texts = drafts(content)
            if texts:
                oks += 1
                off += sum(non_taiwan(t) for t in texts if name != "英文道謝")
            report.append(f"- **{name}** ({result['seconds']:.1f}s)\n" +
                          ("".join(f"  - {t}\n" for t in texts) if texts else f"  - (unparsed) {content[:200]!r}\n"))
        avg_cost = sum(costs) / len(costs) if costs else 0
        print(f"{model:32s} {oks:>2d}/{len(SCENARIOS):<2d} {sum(seconds) / len(seconds):6.1f} {max(seconds):6.1f} "
              f"{avg_cost:9.5f} {off:6d}")
    out = ROOT / "build" / "bench-writers.md"
    out.parent.mkdir(exist_ok=True)
    out.write_text("".join(report))
    print(f"\ndrafts: {out}")


if __name__ == "__main__":
    main()
