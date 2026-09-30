#!/usr/bin/env python3
"""Draw the READMEs' two diagrams in Wingman's own look and render them to PNG with Chrome.

    scripts/make-diagrams.py      writes docs/flow-{en,zh-Hant}.png and docs/architecture-{en,zh-Hant}.png

Every word and position lives here, so a change is an edit to this file and a rerun. The look follows the
demo GIF and the app icon: a dark ground, the panel's cards, Jev in indigo and the writing model in cyan,
the icon's indigo-to-cyan gradient on the one card that talks to both. Needs Google Chrome.
"""
from __future__ import annotations

import base64
import html
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")
ICON = base64.b64encode((ROOT / "Resources/AppIcon-1024.png").read_bytes()).decode()

STYLE = """
* { box-sizing: border-box; margin: 0; }
body { background: #0E0F13; color: #F4F4F5; -webkit-font-smoothing: antialiased;
       font-family: -apple-system, "SF Pro Text", "PingFang TC", "Helvetica Neue", sans-serif; }
.canvas { position: relative; overflow: hidden;
          background: radial-gradient(900px 500px at 0% 0%, rgba(91,79,224,.20), transparent 60%),
                      radial-gradient(800px 500px at 100% 100%, rgba(38,201,206,.12), transparent 60%), #0E0F13; }
.head { position: absolute; left: 48px; top: 36px; display: flex; gap: 16px; align-items: center; }
.head img { width: 48px; height: 48px; }
.head b { display: block; font-size: 26px; letter-spacing: -.01em; }
.head span { display: block; font-size: 15px; color: #A1A1AA; margin-top: 2px; }
.card { position: absolute; border-radius: 14px; background: #17181E; border: 1px solid rgba(255,255,255,.10);
        box-shadow: 0 12px 30px -18px rgba(0,0,0,.8); padding: 14px 16px; }
.card h3 { font-size: 16px; font-weight: 650; letter-spacing: -.005em; }
.card code { display: block; font: 12px/1.5 "SF Mono", Menlo, monospace; color: #8FA3C8; margin-top: 3px; }
.card p { font-size: 13px; line-height: 1.5; color: #A1A1AA; margin-top: 4px; }
.card.core { border: 1.5px solid transparent;
             background: linear-gradient(#17181E, #17181E) padding-box, linear-gradient(120deg, #6A5CF0, #26C9CE) border-box; }
.card.jev { border-color: rgba(139,124,255,.75); background: #1A1830; }
.card.jev h3 { color: #B3A9FF; }
.card.llm { border-color: rgba(63,208,216,.7); background: #122428; }
.card.llm h3 { color: #6FE0E6; }
.label { position: absolute; font-size: 12.5px; color: #8B8B96; white-space: nowrap; }
.caps { position: absolute; font-size: 12px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: #71717A; }
.frame { position: absolute; border: 1.5px dashed rgba(255,255,255,.18); border-radius: 22px; }
.tag { position: absolute; background: #0E0F13; padding: 2px 12px; border-radius: 999px; font-size: 14px; font-weight: 600;
       border: 1px solid rgba(255,255,255,.16); }
.tag i { font-style: normal; font-weight: 400; color: #A1A1AA; margin-left: 6px; }
.lane { position: absolute; border-radius: 16px; background: rgba(255,255,255,.028); border: 1px solid rgba(255,255,255,.05); }
.lane-name { position: absolute; font-size: 14px; font-weight: 600; display: flex; align-items: center; gap: 8px; }
.dot { width: 9px; height: 9px; border-radius: 50%; display: inline-block; }
.step .n { display: inline-grid; place-items: center; width: 22px; height: 22px; border-radius: 50%; font-size: 12px;
           font-weight: 700; background: #F4F4F5; color: #0E0F13; margin-right: 8px; vertical-align: 1px; }
.step.jev .n { background: #8B7CFF; color: #0E0F13; }
.step.llm .n { background: #3FD0D8; color: #0E0F13; }
.chip { display: inline-block; margin-top: 8px; font-size: 12px; padding: 2px 9px; border-radius: 999px;
        background: rgba(255,255,255,.07); color: #D4D4D8; }
.stop { margin-top: 8px; font-size: 12px; line-height: 1.45; color: #D4D4D8; border: 1px dashed rgba(255,255,255,.25);
        border-radius: 8px; padding: 5px 8px; }
.foot { position: absolute; font-size: 14px; color: #A1A1AA; }
.foot b { color: #F4F4F5; font-weight: 600; }
svg { position: absolute; left: 0; top: 0; }
"""

