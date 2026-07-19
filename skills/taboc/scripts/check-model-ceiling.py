#!/usr/bin/env python3
import argparse
import re


EFFORT_RANK = {"low": 1, "medium": 2, "high": 3, "xhigh": 4, "max": 5, "ultra": 6}
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
    parser.add_argument("--main-model", default="")
    parser.add_argument("--main-effort", default="")
    parser.add_argument("--strict-overrides", action="store_true")
    options = parser.parse_args()

    child_effort_name = normalize(options.effort)
    if child_effort_name != "inherit-main":
        child_effort = EFFORT_RANK.get(child_effort_name)
        main_effort = EFFORT_RANK.get(normalize(options.main_effort))
        if child_effort is None or main_effort is None:
            parser.error("explicit effort requires a trusted main effort; use inherit-main when unknown")
        if child_effort > main_effort:
            parser.error(f"child effort exceeds main effort: {options.effort} > {options.main_effort}")
        if options.strict_overrides and child_effort == main_effort:
            parser.error("explicit effort must be a strict downgrade; use inherit-main for equal effort")

    child_model = normalize(options.model)
    if child_model == "inherit-main":
        return 0
    main_model = normalize(options.main_model)
    if not main_model:
        parser.error("explicit model requires a trusted main model; use inherit-main when unknown")
    if child_model == main_model:
        if options.strict_overrides:
            parser.error("explicit model must be a strict downgrade; use inherit-main for the main model")
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
