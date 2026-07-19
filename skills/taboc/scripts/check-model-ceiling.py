#!/usr/bin/env python3
import argparse
import re


EFFORT_RANK = {"low": 1, "medium": 2, "high": 3, "max": 4, "xhigh": 5}
MODEL_TIERS = {
    "codex": {"terra": 1, "luna": 2, "sol": 3},
    "claude": {"haiku": 1, "sonnet": 2, "opus": 3},
}


def normalize(value: str) -> str:
    return re.sub(r"-+", "-", value.strip().lower().replace("_", "-"))


def classify(model: str) -> tuple[str, str, int] | None:
    normalized = normalize(model)
    for family, tiers in MODEL_TIERS.items():
        for tier, rank in tiers.items():
            if re.search(rf"(?:^|-){re.escape(tier)}(?:-|$)", normalized):
                series = re.sub(rf"(?:^|-){re.escape(tier)}(?=-|$)", "", normalized).strip("-")
                return family, series or family, rank
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--effort", required=True)
    parser.add_argument("--main-model", required=True)
    parser.add_argument("--main-effort", required=True)
    options = parser.parse_args()

    child_effort = EFFORT_RANK.get(normalize(options.effort))
    main_effort = EFFORT_RANK.get(normalize(options.main_effort))
    if child_effort is None or main_effort is None:
        parser.error("effort must be low, medium, high, max, or xhigh")
    if child_effort > main_effort:
        parser.error(f"child effort exceeds main effort: {options.effort} > {options.main_effort}")

    child_model = normalize(options.model)
    main_model = normalize(options.main_model)
    if child_model == main_model:
        return 0
    child = classify(child_model)
    main = classify(main_model)
    if child is None or main is None or child[:2] != main[:2]:
        parser.error(
            f"cannot prove child model is not stronger: {options.main_model} -> {options.model}; "
            "use the main model or a known weaker tier in the same series"
        )
    if child[2] > main[2]:
        parser.error(f"child model exceeds main model: {options.main_model} -> {options.model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
