"""Compare Databricks baseline vs EMR validation results."""

from __future__ import annotations

import math
import re
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple

from baseline import format_table_label
from models import EmrTableResult, SchemaEntry, TableBaseline, ValidationResult
from profile import compare_checksums, compare_null_counts

# ISO-8601 timestamps from Databricks JSON (…Z) vs EMR PySpark (microseconds, no Z).
_ISO_TIMESTAMP_RE = re.compile(
    r"^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}"
)

TYPE_WIDENING: Dict[str, Set[str]] = {
    "int": {"bigint", "long"},
    "integer": {"bigint", "long"},
    "smallint": {"int", "integer", "bigint", "long"},
    "tinyint": {"smallint", "int", "integer", "bigint", "long"},
    "float": {"double"},
    "real": {"float", "double"},
}


def _normalize_type(type_name: str) -> str:
    return type_name.lower().replace(" ", "").strip('"')


def _types_compatible(baseline_type: str, emr_type: str) -> Tuple[bool, bool]:
    base = _normalize_type(baseline_type)
    emr = _normalize_type(emr_type)
    if base == emr:
        return True, False
    allowed = TYPE_WIDENING.get(base, set())
    if emr in allowed:
        return True, True
    return False, False


def compare_schema(
    baseline_schema: List[SchemaEntry],
    emr_schema: List[SchemaEntry],
) -> Tuple[bool, List[str], bool]:
    issues: List[str] = []
    has_warn = False

    baseline_cols = [name for name, _ in baseline_schema]
    emr_cols = [name for name, _ in emr_schema]
    if baseline_cols != emr_cols:
        missing = set(baseline_cols) - set(emr_cols)
        extra = set(emr_cols) - set(baseline_cols)
        if missing:
            issues.append(f"Missing columns on EMR: {sorted(missing)}")
        if extra:
            issues.append(f"Extra columns on EMR: {sorted(extra)}")
        if not missing and not extra:
            issues.append(
                f"Column order mismatch: baseline {baseline_cols} vs EMR {emr_cols}"
            )
        return False, issues, False

    emr_type_map = {name: typ for name, typ in emr_schema}
    for name, base_type in baseline_schema:
        emr_type = emr_type_map[name]
        compatible, warn = _types_compatible(base_type, emr_type)
        if not compatible:
            issues.append(f"Type mismatch for {name}: {base_type} vs {emr_type}")
        elif warn:
            has_warn = True
            issues.append(f"Type widening for {name}: {base_type} -> {emr_type}")

    return len([issue for issue in issues if "mismatch" in issue or "Missing" in issue or "Extra" in issue]) == 0, issues, has_warn


def compare_count(baseline_count: int, emr_count: int) -> Tuple[float, str]:
    if baseline_count == 0 and emr_count == 0:
        return 0.0, "PASS"
    if baseline_count == 0:
        return 100.0, "FAIL"
    delta_pct = abs(emr_count - baseline_count) / baseline_count * 100.0
    if delta_pct > 5.0:
        return delta_pct, "FAIL"
    if delta_pct > 0.1:
        return delta_pct, "WARN"
    return delta_pct, "PASS"


def _fraction_digits_to_microseconds(frac_digits: str) -> int:
    """Convert variable-length fractional seconds (.605, .72, .720000) to microseconds."""
    if not frac_digits:
        return 0
    scale = 10 ** len(frac_digits)
    return int(frac_digits) * 1_000_000 // scale


def _parse_timestamp_string(value: str) -> Optional[datetime]:
    """Parse ISO-8601 timestamp strings from Databricks vs EMR JSON serializers."""
    raw = value.strip()
    if not raw or not _ISO_TIMESTAMP_RE.match(raw):
        return None

    tz_offset = ""
    if raw.endswith(("Z", "z")):
        body = raw[:-1]
        tz_offset = "+00:00"
    else:
        body = raw

    if "." in body:
        base, frac_part = body.split(".", 1)
        frac_digits = "".join(ch for ch in frac_part if ch.isdigit())
        if not frac_digits:
            return None
        micros = _fraction_digits_to_microseconds(frac_digits)
        body = f"{base}.{micros:06d}"

    normalized = body + tz_offset
    try:
        parsed = datetime.fromisoformat(normalized)
    except ValueError:
        return None
    if parsed.tzinfo is not None:
        return parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


def _normalize_value(value: Any) -> Any:
    if value is None:
        return None
    if isinstance(value, float):
        if math.isnan(value):
            return None
        return round(value, 8)
    if isinstance(value, str):
        stripped = value.strip()
        parsed_ts = _parse_timestamp_string(stripped)
        if parsed_ts is not None:
            return parsed_ts.isoformat(timespec="microseconds")
        return stripped
    return value