COLORS = {"ink": "rgba(255,255,255,.42)", "jev": "#8B7CFF", "llm": "#3FD0D8"}


class Page:
    def __init__(self, width: int, height: int):
        self.width, self.height = width, height
        self.parts: list[str] = []
        self.lines: list[str] = []

    def add(self, markup: str, x: float, y: float, w: float | None = None, h: float | None = None, cls: str = "card"):
        size = (f"width:{w}px;" if w else "") + (f"min-height:{h}px;" if h else "")
        self.parts.append(f'<div class="{cls}" style="left:{x}px;top:{y}px;{size}">{markup}</div>')

    def arrow(self, points: list[tuple[float, float]], color: str = "ink", dashed: bool = False):
        path = " ".join(f"{x},{y}" for x, y in points)
        dash = ' stroke-dasharray="6 5"' if dashed else ""
        self.lines.append(f'<polyline points="{path}" fill="none" stroke="{COLORS[color]}" stroke-width="1.8"'
                          f' stroke-linejoin="round"{dash} marker-end="url(#{color})"/>')

    def line(self, points: list[tuple[float, float]]):
        path = " ".join(f"{x},{y}" for x, y in points)
        self.lines.append(f'<polyline points="{path}" fill="none" stroke="{COLORS["ink"]}" stroke-width="1.8"'
                          f' stroke-linejoin="round"/>')

    def badge(self, x: float, y: float, text: str, color: str):
        width = 14 + 14 * len(text)
        self.lines.append(f'<rect x="{x - width / 2}" y="{y - 12}" width="{width}" height="24" rx="12" fill="#0E0F13" '
                          f'stroke="{COLORS[color]}" stroke-width="1.5"/>'
                          f'<text x="{x}" y="{y + 4.5}" text-anchor="middle" font-size="13" font-weight="700" '
                          f'fill="{COLORS[color]}">{html.escape(text)}</text>')

    def header(self, title: str, subtitle: str):
        self.parts.append(f'<div class="head"><img src="data:image/png;base64,{ICON}" alt=""><div>'
                          f'<b>{html.escape(title)}</b><span>{html.escape(subtitle)}</span></div></div>')

    def render(self) -> str:
        markers = "".join(
            f'<marker id="{name}" viewBox="0 0 10 10" refX="8.5" refY="5" markerWidth="7" markerHeight="7" '
            f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{color}"/></marker>'
            for name, color in COLORS.items())
        svg = (f'<svg width="{self.width}" height="{self.height}" viewBox="0 0 {self.width} {self.height}">'
               f'<defs>{markers}</defs>{"".join(self.lines)}</svg>')
        return (f'<!doctype html><html><head><meta charset="utf-8"><style>{STYLE}</style></head><body>'
                f'<div class="canvas" style="width:{self.width}px;height:{self.height}px">'
                f'{"".join(self.parts)}{svg}</div></body></html>')


def card(title: str, code: str = "", *lines: str) -> str:
    markup = f"<h3>{html.escape(title)}</h3>"
    if code:
        markup += f"<code>{html.escape(code)}</code>"
    return markup + "".join(f"<p>{html.escape(line)}</p>" for line in lines)


# ---------------------------------------------------------------- the flow of one suggestion

