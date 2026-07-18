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
                "pool": row.get("Pool") or row.get("执行池") or "—",
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
        task, agent, pool, model, effort = cells
        rows[task] = {"agent": agent, "pool": pool, "model": model, "effort": effort}
    return rows


def statuses(directory: Path) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    if not directory.exists():
        return result
    for path in directory.glob("*.status"):
        cells = path.read_text(encoding="utf-8", errors="replace").strip().split("|")
        if len(cells) < 4:
            continue
        state, model, effort, attempt = cells[:4]
        result[path.stem] = {"state": state, "model": model, "effort": effort, "attempt": attempt}
    return result


def esc(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True)
    options = parser.parse_args()
    root = Path(options.repo) / ".taboc"
    board = board_rows(root / "board.md")
    assigned = assignments(root / "assignments.tsv")
    worker_status = statuses(root / "opencode")
    tasks = list(OrderedDict.fromkeys([*board, *assigned, *worker_status]))
    print("| Task | Agent | Pool | Model | Effort | State |")
    print("|---|---|---|---|---|---|")
    for task in tasks:
        base = board.get(task, {})
        item = assigned.get(task, {})
        agent = item.get("agent", base.get("agent", task))
        pool = item.get("pool", base.get("pool", "unregistered"))
        model = item.get("model", "unregistered")
        effort = item.get("effort", "unregistered")
        state = base.get("state", "—")
        live = worker_status.get(agent) or worker_status.get(task)
        if live:
            state = live["state"]
            if live["model"] not in {"-", "pending", ""}:
                model = live["model"]
            if live["effort"] not in {"-", "pending", ""}:
                effort = live["effort"]
        print("| " + " | ".join(map(esc, [task, agent, pool, model, effort, state])) + " |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