def _values_equal(base_val: Any, emr_val: Any) -> bool:
    base_norm = _normalize_value(base_val)
    emr_norm = _normalize_value(emr_val)
    if base_norm == emr_norm:
        return True
    if isinstance(base_val, str) and isinstance(emr_val, str):
        base_ts = _parse_timestamp_string(base_val)
        emr_ts = _parse_timestamp_string(emr_val)
        if base_ts is not None and emr_ts is not None:
            return base_ts == emr_ts
    try:
        if base_norm is not None and emr_norm is not None:
            return abs(float(base_norm) - float(emr_norm)) <= 1e-6
    except (TypeError, ValueError):
        pass
    return False


def _is_minor_float_diff(base_val: Any, emr_val: Any) -> bool:
    """True when a sample cell diff is floating-point drift, not a real value change."""
    if isinstance(base_val, bool) or isinstance(emr_val, bool):
        return False
    if base_val is None or emr_val is None:
        return False
    if not isinstance(base_val, (int, float)) or not isinstance(emr_val, (int, float)):
        return False
    # Integer key/ID mismatches are hard failures; WARN only for float precision drift.
    return isinstance(base_val, float) or isinstance(emr_val, float)


def _row_diffs(
    base_row: Dict[str, Any],
    emr_row: Dict[str, Any],
    skip_cols: Set[str],
) -> Dict[str, Dict[str, Any]]:
    row_diffs: Dict[str, Dict[str, Any]] = {}
    cols = sorted(set(base_row.keys()) | set(emr_row.keys()))
    for col in cols:
        if col in skip_cols:
            continue
        base_val = base_row.get(col)
        emr_val = emr_row.get(col)
        if not _values_equal(base_val, emr_val):
            row_diffs[col] = {"baseline": base_val, "emr": emr_val}
    return row_diffs


def _row_match_kind(
    base_row: Dict[str, Any],
    emr_row: Dict[str, Any],
    skip_cols: Set[str],
) -> Optional[str]:
    """Return 'exact', 'warn', or None when rows are not the same sample record."""
    diffs = _row_diffs(base_row, emr_row, skip_cols)
    if not diffs:
        return "exact"
    if all(
        _is_minor_float_diff(change.get("baseline"), change.get("emr"))
        for change in diffs.values()
    ):
        return "warn"
    return None


def compare_sample(
    baseline_sample: List[Dict[str, Any]],
    emr_sample: List[Dict[str, Any]],
    non_comparable_cols: Optional[List[str]] = None,
) -> Tuple[bool, List[Dict[str, Any]], bool]:
    skip_cols = set(non_comparable_cols or [])
    diffs: List[Dict[str, Any]] = []
    has_warn = False

    if len(baseline_sample) != len(emr_sample):
        diffs.append(
            {
                "issue": "sample_length_mismatch",
                "baseline_rows": len(baseline_sample),
                "emr_rows": len(emr_sample),
            }
        )
        return False, diffs, False

    emr_pool = list(emr_sample)
    for base_idx, base_row in enumerate(baseline_sample):
        best_idx: Optional[int] = None
        best_kind: Optional[str] = None
        best_warn_diffs: Dict[str, Dict[str, Any]] = {}
        for pool_idx, emr_row in enumerate(emr_pool):
            kind = _row_match_kind(base_row, emr_row, skip_cols)
            if kind == "exact":
                best_idx = pool_idx
                best_kind = kind
                break
            if kind == "warn" and best_kind != "exact":
                best_idx = pool_idx
                best_kind = kind
                best_warn_diffs = _row_diffs(base_row, emr_row, skip_cols)
        if best_idx is None:
            if len(emr_pool) == 1:
                diffs.append(
                    {
                        "row_index": base_idx,
                        "diffs": _row_diffs(base_row, emr_pool[0], skip_cols),
                    }
                )
                emr_pool.pop(0)
            elif emr_pool:
                diffs.append(
                    {
                        "row_index": base_idx,
                        "issue": "sample_row_unmatched",
                        "diffs": _row_diffs(base_row, emr_pool[0], skip_cols),
                    }
                )
            else:
                diffs.append(
                    {
                        "row_index": base_idx,
                        "issue": "sample_row_unmatched",
                        "baseline_row": {
                            key: value
                            for key, value in base_row.items()
                            if key not in skip_cols
                        },
                    }
                )
            continue
        emr_pool.pop(best_idx)
        if best_kind == "warn":
            has_warn = True
            diffs.append({"row_index": base_idx, "diffs": best_warn_diffs})

    for emr_row in emr_pool:
        diffs.append(
            {
                "issue": "sample_row_unmatched",
                "emr_row": {
                    key: value for key, value in emr_row.items() if key not in skip_cols
                },
            }
        )

    if not diffs:
        return True, diffs, has_warn

    if any(diff.get("issue") == "sample_row_unmatched" for diff in diffs):
        return False, diffs, False

    if has_warn:
        return False, diffs, True
    return False, diffs, False