FLOW = {
    "en": dict(
        title="Wingman", subtitle="One suggestion, from a message arriving to you pressing Enter",
        lanes=("Your Mac", "Jev · TypeSafe", "LLM · OpenRouter"),
        steps=[
            ("Read the chat", "A new message, then 1 s of quiet. Only the last 20 messages go on.", "on your Mac"),
            ("Ask 6 questions", "Intent, needs a reply, how soon, which way to reply, the mood, any subtext: each with probabilities.", "about 0.3 s"),
            ("Code decides", "Take the 3 most likely ways to reply.", "on your Mac"),
            ("Write 3 drafts", "One per way, each shown as soon as it is written.", "2–4 s, streamed"),
            ("Pick the best", "The 3 drafts are the options of one question. The top one gets ★.", "about 0.3 s"),
            ("Type it in", "Enter types the ★ draft. The Enter that sends is yours.", "on your Mac"),
        ],
        stop="Automatic, and needs a reply below 0.5: stop here, no drafts written.",
        foot="<b>2 Jev calls + 1 LLM call</b> per suggestion · about US$0.0002 · Wingman never sends anything itself",
    ),
    "zh-Hant": dict(
        title="Wingman", subtitle="一次建議怎麼跑：從訊息進來到你按下 Enter",
        lanes=("你的 Mac", "Jev · TypeSafe", "LLM · OpenRouter"),
        steps=[
            ("讀聊天", "新訊息進來、停住 1 秒後開始，只送最近 20 則。", "在你的 Mac"),
            ("一次問 6 題", "意圖、要不要回、多急、用哪種回法、氣氛、話中有話，各附機率。", "約 0.3 秒"),
            ("程式決定", "取機率最高的 3 種回法。", "在你的 Mac"),
            ("各寫一句", "照 3 種回法各寫一句，寫好一句先顯示一句。", "2–4 秒，串流"),
            ("挑最好的", "3 句草稿當成同一題的選項，機率最高的標 ★。", "約 0.3 秒"),
            ("填入，不送出", "Enter 填入 ★ 那句，送出的 Enter 由你按。", "在你的 Mac"),
        ],
        stop="自動分析，且「要不要回」低於 0.5：停在這裡，不寫草稿。",
        foot="一次建議 <b>2 次 Jev + 1 次 LLM</b> · 約 US$0.0002 · Wingman 從不自動送出",
    ),
}


def flow(language: str) -> str:
    w = FLOW[language]
    page = Page(1440, 870)
    page.header(w["title"], w["subtitle"])
    lanes = [(128, 268), (410, 184), (608, 184)]            # top, height of each lane
    colors = ["#F4F4F5", "#8B7CFF", "#3FD0D8"]
    for (top, height), name, color in zip(lanes, w["lanes"], colors):
        page.add("", 40, top, 1360, height, "lane")
        page.add(f'<span class="dot" style="background:{color}"></span>{html.escape(name)}', 60, top + 16, cls="lane-name")
    # Which lane each step runs in, and its card.
    rows = [0, 1, 0, 2, 1, 0]
    kinds = ["", "jev", "", "llm", "jev", ""]
    left, width, pitch = 64, 192, 222
    boxes = []
    for i, ((title, detail, when), row, kind) in enumerate(zip(w["steps"], rows, kinds)):
        top = lanes[row][0] + 52
        height = None                                      # as tall as its words
        x = left + i * pitch
        extra = f'<div class="stop">{html.escape(w["stop"])}</div>' if i == 2 else ""
        page.add(f'<h3><span class="n">{i + 1}</span>{html.escape(title)}</h3><p>{html.escape(detail)}</p>'
                 f'<span class="chip">{html.escape(when)}</span>{extra}',
                 x, top, width, height, f"card step {kind}".strip())
        boxes.append((x, top, width, height))
    for i in range(5):
        (x1, y1, w1, h1), (x2, y2, w2, h2) = boxes[i], boxes[i + 1]
        a, b = (x1 + w1, y1 + 40), (x2, y2 + 40)
        mid = (a[0] + b[0]) / 2
        page.arrow([a, (mid, a[1]), (mid, b[1]), b], ["ink", "jev", "ink", "llm", "jev", "ink"][i + 1])
    page.add(w["foot"], 64, 818, cls="foot")
    return page.render()


