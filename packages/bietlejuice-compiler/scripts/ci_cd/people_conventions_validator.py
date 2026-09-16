"""People domain repository guard rails for dags/people/** and dags/enterprise_efficiency/**.

Enforces conventions from people_data_quality.mdc and people_metadata.mdc that are
not covered by repo-wide validators:

* Mandatory data_quality YAML for clean+ query/metadata pairs — use
  ``validate_people_data_quality_files_exist.py`` (generic pairing gate).
* Data-quality severity rules and required clean-layer has_size_variation.
* Intent comments on custom DQ checks.
* SQL SELECT column order vs metadata columns block order.
* Grain documentation (``One row per``) for modeled enrich/dw/metric tables.
* Subqueries in FROM — prefer named CTEs (sql_conventions.mdc).
* Deprecated upstream schemas in SQL (legacy DAG folders exempt).

Dual-runtime and join-shape SQL gates stay in the repo-wide CI steps
(``validate-databricks-sql-constructs``, ``validate-join-shapes``).

Usage (CI — one check group per Woodpecker step):
    python people_conventions_validator.py --check dq -b "$CI_COMMIT_BRANCH"
    python people_conventions_validator.py --check sql-metadata -b "$CI_COMMIT_BRANCH"
    python people_conventions_validator.py --check sql-style -b "$CI_COMMIT_BRANCH"

Usage (local — all groups):
    python people_conventions_validator.py --check all -b "$(git branch --show-current)"
    python people_conventions_validator.py --check all -a
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Literal, Optional, Sequence, Set, Tuple

import yaml
from sqlglot import exp, parse_one

from bietlejuice.ci.ci_diff_ref import resolve_diff_from_ref
from scripts.ci_cd.domain_cli import (
    branch_name_arg_type,
    repo_relative_file_arg_type,
)
from scripts.ci_cd.people_deprecated_sources import (
    find_deprecated_source_hits,
    hint_for_label,
    is_legacy_dag_exempt,
)
from scripts.ci_cd.people_domain_scope import (
    SCOPE_PATHS_HELP,
    dq_path_for_metadata,
    dq_path_for_sql,
    expand_scoped_paths,
    is_scoped_domain_path,
    iter_scoped_domain_roots,
    metadata_path_for_sql,
)
from scripts.governance_metadata_validation.validate_lineage_consistency import (
    normalize_sql,
)
from scripts.services.git_service import GitService

CheckGroup = Literal[
    "dq",
    "sql-metadata",
    "sql-style",
    "deprecated-sources",
    "all",
]
CHECK_GROUPS: Tuple[CheckGroup, ...] = (
    "dq",
    "sql-metadata",
    "sql-style",
    "deprecated-sources",
    "all",
)

PEOPLE_PREFIX = "dags/people/"  # legacy alias for tests importing this module
_DQ_LAYER_RE = re.compile(r"/data_quality/(?P<layer>[^/]+)/")
_DQ_FILE_RE = re.compile(r"/data_quality/[^/]+/[^/]+\.yml$")
_ONE_ROW_PER_RE = re.compile(r"^one_row_per_", re.IGNORECASE)
_GRAIN_PHRASE_RE = re.compile(r"one row per", re.IGNORECASE)
_FROM_SUBQUERY_RE = re.compile(
    r"\bFROM\s*\(\s*SELECT\b",
    re.IGNORECASE | re.DOTALL,
)

_SK_COLUMN_RE = re.compile(r"^sk_", re.IGNORECASE)
_DEFAULT_SIZE_VARIATION_BOUNDS = (-10, 25)

_CHECK_FIX_HINTS: Dict[str, str] = {
    "dq_severity_order": (
        "Move `severity_level` to the last key in the Inmetro check block "
        "(after thresholds and `constraint`)."
    ),
    "dq_has_size_floor": (
        "Set `has_size.greater_than: 1` only. Use `has_size_variation` for row-count drift."
    ),
    "dq_severity": (
        "Use `severity_level: Warning` unless the check is an allowed Error case "
        "(has_size with greater_than: 1, clean has_size_variation, sk_* complete/unique, "
        "or one_row_per_* custom grain checks). See people_data_quality.mdc §1."
    ),
    "dq_custom_comment": (
        "Add a `# ...` comment on the line above the `custom:` block describing the "
        "business rule the SQL enforces."
    ),
    "dq_size_variation_bounds": (
        "Add a `# ...` comment on the line above `has_size_variation:` explaining why "
        "bounds differ from the default -10 / +25, or restore the default bounds."
    ),
    "dq_has_size_variation": (
        "Add `table_level_validations.has_size_variation` on clean tables "
        "(Error, variation_type: percentage, gte: -10, lte: 25 unless commented)."
    ),
    "dq_grain_severity": (
        "Set `severity_level: Error` on `one_row_per_*` custom grain checks."
    ),
    "dq_parse": "Fix YAML syntax or encoding so the file loads as a single mapping.",
    "metadata_pair": (
        "Create the missing metadata YAML beside `metadata/{layer}/{table}.yml` "
        "(run `make validate-metadata-files-exist` for the repo-wide pairing gate)."
    ),
    "column_order": (
        "Reorder the SQL SELECT list to match the `columns:` block in metadata "
        "(Kimball order: IDs → UUIDs → …; see naming_cheatsheet.mdc)."
    ),
    "grain_documentation": (
        "Add a grain sentence to `description`, e.g. "
        "`One row per person_number per calendar day.`"
    ),
    "subquery_in_from": (
        "Lift the inner SELECT into a `WITH <name> AS (...)` CTE and reference "
        "`<name>` in `FROM`."
    ),
    "subquery": "Ensure the SQL file is readable UTF-8 text.",
    "deprecated_source": (
        "Replace the deprecated schema with the successor noted in the error message "
        "(pin_* clean, datalake_people, greenhouse_v3, etc.)."
    ),
}


def _fix_hint_for_check(check: str) -> Optional[str]:
    if check in _CHECK_FIX_HINTS:
        return _CHECK_FIX_HINTS[check]
    if check.startswith("deprecated_source:"):
        return _CHECK_FIX_HINTS["deprecated_source"]
    return None


def _remediation_footer(group: CheckGroup) -> str:
    local_targets = {
        "dq": (
            "make validate-people-dq-conventions "
            "paths=dags/people/<dag>  # or dags/enterprise_efficiency/<dag>"
        ),
        "sql-metadata": (
            "make validate-people-sql-metadata-conventions paths=dags/people/<dag>"
        ),
        "sql-style": (
            "make validate-people-sql-style-conventions paths=dags/people/<dag>"
        ),
        "deprecated-sources": (
            "make validate-people-deprecated-sources-conventions "
            "paths=dags/people/<dag>"
        ),
        "all": "make validate-people-conventions paths=dags/people/<dag>",
    }
    lines = [
        "",
        "How to fix:",
        f"  • Local rerun: {local_targets[group]}",
        "  • DQ severity & checks: .cursor/rules/people/people_data_quality.mdc",
        "  • Column order & grain: .cursor/rules/people/people_metadata.mdc",
        "  • Missing data_quality YAML: make validate-people-data-quality-files-exist "
        "paths=dags/people/<dag>",
    ]
    return "\n".join(lines)


@dataclass(frozen=True)
class Finding:
    """Single convention violation reported to CI or local runs."""

    filepath: str
    check: str
    message: str
    line_no: Optional[int] = None
    fix: Optional[str] = None

    def format(self) -> str:
        """Return a human-readable line for stderr with an optional fix hint."""
        location = (
            f"{self.filepath}:{self.line_no}"
            if self.line_no is not None
            else self.filepath
        )
        fix = self.fix or _fix_hint_for_check(self.check)
        base = f"  {location}: [{self.check}] {self.message}"
        if fix:
            return f"{base}\n      → Fix: {fix}"
        return base


def get_changed_files(branch: str, suffix: str = "") -> List[Path]:
    """List upserted files under scoped domains in the branch diff vs merge base.

    CI validates only what the PR changes so authors fix their own regressions
    without blocking unrelated legacy debt elsewhere in the monorepo.
    """
    git_service = GitService()
    from_ref = resolve_diff_from_ref(branch)
    diff: Dict[str, str] = git_service.get_modified_files_from_diff(from_ref, "HEAD")
    paths: List[Path] = []
    for filepath, status in diff.items():
        if status not in git_service.UPSERT_STATUS_CODES:
            continue
        if not is_scoped_domain_path(filepath):
            continue
        if suffix and not filepath.endswith(suffix):
            continue
        paths.append(Path(filepath))
    return paths


def _is_dq_yaml(path: Path) -> bool:
    """Return True when ``path`` is a table ``data_quality/{layer}/{table}.yml`` file.

    Ignores manifest sidecars so CI does not treat non-table YAML as DQ configs.
    """
    normalized = str(path).replace("\\", "/")
    return bool(_DQ_FILE_RE.search(normalized))


def expand_people_paths(raw_paths: Sequence[str]) -> List[Path]:
    """Expand scoped DAG path arguments to concrete files (backward-compatible alias)."""
    return expand_scoped_paths(raw_paths)


def _dq_layer_from_path(path: str) -> Optional[str]:
    """Extract the pipeline layer (clean, enrich, dw, …) from a ``data_quality`` path."""
    match = _DQ_LAYER_RE.search(path.replace("\\", "/"))
    return match.group("layer") if match else None


def _severity_is_last(params: dict) -> bool:
    """Return True when ``severity_level`` is the last key in an Inmetro check block.

    ``people_data_quality.mdc`` requires this ordering so reviewers can scan
    thresholds before the severity decision at the end of each block.
    """
    if not params:
        return True
    keys = list(params.keys())
    return keys[-1] == "severity_level"


def _check_block_findings(
    filepath: str,
    layer: str,
    block_name: str,
    column_key: str,
    check_name: str,
    params: dict,
) -> List[Finding]:
    """Validate ``severity_level: Error`` usage for a single Inmetro check block.

    People DQ limits Error to emptiness floors, clean volume drift, ``sk_*``
    completeness/uniqueness, and ``one_row_per_*`` grain checks. Everything else
    must be Warning so PEOPLE_ALERTS stays actionable instead of paging on
    expected source noise or DW modeling drift.
    """
    findings: List[Finding] = []
    if not isinstance(params, dict):
        return findings

    severity = params.get("severity_level")
    if severity is None:
        return findings

    severity_norm = str(severity).strip().lower()
    is_error = severity_norm == "error"

    if not _severity_is_last(params):
        findings.append(
            Finding(
                filepath,
                "dq_severity_order",
                f"{block_name}.{column_key}.{check_name}: "
                "severity_level must be the last key in the check block",
            )
        )

    if not is_error:
        return findings

    allowed_error = False
    if check_name == "has_size":
        gt = params.get("greater_than")
        if gt is None:
            findings.append(
                Finding(
                    filepath,
                    "dq_has_size_floor",
                    f"{block_name}.{column_key}.{check_name}: "
                    "greater_than: 1 is required when severity_level is Error",
                )
            )
        elif gt != 1:
            findings.append(
                Finding(
                    filepath,
                    "dq_has_size_floor",
                    f"{block_name}.{column_key}.{check_name}: "
                    f"greater_than must be 1 (found {gt!r}); use has_size_variation "
                    "for volume drift",
                )
            )
        else:
            allowed_error = True
    elif check_name == "has_size_variation":
        allowed_error = layer == "clean"
        if layer != "clean":
            findings.append(
                Finding(
                    filepath,
                    "dq_severity",
                    f"{block_name}.{column_key}.{check_name}: "
                    "has_size_variation must use severity_level: Warning on "
                    f"{layer} tables (Error is clean-only)",
                )
            )
    elif check_name in ("is_complete", "is_unique"):
        allowed_error = _SK_COLUMN_RE.match(column_key) is not None
        if not allowed_error:
            findings.append(
                Finding(
                    filepath,
                    "dq_severity",
                    f"{block_name}.{column_key}.{check_name}: "
                    "is_complete/is_unique with Error is allowed only on sk_* columns",
                )
            )
    elif check_name == "custom" and _ONE_ROW_PER_RE.match(column_key):
        allowed_error = True
    elif check_name == "custom":
        findings.append(
            Finding(
                filepath,
                "dq_severity",
                f"{block_name}.{column_key}.{check_name}: "
                "custom checks must use severity_level: Warning unless the key is "
                "one_row_per_* (grain uniqueness)",
            )
        )
    else:
        findings.append(
            Finding(
                filepath,
                "dq_severity",
                f"{block_name}.{column_key}.{check_name}: "
                "severity_level: Error is not allowed for this check type in People DQ",
            )
        )

    return findings


def _custom_comment_findings(
    filepath: str, raw_text: str, column_key: str, params: dict
) -> List[Finding]:
    """Require an intent comment immediately above a ``custom`` column check.

    Custom SQL constraints are opaque to downstream readers; a short ``#`` comment
    documents the business rule so on-call engineers know why the check exists.
    """
    if not isinstance(params, dict):
        return []
    if "constraint" not in params:
        return []

    lines = raw_text.splitlines()
    key_pattern = re.compile(
        rf"^\s*{re.escape(column_key)}\s*:\s*$",
        re.IGNORECASE,
    )
    custom_pattern = re.compile(r"^\s*custom\s*:\s*$", re.IGNORECASE)
    key_line_idx: Optional[int] = None
    custom_line_idx: Optional[int] = None
    for idx, line in enumerate(lines):
        if key_line_idx is None and key_pattern.match(line):
            key_line_idx = idx
        if key_line_idx is not None and custom_pattern.match(line):
            custom_line_idx = idx
            break

    if custom_line_idx is None:
        return []

    for prev in range(custom_line_idx - 1, max(custom_line_idx - 4, -1), -1):
        stripped = lines[prev].strip()
        if stripped.startswith("#"):
            return []
        if stripped and not stripped.endswith(":"):
            break

    for nxt in range(custom_line_idx + 1, min(custom_line_idx + 6, len(lines))):
        stripped = lines[nxt].strip()
        if stripped.startswith("#"):
            return []
        if stripped.startswith("constraint:"):
            break
        if stripped and not stripped.endswith(":"):
            break

    return [
        Finding(
            filepath,
            "dq_custom_comment",
            f"column_level_validations.{column_key}.custom: "
            "add an intent comment (# ...) immediately above the custom block",
            line_no=custom_line_idx + 1,
        )
    ]


def _has_size_variation_bounds_findings(
    filepath: str, layer: str, params: dict, raw_text: str
) -> List[Finding]:
    """Flag clean ``has_size_variation`` bounds outside the default -10% / +25% range.

    Non-default bounds are allowed when justified; without a nearby ``#`` comment
    authors cannot explain why a table needs wider drift tolerance, and reviewers
    cannot approve the change safely.
    """
    if layer != "clean":
        return []
    gte = params.get("greater_than_or_equal_to")
    lte = params.get("less_than_or_equal_to")
    effective_gte = gte if gte is not None else _DEFAULT_SIZE_VARIATION_BOUNDS[0]
    effective_lte = lte if lte is not None else _DEFAULT_SIZE_VARIATION_BOUNDS[1]
    if (
        effective_gte == _DEFAULT_SIZE_VARIATION_BOUNDS[0]
        and effective_lte == _DEFAULT_SIZE_VARIATION_BOUNDS[1]
    ):
        return []

    lines = raw_text.splitlines()
    hsv_pattern = re.compile(r"^\s*has_size_variation\s*:\s*$", re.IGNORECASE)
    hsv_line_idx: Optional[int] = None
    for idx, line in enumerate(lines):
        if hsv_pattern.match(line):
            hsv_line_idx = idx
            break

    if hsv_line_idx is not None:
        for prev in range(hsv_line_idx - 1, max(hsv_line_idx - 4, -1), -1):
            stripped = lines[prev].strip()
            if stripped.startswith("#"):
                return []
            if stripped and not stripped.endswith(":"):
                break

    return [
        Finding(
            filepath,
            "dq_size_variation_bounds",
            "clean has_size_variation: non-default bounds require a comment "
            f"justifying the value (expected gte={_DEFAULT_SIZE_VARIATION_BOUNDS[0]}, "
            f"lte={_DEFAULT_SIZE_VARIATION_BOUNDS[1]})",
            line_no=hsv_line_idx + 1 if hsv_line_idx is not None else None,
        )
    ]


def validate_dq_file(path: Path) -> List[Finding]:
    """Run all People ``data_quality`` content rules on a single YAML file.

    Covers required clean ``has_size_variation``, severity placement, Error-only
    allowlist, custom-check comments, grain-check severity, and justified bounds.
    Pairing with query/metadata files is handled by
    ``validate_people_data_quality_files_exist.py``.
    """
    findings: List[Finding] = []
    layer = _dq_layer_from_path(str(path))
    if layer is None:
        return findings

    try:
        raw_text = path.read_text(encoding="utf-8")
        data = yaml.safe_load(raw_text)
    except (OSError, yaml.YAMLError) as exc:
        return [Finding(str(path), "dq_parse", f"cannot read or parse YAML: {exc}")]

    if not isinstance(data, dict):
        return [Finding(str(path), "dq_parse", "root must be a mapping")]

    table_level = data.get("table_level_validations") or {}
    if layer == "clean" and "has_size_variation" not in table_level:
        findings.append(
            Finding(
                str(path),
                "dq_has_size_variation",
                "clean tables must define table_level_validations.has_size_variation",
            )
        )

    if isinstance(table_level, dict):
        for check_name, params in table_level.items():
            findings.extend(
                _check_block_findings(
                    str(path),
                    layer,
                    "table_level_validations",
                    check_name,
                    check_name,
                    params,
                )
            )
            if check_name == "has_size_variation" and isinstance(params, dict):
                findings.extend(
                    _has_size_variation_bounds_findings(
                        str(path), layer, params, raw_text
                    )
                )

    column_level = data.get("column_level_validations") or {}
    if isinstance(column_level, dict):
        for column_key, checks in column_level.items():
            if not isinstance(checks, dict):
                continue
            for check_name, params in checks.items():
                findings.extend(
                    _check_block_findings(
                        str(path),
                        layer,
                        "column_level_validations",
                        column_key,
                        check_name,
                        params,
                    )
                )
                if check_name == "custom":
                    findings.extend(
                        _custom_comment_findings(
                            str(path), raw_text, column_key, params
                        )
                    )
                    if _ONE_ROW_PER_RE.match(column_key):
                        severity = (params or {}).get("severity_level", "")
                        if str(severity).lower() != "error":
                            findings.append(
                                Finding(
                                    str(path),
                                    "dq_grain_severity",
                                    f"column_level_validations.{column_key}.custom: "
                                    "one_row_per_* grain checks must use "
                                    "severity_level: Error",
                                )
                            )

    return findings


def extract_ordered_columns_from_sql(
    sql_path: Path,
) -> Tuple[List[str], bool, Optional[str]]:
    """Parse the outer SELECT column list from a pipeline SQL file.

    Returns ``(columns, has_star, error)``. Used to enforce Kimball column order
    against metadata; ``SELECT *`` skips validation because column order is unknown.
    """
    try:
        with open(sql_path, encoding="utf-8") as handle:
            sql = handle.read()
        normalized = normalize_sql(sql)
        parsed = parse_one(normalized, read="databricks")
        final_select = parsed.find(exp.Select)
        if not final_select:
            return [], False, "no SELECT found"
        ordered: List[str] = []
        for column in final_select.expressions:
            if isinstance(column, exp.Star):
                return [], True, None
            name = column.alias_or_name
            if name == "*" or isinstance(column, exp.Star):
                return [], True, None
            if name:
                ordered.append(name.lower())
        return ordered, False, None
    except Exception as exc:
        return [], False, str(exc)


def extract_ordered_metadata_columns(meta_path: Path) -> List[str]:
    """Return lowercase column keys in metadata YAML declaration order."""
    with open(meta_path, encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    columns = data.get("columns") or {}
    if not isinstance(columns, dict):
        return []
    return [key.lower() for key in columns.keys()]


def validate_column_order_pair(sql_path: Path, meta_path: Path) -> List[Finding]:
    """Ensure SQL SELECT column order matches the metadata ``columns`` block.

    Consistent ordering across SQL and metadata makes cross-layer diffs and
    manual review predictable; mismatches often signal a column added in the
    wrong section of the model.
    """
    if not meta_path.is_file():
        return [
            Finding(
                str(sql_path),
                "metadata_pair",
                f"missing metadata file {meta_path}",
            )
        ]

    sql_cols, has_star, err = extract_ordered_columns_from_sql(sql_path)
    if has_star:
        return [
            Finding(
                str(sql_path),
                "column_order",
                "SELECT * prevents column-order validation; list columns explicitly",
            )
        ]
    if err:
        return [Finding(str(sql_path), "column_order", f"cannot parse SQL: {err}")]

    meta_cols = extract_ordered_metadata_columns(meta_path)
    if not meta_cols:
        return [
            Finding(
                str(meta_path),
                "column_order",
                "metadata file has no columns block",
            )
        ]

    if sql_cols != meta_cols:
        return [
            Finding(
                str(sql_path),
                "column_order",
                f"SQL column order does not match metadata "
                f"(sql={sql_cols}, metadata={meta_cols})",
            )
        ]
    return []


def validate_grain_documentation(
    meta_path: Path, dq_path: Optional[Path]
) -> List[Finding]:
    """Require an explicit ``One row per …`` grain phrase in table metadata.

    Modeled enrich/dw/metric tables (and any table with ``one_row_per_*`` DQ)
    must document grain in the description so consumers know how to join and
    aggregate without silent duplicate inflation.
    """
    parts = meta_path.parts
    try:
        layer = parts[parts.index("metadata") + 1]
    except (ValueError, IndexError):
        layer = ""

    requires_grain = layer in {"enrich", "dw", "metric"}
    if dq_path and dq_path.is_file():
        try:
            dq_raw = dq_path.read_text(encoding="utf-8")
            dq_data = yaml.safe_load(dq_raw)
            column_level = (dq_data or {}).get("column_level_validations") or {}
            if isinstance(column_level, dict):
                for key in column_level:
                    if _ONE_ROW_PER_RE.match(key):
                        requires_grain = True
                        break
        except (OSError, yaml.YAMLError):
            pass

    if not requires_grain:
        return []

    with open(meta_path, encoding="utf-8") as handle:
        data = yaml.safe_load(handle)
    description = (data or {}).get("description") or ""
    if _GRAIN_PHRASE_RE.search(description):
        return []

    return [
        Finding(
            str(meta_path),
            "grain_documentation",
            "table description must state grain with 'One row per ...' "
            "(people_metadata.mdc)",
        )
    ]


def validate_subqueries_in_sql(sql_path: Path) -> List[Finding]:
    """Discourage subqueries directly in ``FROM``; prefer a named CTE.

    Inline ``FROM (SELECT …)`` queries are harder to read, debug on Spark, and
    diverge from ``sql_conventions.mdc``; lifting logic into ``WITH`` blocks
    keeps dual-runtime SQL maintainable.
    """
    try:
        sql = sql_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [Finding(str(sql_path), "subquery", f"cannot read file: {exc}")]

    normalized = normalize_sql(sql)
    if _FROM_SUBQUERY_RE.search(normalized):
        match = _FROM_SUBQUERY_RE.search(normalized)
        line_no = normalized[: match.start()].count("\n") + 1 if match else None
        return [
            Finding(
                str(sql_path),
                "subquery_in_from",
                "avoid subqueries in FROM; use a named CTE at the top of the query",
                line_no=line_no,
            )
        ]

    try:
        parsed = parse_one(normalized, read="databricks")
        cte_names: Set[str] = set()
        with_node = parsed.find(exp.With)
        if with_node:
            for cte in with_node.expressions:
                alias = cte.alias
                if alias:
                    cte_names.add(alias.lower())

        findings: List[Finding] = []
        for subquery in parsed.find_all(exp.Subquery):
            parent = subquery.parent
            if isinstance(parent, exp.From) and subquery.alias:
                alias = subquery.alias.lower()
                if alias not in cte_names:
                    line_no = None
                    if subquery.meta and "line" in subquery.meta:
                        line_no = subquery.meta["line"]
                    findings.append(
                        Finding(
                            str(sql_path),
                            "subquery_in_from",
                            "avoid subqueries in FROM; use a named CTE at the top "
                            "of the query",
                            line_no=line_no,
                        )
                    )
        return findings
    except Exception:
        return []


def validate_deprecated_sources_in_sql(sql_path: Path) -> List[Finding]:
    """Block references to phased-out upstream schemas in new scoped-domain SQL.

    Legacy monolithic schemas (``datalake_hr_system``, v1 Greenhouse, etc.) are
    being replaced by ``pin_*`` and ``datalake_people``; new queries should not
    extend that debt. Exempt legacy DAG folders under ``dags/people/`` only.
    """
    if is_legacy_dag_exempt(sql_path):
        return []
    try:
        sql = sql_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [Finding(str(sql_path), "deprecated_source", f"cannot read file: {exc}")]

    findings: List[Finding] = []
    for label, line_no, line_text in find_deprecated_source_hits(sql):
        findings.append(
            Finding(
                str(sql_path),
                f"deprecated_source:{label}",
                f"deprecated upstream reference ({hint_for_label(label)}): {line_text}",
                line_no=line_no,
            )
        )
    return findings


# Backward-compatible aliases for unit tests and local imports.
_metadata_path_for_sql = metadata_path_for_sql
_dq_path_for_sql = dq_path_for_sql
_dq_path_for_metadata = dq_path_for_metadata


def collect_files(
    branch: Optional[str],
    all_files: bool,
    paths: Optional[Sequence[str]],
) -> Tuple[List[Path], List[Path], List[Path]]:
    """Gather data_quality, query SQL, and metadata paths for the active scan mode.

    Supports branch diff (CI), explicit ``--paths``, or full-repo audit (``-a``).
    Returns three lists so each check group can target the right artifact types.
    """
    if paths:
        expanded = expand_people_paths(paths)
        dq_files = [p for p in expanded if _is_dq_yaml(p)]
        sql_files = [p for p in expanded if p.suffix == ".sql"]
        meta_files = [
            p
            for p in expanded
            if "/metadata/" in str(p).replace("\\", "/") and p.suffix == ".yml"
        ]
        return dq_files, sql_files, meta_files

    if all_files:
        dq_files: List[Path] = []
        sql_files: List[Path] = []
        meta_files: List[Path] = []
        for root in iter_scoped_domain_roots():
            dq_files.extend(
                [p for p in root.rglob("data_quality/**/*.yml") if _is_dq_yaml(p)]
            )
            sql_files.extend(sorted(root.rglob("queries/**/*.sql")))
            meta_files.extend(sorted(root.rglob("metadata/**/*.yml")))
        return dq_files, sql_files, meta_files

    dq_files = get_changed_files(branch or "", ".yml")
    dq_files = [p for p in dq_files if _is_dq_yaml(p)]
    sql_files = get_changed_files(branch or "", ".sql")
    sql_files = [p for p in sql_files if "/queries/" in str(p).replace("\\", "/")]
    meta_files = get_changed_files(branch or "", ".yml")
    meta_files = [p for p in meta_files if "/metadata/" in str(p).replace("\\", "/")]
    return dq_files, sql_files, meta_files


def validate_by_group(
    branch: Optional[str],
    all_files: bool,
    paths: Optional[Sequence[str]],
    group: CheckGroup,
) -> List[Finding]:
    """Run one convention group across collected files and aggregate findings.

    Woodpecker invokes a single group per step so DQ, SQL/metadata, style, and
    deprecated-source failures surface in parallel jobs with smaller logs.
    """
    dq_files, sql_files, meta_files = collect_files(branch, all_files, paths)

    if (
        not dq_files
        and not sql_files
        and not meta_files
        and not all_files
        and not paths
    ):
        return []

    findings: List[Finding] = []

    if group in ("dq", "all"):
        for path in dq_files:
            if path.is_file():
                findings.extend(validate_dq_file(path))

    if group in ("sql-metadata", "all"):
        for path in sql_files:
            if path.is_file():
                meta = _metadata_path_for_sql(path)
                if meta:
                    findings.extend(validate_column_order_pair(path, meta))
        for path in meta_files:
            if path.is_file():
                findings.extend(
                    validate_grain_documentation(path, _dq_path_for_metadata(path))
                )

    if group in ("sql-style", "all"):
        for path in sql_files:
            if path.is_file():
                findings.extend(validate_subqueries_in_sql(path))

    if group in ("deprecated-sources", "all"):
        for path in sql_files:
            if path.is_file():
                findings.extend(validate_deprecated_sources_in_sql(path))

    return findings


def parse_args() -> argparse.Namespace:
    """Parse CLI flags: check group, branch diff, full audit, or explicit paths."""
    parser = argparse.ArgumentParser(
        description="Validate People domain repository conventions."
    )
    parser.add_argument(
        "--check",
        choices=CHECK_GROUPS,
        default="all",
        help="Which convention group to run (CI runs one group per Woodpecker step)",
    )
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("-b", "--branch", type=branch_name_arg_type)
    group.add_argument(
        "-a",
        "--all-files",
        action="store_true",
        help="Audit every file under scoped domains (people + enterprise_efficiency)",
    )
    group.add_argument(
        "--paths",
        nargs="+",
        type=repo_relative_file_arg_type,
        help=f"Scoped DAG paths under {SCOPE_PATHS_HELP}",
    )
    return parser.parse_args()


def _nothing_to_validate_message(group: CheckGroup) -> str:
    """Return a no-op message when the branch diff has no files for this check group."""
    labels = {
        "dq": "People data_quality YAML",
        "sql-metadata": "People SQL/metadata pairing",
        "sql-style": "People SQL style",
        "deprecated-sources": "People deprecated SQL sources",
        "all": "People DAG",
    }
    return f"No changed {labels[group]} files detected — nothing to validate."


def main() -> int:
    """CLI entrypoint: run selected conventions and exit 1 when violations exist."""
    args = parse_args()
    branch = args.branch
    group: CheckGroup = args.check

    findings = validate_by_group(branch, args.all_files, args.paths, group)

    if not findings and not args.all_files and not args.paths and branch:
        dq_files, sql_files, meta_files = collect_files(branch, False, None)
        relevant = {
            "dq": dq_files,
            "sql-metadata": sql_files + meta_files,
            "sql-style": sql_files,
            "deprecated-sources": sql_files,
            "all": dq_files + sql_files + meta_files,
        }
        if not relevant[group]:
            print(_nothing_to_validate_message(group))
            return 0

    if not findings:
        print(f"OK: Scoped domain conventions validation passed ({group}).")
        return 0

    print(
        f"\n❌  Found {len(findings)} scoped domain convention violation(s) [{group}]:\n",
        file=sys.stderr,
    )
    for finding in findings:
        print(finding.format(), file=sys.stderr)
    print(_remediation_footer(group), file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
