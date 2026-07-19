#!/usr/bin/env python3
import argparse
import os
import re
import tempfile
from pathlib import Path


WORKER_ID = re.compile(r"^[A-Za-z0-9._-]+$")


def readonly_protocol(worker: str) -> str:
    return f"""profile=readonly：不得编辑业务文件，不得写 [SEAL]。完成后 append：
  [HANDOFF] {worker} → <下游或主 agent> | <结论与 file:line 证据>
"""


def simple_protocol(repo: str, branch: str, worker: str) -> str:
    return f"""profile=simple：改文件 F 前执行：
  L=.taboc/locks/$(printf '%s' "F" | sed 's#/#__#g')
  mkdir "${{L}}" 2>/dev/null && {{ printf '%s %s\\n' "{worker}" "F" > "${{L}}/meta"; echo GOT; }} || echo BUSY
GOT 才改；BUSY 拉其他 open 任务，禁止空转。先写复现测试红，再修绿，只跑定向测试。
改完执行 `rm "${{L}}/meta" && rmdir "${{L}}"`。释放全部锁后 append：
  [DONE] {worker} | <任务> | 根因 file:line | 改动 | 定向测试红→绿 | 遗留
  [SEAL] {repo} | <子模块或 -> | {branch} | <相对文件,逗号分隔> | <commit msg>
"""


def render(options: argparse.Namespace) -> str:
    protocol = (
        readonly_protocol(options.worker)
        if options.profile == "readonly"
        else simple_protocol(options.repo, options.branch, options.worker)
    )
    return f"""【taboc 协议】
仓库：{options.repo}；分支：{options.branch}；你的 id：{options.worker}；profile：{options.profile}。
黑板：{options.repo}/.taboc/board.md、journal.md、locks/。只改工作区，绝不 commit/push。

任务：{options.task}
输入：{options.context}
边界：{options.boundary}
验证：{options.validation}；不得运行或声称通过全量测试。
输出预算：结论短写；证据用 file:line；不要复述大段源码或日志。

{protocol}
设计语义、数据写、生产写、高风险或不可逆动作不得自裁。append：
  [DECISION] {options.worker} | <问题与推荐选项>
然后停止。最终回复只给完成状态、证据和遗留。无 open 任务时结束，禁止 idle。
"""


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
        os.replace(temporary, path)
    except BaseException:
        try:
            os.unlink(temporary)
        except FileNotFoundError:
            pass
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate a complete taboc OpenCode worker prompt")
    parser.add_argument("--output", required=True)
    parser.add_argument("--repo", required=True)
    parser.add_argument("--branch", required=True)
    parser.add_argument("--id", dest="worker", required=True)
    parser.add_argument("--profile", choices=["readonly", "simple"], required=True)
    parser.add_argument("--task", required=True)
    parser.add_argument("--context", default="无；HANDOFF 信息自行读 journal 对应条目")
    parser.add_argument("--boundary", default="仅限任务相关普通仓库文件；禁读敏感信息，禁碰其他 worker 范围")
    parser.add_argument("--validation", default="按任务选择定向检查")
    options = parser.parse_args()
    if not Path(options.repo).is_absolute() or not Path(options.output).is_absolute():
        parser.error("repo and output must be absolute paths")
    if not WORKER_ID.fullmatch(options.worker):
        parser.error("invalid worker id")
    atomic_write(Path(options.output), render(options))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
