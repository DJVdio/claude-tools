#!/usr/bin/env python3
"""archive-ops skill 核心 CLI。

职责：纯 I/O + 索引维护，不做任何 LLM 推理。
归档/读档的 tag 抽取由调用方（Claude 主 agent）完成，本 CLI 只接收已抽好的结构化数据。

子命令：
    collect <dir>              读目录下的 需求/design/plan md，返回 JSON
    archive-store ...          接收抽好的 tags 写入索引
    lookup --tags-json ...     按 tag 倒排查询，加权返回 top-K
    list [--project X]         列出已归档
    show <id>                  展开某条归档
    forget <id>                删除某条归档
"""
import argparse
import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path

import yaml

SKILL_DIR = Path(__file__).resolve().parent
# data/ 默认跟 skill 捆绑;环境变量 ARCHIVE_OPS_DATA_DIR 可重定向(跨项目/团队共享场景)
# 空字符串 / 纯空白 视为未设置,避免 Path("") 歧义
_DATA_OVERRIDE = (os.environ.get("ARCHIVE_OPS_DATA_DIR") or "").strip()
if _DATA_OVERRIDE:
    DATA_DIR = Path(_DATA_OVERRIDE).expanduser().resolve()
    # 重定向路径若不存在,stderr warn(避免拼写错误导致数据飘向空目录,用户却不知)
    if not DATA_DIR.exists():
        print(f"[data-dir] ARCHIVE_OPS_DATA_DIR={_DATA_OVERRIDE} 不存在,将新建。"
              f"若是拼写错误请立即 Ctrl-C 并修正环境变量", file=sys.stderr)
else:
    DATA_DIR = SKILL_DIR / "data"
ARCHIVES_DIR = DATA_DIR / "archives"
INDEX_PATH = DATA_DIR / "index.json"
SYNONYMS_PATH = SKILL_DIR / "synonyms.yaml"

# Tag 维度权重(与 spec §5 一致)
# 注:problems=solutions=3 对等,因为"踩过的坑"和"怎么解决"对用户同等重要
# (Round 1 D agent 反馈:原 3:2 偏问题,用户查"怎么解 X"时方案应同权重)
DIMENSION_WEIGHT = {
    "modules": 2,
    "tech": 1,
    "problems": 3,
    "solutions": 3,
    "files": 1,
}
DIMENSIONS = list(DIMENSION_WEIGHT.keys())

# id 格式校验:首字符字母数字,其余允许 [A-Za-z0-9_.\-],长度 1-100
# 允许 '.' 以兼容历史 id(如 `foo.v2`),但显式拒绝 '..' 防路径穿越
# 其它路径字符('/' '\\' '\n' 等)天然不在字符集里
_VALID_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.\-]{0,99}$")

# schema 版本号,未来字段演进用
SCHEMA_VERSION = 1


# ====================== 基础 I/O ======================

def ensure_data_dir():
    """首次运行自动建 data/archives 和空 index.json。"""
    ARCHIVES_DIR.mkdir(parents=True, exist_ok=True)
    if not INDEX_PATH.exists():
        _atomic_write_json(INDEX_PATH, {"by_tag": {}, "by_id": {}})


def _atomic_write_json(path: Path, data: dict):
    """通过 rename 原子替换，避免半写文件。"""
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
    os.replace(tmp, path)


def _read_json(path: Path) -> dict:
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def load_index() -> dict:
    ensure_data_dir()
    idx = _read_json(INDEX_PATH)
    idx.setdefault("by_tag", {})
    idx.setdefault("by_id", {})
    return idx


def save_index(idx: dict):
    _atomic_write_json(INDEX_PATH, idx)


# ====================== project 推断 ======================

def infer_project(path: Path) -> str:
    """推断项目名。依次尝试：
    1) 向上找 `.git` 目录 → 用其所在目录名
    2) 向上找 `CLAUDE.md` → 用其所在目录名
    3) 路径里含 `/docs/` → 取 docs 的父目录名
    4) 兜底：path 自身的名字
    """
    p = path.resolve()
    if p.is_file():
        p = p.parent

    # 1. .git
    cur = p
    while cur != cur.parent:
        if (cur / ".git").exists():
            return cur.name
        cur = cur.parent

    # 2. CLAUDE.md
    cur = p
    while cur != cur.parent:
        if (cur / "CLAUDE.md").exists():
            return cur.name
        cur = cur.parent

    # 3. 路径里有 /docs/，取 docs 的父目录名
    parts = p.parts
    for i, seg in enumerate(parts):
        if seg == "docs" and i > 0:
            return parts[i - 1]

    return p.name or "unknown"


