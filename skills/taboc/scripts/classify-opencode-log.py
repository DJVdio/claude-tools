#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path


RETRYABLE = re.compile(
    r"(?:^|\D)(?:402|429)(?:\D|$)|quota|rate.?limit|usage.?limit|credit|capacity|"
    r"overload|model.+(?:unavailable|not found|disabled)|ECONNRESET|ETIMEDOUT|"
    r"ENOTFOUND|stream error|empty response|temporarily unavailable|TabocAttemptTimeout",
    re.IGNORECASE,
)


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: classify-opencode-log.py LOG", file=sys.stderr)
        return 2
    errors: list[str] = []
    with Path(sys.argv[1]).open(encoding="utf-8", errors="replace") as stream:
        for line in stream:
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict) and event.get("type") == "error":
                errors.append(json.dumps(event, ensure_ascii=False))
    if not errors:
        print("clean")
    elif any(RETRYABLE.search(error) for error in errors):
        print("retryable")
    else:
        print("error")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
