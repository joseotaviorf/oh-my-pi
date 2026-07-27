"""Dual-syntax assertions for dags/.airflowignore.

Every consumer of the file (data_ai dev/forno/prod deployments, local `astro/`)
sets AIRFLOW__CORE__DAG_IGNORE_FILE_SYNTAX=glob, so the glob patterns are the
effective ones; the regexp guard only matters if a deployment ever loses that
setting. Migration DAGs must stay ignored under BOTH syntaxes, and the validation
twin glob must stay OUT of the file so prod keeps parsing those DQ DAGs.
"""

from __future__ import annotations

from pathlib import Path

import pytest
from airflow.utils.file import _GlobIgnoreRule, _RegexpIgnoreRule

REPO_ROOT = Path(__file__).resolve().parents[2]
DAGS_BASE = REPO_ROOT / "dags"
AIRFLOWIGNORE = DAGS_BASE / ".airflowignore"

MIGRATION_TWIN = (
    DAGS_BASE
    / "platform/migration_twin_agents__dw_agent_accreditation"
    / "migration_twin_agents__dw_agent_accreditation_dag.py"
)
MIGRATION_EMR = (
    DAGS_BASE
    / "platform/migration_emr_agents__dw_agent_accreditation"
    / "migration_emr_agents__dw_agent_accreditation_dag.py"
)
MIGRATION_COMPARE = (
    DAGS_BASE
    / "platform/migration_compare_agents__dw_agent_accreditation"
    / "migration_compare_agents__dw_agent_accreditation_dag.py"
)
VALIDATION_STUB = DAGS_BASE / "people/dw_employee/dw_employee_validation_dag.py"
NORMAL_DAG = DAGS_BASE / "people/dw_employee/dw_employee_dag.py"

GLOB_MIGRATION_PATTERNS = (
    "platform/migration_twin_*/",
    "platform/migration_emr_*/",
    "platform/migration_compare_*/",
)
REGEXP_MIGRATION_PATTERN = "platform/migration_(twin|emr|compare)_"
VALIDATION_GLOB = "*_validation_dag.py"


def _active_patterns() -> list[str]:
    """Non-comment, non-blank lines — the patterns Airflow actually compiles."""
    return [
        line.strip()
        for line in AIRFLOWIGNORE.read_text().splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def _compile_rules(rule_cls, patterns: tuple[str, ...] | list[str]):
    rules = []
    for pat in patterns:
        rule = rule_cls.compile(pat, DAGS_BASE, AIRFLOWIGNORE)
        if rule is not None:
            rules.append(rule)
    return rules


def _matches(rule_cls, patterns, path: Path) -> bool:
    rules = _compile_rules(rule_cls, patterns)
    if not rules:
        return False
    return rule_cls.match(path, rules)


@pytest.mark.parametrize(
    "path",
    [MIGRATION_TWIN, MIGRATION_EMR, MIGRATION_COMPARE],
    ids=["twin", "emr", "compare"],
)
def test_glob_migration_patterns_ignore_migration_dags(path: Path):
    assert _matches(_GlobIgnoreRule, GLOB_MIGRATION_PATTERNS, path)


@pytest.mark.parametrize(
    "path",
    [MIGRATION_TWIN, MIGRATION_EMR, MIGRATION_COMPARE],
    ids=["twin", "emr", "compare"],
)
def test_regexp_guard_ignores_migration_dags(path: Path):
    assert _matches(_RegexpIgnoreRule, [REGEXP_MIGRATION_PATTERN], path)


def test_regexp_guard_is_inert_under_glob():
    """Parens are literal under glob — the regexp guard must not match as a glob."""
    assert not _matches(_GlobIgnoreRule, [REGEXP_MIGRATION_PATTERN], MIGRATION_TWIN)


def test_validation_glob_absent_so_prod_keeps_validation_dags():
    """The pattern would match under glob — every consumer is on glob, so it must
    not be in the file, otherwise prod silently loses its validation twins."""
    assert _matches(_GlobIgnoreRule, [VALIDATION_GLOB], VALIDATION_STUB)
    assert VALIDATION_GLOB not in _active_patterns()
    assert not _matches(_GlobIgnoreRule, _active_patterns(), VALIDATION_STUB)


def test_normal_dag_not_ignored_by_migration_or_validation_patterns():
    assert not _matches(_GlobIgnoreRule, GLOB_MIGRATION_PATTERNS, NORMAL_DAG)
    assert not _matches(_RegexpIgnoreRule, [REGEXP_MIGRATION_PATTERN], NORMAL_DAG)
    assert not _matches(_GlobIgnoreRule, [VALIDATION_GLOB], NORMAL_DAG)


def test_airflowignore_file_contains_dual_syntax_guard():
    patterns = _active_patterns()
    assert REGEXP_MIGRATION_PATTERN in patterns
    for pat in GLOB_MIGRATION_PATTERNS:
        assert pat in patterns
