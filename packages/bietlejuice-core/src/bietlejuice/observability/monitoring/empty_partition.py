"""Judgment logic for empty-partition signals (partition row_count = 0)."""

from __future__ import annotations

import math
from datetime import date, datetime
from typing import Any, Iterable

from bietlejuice.observability.monitoring.constants import (
    DEFAULT_FRESHNESS_HOURS,
    GCHAT_TEXT_MAX,
    SIGNAL_EMPTY_PARTITION,
    UNKNOWN_OWNER,
    UNKNOWN_PARTITION,
    UNKNOWN_TEAM,
)
from bietlejuice.observability.monitoring.sla_expectations import (
    TableSla,
    format_empty_partition_sla_brief,
)

ALERT_HEADER = "⚠️ Empty Partition Detected"
PartitionRow = dict[str, Any]
TableRow = dict[str, Any]
Finding = dict[str, Any]
TableMetricsIndex = dict[tuple[str, str, str], TableRow]


def normalize_partition_key(partition_key: Any) -> list[dict[str, Any]]:
    """Normalize deltalake/pandas partition_key values to a plain list of dicts.

    ``DeltaTable.to_pandas()`` returns struct arrays as ``numpy.ndarray``, which
    breaks truthiness checks and iteration in judgment code.
    """

    if partition_key is None:
        return []
    if hasattr(partition_key, "tolist"):
        partition_key = partition_key.tolist()
    if not isinstance(partition_key, (list, tuple)):
        return []
    normalized: list[dict[str, Any]] = []
    for entry in partition_key:
        if entry is None:
            continue
        if isinstance(entry, dict):
            normalized.append(entry)
            continue
        if hasattr(entry, "tolist"):
            entry = entry.tolist()
        if isinstance(entry, (list, tuple)) and len(entry) >= 2:
            normalized.append({"name": entry[0], "value": entry[1]})
    return normalized


def partition_key_fingerprint(partition_key: Any) -> str:
    normalized = normalize_partition_key(partition_key)
    if not normalized:
        return ""
    parts = sorted(
        f"{entry.get('name')}={entry.get('value')}"
        for entry in normalized
        if entry and entry.get("name") is not None
    )
    return "|".join(parts)


def _normalize_partition_value(column: str, value: Any) -> str:
    if column in ("month", "day"):
        try:
            return str(int(value)).zfill(2)
        except (TypeError, ValueError):
            pass
    return str(value)


def partition_matches_run_logical_date(row: PartitionRow) -> bool:
    """True when partition_key year/month/day matches the row's run_logical_date."""
    run_logical_date = row.get("run_logical_date")
    if not run_logical_date:
        return True
    try:
        parsed = datetime.strptime(str(run_logical_date), "%Y-%m-%d")
    except ValueError:
        return True
    expected = {
        "year": str(parsed.year),
        "month": str(parsed.month).zfill(2),
        "day": str(parsed.day).zfill(2),
    }
    values = {
        entry.get("name"): entry.get("value")
        for entry in normalize_partition_key(row.get("partition_key"))
        if entry.get("name") is not None
    }
    if not values:
        return False
    for column, expected_value in expected.items():
        if column not in values:
            continue
        if _normalize_partition_value(column, values[column]) != expected_value:
            return False
    return True


def is_partitioned_row(row: PartitionRow) -> bool:
    return bool(normalize_partition_key(row.get("partition_key")))


def is_cdc_ingestion_row(row: PartitionRow) -> bool:
    """CDC ingestion lives at raw layer; covered separately by [DIN] CDC alerts."""
    return str(row.get("layer") or "").lower() == "raw"


def dedupe_to_latest(rows: Iterable[PartitionRow]) -> list[PartitionRow]:
    """Keep the latest row per (database, table, partition_key) by delta version."""
    best: dict[tuple[str, str, str], PartitionRow] = {}
    for row in rows:
        database = row.get("database") or ""
        table = row.get("table") or ""
        partition_fp = partition_key_fingerprint(row.get("partition_key"))
        key = (database, table, partition_fp)
        current = best.get(key)
        if current is None or _row_sort_key(row) > _row_sort_key(current):
            best[key] = row
    return list(best.values())


def _row_sort_key(row: PartitionRow) -> tuple:
    version = row.get("profiled_delta_version")
    profiled_at = row.get("profiled_at")
    if isinstance(profiled_at, datetime):
        at_key = profiled_at
    elif profiled_at is not None:
        at_key = str(profiled_at)
    else:
        at_key = ""
    return (version or 0, at_key)


