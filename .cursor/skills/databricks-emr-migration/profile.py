"""Column profile SQL generation and parsing for migration validation."""

from __future__ import annotations

import re
from dataclasses import asdict
from decimal import Decimal
from typing import Any, Dict, List, Optional, Set, Tuple

from input_validation import validate_order_by_column
from models import ColumnProfile, SchemaEntry, TableProfile

PROFILE_VERSION = 1
MAX_PROFILE_COLUMNS = 120
MIG_NULL_SENTINEL = "__MIG_NULL__"

_COMPLEX_TYPE_PREFIXES = ("array<", "map<", "struct<")
_FLOAT_TYPES = frozenset({"float", "double", "real"})
_INTEGER_TYPES = frozenset(
    {"tinyint", "smallint", "int", "integer", "bigint", "long", "short", "byte"}
)
_DECIMAL_RE = re.compile(r"^decimal\s*\(", re.IGNORECASE)
_TIMESTAMP_TYPES = frozenset({"timestamp", "timestamp_ntz", "date"})


def _normalize_type_name(type_name: str) -> str:
    return type_name.lower().replace(" ", "").strip('"')


def is_profileable_type(type_name: str) -> bool:
    normalized = _normalize_type_name(type_name)
    if any(normalized.startswith(prefix) for prefix in _COMPLEX_TYPE_PREFIXES):
        return False
    if normalized in {"binary"}:
        return False
    return True


def normalize_for_hash(column: str, type_name: str) -> str:
    """Return a Spark SQL expression that normalizes ``column`` before xxhash64."""
    validate_order_by_column(column)
    return _normalize_col_for_hash(f"`{column}`", type_name)


def _normalize_col_for_hash(col_ref: str, type_name: str) -> str:
    normalized = _normalize_type_name(type_name)

    if normalized in _TIMESTAMP_TYPES:
        if normalized == "date":
            return f"DATE_FORMAT({col_ref}, 'yyyy-MM-dd')"
        return (
            f"DATE_FORMAT(CAST({col_ref} AS TIMESTAMP), "
            f"'yyyy-MM-dd HH:mm:ss.SSSSSS')"
        )
    if normalized in _FLOAT_TYPES:
        return f"CAST(CAST({col_ref} AS DECIMAL(38, 18)) AS STRING)"
    if normalized in _INTEGER_TYPES or _DECIMAL_RE.match(normalized):
        return f"CAST({col_ref} AS STRING)"
    if normalized in {"boolean", "bool"}:
        return f"CAST({col_ref} AS STRING)"
    return f"CAST({col_ref} AS STRING)"


def _hash_expression(name: str, type_name: str, *, table_alias: str = "t") -> str:
    col_ref = f"{table_alias}.`{name}`"
    normalized = _normalize_col_for_hash(col_ref, type_name)
    return f"xxhash64(COALESCE({normalized}, '{MIG_NULL_SENTINEL}'))"


def select_profile_columns(
    schema: List[SchemaEntry],
    *,
    checksum_skipped: Optional[Set[str]] = None,
    max_columns: int = MAX_PROFILE_COLUMNS,
) -> tuple[List[SchemaEntry], List[str], List[str], List[str]]:
    """Return profiled columns, skipped complex cols, truncated cols, checksum-skipped."""
    skipped: List[str] = []
    profileable: List[SchemaEntry] = []
    checksum_skip = {name.lower() for name in (checksum_skipped or set())}

    for name, type_name in schema:
        if not is_profileable_type(type_name):
            skipped.append(name)
            continue
        profileable.append((name, type_name))

    truncated: List[str] = []
    if len(profileable) > max_columns:
        truncated = [name for name, _ in profileable[max_columns:]]
        profileable = profileable[:max_columns]

    checksum_skipped_columns = [
        name for name, _ in profileable if name.lower() in checksum_skip
    ]
    return profileable, skipped, truncated, checksum_skipped_columns


def build_profile_query(
    pinned_sql: str,
    schema: List[SchemaEntry],
    *,
    checksum_skipped: Optional[Set[str]] = None,
    max_columns: int = MAX_PROFILE_COLUMNS,
) -> tuple[str, TableProfile]:
    """Build a single-pass profile query and empty profile metadata shell."""
    profile_columns, skipped, truncated, checksum_skipped_columns = select_profile_columns(
        schema,
        checksum_skipped=checksum_skipped,
        max_columns=max_columns,
    )
    checksum_skip_lower = {name.lower() for name in (checksum_skipped or set())}

    inner_projections: List[str] = []
    outer_select = ["COUNT(*) AS cnt"]
    empty_columns: Dict[str, ColumnProfile] = {}

    for name, type_name in profile_columns:
        validate_order_by_column(name)
        inner_projections.append(f"t.`{name}`")
        hash_alias = f"h_{name}"
        inner_projections.append(
            f"{_hash_expression(name, type_name)} AS `{hash_alias}`"
        )
        outer_select.append(f"COUNT_IF(`{name}` IS NULL) AS `null_{name}`")
        empty_columns[name] = ColumnProfile(null_count=0)
        if name.lower() not in checksum_skip_lower:
            sum_expr = f"SUM(CAST(`{hash_alias}` AS DECIMAL(38, 0)))"
            outer_select.append(f"CAST({sum_expr} AS STRING) AS `chk_sum_{name}`")
            outer_select.append(
                f"SUBSTR(SHA2(CAST({sum_expr} AS STRING), 256), 1, 32) AS `chk_{name}`"
            )

    inner_sql = ",\n    ".join(inner_projections)
    outer_sql = ",\n  ".join(outer_select)
    query = (
        f"SELECT\n  {outer_sql}\n"
        f"FROM (\n"
        f"  SELECT\n    {inner_sql}\n"
        f"  FROM ({pinned_sql}) AS t\n"
        f") AS hashed"
    )

    metadata = TableProfile(
        version=PROFILE_VERSION,
        columns=empty_columns,
        skipped_columns=skipped,
        truncated_columns=truncated,
        checksum_skipped_columns=checksum_skipped_columns,
    )
    return query, metadata


