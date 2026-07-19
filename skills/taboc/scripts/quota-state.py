#!/usr/bin/env python3
import argparse
import json
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path


QUOTA = re.compile(r"(?:^|\D)(?:402|429)(?:\D|$)|quota|rate.?limit|usage.?limit|credit", re.I)
ISO_TIME = re.compile(r"\d{4}-\d{2}-\d{2}[T ][0-9:.]+(?:Z|[+-]\d{2}:?\d{2})")
DURATION = re.compile(r"(?:retry\s+after|resets?\s+in)\s+(\d+)\s*(seconds?|minutes?|hours?|days?)", re.I)


def error_events(path: Path) -> list[dict]:
    events = []
    with path.open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and event.get("type") == "error" and QUOTA.search(json.dumps(event)):
                events.append(event)
    return events


def walk(value, key=""):
    if isinstance(value, dict):
        for child_key, child in value.items():
            yield from walk(child, str(child_key).lower())
    elif isinstance(value, list):
        for child in value:
            yield from walk(child, key)
    else:
        yield key, value


def parse_until(events: list[dict], now: int, fallback: int) -> tuple[int, str]:
    for event in events:
        for key, value in walk(event):
            if not any(token in key for token in ("reset", "retry", "until")):
                continue
            if isinstance(value, (int, float)):
                number = float(value)
                if "retry" in key or number < 1_000_000:
                    return now + max(1, int(number)), "provider"
                if number > 10_000_000_000:
                    number /= 1000
                return int(number), "provider"
            if isinstance(value, str) and value.isdigit():
                number = int(value)
                return (now + number if "retry" in key or number < 1_000_000 else number), "provider"
    text = json.dumps(events, ensure_ascii=False)
    match = DURATION.search(text)
    if match:
        scale = {"second": 1, "minute": 60, "hour": 3600, "day": 86400}[match.group(2).lower().rstrip("s")]
        return now + int(match.group(1)) * scale, "provider"
    match = ISO_TIME.search(text)
    if match:
        value = match.group(0).replace(" ", "T").replace("Z", "+00:00")
        return int(datetime.fromisoformat(value).timestamp()), "provider"
    return now + fallback, "inferred-24h"


def describe(data: dict) -> str:
    return f"blocked|until={data['until']}|source={data['source']}|model={data['model']}"


def check(path: Path) -> int:
    if not path.exists():
        print("clear")
        return 0
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        until_epoch = int(data["until_epoch"])
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        print(f"blocked|until=unknown|source=invalid-state|model=unknown")
        return 75
    if until_epoch <= int(time.time()):
        path.unlink(missing_ok=True)
        print("clear")
        return 0
    print(describe(data))
    return 75


def record(path: Path, log: Path, model: str, fallback: int) -> int:
    events = error_events(log)
    if not events:
        return 1
    now = int(time.time())
    until_epoch, source = parse_until(events, now, fallback)
    try:
        existing = json.loads(path.read_text(encoding="utf-8"))
        existing_until = int(existing["until_epoch"])
    except (OSError, ValueError, KeyError, json.JSONDecodeError):
        existing_until = 0
    if existing_until > until_epoch:
        until_epoch = existing_until
        source = existing.get("source", source)
    data = {
        "detected_at": datetime.fromtimestamp(now, timezone.utc).isoformat().replace("+00:00", "Z"),
        "model": model,
        "source": source,
        "until": datetime.fromtimestamp(until_epoch, timezone.utc).isoformat().replace("+00:00", "Z"),
        "until_epoch": until_epoch,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(f"{path.suffix}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)
    print(describe(data))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    check_parser = subparsers.add_parser("check")
    check_parser.add_argument("--state", required=True, type=Path)
    record_parser = subparsers.add_parser("record")
    record_parser.add_argument("--state", required=True, type=Path)
    record_parser.add_argument("--log", required=True, type=Path)
    record_parser.add_argument("--model", required=True)
    record_parser.add_argument("--fallback-seconds", type=int, default=86400)
    options = parser.parse_args()
    if options.command == "check":
        return check(options.state)
    return record(options.state, options.log, options.model, max(1, options.fallback_seconds))


if __name__ == "__main__":
    raise SystemExit(main())
