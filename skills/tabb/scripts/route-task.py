#!/usr/bin/env python3
import argparse


EFFORTS = ["low", "medium", "high", "xhigh", "max", "ultra"]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--class", dest="task_class", required=True, choices=["readonly", "work"])
    parser.add_argument("--current-model", required=True)
    parser.add_argument("--current-effort", required=True, choices=EFFORTS)
    options = parser.parse_args()
    effort = "low" if options.task_class == "readonly" else options.current_effort
    print(f"premium\t{options.current_model}\t{effort}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