def parse_profile_from_row(
    row: Dict[str, Any],
    metadata: TableProfile,
) -> TableProfile:
    """Populate ``TableProfile`` from a single aggregate result row."""
    columns: Dict[str, ColumnProfile] = {}
    checksum_skip = {name.lower() for name in metadata.checksum_skipped_columns}

    for col_name in metadata.columns:
        null_key = f"null_{col_name}"
        null_raw = row.get(null_key, row.get(f"`{null_key}`", 0))
        null_count = int(null_raw or 0)
        checksum: Optional[str] = None
        checksum_sum: Optional[str] = None
        if col_name.lower() not in checksum_skip:
            chk_key = f"chk_{col_name}"
            sum_key = f"chk_sum_{col_name}"
            checksum = _string_or_none(row.get(chk_key, row.get(f"`{chk_key}`")))
            checksum_sum = _string_or_none(row.get(sum_key, row.get(f"`{sum_key}`")))
        columns[col_name] = ColumnProfile(
            null_count=null_count,
            checksum=checksum,
            checksum_sum=checksum_sum,
        )

    return TableProfile(
        version=metadata.version,
        columns=columns,
        skipped_columns=list(metadata.skipped_columns),
        truncated_columns=list(metadata.truncated_columns),
        checksum_skipped_columns=list(metadata.checksum_skipped_columns),
    )


def _string_or_none(value: Any) -> Optional[str]:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def profile_to_dict(profile: Optional[TableProfile]) -> Optional[Dict[str, Any]]:
    if profile is None:
        return None
    payload = asdict(profile)
    payload["version"] = profile.version
    return payload


def profile_from_dict(data: Optional[Dict[str, Any]]) -> Optional[TableProfile]:
    if not data:
        return None
    columns_raw = data.get("columns") or {}
    columns: Dict[str, ColumnProfile] = {}
    for name, col_data in columns_raw.items():
        if isinstance(col_data, ColumnProfile):
            columns[name] = col_data
        else:
            columns[name] = ColumnProfile(
                null_count=int(col_data.get("null_count", 0)),
                checksum=col_data.get("checksum"),
                checksum_sum=col_data.get("checksum_sum"),
            )
    return TableProfile(
        version=int(data.get("version", PROFILE_VERSION)),
        columns=columns,
        skipped_columns=list(data.get("skipped_columns") or []),
        truncated_columns=list(data.get("truncated_columns") or []),
        checksum_skipped_columns=list(data.get("checksum_skipped_columns") or []),
    )


def compare_delta_pct(baseline_value: Decimal, emr_value: Decimal) -> Tuple[float, str]:
    """Same PASS/WARN/FAIL bands as row-count comparison."""
    if baseline_value == 0 and emr_value == 0:
        return 0.0, "PASS"
    if baseline_value == 0 or emr_value == 0:
        return 100.0, "FAIL"
    delta_pct = float(abs(emr_value - baseline_value) / max(baseline_value, emr_value) * 100)
    if delta_pct > 5.0:
        return delta_pct, "FAIL"
    if delta_pct > 0.1:
        return delta_pct, "WARN"
    return delta_pct, "PASS"


def _parse_decimal(value: Optional[str]) -> Decimal:
    if value is None or value == "":
        return Decimal(0)
    return Decimal(str(value))


def compare_null_counts(
    baseline: TableProfile,
    emr: TableProfile,
) -> Tuple[bool, List[str], str]:
    issues: List[str] = []
    worst = "PASS"
    all_names = sorted(set(baseline.columns) | set(emr.columns))
    for name in all_names:
        base_col = baseline.columns.get(name)
        emr_col = emr.columns.get(name)
        base_null = base_col.null_count if base_col else 0
        emr_null = emr_col.null_count if emr_col else 0
        if base_null != emr_null:
            issues.append(
                f"Null count mismatch for {name}: baseline={base_null}, emr={emr_null}"
            )
            worst = "FAIL"
    return len(issues) == 0, issues, worst


def compare_checksums(
    baseline: TableProfile,
    emr: TableProfile,
) -> Tuple[bool, List[str], bool, str]:
    """Compare checksums; return (ok, issues, has_warn, worst_status)."""
    issues: List[str] = []
    has_warn = False
    worst = "PASS"
    checksum_skip = {name.lower() for name in baseline.checksum_skipped_columns}

    for name in sorted(baseline.columns):
        if name.lower() in checksum_skip:
            continue
        base_col = baseline.columns.get(name)
        emr_col = emr.columns.get(name)
        if base_col is None or emr_col is None:
            continue
        base_hex = base_col.checksum
        emr_hex = emr_col.checksum
        if base_hex and emr_hex and base_hex == emr_hex:
            continue

        base_sum = _parse_decimal(base_col.checksum_sum)
        emr_sum = _parse_decimal(emr_col.checksum_sum)
        delta_pct, status = compare_delta_pct(base_sum, emr_sum)
        if status == "PASS":
            continue
        detail = (
            f"Checksum mismatch for {name}: "
            f"baseline={base_hex or base_col.checksum_sum}, "
            f"emr={emr_hex or emr_col.checksum_sum}, "
            f"delta={delta_pct:.3f}%"
        )
        issues.append(detail)
        if status == "FAIL":
            worst = "FAIL"
        elif status == "WARN" and worst != "FAIL":
            worst = "WARN"
            has_warn = True

    ok = len(issues) == 0
    return ok, issues, has_warn, worst
