#!/usr/bin/env python3
"""db-ops skill core CLI.

Driven by Claude Code following the three-step interaction flow defined in SKILL.md.
Sub-commands output JSON on stdout (render-prod outputs raw SQL text).

All errors propagate as JSON `{"error": "..."}` on stdout so Claude can parse uniformly;
exit code = 0 for parseable results (including business errors), exit code = 2 only for
hard refusals (CRITICAL routed to wrong subcommand, phrase mismatch).
"""
import argparse
import hashlib
import json
import os
import re
import sys
import time
import uuid
from datetime import datetime
from pathlib import Path

import pymysql
import pymysql.cursors
import sqlparse
import yaml

SKILL_DIR = Path(__file__).resolve().parent

# Fallback YAML when config.yml is absent (preserves legacy asms behavior).
LEGACY_YAML_PATH = Path(
    "/Users/hufangwei/asms/asms_backend/yshop-server/src/main/resources/application-test.yaml"
)

# MUST stay in sync with SKILL.md banner template (RISK_EMOJI table).
RISK_EMOJI = {"LOW": "🟢", "MEDIUM": "🟡", "HIGH": "⚠️", "CRITICAL": "🔴"}

DEFAULT_OPTIONS = {
    "audit_log_enabled": True,
    "audit_log_path": None,
    "exec_max_rows": 2000,
    "display_max_rows": 50,
    "dry_run_sample_rows": 20,
    "large_select_warn_rows": 1_000_000,
}


# ============================================================================
# Config loading
# ============================================================================

