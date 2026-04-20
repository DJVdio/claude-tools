"""Unit tests for db_ops.classify().

Run from repo root:
    cd ~/.claude/skills/db-ops
    python3 -m pytest tests/ -v

Covers:
- SKILL.md manual checklist (6 cases)
- Round 1 review findings (CTE, DROP TRIGGER, multi-table DELETE, REPLACE,
  PROCEDURAL, SYSTEM, LOAD DATA)
- Boundary cases (empty, multi-statement, malformed)
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import pytest  # noqa: E402

from db_ops import classify, split_statements, _DELETE_FROM_RE  # noqa: E402


# ---------------------------------------------------------------------------
# SKILL.md manual checklist (6 cases)
# ---------------------------------------------------------------------------

def test_select_low():
    r = classify("SELECT * FROM sys_menu LIMIT 5")
    assert r["level"] == "LOW"
    assert r["stmt_type"] == "SELECT"


def test_update_with_where_medium():
    r = classify("UPDATE sys_menu SET name='x' WHERE id=1")
    assert r["level"] == "MEDIUM"
    assert r["stmt_type"] == "UPDATE"
    assert r["has_where"] is True


def test_delete_with_where_high():
    r = classify("DELETE FROM sys_menu WHERE parent_id=-999")
    assert r["level"] == "HIGH"
    assert r["stmt_type"] == "DELETE"
    assert r["has_where"] is True


def test_delete_no_where_critical():
    r = classify("DELETE FROM sys_menu")
    assert r["level"] == "CRITICAL"
    assert r["stmt_type"] == "DELETE"


def test_update_no_where_critical():
    r = classify("UPDATE sys_menu SET deleted=1")
    assert r["level"] == "CRITICAL"


def test_truncate_critical():
    r = classify("TRUNCATE TABLE sys_menu")
    assert r["level"] == "CRITICAL"


# ---------------------------------------------------------------------------
# Round 1 review findings — DROP coverage
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("sql", [
    "DROP DATABASE foo",
    "DROP SCHEMA foo",
    "DROP TABLE foo",
    "DROP INDEX i ON t",
    "DROP VIEW v",
    "DROP TRIGGER tr",
    "DROP FUNCTION f",
    "DROP PROCEDURE p",
    "DROP EVENT e",
    "DROP USER 'u'@'%'",
    "DROP ROLE r",
])
def test_drop_all_subtypes_critical(sql):
    r = classify(sql)
    assert r["level"] == "CRITICAL", f"{sql} should be CRITICAL but got {r}"


# ---------------------------------------------------------------------------
# Round 1 review findings — CTE/WITH
# ---------------------------------------------------------------------------

def test_cte_select_low():
    r = classify("WITH c AS (SELECT id FROM t) SELECT * FROM c")
    assert r["level"] == "LOW"
    assert r["stmt_type"] == "CTE_SELECT"


def test_cte_with_delete_high():
    r = classify(
        "WITH c AS (SELECT id FROM t WHERE x=1) DELETE FROM target WHERE id IN (SELECT id FROM c)"
    )
    assert r["level"] == "HIGH"
    assert r["stmt_type"] == "CTE_DML"


def test_cte_with_update_high():
    r = classify("WITH c AS (SELECT id FROM t) UPDATE target SET v=1 WHERE id IN (SELECT id FROM c)")
    assert r["level"] == "HIGH"


# ---------------------------------------------------------------------------
# Round 1 review findings — DELETE multi-table syntax
# ---------------------------------------------------------------------------

def test_delete_multi_table_with_where_high():
    """`DELETE t1 FROM t1 JOIN t2 ON ... WHERE ...` — bug fix verification."""
    r = classify("DELETE t1 FROM t1 JOIN t2 ON t1.id=t2.id WHERE t2.flag=1")
    assert r["level"] == "HIGH"
    assert r["has_where"] is True


def test_delete_multi_table_no_where_critical():
    r = classify("DELETE t1 FROM t1 JOIN t2 ON t1.id=t2.id")
    assert r["level"] == "CRITICAL"


def test_delete_from_regex_handles_alias():
    """Verify the regex used by _estimate_test for DELETE→SELECT snapshot."""
    sql_one = "DELETE t1 FROM t1 JOIN t2 ON t1.id=t2.id WHERE t2.flag=1"
    snap = _DELETE_FROM_RE.sub("SELECT * FROM ", sql_one, count=1)
    assert snap.upper().startswith("SELECT * FROM")


def test_delete_from_regex_simple():
    sql_one = "DELETE FROM sys_menu WHERE id=1"
    snap = _DELETE_FROM_RE.sub("SELECT * FROM ", sql_one, count=1)
    assert snap.upper().startswith("SELECT * FROM")


# ---------------------------------------------------------------------------
# Round 1 review findings — PROCEDURAL / SYSTEM / LOAD DATA
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("sql", [
    "CALL my_proc(1, 2)",
    "EXECUTE stmt USING @a",
    "EXEC sp_help",
    "HANDLER tbl READ FIRST",
])
def test_procedural_critical(sql):
    r = classify(sql)
    assert r["level"] == "CRITICAL"
    assert r["stmt_type"] == "PROCEDURAL"


@pytest.mark.parametrize("sql", [
    "SET SESSION max_execution_time=5000",
    "LOCK TABLES t WRITE",
    "UNLOCK TABLES",
    "FLUSH PRIVILEGES",
    "RESET MASTER",
    "KILL 12345",
])
def test_system_medium(sql):
    r = classify(sql)
    assert r["level"] == "MEDIUM"
    assert r["stmt_type"] == "SYSTEM"


def test_load_data_high():
    r = classify("LOAD DATA INFILE '/tmp/x.csv' INTO TABLE t")
    assert r["level"] == "HIGH"


# ---------------------------------------------------------------------------
# REPLACE & INSERT
# ---------------------------------------------------------------------------

def test_insert_medium():
    r = classify("INSERT INTO t (a, b) VALUES (1, 2)")
    assert r["level"] == "MEDIUM"
    assert r["stmt_type"] == "INSERT"


def test_replace_medium():
    r = classify("REPLACE INTO t (a, b) VALUES (1, 2)")
    assert r["level"] == "MEDIUM"


# ---------------------------------------------------------------------------
# DDL ALTER/CREATE/RENAME
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("sql", [
    "ALTER TABLE t ADD COLUMN c INT",
    "CREATE TABLE t (id INT)",
    "CREATE INDEX i ON t (c)",
    "RENAME TABLE t TO t2",
])
def test_ddl_high(sql):
    r = classify(sql)
    assert r["level"] == "HIGH"
    assert r["stmt_type"] == "DDL"


# ---------------------------------------------------------------------------
# SELECT-like family
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("sql", [
    "SHOW TABLES",
    "DESC sys_menu",
    "DESCRIBE sys_menu",
    "EXPLAIN SELECT * FROM t",
    "USE crm_syb",
])
def test_select_like_low(sql):
    r = classify(sql)
    assert r["level"] == "LOW"


# ---------------------------------------------------------------------------
# Boundary cases
# ---------------------------------------------------------------------------

def test_empty_invalid():
    r = classify("")
    assert r["level"] == "INVALID"


def test_whitespace_only_invalid():
    r = classify("   \n\t  ;  ")
    assert r["level"] == "INVALID"


def test_multi_statement_critical():
    r = classify("SELECT 1; DELETE FROM t;")
    assert r["level"] == "CRITICAL"
    assert r["stmt_type"] == "MULTI"


def test_multi_statement_count_in_reasons():
    r = classify("SELECT 1; SELECT 2; SELECT 3;")
    assert r["level"] == "CRITICAL"
    assert "3 statements" in r["reasons"][0]


def test_split_statements_strips_empties():
    assert split_statements("SELECT 1;;;SELECT 2;") == ["SELECT 1", "SELECT 2"]


# ---------------------------------------------------------------------------
# Comment / case insensitivity smoke tests
# ---------------------------------------------------------------------------

def test_lowercase_select_low():
    r = classify("select * from t where x=1")
    assert r["level"] == "LOW"


def test_mixed_case_drop_critical():
    r = classify("DrOp TaBlE foo")
    assert r["level"] == "CRITICAL"