# ====================== collect ======================

MD_TARGETS = ("需求.md",)  # 主入口
DESIGN_RE = re.compile(r".*-design\.md$")
PLAN_RE = re.compile(r".*-plan\.md$")


def cmd_collect(args):
    """读目录下的 需求.md + *-design.md + *-plan.md，打印 JSON。"""
    target = Path(args.dir).expanduser().resolve()
    if not target.exists() or not target.is_dir():
        print(f"[collect] 目录不存在或非目录: {target}", file=sys.stderr)
        sys.exit(2)

    files = {}
    # 需求.md
    for name in MD_TARGETS:
        f = target / name
        if f.exists():
            files[str(f)] = f.read_text(encoding="utf-8", errors="replace")
    # design / plan（可能多份）
    for md in sorted(target.glob("*.md")):
        if DESIGN_RE.match(md.name) or PLAN_RE.match(md.name):
            files[str(md)] = md.read_text(encoding="utf-8", errors="replace")

    # 标题：优先取 需求.md 第一行 # 标题，取不到用目录名
    title = target.name
    req_md = target / "需求.md"
    if req_md.exists():
        for line in req_md.read_text(encoding="utf-8", errors="replace").splitlines()[:20]:
            m = re.match(r"^#+\s+(.+?)\s*$", line.strip())
            if m:
                title = m.group(1).strip()
                break

    out = {
        "title": title,
        "path": str(target),
        "project": infer_project(target),
        "files": files,
    }
    print(json.dumps(out, ensure_ascii=False, indent=2))


# ====================== archive-store ======================

def _normalize_tags(raw: dict) -> dict:
    """保证 5 个维度都存在,且每个是 list of strings。
    未知维度会在 stderr 发 warning(而不是静默丢弃,以便调用方发现 schema 偏离)。"""
    if not isinstance(raw, dict):
        print(f"[tags] 期望 dict,收到 {type(raw).__name__},已置空", file=sys.stderr)
        raw = {}
    unknown = [k for k in raw.keys() if k not in DIMENSIONS]
    if unknown:
        print(f"[tags] 以下维度不在 5 类标准内,已丢弃: {unknown}", file=sys.stderr)
    out = {}
    for dim in DIMENSIONS:
        v = raw.get(dim, [])
        if not isinstance(v, list):
            print(f"[tags] 维度 {dim} 期望 list,收到 {type(v).__name__},已置空", file=sys.stderr)
            v = []
        # 去重 + 去空 + strip
        out[dim] = sorted({str(x).strip() for x in v if str(x).strip()})
    return out


def _rebuild_by_tag_for_id(idx: dict, id_: str, tags: dict):
    """把某个 id 从 by_tag 全量撤掉再按 tags 加回。"""
    # 撤
    for key, ids in list(idx["by_tag"].items()):
        if id_ in ids:
            ids = [x for x in ids if x != id_]
            if ids:
                idx["by_tag"][key] = ids
            else:
                del idx["by_tag"][key]
    # 加
    for dim, vals in tags.items():
        for v in vals:
            key = f"{dim}:{v}"
            idx["by_tag"].setdefault(key, [])
            if id_ not in idx["by_tag"][key]:
                idx["by_tag"][key].append(id_)


def _validate_id(id_: str) -> str:
    """校验并返回归一化后的 id。非法即退出码 1。
    防路径穿越('/', '\\', '..', '\\n' 等)并保证文件名可读。"""
    id_ = (id_ or "").strip()
    if not id_:
        print('[archive-store] --id 不能为空', file=sys.stderr)
        sys.exit(1)
    if ".." in id_:
        # 单独拦截 ".."(正则放行了单个 '.',所以得显式拒绝连写)
        print(f'[archive-store] --id 禁止包含 "..": {id_!r}', file=sys.stderr)
        sys.exit(1)
    if not _VALID_ID_RE.match(id_):
        print(f'[archive-store] --id 格式非法: {id_!r}'
              f'\n  要求:字母数字/下划线/连字符/点号,首字符字母数字,长度 1-100',
              file=sys.stderr)
        sys.exit(1)
    return id_


