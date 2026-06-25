#!/usr/bin/env python3
"""Derive report CSVs from bundle / all-readers outputs (no extra Databricks SQL)."""

from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path
from typing import Any

from csv_utils import write_csv

TRINO_DERIVED = (
    "trino_runtime_by_tool",
    "trino_superset_reason",
    "metabase_summary",
    "trino_adhoc_executors",
)

RUNTIME_FIELDS = [
    "tool",
    "executions_90d",
    "distinct_users_90d",
    "user_days_90d",
    "avg_users_per_day_90d",
    "executions_30d",
    "distinct_users_30d",
    "user_days_30d",
    "avg_users_per_day_30d",
]

REASON_FIELDS = ["query_reason", "executions_90d", "executions_30d"]

SUMMARY_FIELDS = [
    "distinct_cards_90d",
    "distinct_cards_30d",
    "executions_cards_90d",
    "executions_cards_30d",
    "executions_sem_card_90d",
    "executions_sem_card_30d",
]

ADHOC_FIELDS = ["tool", "executor_user", "executions_90d", "executions_30d", "active_days_90d"]

READS_FIELDS = [
    "grain",
    "user_email",
    "reads_90d",
    "writes_90d",
    "reads_30d",
    "distinct_readers_90d",
    "distinct_readers_30d",
    "user_days_90d",
    "avg_readers_per_day_90d",
    "first_access",
    "last_access",
]

CONTACT_FIELDS = ["contact_email", "cards_executed_90d", "executions_90d", "executions_30d"]


