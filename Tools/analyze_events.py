#!/usr/bin/env python3
"""Summarise a Top Off analytics log (events.jsonl), such as one a TestFlight tester exported.

    python3 Tools/analyze_events.py events.jsonl [more.jsonl ...]

Several files (several testers) are combined. Standard library only.
An attempt that was left but later finished is not counted as abandoned, matching
`AnalyticsSummary` in the app.
"""
import json
import sys
from collections import defaultdict


def load(paths):
    events = []
    for path in paths:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                line = line.strip()
                if line:
                    events.append(json.loads(line))
    events.sort(key=lambda e: (int(e["properties"].get("ts", 0)), int(e["properties"].get("seq", 0))))
    return events


def main(paths):
    events = load(paths)
    installs = {e["properties"]["install_id"] for e in events}
    sessions = {e["properties"]["session_id"] for e in events if e["name"] == "session_start"}
    print(f"{len(events)} events, {len(installs)} install(s), {len(sessions)} session(s)\n")

    levels = defaultdict(lambda: defaultdict(int))
    attempt_done, attempt_left = set(), {}
    for e in events:
        p = e["properties"]
        if "mode" not in p or "level_id" not in p:
            if e["name"] == "stuck_shown":
                for key in levels:
                    if key[1] == p["level_id"]:
                        levels[key]["stuck"] += 1
            continue
        key = (p["mode"], p["level_id"])
        attempt = (p["install_id"], key, p.get("attempt"))
        row = levels[key]
        row["number"] = p.get("level_number", "")
        if e["name"] == "level_started":
            row["starts"] += 1
        elif e["name"] == "level_completed":
            attempt_done.add(attempt)
            row["done"] += 1
            row["moves"] += int(p["moves"])
            row["par"] += int(p["par"])
            row["secs"] += int(p["duration_s"])
            row["stars"] += int(p["stars"])
            row["hints"] += int(p["hints"])
            row["undos"] += int(p["undos"])
        elif e["name"] == "level_abandoned":
            attempt_left[attempt] = key
    for attempt, key in attempt_left.items():
        if attempt not in attempt_done:
            levels[key]["abandoned"] += 1

    print(f"{'level':<14}{'starts':>7}{'done%':>7}{'quit':>6}{'stuck':>6}{'moves/par':>10}{'secs':>6}{'stars':>6}{'hints':>6}")
    for key in sorted(levels, key=lambda k: (k[0], int(k[1]))):
        r = levels[key]
        starts, done = r["starts"], r["done"]
        pct = f"{100 * done // starts}" if starts else "-"
        ratio = f"{r['moves'] / r['par']:.2f}" if r["par"] else "-"
        secs = f"{r['secs'] // done}" if done else "-"
        stars = f"{r['stars'] / done:.1f}" if done else "-"
        label = f"{key[0]} {r['number'] or key[1]}"
        print(f"{label:<14}{starts:>7}{pct:>7}{r['abandoned']:>6}{r['stuck']:>6}{ratio:>10}{secs:>6}{stars:>6}{r['hints']:>6}")

    boosters = defaultdict(int)
    for e in events:
        if e["name"].startswith("booster_"):
            boosters[e["name"]] += 1
    if boosters:
        print("\nboosters:", dict(boosters))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
