#!/usr/bin/env python3
import argparse
from collections import OrderedDict
from pathlib import Path


def board_rows(path: Path) -> OrderedDict[str, dict[str, str]]:
    rows: OrderedDict[str, dict[str, str]] = OrderedDict()
    if not path.exists():
        return rows
    headers: list[str] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if not line.lstrip().startswith("|"):
            continue
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if not headers:
            headers = cells
            continue
        if all(set(cell) <= {"-", ":", " "} for cell in cells):
            continue
        row = dict(zip(headers, cells))
        task = row.get("Task") or row.get("任务") or (cells[0] if cells else "")
        if task:
            rows[task] = {
                "agent": row.get("Claimed By") or row.get("Agent") or row.get("认领者") or "—",
                "state": row.get("Status") or row.get("状态") or "—",
            }
    return rows


def assignments(path: Path) -> OrderedDict[str, dict[str, str]]:
    rows: OrderedDict[str, dict[str, str]] = OrderedDict()
    if not path.exists():
        return rows
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        cells = line.split("\t")
        if len(cells) != 5:
            continue
        task, agent, role, model, effort = cells
        rows[task] = {"agent": agent, "role": role, "model": model, "effort": effort}
    return rows


def esc(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    options = parser.parse_args()
    root = Path(options.repo) / ".tabb"
    board = board_rows(root / "board.md")
    assigned = assignments(root / "assignments.tsv")
    tasks = list(OrderedDict.fromkeys([*board, *assigned]))
    print("| Task | Agent | Role | Model | Effort | State |")
    print("|---|---|---|---|---|---|")
    for task in tasks:
        base = board.get(task, {})
        item = assigned.get(task, {})
        missing = "unregistered" if base.get("agent") not in {None, "", "—"} else "not-dispatched"
        values = [
            task,
            item.get("agent", base.get("agent", "—")),
            item.get("role", missing),
            item.get("model", missing),
            item.get("effort", missing),
            base.get("state", "—"),
        ]
        print("| " + " | ".join(map(esc, values)) + " |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