# ---------------------------------------------------------------- the parts and the Mac's edge

ARCH = {
    "en": dict(
        title="Wingman", subtitle="System design: reading, deciding and typing stay on your Mac. Two kinds of request leave it.",
        mac="Your Mac", mac_note="chats not stored unless you choose · keys stay in the Keychain", apps="Chat apps", wingman="Wingman.app", outside="Outside your Mac",
        slack=("Slack · Discord", "accessibility tree"),
        web=("Messenger · Instagram · Threads", "exact host · posts: only your reply box"),
        pixels=("LINE · Telegram", "on-device OCR, captures never leave"),
        readers=("Readers", "ChatApp · AXSnapshot · *Parser · PixelReader", "one way of reading per app"),
        model=("Decisions", "AppModel.swift", "new message? 1 s of quiet? needs a reply?"),
        brain=("Model requests", "Brain.swift", "Jev: 6 questions, then ranking", "Writer: brief, streamed drafts"),
        panel=("Panel", "Panels.swift", "✦ pill · 3 drafts · ★"),
        inserter=("Typing", "Inserter.swift", "checks the chat and the focus, never presses Enter"),
        jev=("Jev · TypeSafe", "", "① 6 questions → ② answers + probabilities", "⑤ the 3 drafts → ⑥ a score each",
             "about 0.3 s · direct, or via OpenRouter"),
        llm=("LLM · OpenRouter", "", "③ top 3 ways + messages → ④ drafts, streamed", "zero-data-retention providers only"),
        read="read", last20="last 20 messages", expected="a reply is expected", drafts="drafts, ★", pick="Enter or 1–3",
        types="types it in",
        leaves="<b>Only this leaves your Mac:</b><br>the last 20 messages, the chat's name and the senders' names.",
    ),
    "zh-Hant": dict(
        title="Wingman", subtitle="系統架構：讀、判斷、填入都在你的 Mac 上，只有兩種請求會離開",
        mac="你的 Mac", mac_note="聊天內容預設不存檔 · key 只在鑰匙圈", apps="聊天 App", wingman="Wingman.app", outside="Mac 之外",
        slack=("Slack · Discord", "輔助使用樹"),
        web=("Messenger · Instagram · Threads", "確切網址 · 貼文只讀游標所在的留言框"),
        pixels=("LINE · Telegram", "本機 OCR，截圖不上傳"),
        readers=("讀取器", "ChatApp · AXSnapshot · *Parser · PixelReader", "每個 App 一種讀法"),
        model=("判斷流程", "AppModel.swift", "有新訊息？停住 1 秒？要不要回？"),
        brain=("模型請求", "Brain.swift", "Jev：6 個問題，之後評分", "寫字：指示、草稿串流"),
        panel=("建議面板", "Panels.swift", "✦ 提示 · 3 句建議 · ★"),
        inserter=("填入器", "Inserter.swift", "確認聊天室和游標，只打字、不按 Enter"),
        jev=("Jev · TypeSafe", "", "① 6 個問題 → ② 答案 + 機率", "⑤ 3 句草稿 → ⑥ 每句分數", "約 0.3 秒 · 直連或經 OpenRouter"),
        llm=("LLM · OpenRouter", "", "③ 前 3 種回法 + 對話 → ④ 草稿串流", "只走零資料保留的供應商"),
        read="讀", last20="最近 20 則", expected="需要回", drafts="草稿、★", pick="Enter 或 1–3",
        types="填進輸入框",
        leaves="<b>離開 Mac 的只有：</b><br>最近 20 則訊息、聊天室名和發言人名字。",
    ),
}