def _read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open(encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def _float(val: str | None) -> float:
    if val is None or val == "":
        return 0.0
    return float(val)


def _int(val: str | None) -> int:
    if val is None or val == "":
        return 0
    return int(float(val))


def split_trino_usage_bundle(rows: list[dict[str, str]]) -> dict[str, list[dict[str, str]]]:
    runtime: list[dict[str, str]] = []
    reason: list[dict[str, str]] = []
    summary: list[dict[str, str]] = []
    adhoc: list[dict[str, str]] = []

    for row in rows:
        kind = row.get("result_kind", "")
        if kind == "runtime_by_tool":
            runtime.append(
                {
                    "tool": row.get("dim_a", ""),
                    "executions_90d": row.get("m1", ""),
                    "distinct_users_90d": row.get("m2", ""),
                    "user_days_90d": row.get("m3", ""),
                    "avg_users_per_day_90d": row.get("m4", ""),
                    "executions_30d": row.get("m5", ""),
                    "distinct_users_30d": row.get("m6", ""),
                    "user_days_30d": row.get("m7", ""),
                    "avg_users_per_day_30d": row.get("m8", ""),
                }
            )
        elif kind == "superset_reason":
            reason.append(
                {
                    "query_reason": row.get("dim_a", ""),
                    "executions_90d": row.get("m1", ""),
                    "executions_30d": row.get("m2", ""),
                }
            )
        elif kind == "metabase_summary":
            summary.append(
                {
                    "distinct_cards_90d": row.get("m1", ""),
                    "distinct_cards_30d": row.get("m2", ""),
                    "executions_cards_90d": row.get("m3", ""),
                    "executions_cards_30d": row.get("m4", ""),
                    "executions_sem_card_90d": row.get("m5", ""),
                    "executions_sem_card_30d": row.get("m6", ""),
                }
            )
        elif kind == "adhoc_executor":
            adhoc.append(
                {
                    "tool": row.get("dim_a", ""),
                    "executor_user": row.get("dim_b", ""),
                    "executions_90d": row.get("m1", ""),
                    "executions_30d": row.get("m2", ""),
                    "active_days_90d": row.get("m3", ""),
                }
            )

    runtime.sort(key=lambda r: _int(r.get("executions_90d")), reverse=True)
    reason.sort(key=lambda r: _int(r.get("executions_90d")), reverse=True)
    adhoc.sort(key=lambda r: _int(r.get("executions_90d")), reverse=True)

    return {
        "trino_runtime_by_tool": runtime,
        "trino_superset_reason": reason,
        "metabase_summary": summary,
        "trino_adhoc_executors": adhoc,
    }


def build_trino_adhoc_top(executors: list[dict[str, str]], *, limit: int = 15) -> list[dict[str, str]]:
    return executors[:limit]


def build_metabase_card_contacts(
    active_cards: list[dict[str, str]], *, limit: int | None = None
) -> list[dict[str, str]]:
    by_email: dict[str, dict[str, Any]] = defaultdict(
        lambda: {"cards": set(), "executions_90d": 0, "executions_30d": 0}
    )
    for row in active_cards:
        email = (row.get("creator_email") or "").strip()
        if not email:
            continue
        entry = by_email[email]
        entry["cards"].add(row.get("card_id", ""))
        entry["executions_90d"] += _int(row.get("executions_90d"))
        entry["executions_30d"] += _int(row.get("executions_30d"))

    rows = [
        {
            "contact_email": email,
            "cards_executed_90d": str(len(info["cards"])),
            "executions_90d": str(info["executions_90d"]),
            "executions_30d": str(info["executions_30d"]),
        }
        for email, info in by_email.items()
    ]
    rows.sort(key=lambda r: _int(r.get("executions_90d")), reverse=True)
    return rows if limit is None else rows[:limit]


def build_databricks_reads(all_readers: list[dict[str, str]], *, top_n: int = 25) -> list[dict[str, str]]:
    if not all_readers:
        return []

    total_reads_90d = sum(_int(r.get("reads_90d")) for r in all_readers)
    total_writes_90d = sum(_int(r.get("writes_90d")) for r in all_readers)
    total_reads_30d = sum(_int(r.get("reads_30d")) for r in all_readers)
    readers_90d = {r["user_email"] for r in all_readers if r.get("user_email")}
    readers_30d = {r["user_email"] for r in all_readers if _int(r.get("reads_30d")) > 0}
    user_days_90d = sum(_int(r.get("active_days_90d")) for r in all_readers)
    first_accesses = [r.get("first_access") for r in all_readers if r.get("first_access")]
    last_accesses = [r.get("last_access") for r in all_readers if r.get("last_access")]
    first_access = min(first_accesses) if first_accesses else ""
    last_access = max(last_accesses) if last_accesses else ""

    total_row = {
        "grain": "TOTAL",
        "user_email": "",
        "reads_90d": str(total_reads_90d),
        "writes_90d": str(total_writes_90d),
        "reads_30d": str(total_reads_30d),
        "distinct_readers_90d": str(len(readers_90d)),
        "distinct_readers_30d": str(len(readers_30d)),
        "user_days_90d": str(user_days_90d),
        "avg_readers_per_day_90d": str(round(len(readers_90d) / 90.0, 2)),
        "first_access": first_access,
        "last_access": last_access,
    }

    top_users = sorted(all_readers, key=lambda r: _int(r.get("reads_90d")), reverse=True)[:top_n]
    user_rows = [
        {
            "grain": "USER",
            "user_email": row.get("user_email", ""),
            "reads_90d": row.get("reads_90d", ""),
            "writes_90d": row.get("writes_90d", ""),
            "reads_30d": row.get("reads_30d", ""),
            "distinct_readers_90d": "",
            "distinct_readers_30d": "",
            "user_days_90d": row.get("active_days_90d", ""),
            "avg_readers_per_day_90d": "",
            "first_access": row.get("first_access", ""),
            "last_access": row.get("last_access", ""),
        }
        for row in top_users
    ]
    return [total_row, *user_rows]


def postprocess_raw_dir(raw_dir: Path) -> list[str]:
    """Write derived CSVs; return names of files written."""
    written: list[str] = []

    bundle_path = raw_dir / "trino_usage_bundle.csv"
    if bundle_path.exists():
        bundle_rows = _read_csv(bundle_path)
        split = split_trino_usage_bundle(bundle_rows)
        for name, rows in split.items():
            write_csv(raw_dir / f"{name}.csv", rows)
            written.append(name)

        top = build_trino_adhoc_top(split["trino_adhoc_executors"])
        write_csv(raw_dir / "trino_adhoc_top.csv", top)
        written.append("trino_adhoc_top")

    active_cards_path = raw_dir / "metabase_active_cards.csv"
    if active_cards_path.exists():
        active_cards = _read_csv(active_cards_path)
        contacts = build_metabase_card_contacts(active_cards)
        write_csv(raw_dir / "metabase_card_contacts.csv", contacts)
        written.append("metabase_card_contacts")

    all_readers_path = raw_dir / "databricks_all_readers.csv"
    if all_readers_path.exists():
        all_readers = _read_csv(all_readers_path)
        reads = build_databricks_reads(all_readers)
        write_csv(raw_dir / "databricks_reads.csv", reads)
        written.append("databricks_reads")

    return written