def _as_optional_int(value: Any) -> int | None:
    """Parse store/pandas metric values; ``None`` and ``nan`` map to unknown."""
    if value is None:
        return None
    if isinstance(value, float) and math.isnan(value):
        return None
    try:
        if hasattr(value, "item"):
            value = value.item()
        if isinstance(value, float) and math.isnan(value):
            return None
        return int(value)
    except (TypeError, ValueError):
        return None


def _is_candidate_row(row: PartitionRow) -> bool:
    if not is_partitioned_row(row):
        return False
    if is_cdc_ingestion_row(row):
        return False
    if not partition_matches_run_logical_date(row):
        return False
    return True


def _has_exact_year_month_day_partition(row: PartitionRow) -> bool:
    values = {
        entry.get("name")
        for entry in normalize_partition_key(row.get("partition_key"))
        if entry.get("name") is not None
    }
    return values == {"year", "month", "day"}


def judge_empty_partitions(
    rows: Iterable[PartitionRow],
    *,
    expectations: dict[tuple[str, str], TableSla] | None = None,
    freshness_hours: int = DEFAULT_FRESHNESS_HOURS,
) -> list[Finding]:
    """
    Pure judgment: run partition with row_count = 0 for opt-in tables.

    ``row_count`` is measured on the partition from ``run_logical_date`` (profiling thin
    slice). ``rows_written`` is retained on findings for context only — it is often
    missing (``nan``) on MERGE/metadata commits and is not used as a trigger.

    ``freshness_hours`` is applied by the store reader; kept here for API symmetry.
    """
    del freshness_hours  # applied at read time
    expectations = expectations or {}
    findings: list[Finding] = []
    for row in dedupe_to_latest(rows):
        if not _is_candidate_row(row):
            continue
        if not _has_exact_year_month_day_partition(row):
            continue
        row_count = _as_optional_int(row.get("row_count"))
        if row_count is None or row_count != 0:
            continue
        database = row.get("database") or ""
        table = row.get("table") or ""
        sla = expectations.get((database, table))
        if sla is None or not sla.has_empty_partition():
            continue
        partition_fp = partition_key_fingerprint(row.get("partition_key"))
        findings.append(
            {
                "signal_type": SIGNAL_EMPTY_PARTITION,
                "database": row.get("database") or "",
                "table": row.get("table") or "",
                "layer": row.get("layer"),
                "partition_key": row.get("partition_key"),
                "partition_fingerprint": partition_fp,
                "rows_written": row.get("rows_written"),
                "row_count": row_count,
                "profiled_delta_version": row.get("profiled_delta_version"),
                "profiled_at": row.get("profiled_at"),
                "run_logical_date": row.get("run_logical_date"),
                "environment": row.get("environment"),
                "sla_summary": format_empty_partition_sla_brief(),
            }
        )
    return findings


def build_table_metrics_index(rows: Iterable[TableRow]) -> TableMetricsIndex:
    """Latest table-grain row per (database, table, run_logical_date) by delta version."""
    best: TableMetricsIndex = {}
    for row in rows:
        database = row.get("database") or ""
        table = row.get("table") or ""
        run_logical_date = str(row.get("run_logical_date") or "")
        key = (database, table, run_logical_date)
        current = best.get(key)
        if current is None or _row_sort_key(row) > _row_sort_key(current):
            best[key] = row
    return best


def attach_table_context(
    findings: list[Finding],
    table_index: TableMetricsIndex,
) -> None:
    """Enrich findings with table-grain ``latest_partition_value`` when available."""
    for finding in findings:
        key = (
            finding.get("database") or "",
            finding.get("table") or "",
            str(finding.get("run_logical_date") or ""),
        )
        table_row = table_index.get(key)
        if table_row is None:
            continue
        finding["latest_partition_value"] = table_row.get("latest_partition_value")


def _partition_fingerprint_sort_key(fingerprint: str) -> tuple:
    """Chronological sort key from ``day=02|month=08|year=2026`` fingerprints."""

    if not fingerprint:
        return ()
    parts: dict[str, str] = {}
    for segment in fingerprint.split("|"):
        if "=" not in segment:
            continue
        name, value = segment.split("=", 1)
        parts[name.strip()] = value.strip()
    sort_key: list[Any] = []
    for column in ("year", "month", "day"):
        if column not in parts:
            continue
        try:
            sort_key.append(int(parts[column]))
        except ValueError:
            sort_key.append(parts[column])
    return tuple(sort_key)