def architecture(language: str) -> str:
    w = ARCH[language]
    page = Page(1440, 960)
    page.header(w["title"], w["subtitle"])
    page.add("", 40, 136, 860, 790, "frame")
    page.add(f'{html.escape(w["mac"])}<i>{html.escape(w["mac_note"])}</i>', 64, 124, cls="tag")
    page.add(html.escape(w["apps"]), 72, 176, cls="caps")
    page.add(html.escape(w["wingman"]), 448, 176, cls="caps")
    page.add(html.escape(w["outside"]), 1000, 176, cls="caps")

    # Chat apps.
    ax, aw = 72, 300
    for top, key in ((204, "slack"), (304, "web"), (404, "pixels")):
        page.add(card(w[key][0], "", w[key][1]), ax, top, aw, 78)
    # Wingman, top to bottom.
    wx, ww = 448, 400
    rows = {"readers": (204, 100), "model": (340, 96), "brain": (472, 180), "panel": (688, 88), "inserter": (812, 92)}
    for key, (top, height) in rows.items():
        page.add(card(*w[key]), wx, top, ww, height, "card core" if key == "brain" else "card")
    # Outside.
    ox, ow = 1000, 360
    page.add(card(*w["jev"]), ox, 440, ow, 138, "card jev")
    page.add(card(*w["llm"]), ox, 594, ow, 118, "card llm")
    page.add(w["leaves"], ox, 736, ow, cls="foot")

    # Reading: three apps onto one bus into the readers.
    bus = 410
    page.arrow([(ax + aw, 243), (wx, 243)])
    page.line([(ax + aw, 343), (bus, 343), (bus, 243)])
    page.line([(ax + aw, 443), (bus, 443), (bus, 343)])
    page.add(html.escape(w["read"]), bus + 8, 380, cls="label")
    # Down the Wingman column.
    mid = wx + ww / 2
    for (y1, y2), text in (((304, 340), w["last20"]), ((436, 472), w["expected"]),
                           ((652, 688), w["drafts"]), ((776, 812), w["pick"])):
        page.arrow([(mid, y1), (mid, y2)])
        page.add(html.escape(text), mid + 12, (y1 + y2) / 2 - 9, cls="label")
    page.arrow([(wx, 858), (ax + aw / 2, 858), (ax + aw / 2, 482)])
    page.add(html.escape(w["types"]), ax + aw / 2 + 12, 836, cls="label")

    # Across the Mac's edge: requests solid, answers dashed, numbered as in the flow.
    right = wx + ww
    for y, color, dashed, number in ((494, "jev", False, "①⑤"), (530, "jev", True, "②⑥"),
                                    (614, "llm", False, "③"), (650, "llm", True, "④")):
        start, end = ((right, y), (ox, y)) if not dashed else ((ox, y), (right, y))
        page.arrow([start, end], color, dashed)
        page.badge((right + ox) / 2, y, number, color)
    return page.render()


def render(markup: str, out: Path, width: int, height: int) -> None:
    with tempfile.TemporaryDirectory() as folder:
        source = Path(folder) / "page.html"
        source.write_text(markup)
        command = [CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={folder}/profile",
                   "--force-device-scale-factor=2", f"--window-size={width},{height}", f"--screenshot={out}",
                   source.as_uri()]
        out.unlink(missing_ok=True)
        process = subprocess.Popen(command, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        # Headless Chrome writes the screenshot and then lingers; stop it once the file has settled.
        size, deadline = -1, time.time() + 45
        while time.time() < deadline and process.poll() is None:
            time.sleep(0.5)
            current = out.stat().st_size if out.exists() else -1
            if current > 0 and current == size:
                break
            size = current
        process.kill()
    if not out.exists():
        sys.exit(f"Chrome wrote no {out.name}")
    print(f"{out.relative_to(ROOT)} {out.stat().st_size // 1024} KB")


def main() -> None:
    for language in ("en", "zh-Hant"):
        render(flow(language), ROOT / f"docs/flow-{language}.png", 1440, 870)
        render(architecture(language), ROOT / f"docs/architecture-{language}.png", 1440, 960)


if __name__ == "__main__":
    main()