def load_config():
    """Load db-ops/config.yml; return dict with environments + options.

    Backward compatible: if config.yml absent, return a synthesized config that
    points TEST at LEGACY_YAML_PATH (= existing asms behavior).
    """
    cfg_path = SKILL_DIR / "config.yml"
    if cfg_path.exists():
        try:
            raw = yaml.safe_load(cfg_path.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError as e:
            raise SkillError(f"config.yml parse error: {e}")
        envs = raw.get("environments") or {}
        if "test" not in envs or "prod" not in envs:
            raise SkillError("config.yml: environments.test and environments.prod are required")
        opts = {**DEFAULT_OPTIONS, **(raw.get("options") or {})}
        return {"environments": envs, "options": opts}

    # Legacy fallback: synthesize from LEGACY_YAML_PATH.
    return {
        "environments": {
            "test": {
                "label": "🧪 测试服",
                "dialect": "mysql",
                "direct_execute": True,
                "connection": {"source": "spring-yaml", "path": str(LEGACY_YAML_PATH)},
            },
            "prod": {
                "label": "🔥 正式服",
                "dialect": "mysql",
                "direct_execute": False,
                "sql_executor_tool": "DMS https://dms.aliyun.com/",
                "rollback_hint": "binlog",
            },
        },
        "options": dict(DEFAULT_OPTIONS),
    }


def _resolve_env_value(value):
    """Resolve `<env:VAR_NAME>` placeholder in config strings."""
    if isinstance(value, str):
        m = re.fullmatch(r"<env:([A-Z_][A-Z0-9_]*)>", value)
        if m:
            return os.environ.get(m.group(1), "")
    return value


class SkillError(Exception):
    """Raised when configuration or environment is unusable. Caught in main()."""


def _scan_spring_yaml_paths():
    """Return candidate Spring YAML paths under CWD; ordered by likely-correctness."""
    candidates = []
    cwd = Path.cwd()
    patterns = [
        "src/main/resources/application-test.yaml",
        "src/main/resources/application-test.yml",
        "src/main/resources/application.yaml",
        "src/main/resources/application.yml",
        "**/application-test.yaml",
        "**/application-test.yml",
    ]
    for pattern in patterns:
        for p in cwd.glob(pattern):
            if p not in candidates:
                candidates.append(p)
    return candidates


def _load_from_spring_yaml(yaml_path):
    """Parse Spring Boot YAML for spring.datasource.dynamic.datasource.master."""
    if not yaml_path.exists():
        raise SkillError(f"Spring YAML not found: {yaml_path}")
    master = None
    for doc in yaml.safe_load_all(yaml_path.read_text(encoding="utf-8")):
        if not isinstance(doc, dict):
            continue
        try:
            candidate = doc["spring"]["datasource"]["dynamic"]["datasource"]["master"]
        except (KeyError, TypeError):
            continue
        if isinstance(candidate, dict) and "url" in candidate:
            master = candidate
            break
    if master is None:
        raise SkillError(
            f"Cannot locate spring.datasource.dynamic.datasource.master in {yaml_path}"
        )
    url = master["url"]
    m = re.match(r"jdbc:mysql://([^:/]+):(\d+)/([^?]+)", url)
    if not m:
        raise SkillError(f"Cannot parse JDBC url: {url}")
    return {
        "host": m.group(1),
        "port": int(m.group(2)),
        "db": m.group(3),
        "user": master["username"],
        "password": master["password"],
    }


def _load_from_dotenv(env_path):
    """Parse .env file for DB_HOST/DB_PORT/DB_USER/DB_PASSWORD/DB_NAME."""
    if not env_path.exists():
        raise SkillError(f".env not found: {env_path}")
    kv = {}
    for line in env_path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        kv[k.strip()] = v.strip().strip('"').strip("'")
    required = ["DB_HOST", "DB_PORT", "DB_USER", "DB_PASSWORD", "DB_NAME"]
    missing = [k for k in required if k not in kv]
    if missing:
        raise SkillError(f".env missing keys: {missing}")
    return {
        "host": kv["DB_HOST"],
        "port": int(kv["DB_PORT"]),
        "user": kv["DB_USER"],
        "password": kv["DB_PASSWORD"],
        "db": kv["DB_NAME"],
    }


def resolve_test_connection(config):
    """Resolve TEST environment connection params from config dict."""
    env_cfg = config["environments"]["test"]
    if not env_cfg.get("direct_execute", False):
        raise SkillError("config: TEST direct_execute must be true")

    conn_cfg = env_cfg.get("connection") or {}
    source = conn_cfg.get("source", "spring-yaml")

    if source == "spring-yaml":
        path_value = conn_cfg.get("path")
        if not path_value or path_value == "<auto-detect>":
            candidates = _scan_spring_yaml_paths()
            if not candidates:
                raise SkillError(
                    "spring-yaml auto-detect found no application*.yaml under cwd; "
                    "please set environments.test.connection.path explicitly"
                )
            if len(candidates) > 1:
                # Make ambiguity visible: warn to stderr but proceed with the first.
                others = ", ".join(str(p) for p in candidates[1:5])
                print(
                    f"[db-ops] WARNING: spring-yaml auto-detect found {len(candidates)} candidates, "
                    f"using {candidates[0]}; other candidates: {others}",
                    file=sys.stderr,
                )
            yaml_path = candidates[0]
        else:
            yaml_path = Path(path_value).expanduser()
        return _load_from_spring_yaml(yaml_path)

    if source == "dotenv":
        path_value = conn_cfg.get("path") or ".env"
        env_path = Path(path_value).expanduser()
        if not env_path.is_absolute():
            env_path = Path.cwd() / env_path
        return _load_from_dotenv(env_path)

    if source == "explicit":
        # Resolve <env:VAR> placeholders on every string field, not just user/password.
        cfg = {
            "host": _resolve_env_value(conn_cfg.get("host")),
            "port": int(_resolve_env_value(conn_cfg.get("port", 3306)) or 3306),
            "user": _resolve_env_value(conn_cfg.get("user")),
            "password": _resolve_env_value(conn_cfg.get("password")),
            "db": _resolve_env_value(conn_cfg.get("db")),
        }
        missing = [k for k, v in cfg.items() if v in (None, "")]
        if missing:
            raise SkillError(f"explicit connection missing fields: {missing}")
        return cfg

    raise SkillError(f"unknown connection.source: {source}")


# ============================================================================
# Audit log
# ============================================================================

def _audit_log(config, *, env, level, sql, result_summary):
    """Append a single line to audit log. Best-effort: failures are silent."""
    opts = config["options"]
    if not opts.get("audit_log_enabled", True):
        return
    log_path_value = opts.get("audit_log_path")
    if not log_path_value or log_path_value == "<auto-detect>":
        log_path = SKILL_DIR / "audit.log"
    else:
        log_path = Path(log_path_value).expanduser()

    try:
        sql_oneline = " ".join(sql.split())
        sql_first = sql_oneline[:120]
        sql_hash = hashlib.sha256(sql.encode("utf-8")).hexdigest()[:12]
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        line = f"{ts}\t{env}\t{level}\t{sql_hash}\t{result_summary}\t{sql_first}\n"
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass  # audit failure must never break the actual operation


# ============================================================================
# DB connection
# ============================================================================

def connect(cfg):
    return pymysql.connect(
        host=cfg["host"],
        port=cfg["port"],
        user=cfg["user"],
        password=cfg["password"],
        database=cfg["db"],
        charset="utf8mb4",
        autocommit=False,
        cursorclass=pymysql.cursors.DictCursor,
        connect_timeout=10,
        read_timeout=30,
        write_timeout=30,
    )


# ============================================================================
# SQL classification
# ============================================================================

def split_statements(sql):
    raw = sqlparse.split(sql or "")
    return [s.strip() for s in raw if s and s.strip().rstrip(";").strip()]


_SELECT_LIKE_RE = re.compile(r"^\s*(SELECT|SHOW|DESC|DESCRIBE|EXPLAIN|USE)\b", re.IGNORECASE)
_DROP_TRUNCATE_RE = re.compile(
    r"^\s*(DROP\s+(DATABASE|SCHEMA|TABLE|INDEX|VIEW|TRIGGER|FUNCTION|PROCEDURE|EVENT|USER|ROLE)|TRUNCATE)\b",
    re.IGNORECASE,
)
_ALTER_CREATE_RE = re.compile(r"^\s*(ALTER|CREATE|RENAME)\b", re.IGNORECASE)
_REPLACE_RE = re.compile(r"^\s*REPLACE\b", re.IGNORECASE)
_WITH_RE = re.compile(r"^\s*WITH\b", re.IGNORECASE)
_WITH_DML_RE = re.compile(r"\b(DELETE|UPDATE|INSERT|MERGE)\b", re.IGNORECASE)
_PROCEDURAL_RE = re.compile(
    r"^\s*(CALL|EXECUTE|EXEC|DEALLOCATE|PREPARE|HANDLER)\b", re.IGNORECASE
)
_SYSTEM_RE = re.compile(r"^\s*(SET|LOCK|UNLOCK|FLUSH|RESET|KILL|ANALYZE|OPTIMIZE|REPAIR|CHECK)\b", re.IGNORECASE)
_LOAD_DATA_RE = re.compile(r"^\s*LOAD\s+DATA\b", re.IGNORECASE)
_WHERE_RE = re.compile(r"\bWHERE\b", re.IGNORECASE)
# DELETE multi-table: `DELETE t1 [,t2] FROM t1 JOIN t2 ...` or `DELETE FROM t1 USING ...`
_DELETE_FROM_RE = re.compile(r"^\s*DELETE\s+(?:[\w`,\s]+?\s+)?FROM\s+", re.IGNORECASE)


def classify(sql):
    """Pure static risk classification.

    Returns dict with: level, reasons, stmt_type, has_where.
    """
    stmts = split_statements(sql)
    if not stmts:
        return {"level": "INVALID", "reasons": ["empty SQL"]}
    if len(stmts) > 1:
        return {
            "level": "CRITICAL",
            "reasons": [f"multi-statement ({len(stmts)} statements)"],
            "stmt_type": "MULTI",
            "has_where": False,
        }

    stmt = stmts[0]
    parsed = sqlparse.parse(stmt)
    if not parsed:
        return {"level": "INVALID", "reasons": ["parse failure"]}

    stmt_type = parsed[0].get_type() or "UNKNOWN"

    # CTE: WITH ... [SELECT|UPDATE|DELETE|INSERT|MERGE]
    if _WITH_RE.match(stmt):
        if _WITH_DML_RE.search(stmt):
            return {
                "level": "HIGH",
                "reasons": ["CTE wrapping DML (WITH ... DELETE/UPDATE/INSERT/MERGE)"],
                "stmt_type": "CTE_DML",
                "has_where": bool(_WHERE_RE.search(stmt)),
            }
        return {"level": "LOW", "reasons": ["CTE read-only"], "stmt_type": "CTE_SELECT", "has_where": False}

    if _SELECT_LIKE_RE.match(stmt):
        return {"level": "LOW", "reasons": ["read-only"], "stmt_type": "SELECT", "has_where": False}

    if _DROP_TRUNCATE_RE.match(stmt):
        return {
            "level": "CRITICAL",
            "reasons": ["DROP/TRUNCATE (irreversible DDL)"],
            "stmt_type": "DDL",
            "has_where": False,
        }

    if _ALTER_CREATE_RE.match(stmt):
        return {"level": "HIGH", "reasons": ["schema-changing DDL"], "stmt_type": "DDL", "has_where": False}

    if _LOAD_DATA_RE.match(stmt):
        return {"level": "HIGH", "reasons": ["LOAD DATA (bulk import)"], "stmt_type": "LOAD", "has_where": False}

    if _PROCEDURAL_RE.match(stmt):
        # Stored procedures can do anything; user must explicitly consent.
        return {
            "level": "CRITICAL",
            "reasons": ["procedural call (CALL/EXECUTE/HANDLER) — opaque side-effects"],
            "stmt_type": "PROCEDURAL",
            "has_where": False,
        }

    if _SYSTEM_RE.match(stmt):
        return {
            "level": "MEDIUM",
            "reasons": ["session/system statement (SET/LOCK/FLUSH/...)"],
            "stmt_type": "SYSTEM",
            "has_where": False,
        }

    has_where = bool(_WHERE_RE.search(stmt))

    if stmt_type == "UPDATE":
        if has_where:
            return {"level": "MEDIUM", "reasons": ["UPDATE with WHERE"], "stmt_type": "UPDATE", "has_where": True}
        return {"level": "CRITICAL", "reasons": ["UPDATE without WHERE"], "stmt_type": "UPDATE", "has_where": False}

    if stmt_type == "DELETE":
        if has_where:
            return {"level": "HIGH", "reasons": ["DELETE with WHERE"], "stmt_type": "DELETE", "has_where": True}
        return {"level": "CRITICAL", "reasons": ["DELETE without WHERE"], "stmt_type": "DELETE", "has_where": False}

    if stmt_type == "INSERT" or _REPLACE_RE.match(stmt):
        return {
            "level": "MEDIUM",
            "reasons": [f"{stmt_type or 'REPLACE'} statement"],
            "stmt_type": stmt_type or "REPLACE",
            "has_where": False,
        }

    return {"level": "INVALID", "reasons": [f"unrecognized statement type: {stmt_type}"]}


# ============================================================================
# Dry-run estimation (TEST only)
# ============================================================================

def _estimate_test(sql, cls, cfg, options):
    """Connect to TEST DB and try to estimate rows + sample rows. Always rollback.

    Diagnostic info goes into cls['_dry_run_diagnostic'] (NOT cls['reasons'])
    so banner 'reasons' field stays purely about business risk.
    """
    stmt_type = cls.get("stmt_type")
    sql_one = sql.rstrip().rstrip(";").strip()
    estimated_rows = None
    sample_rows = []
    diagnostic = None
    sample_limit = options.get("dry_run_sample_rows", 20)

    try:
        conn = connect(cfg)
    except Exception as e:
        return None, [], f"connect failed: {type(e).__name__}: {e}"

    try:
        with conn.cursor() as cur:
            if stmt_type in ("SELECT", "CTE_SELECT"):
                try:
                    cur.execute("EXPLAIN " + sql_one)
                    explained = cur.fetchall()
                    estimated_rows = sum(int(r.get("rows") or 0) for r in explained)
                except Exception as e:
                    diagnostic = f"EXPLAIN skipped: {type(e).__name__}: {e}"
            elif stmt_type in ("UPDATE", "DELETE") and cls.get("has_where"):
                conn.begin()
                try:
                    if stmt_type == "DELETE":
                        snap = _DELETE_FROM_RE.sub("SELECT * FROM ", sql_one, count=1)
                        if snap != sql_one:  # substitution actually happened
                            try:
                                cur.execute(snap.rstrip(";") + f" LIMIT {int(sample_limit)}")
                                sample_rows = list(cur.fetchall())
                            except Exception as e:
                                diagnostic = f"sample query failed: {type(e).__name__}: {e}"
                    cur.execute(sql_one)
                    estimated_rows = cur.rowcount
                except Exception as e:
                    diagnostic = f"dry-run failed: {type(e).__name__}: {e}"
                finally:
                    try:
                        conn.rollback()
                    except Exception:
                        pass
            # DDL/SYSTEM/PROCEDURAL/LOAD/CTE_DML: skip dry-run
    finally:
        try:
            conn.close()
        except Exception:
            pass
    return estimated_rows, sample_rows, diagnostic


# ============================================================================
# Public commands
# ============================================================================

def analyze(sql, env, config):
    cls = classify(sql)
    if cls["level"] == "INVALID":
        cls["estimated_rows"] = None
        cls["dry_run_sample_rows"] = []
        cls["dry_run_diagnostic"] = None
        cls["needs_phrase"] = False
        return cls

    if env == "test":
        cfg = resolve_test_connection(config)
        est, sample, diag = _estimate_test(sql, cls, cfg, config["options"])
        cls["estimated_rows"] = est
        cls["dry_run_sample_rows"] = sample
        # Large SELECT warning goes into diagnostic, NOT reasons
        # (reasons must stay purely about business risk, not informational notes).
        warn_threshold = config["options"].get("large_select_warn_rows", 1_000_000)
        if cls.get("stmt_type") in ("SELECT", "CTE_SELECT") and est and est > warn_threshold:
            warn = f"large result set (estimated {est} rows > {warn_threshold})"
            diag = f"{diag}; {warn}" if diag else warn
        cls["dry_run_diagnostic"] = diag
    else:
        cls["estimated_rows"] = None
        cls["dry_run_sample_rows"] = []
        cls["dry_run_diagnostic"] = None

    cls["needs_phrase"] = cls["level"] == "CRITICAL"
    return cls


def exec_test(sql, cfg, config):
    """Execute on TEST DB. Returns dict with affected_rows / rows / elapsed_ms.

    SELECT-style statements populate `rows` and `row_count` (= len(rows));
    DML statements populate `affected_rows` (sum of rowcount for INSERT/UPDATE/DELETE).
    Mixing the two is avoided to keep semantics clean.
    """
    stmts = split_statements(sql)
    if not stmts:
        return {"error": "empty SQL"}
    max_rows = config["options"].get("exec_max_rows", 2000)
    conn = connect(cfg)
    start = time.time()
    affected_rows = 0
    rows = []
    truncated = False
    try:
        conn.begin()
        with conn.cursor() as cur:
            for stmt in stmts:
                cur.execute(stmt)
                if cur.description:  # SELECT-like: produces a result set
                    fetched = list(cur.fetchall())
                    if len(fetched) > max_rows:
                        truncated = True
                    rows = fetched[:max_rows]
                else:  # DML: rowcount = affected rows
                    affected_rows += cur.rowcount if cur.rowcount is not None else 0
        conn.commit()
    except Exception as e:
        try:
            conn.rollback()
        except Exception:
            pass
        return {"error": f"{type(e).__name__}: {e}"}
    finally:
        try:
            conn.close()
        except Exception:
            pass
    elapsed_ms = int((time.time() - start) * 1000)
    return {
        "affected_rows": affected_rows,
        "rows": rows,
        "row_count": len(rows),
        "truncated": truncated,
        "elapsed_ms": elapsed_ms,
    }


def render_prod(sql, config):
    cls = classify(sql)
    level = cls["level"]
    reasons = ", ".join(cls.get("reasons", []))
    emoji = RISK_EMOJI.get(level, "⚠️")
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    audit_id = uuid.uuid4().hex[:8]
    body = sql.strip()
    if not body.rstrip().endswith(";"):
        body = body.rstrip() + ";"
    prod_cfg = config["environments"]["prod"]
    target_tool = prod_cfg.get("sql_executor_tool", "DMS https://dms.aliyun.com/")
    rollback_hint = prod_cfg.get("rollback_hint", "binlog")

    return (
        "-- ════════════════════════════════════════════════════════════\n"
        f"-- 🔥 目标环境: PROD ({target_tool})\n"
        f"-- {emoji}  风险等级: {level}\n"
        f"-- 风险原因: {reasons}\n"
        "-- 预估影响行数: 无法评估(未连接 PROD)\n"
        f"-- 生成时间: {now}\n"
        f"-- 生成者: db-ops skill (audit-id: {audit_id})\n"
        "--\n"
        "-- ⚠ 执行前请在执行工具中:\n"
        "--   1. 先用 SELECT 版本确认受影响数据\n"
        "--   2. 开启事务 / 工单审核\n"
        f"--   3. 保留 {rollback_hint} 位置以便回滚\n"
        "-- ════════════════════════════════════════════════════════════\n\n"
        f"{body}\n"
    )


# ============================================================================
# CLI
# ============================================================================

def _dump(obj):
    print(json.dumps(obj, ensure_ascii=False, default=str))
    sys.stdout.flush()


def main():
    ap = argparse.ArgumentParser(prog="db_ops")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_an = sub.add_parser("analyze", help="classify SQL risk + (test) dry-run estimate")
    p_an.add_argument("--sql", required=True)
    p_an.add_argument("--env", choices=["test", "prod"], default="test")

    p_ex = sub.add_parser("exec-test", help="execute SQL on TEST DB (non-CRITICAL)")
    p_ex.add_argument("--sql", required=True)

    p_exc = sub.add_parser("exec-test-critical", help="execute CRITICAL SQL on TEST DB with phrase")
    p_exc.add_argument("--sql", required=True)
    p_exc.add_argument("--phrase", required=True)

    p_pr = sub.add_parser("render-prod", help="render PROD SQL text with risk comment header")
    p_pr.add_argument("--sql", required=True)

    sub.add_parser("self-check", help="validate config + connection (smoke test)")

    args = ap.parse_args()

    try:
        config = load_config()

        if args.cmd == "analyze":
            result = analyze(args.sql, args.env, config)
            _audit_log(config, env=args.env, level=result.get("level", "?"),
                       sql=args.sql, result_summary=f"analyze level={result.get('level')}")
            _dump(result)

        elif args.cmd == "exec-test":
            cls = classify(args.sql)
            if cls["level"] == "CRITICAL":
                _audit_log(config, env="test", level="CRITICAL", sql=args.sql,
                           result_summary="exec-test REJECTED: CRITICAL routed to wrong subcommand")
                _dump({"error": "CRITICAL level requires exec-test-critical with phrase"})
                sys.exit(2)
            cfg = resolve_test_connection(config)
            result = exec_test(args.sql, cfg, config)
            _audit_log(
                config, env="test", level=cls["level"], sql=args.sql,
                result_summary=(
                    f"exec-test affected={result.get('affected_rows', 0)} "
                    f"rows={result.get('row_count', 0)} ms={result.get('elapsed_ms', '?')}"
                    if "error" not in result else f"exec-test ERROR: {result['error']}"
                ),
            )
            _dump(result)

        elif args.cmd == "exec-test-critical":
            if args.phrase != "yes execute on TEST":
                _audit_log(config, env="test", level="CRITICAL", sql=args.sql,
                           result_summary="exec-test-critical REJECTED: phrase mismatch")
                _dump({"error": "phrase mismatch, operation aborted"})
                sys.exit(2)
            cls = classify(args.sql)
            cfg = resolve_test_connection(config)
            result = exec_test(args.sql, cfg, config)
            _audit_log(
                config, env="test", level=cls["level"], sql=args.sql,
                result_summary=(
                    f"exec-test-critical affected={result.get('affected_rows', 0)} "
                    f"rows={result.get('row_count', 0)} ms={result.get('elapsed_ms', '?')}"
                    if "error" not in result else f"exec-test-critical ERROR: {result['error']}"
                ),
            )
            _dump(result)

        elif args.cmd == "render-prod":
            text = render_prod(args.sql, config)
            cls = classify(args.sql)
            _audit_log(config, env="prod", level=cls["level"], sql=args.sql,
                       result_summary="render-prod (text only, not executed)")
            print(text)

        elif args.cmd == "self-check":
            envs = list(config["environments"].keys())
            try:
                cfg = resolve_test_connection(config)
                conn = connect(cfg)
                conn.close()
                _dump({"ok": True, "environments": envs, "test_connection": "ok",
                       "audit_log": str(SKILL_DIR / "audit.log")})
            except Exception as e:
                _dump({"ok": False, "environments": envs,
                       "test_connection": f"FAIL: {type(e).__name__}: {e}"})

    except SkillError as e:
        _dump({"error": f"config: {e}"})
        sys.exit(1)


if __name__ == "__main__":
    main()