def attach_latest_partition_with_data(
    findings: list[Finding],
    partition_rows: Iterable[PartitionRow],
) -> None:
    """Set ``latest_partition_with_data`` from partition-metrics rows with ``row_count > 0``."""

    rows_with_data: dict[tuple[str, str], list[PartitionRow]] = {}
    for row in partition_rows:
        row_count = _as_optional_int(row.get("row_count"))
        if row_count is None or row_count <= 0:
            continue
        database = row.get("database") or ""
        table = row.get("table") or ""
        if not database or not table:
            continue
        rows_with_data.setdefault((database, table), []).append(row)

    for finding in findings:
        key = (finding.get("database") or "", finding.get("table") or "")
        candidates = dedupe_to_latest(rows_with_data.get(key, []))
        if not candidates:
            finding["latest_partition_with_data"] = None
            continue
        best_row = max(
            candidates,
            key=lambda row: _partition_fingerprint_sort_key(
                partition_key_fingerprint(row.get("partition_key"))
            ),
        )
        finding["latest_partition_with_data"] = (
            partition_key_fingerprint(best_row.get("partition_key")) or None
        )


def finding_thread_key(finding: Finding) -> str:
    return (
        f"{finding['signal_type']}:{finding['database']}.{finding['table']}:"
        f"{finding['partition_fingerprint']}"
    )


def _display_owner(value: str | None, unknown_label: str) -> str:
    if not value or value == unknown_label:
        return unknown_label
    return value


def format_environment_tag(environment: str | None) -> str:
    """Return ``[PROD]``, ``[FORNO]``, or ``[<ENV>]`` for the alert header."""

    normalized = (environment or "").strip().lower()
    if normalized == "prod":
        return "[PROD]"
    if normalized == "forno":
        return "[FORNO]"
    if normalized:
        return f"[{normalized.upper()}]"
    return "[UNKNOWN]"


def _parse_partition_parts(value: str) -> dict[str, str]:
    parts: dict[str, str] = {}
    normalized = value.replace("/", "|")
    for segment in normalized.split("|"):
        if "=" not in segment:
            continue
        name, part_value = segment.split("=", 1)
        parts[name.strip()] = part_value.strip()
    return parts


def format_partition_label(value: str | None) -> str:
    """Render partition fingerprints as ``YYYY-MM-DD`` when possible."""
    if not value or not str(value).strip() or value == UNKNOWN_PARTITION:
        return "unknown"
    text = str(value).strip()
    parts = _parse_partition_parts(text)
    if not all(key in parts for key in ("year", "month", "day")):
        return text
    try:
        return date(
            int(parts["year"]),
            int(parts["month"]),
            int(parts["day"]),
        ).isoformat()
    except (TypeError, ValueError):
        return text


def format_finding_message(finding: Finding) -> str:
    table_fqn = f"{finding['database']}.{finding['table']}"
    partition_label = format_partition_label(finding.get("partition_fingerprint"))
    latest_with_data = finding.get("latest_partition_with_data")
    if not latest_with_data:
        latest_with_data = finding.get("latest_partition_value")
    latest_label = format_partition_label(
        str(latest_with_data) if latest_with_data else None
    )
    table_owner = _display_owner(finding.get("table_owner"), UNKNOWN_OWNER)
    team_owner = _display_owner(finding.get("team_owner"), UNKNOWN_TEAM)
    sla_brief = finding.get("sla_summary") or format_empty_partition_sla_brief()
    env_tag = format_environment_tag(finding.get("environment"))
    contact = (
        f"{table_owner} · {team_owner}"
        if table_owner != UNKNOWN_OWNER and team_owner != UNKNOWN_TEAM
        else table_owner
        if table_owner != UNKNOWN_OWNER
        else team_owner
    )
    lines = [
        f"{env_tag} {ALERT_HEADER}",
        f"Table: `{table_fqn}`",
        f"Partition {partition_label} is empty (0 rows). Last with data: {latest_label}.",
        f"SLA: {sla_brief}.",
        "Action: verify the load produced rows for this partition.",
        f"Contact: {contact}",
    ]
    text = "\n".join(lines)
    if len(text) > GCHAT_TEXT_MAX:
        return text[: GCHAT_TEXT_MAX - 3] + "..."
    return text
