#!/usr/bin/env python3
import argparse
import plistlib
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--log", required=True)
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args()
    args = options.args[1:] if options.args[:1] == ["--"] else options.args
    payload = {
        "Label": options.label,
        "ProgramArguments": args,
        "RunAtLoad": True,
        "KeepAlive": False,
        "ProcessType": "Background",
        "StandardOutPath": options.log,
        "StandardErrorPath": options.log,
    }
    with Path(options.output).open("wb") as stream:
        plistlib.dump(payload, stream, sort_keys=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
