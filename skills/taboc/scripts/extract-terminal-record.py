#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--log", required=True)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--profile", choices=["readonly", "simple"], required=True)
    options = parser.parse_args()
    prefixes = [f"[DECISION] {options.worker} |"]
    if options.profile == "readonly":
        prefixes.insert(0, f"[HANDOFF] {options.worker} →")
    else:
        prefixes.insert(0, f"[DONE] {options.worker} |")
    found = ""
    with Path(options.log).open(encoding="utf-8", errors="replace") as stream:
        for raw in stream:
            try:
                event = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if not isinstance(event, dict) or event.get("type") != "text":
                continue
            part = event.get("part")
            text = part.get("text", "") if isinstance(part, dict) else event.get("text", "")
            if not isinstance(text, str):
                continue
            for line in text.splitlines():
                candidate = line.strip()
                if len(candidate) <= 4096 and any(candidate.startswith(prefix) for prefix in prefixes):
                    found = candidate
    if found:
        print(found)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
