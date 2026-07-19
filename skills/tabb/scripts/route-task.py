#!/usr/bin/env python3
import argparse
ROUTES = {
    "readonly": ("gpt-5.6-luna", "low"),
    "simple": ("gpt-5.6-luna", "medium"),
    "complex-short": ("gpt-5.6-luna", "max"),
    "complex-long": ("gpt-5.6-sol", "medium"),
    "very-complex": ("gpt-5.6-sol", "high"),
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--class", dest="task_class", required=True, choices=ROUTES)
    options = parser.parse_args()
    model, effort = ROUTES[options.task_class]
    print(f"premium\t{model}\t{effort}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