def cmd_archive_store(args):
    ensure_data_dir()
    id_ = _validate_id(args.id)

    try:
        tags_raw = json.loads(args.tags_json) if args.tags_json else {}
    except json.JSONDecodeError as e:
        print(f"[archive-store] --tags-json 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    try:
        lessons = json.loads(args.lessons_json) if args.lessons_json else []
    except json.JSONDecodeError as e:
        print(f"[archive-store] --lessons-json 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(lessons, list):
        print(f"[archive-store] --lessons-json 期望 list,收到 {type(lessons).__name__},已包装为单元素",
              file=sys.stderr)
        lessons = [str(lessons)]

    tags = _normalize_tags(tags_raw)
    tag_count = sum(len(v) for v in tags.values())

    record = {
        "schema_version": SCHEMA_VERSION,
        "id": id_,
        "title": args.title or id_,
        "path": args.path or "",
        "project": args.project or "unknown",
        "date_archived": datetime.now().strftime("%Y-%m-%d"),
        "tags": tags,
        "summary": args.summary or "",
        "lessons": lessons,
    }

    archive_file = ARCHIVES_DIR / f"{id_}.json"
    replaced = archive_file.exists()
    if replaced and not args.force:
        print(json.dumps({"ok": False, "error": f"id 已存在: {id_}（用 --force 覆盖）"}, ensure_ascii=False))
        sys.exit(3)

    _atomic_write_json(archive_file, record)

    idx = load_index()
    _rebuild_by_tag_for_id(idx, id_, tags)
    idx["by_id"][id_] = {
        "title": record["title"],
        "path": record["path"],
        "project": record["project"],
        "date_archived": record["date_archived"],
        "tag_count": tag_count,
    }
    save_index(idx)

    print(json.dumps({"ok": True, "id": id_, "replaced": replaced}, ensure_ascii=False))


# ====================== lookup ======================

def cmd_lookup(args):
    ensure_data_dir()
    idx = load_index()

    if args.top <= 0:
        print(f"[lookup] --top 必须 > 0,收到 {args.top}", file=sys.stderr)
        sys.exit(1)
    if args.top > 100:
        print(f"[lookup] --top={args.top} 超过硬上限 100,已截断", file=sys.stderr)
    top = min(args.top, 100)

    try:
        query = json.loads(args.tags_json)
    except json.JSONDecodeError as e:
        print(f"[lookup] --tags-json 解析失败: {e}", file=sys.stderr)
        sys.exit(1)
    if not isinstance(query, dict):
        print(f"[lookup] --tags-json 期望 dict,收到 {type(query).__name__}", file=sys.stderr)
        sys.exit(1)

    unknown = [k for k in query.keys() if k not in DIMENSION_WEIGHT]
    if unknown:
        print(f"[lookup] 以下维度不在 5 类标准内,已忽略: {unknown}", file=sys.stderr)

    # score by id
    scores: dict = {}
    matched: dict = {}
    for dim, vals in query.items():
        if dim not in DIMENSION_WEIGHT:
            continue
        if not isinstance(vals, list):
            print(f"[lookup] 维度 {dim} 期望 list,收到 {type(vals).__name__},已忽略", file=sys.stderr)
            continue
        w = DIMENSION_WEIGHT[dim]
        for v in vals:
            key = f"{dim}:{v}"
            ids = idx["by_tag"].get(key, [])
            for id_ in ids:
                scores[id_] = scores.get(id_, 0) + w
                matched.setdefault(id_, []).append(key)

    if args.project_filter:
        scores = {
            id_: s for id_, s in scores.items()
            if idx["by_id"].get(id_, {}).get("project") == args.project_filter
        }

    # sort
    ranked = sorted(scores.items(), key=lambda x: (-x[1], x[0]))[:top]

    # expand result
    out = []
    for id_, score in ranked:
        archive_file = ARCHIVES_DIR / f"{id_}.json"
        rec = _read_json(archive_file)
        if not rec:
            continue
        out.append({
            "id": id_,
            "title": rec.get("title", ""),
            "path": rec.get("path", ""),
            "project": rec.get("project", ""),
            "date_archived": rec.get("date_archived", ""),
            "score": score,
            "matched_tags": matched.get(id_, []),
            "summary": rec.get("summary", ""),
            "lessons": rec.get("lessons", []),
            "tags": rec.get("tags", {}),
        })

    print(json.dumps(out, ensure_ascii=False, indent=2))


# ====================== list / show / forget ======================

def cmd_list(args):
    ensure_data_dir()
    idx = load_index()
    rows = []
    for id_, meta in idx["by_id"].items():
        if args.project and meta.get("project") != args.project:
            continue
        if args.since and meta.get("date_archived", "") < args.since:
            continue
        rows.append((id_, meta.get("date_archived", ""), meta.get("project", ""), meta.get("title", "")))
    rows.sort(key=lambda x: x[1], reverse=True)
    if not rows:
        print("(无归档)")
        return
    # 简单表格
    w_id = max(len(r[0]) for r in rows)
    w_proj = max(len(r[2]) for r in rows)
    header = f"{'ID':<{w_id}}  {'DATE':<10}  {'PROJECT':<{w_proj}}  TITLE"
    print(header)
    print("-" * len(header))
    for id_, d, proj, title in rows:
        print(f"{id_:<{w_id}}  {d:<10}  {proj:<{w_proj}}  {title}")


def cmd_show(args):
    ensure_data_dir()
    id_ = _validate_id(args.id)
    archive_file = ARCHIVES_DIR / f"{id_}.json"
    if not archive_file.exists():
        print(json.dumps({"ok": False, "error": f"id 不存在: {id_}"}, ensure_ascii=False))
        sys.exit(3)
    rec = _read_json(archive_file)
    print(json.dumps(rec, ensure_ascii=False, indent=2))


def cmd_forget(args):
    """删除归档。删除不可逆,必须显式 --yes(由调用方先让用户 1/2 确认后再带)。"""
    ensure_data_dir()
    id_ = _validate_id(args.id)
    if not args.yes:
        print(json.dumps({
            "ok": False,
            "error": "forget 是不可逆删除,必须加 --yes(调用方应先让用户 1/2 确认)",
            "id": id_,
        }, ensure_ascii=False))
        sys.exit(4)
    archive_file = ARCHIVES_DIR / f"{id_}.json"
    if not archive_file.exists():
        print(json.dumps({"ok": False, "error": f"id 不存在: {id_}"}, ensure_ascii=False))
        sys.exit(3)
    archive_file.unlink()
    idx = load_index()
    # 从 by_tag 撤掉
    _rebuild_by_tag_for_id(idx, id_, {dim: [] for dim in DIMENSIONS})
    idx["by_id"].pop(id_, None)
    save_index(idx)
    print(json.dumps({"ok": True, "id": id_}, ensure_ascii=False))


# ====================== fsck ======================

def cmd_fsck(args):
    """扫 archives/ 对照 by_id,打印一致性报告。
    有 --repair 则修正:
      - archives/ 里有但 by_id 漏:重建索引项
      - by_id 有但 archives/ 没:从索引移除
      - by_tag 引用的 id 在 by_id 里不存在:清理
    """
    ensure_data_dir()
    idx = load_index()
    on_disk = {p.stem for p in ARCHIVES_DIR.glob("*.json")}
    in_index = set(idx["by_id"].keys())

    orphan_files = on_disk - in_index   # 磁盘上有,索引漏
    stale_index = in_index - on_disk    # 索引有,磁盘缺
    dangling_tags = []                  # by_tag 里引用了不存在的 id
    for key, ids in idx["by_tag"].items():
        for i in ids:
            if i not in on_disk:
                dangling_tags.append((key, i))

    report = {
        "ok": not (orphan_files or stale_index or dangling_tags),
        "on_disk": len(on_disk),
        "in_index": len(in_index),
        "orphan_files": sorted(orphan_files),
        "stale_index_entries": sorted(stale_index),
        "dangling_tag_refs": dangling_tags[:20],
        "dangling_tag_refs_total": len(dangling_tags),
    }

    if args.repair and not report["ok"]:
        # 重建孤儿文件的索引。保留 record 的 tags 原貌:
        # 只取 5 个已知维度用于 by_tag 索引,不 normalize 不裁剪其他字段——
        # 未来 schema 若扩展(如 record 存了 v2 新维度),原 record 文件保持完整,
        # 只是暂时不纳入 by_tag 倒排。
        for id_ in orphan_files:
            rec = _read_json(ARCHIVES_DIR / f"{id_}.json")
            if not rec:
                continue  # 损坏 JSON 跳过,不伪造"空 tag 归档"掩盖破损
            raw_tags = rec.get("tags", {}) if isinstance(rec.get("tags"), dict) else {}
            # 只取已知 5 维用于索引,但保持值原样(list 否则空)
            indexable_tags = {}
            for dim in DIMENSIONS:
                v = raw_tags.get(dim, [])
                indexable_tags[dim] = v if isinstance(v, list) else []
            _rebuild_by_tag_for_id(idx, id_, indexable_tags)
            idx["by_id"][id_] = {
                "title": rec.get("title", id_),
                "path": rec.get("path", ""),
                "project": rec.get("project", "unknown"),
                "date_archived": rec.get("date_archived", ""),
                "tag_count": sum(len(v) for v in indexable_tags.values()),
            }
        # 清理无文件的索引项
        for id_ in stale_index:
            _rebuild_by_tag_for_id(idx, id_, {dim: [] for dim in DIMENSIONS})
            idx["by_id"].pop(id_, None)
        # 清理残留 tag 引用
        for key, ids in list(idx["by_tag"].items()):
            cleaned = [i for i in ids if i in on_disk or i in orphan_files]
            if cleaned:
                idx["by_tag"][key] = cleaned
            else:
                del idx["by_tag"][key]
        save_index(idx)
        report["repaired"] = True

    print(json.dumps(report, ensure_ascii=False, indent=2))
    sys.exit(0 if report["ok"] else 5)


# ====================== main ======================

def main():
    ap = argparse.ArgumentParser(prog="archive_ops", description="archive-ops 本地归档/读档索引")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_coll = sub.add_parser("collect", help="读目录下 md 文件返回 JSON")
    p_coll.add_argument("dir", help="需求目录绝对路径")
    p_coll.set_defaults(func=cmd_collect)

    p_store = sub.add_parser("archive-store", help="把抽好的 tag + 摘要 + 教训 落盘")
    p_store.add_argument("--id", required=True)
    p_store.add_argument("--title", default="")
    p_store.add_argument("--path", default="")
    p_store.add_argument("--project", default="unknown")
    p_store.add_argument("--tags-json", default="{}")
    p_store.add_argument("--summary", default="")
    p_store.add_argument("--lessons-json", default="[]")
    p_store.add_argument("--force", action="store_true", help="同 id 存在时覆盖")
    p_store.set_defaults(func=cmd_archive_store)

    p_look = sub.add_parser("lookup", help="按查询 tag 倒排检索")
    p_look.add_argument("--tags-json", required=True)
    p_look.add_argument("--top", type=int, default=5)
    p_look.add_argument("--project-filter", default="")
    p_look.set_defaults(func=cmd_lookup)

    p_list = sub.add_parser("list", help="列出已归档")
    p_list.add_argument("--project", default="")
    p_list.add_argument("--since", default="", help="YYYY-MM-DD")
    p_list.set_defaults(func=cmd_list)

    p_show = sub.add_parser("show", help="展开某条归档")
    p_show.add_argument("id")
    p_show.set_defaults(func=cmd_show)

    p_forget = sub.add_parser("forget", help="删除某条归档(不可逆,需 --yes)")
    p_forget.add_argument("id")
    p_forget.add_argument("--yes", action="store_true", help="确认删除(调用方应先让用户 1/2 确认后再带)")
    p_forget.set_defaults(func=cmd_forget)

    p_fsck = sub.add_parser("fsck", help="索引一致性检查;崩溃/误改后跑一遍")
    p_fsck.add_argument("--repair", action="store_true", help="发现不一致时自动修复")
    p_fsck.set_defaults(func=cmd_fsck)

    args = ap.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