def is_both_empty(baseline: TableBaseline, emr_result: EmrTableResult) -> bool:
    """True when Databricks and EMR both returned no schema and no rows."""
    return (
        not baseline.error
        and not emr_result.error
        and len(baseline.schema) == 0
        and len(emr_result.schema) == 0
        and baseline.count == 0
        and emr_result.count == 0
    )


def _profile_label(
    *,
    profile_match: bool,
    profile_warn: bool,
    has_profile: bool,
) -> str:
    if not has_profile:
        return "skip"
    if profile_match:
        return "ok"
    if profile_warn:
        return "warn"
    return "fail"


def compare_results(
    baseline: TableBaseline,
    emr_result: EmrTableResult,
    skip_sample: bool = True,
    skip_profile: bool = False,
) -> ValidationResult:
    result = ValidationResult(
        table=format_table_label(baseline.layer, baseline.table),
        baseline_count=baseline.count,
        emr_count=emr_result.count,
        count_delta_pct=0.0,
        schema_match=True,
        schema_issues=[],
        sample_match=True,
        sample_diff_rows=[],
        status="PASS",
        message="OK",
    )

    if emr_result.error:
        result.status = "FAIL"
        result.message = emr_result.error
        result.schema_match = False
        result.sample_match = False
        return result

    if is_both_empty(baseline, emr_result):
        result.message = (
            "schema=ok, count_delta=0.000%, sample=ok (empty table on both sides)"
        )
        return result

    schema_ok, schema_issues, schema_warn = compare_schema(baseline.schema, emr_result.schema)
    result.schema_match = schema_ok
    result.schema_issues = schema_issues

    result.count_delta_pct, count_status = compare_count(baseline.count, emr_result.count)

    profile_status = "PASS"
    has_profile = (
        not skip_profile
        and baseline.profile is not None
        and emr_result.profile is not None
    )
    if has_profile:
        null_ok, null_issues, null_status = compare_null_counts(
            baseline.profile,
            emr_result.profile,
        )
        chk_ok, chk_issues, chk_warn, chk_status = compare_checksums(
            baseline.profile,
            emr_result.profile,
        )
        result.profile_issues = null_issues + chk_issues
        result.profile_match = null_ok and chk_ok
        result.profile_warn = chk_warn and null_ok
        result.baseline_profile = baseline.profile
        result.emr_profile = emr_result.profile
        profile_statuses = [null_status, chk_status]
        if "FAIL" in profile_statuses:
            profile_status = "FAIL"
        elif "WARN" in profile_statuses:
            profile_status = "WARN"
        else:
            profile_status = "PASS"
    elif not skip_profile and (baseline.profile or emr_result.profile):
        result.profile_match = False
        result.profile_issues = ["Profile missing on one side (re-run compare)"]
        profile_status = "FAIL"

    sample_status = "PASS"
    sample_warn = False
    if not skip_sample:
        sample_ok, sample_diffs, sample_warn = compare_sample(
            baseline.sample,
            emr_result.sample,
            baseline.non_comparable_cols,
        )
        result.sample_match = sample_ok
        result.sample_warn = sample_warn
        result.sample_diff_rows = sample_diffs
        if not sample_ok and sample_warn:
            sample_status = "WARN"
        elif not sample_ok:
            sample_status = "FAIL"

    statuses = [count_status]
    if not skip_profile:
        statuses.append(profile_status)
    if not schema_ok:
        statuses.append("FAIL")
    elif schema_warn:
        statuses.append("WARN")
    else:
        statuses.append("PASS")
    if not skip_sample:
        statuses.append(sample_status)

    if "FAIL" in statuses:
        result.status = "FAIL"
    elif "WARN" in statuses:
        result.status = "WARN"
    else:
        result.status = "PASS"

    if skip_sample:
        sample_message = "skipped"
    elif result.sample_match:
        sample_message = "ok"
    elif result.sample_warn:
        sample_message = "warn"
    else:
        sample_message = "fail"

    profile_message = _profile_label(
        profile_match=result.profile_match,
        profile_warn=result.profile_warn,
        has_profile=has_profile,
    )

    result.message = (
        f"schema={'ok' if schema_ok else 'fail'}, "
        f"count_delta={result.count_delta_pct:.3f}%, "
        f"profile={profile_message}, "
        f"sample={sample_message}"
    )
    return result
