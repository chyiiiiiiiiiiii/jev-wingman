#!/usr/bin/env python3
"""How Wingman has been doing, from ~/Library/Logs/Wingman.log (times and counts only; the log holds no messages).

    scripts/log-stats.py              everything in the log
    scripts/log-stats.py --days 7     the last seven days

suggest   time from asking to three drafts (judge + write), p50 and p90
judge     Jev's answer time
ready     share of panel opens that found drafts already written by the prefetch
picked    share of panel opens that ended with a draft typed in
★         share of picks that took the draft Jev ranked best
"""
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

LOG = Path.home() / "Library/Logs/Wingman.log"


def percentile(values, share):
    values = sorted(values)
    return values[min(len(values) - 1, int(len(values) * share))] if values else None


def main() -> None:
    since = None
    if "--days" in sys.argv:
        since = datetime.now(timezone.utc) - timedelta(days=float(sys.argv[sys.argv.index("--days") + 1]))
    timings = {"suggest": [], "judge": [], "rank": []}
    opens = ready = picks = best = 0
    for line in LOG.read_text(errors="replace").splitlines():
        stamp, _, event = line.partition(" ")
        try:
            when = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        except ValueError:
            continue
        if since and when < since:
            continue
        if match := re.match(r"(suggest|judge|rank) (\d+)ms", event):
            timings[match[1]].append(int(match[2]))
        elif event.startswith("open drafts="):
            opens += 1
            ready += event.endswith("ready")
        elif event.startswith("pick slot="):
            picks += 1
            best += "best=true" in event
    for name, values in timings.items():
        if values:
            print(f"{name:8} p50 {percentile(values, 0.5):>5} ms   p90 {percentile(values, 0.9):>5} ms   ({len(values)})")
    share = lambda part, whole: f"{part / whole:.0%} ({part}/{whole})" if whole else "–"
    print(f"ready    {share(ready, opens)} of panel opens had drafts waiting")
    print(f"picked   {share(picks, opens)} of panel opens ended with a draft typed in")
    print(f"★        {share(best, picks)} of picks took the best-ranked draft")


if __name__ == "__main__":
    main()
