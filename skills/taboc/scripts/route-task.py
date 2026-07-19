#!/usr/bin/env python3
import argparse
import os
import subprocess
from pathlib import Path


ROUTES = {
    "simple": ("gpt-5.6-luna", "medium"),
    "complex-short": ("gpt-5.6-luna", "max"),
    "complex-long": ("gpt-5.6-sol", "medium"),
    "very-complex": ("gpt-5.6-sol", "high"),
}


def quota_active(state: Path) -> bool:
    result = subprocess.run(
        ["python3", str(Path(__file__).with_name("quota-state.py")), "check", "--state", str(state)],
        check=False,
        stdout=subprocess.DEVNULL,
    )
    return result.returncode == 75


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--class", dest="task_class", required=True, choices=["readonly", *ROUTES])
    parser.add_argument("--quota-state", type=Path)
    options = parser.parse_args()
    state = options.quota_state or Path(
        os.environ.get(
            "TABOC_QUOTA_STATE",
            str(Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "taboc/opencode-free-quota.json"),
        )
    )
    if options.task_class == "readonly" and not quota_active(state):
        print("opencode\topencode/deepseek-v4-flash-free\tmedium")
        return 0
    model, effort = ("gpt-5.6-luna", "low") if options.task_class == "readonly" else ROUTES[options.task_class]
    print(f"premium\t{model}\t{effort}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
