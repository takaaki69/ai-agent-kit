"""Record one line per delegated run, so the split between Claude and the helpers can be counted later.

    python lib/usage_log.py add TOOL EXIT SECONDS WRITE MODEL PROMPT_CHARS OUTPUT_CHARS
    python lib/usage_log.py summary [DAYS]

Each line is JSON: time, project (checkout folder name), tool, exit status, seconds,
write mode, model, and the sizes of the prompt and the answer. The task text and the
answer themselves are never stored.

Where it goes: Drive <root>/_usage/usage.jsonl when Drive credentials are set (the same
ones as the login store, so every project that uses the kit adds to the same file);
otherwise ~/.ai-agent-kit-usage.jsonl. Set AI_KIT_USAGE_LOG=0 to turn it off.
Logging is best effort: a failure prints one line and never changes the run's result.
"""

from __future__ import annotations

import json
import os
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import drive  # noqa: E402

FOLDER, NAME = "_usage", "usage.jsonl"
LOCAL = Path.home() / ".ai-agent-kit-usage.jsonl"


def _read() -> bytes:
    if drive.credential_prefixes():
        return drive.Drive().get(FOLDER, NAME) or b""
    return LOCAL.read_bytes() if LOCAL.exists() else b""


def add(argv: list[str]) -> None:
    tool, status, seconds, write, model, prompt_chars, output_chars = argv
    entry = {
        "time": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "project": Path(os.environ.get("AI_KIT_PROJECT") or os.getcwd()).name,
        "tool": tool,
        "exit": int(status),
        "seconds": int(seconds),
        "write": write == "1",
        "model": model or "default",
        "prompt_chars": int(prompt_chars),
        "output_chars": int(output_chars),
    }
    line = (json.dumps(entry, ensure_ascii=False) + "\n").encode()
    if drive.credential_prefixes():
        store = drive.Drive()
        store.put(FOLDER, NAME, (store.get(FOLDER, NAME) or b"") + line)
    else:
        with LOCAL.open("ab") as f:
            f.write(line)


def summary(days: int) -> None:
    since = datetime.now(timezone.utc) - timedelta(days=days)
    rows = []
    for raw in _read().decode().splitlines():
        try:
            row = json.loads(raw)
            if datetime.fromisoformat(row["time"]) >= since:
                rows.append(row)
        except (ValueError, KeyError):
            continue
    print(f"last {days} days: {len(rows)} delegated runs")
    by: dict[str, list] = defaultdict(list)
    for r in rows:
        by[r["tool"]].append(r)
    for tool, rs in sorted(by.items()):
        ok = sum(1 for r in rs if r["exit"] == 0)
        print(f"  {tool}: {len(rs)} runs ({ok} ok), {sum(r['seconds'] for r in rs) // 60} min, "
              f"prompt {sum(r['prompt_chars'] for r in rs)} chars, answer {sum(r['output_chars'] for r in rs)} chars")
    projects: dict[str, int] = defaultdict(int)
    for r in rows:
        projects[r["project"]] += 1
    if projects:
        print("  by project: " + ", ".join(f"{p} {n}" for p, n in sorted(projects.items())))


def main() -> int:
    if len(sys.argv) > 1 and sys.argv[1] == "summary":
        summary(int(sys.argv[2]) if len(sys.argv) > 2 else 30)
        return 0
    if len(sys.argv) == 9 and sys.argv[1] == "add":
        if os.environ.get("AI_KIT_USAGE_LOG", "1") == "0":
            return 0
        try:
            add(sys.argv[2:])
        except (SystemExit, Exception) as e:  # best effort
            print(f"usage log skipped: {e}", file=sys.stderr)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
