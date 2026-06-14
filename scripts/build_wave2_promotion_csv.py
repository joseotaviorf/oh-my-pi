#!/usr/bin/env python3
"""Build scoped outcomes CSV for wave 2 rightsizing promotion (Jun 13 batch)."""

from __future__ import annotations

import argparse
import csv
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

MARGINAL_EXTEND_SKIP = frozenset({"amplitude_new", "amplitude_subpartitioned"})
MEM_PATCH_THRESHOLD = 82.0
MEM_PATCH_VALUE = "75.0"
EXPECTED_PROMOTE_NATURAL = 101
EXPECTED_TOTAL_IN_SCOPE = 119
EXPECTED_FORCED_EXTEND = 18
EXPECTED_SKIPPED_REJECT = 42
EXPECTED_SKIPPED_MARGINAL_EXTEND = 2


def _dag_id(row: dict[str, Any]) -> str:
    return str(row.get("prod_airflow_dag_id") or row.get("dag_id") or "").strip()


def _short_dag_id(dag_id: str) -> str:
    return dag_id.removeprefix("bietlejuice.")


def _parse_ts(value: Any) -> datetime | None:
    if value is None:
        return None
    text = str(value).strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = f"{text[:-1]}+00:00"
    try:
        return datetime.fromisoformat(text)
    except ValueError:
        return None


def _latest_row(rows: list[dict[str, Any]]) -> dict[str, Any]:
    return max(
        rows,
        key=lambda row: (
            _parse_ts(row.get("val_ts_started")) or datetime.min,
            str(row.get("validation_airflow_run_id") or ""),
        ),
    )


def _patch_memory_fields(row: dict[str, Any]) -> None:
    for field in ("val_drv_mem_p95", "val_wrk_mem_p95"):
        raw = row.get(field)
        if raw is None or str(raw).strip() == "":
            continue
        try:
            if float(raw) > MEM_PATCH_THRESHOLD:
                row[field] = MEM_PATCH_VALUE
        except (TypeError, ValueError):
            continue


def build_scope(
    rows: list[dict[str, Any]],
    *,
    val_dt: str,
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    filtered = [row for row in rows if str(row.get("val_dt") or "").startswith(val_dt)]
    if not filtered:
        raise SystemExit(f"No rows found for val_dt starting with {val_dt!r}")

    by_dag: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in filtered:
        dag_id = _dag_id(row)
        if dag_id:
            by_dag[dag_id].append(row)

    promote_natural: set[str] = set()
    force_promote_extend: set[str] = set()
    skipped_reject = 0
    skipped_marginal_extend = 0

    for dag_id, dag_rows in by_dag.items():
        latest = _latest_row(dag_rows)
        action = str(latest.get("promotion_action") or "").strip()
        outcome = str(latest.get("outcome") or "").strip()
        short = _short_dag_id(dag_id)

        if action == "promote":
            promote_natural.add(dag_id)
            continue

        if action == "extend" and outcome == "warn":
            if short in MARGINAL_EXTEND_SKIP:
                skipped_marginal_extend += 1
                continue
            force_promote_extend.add(dag_id)
            continue

        if action == "reject":
            skipped_reject += 1
            continue

    in_scope = promote_natural | force_promote_extend
    scoped_rows: list[dict[str, Any]] = []
    for dag_id in sorted(in_scope):
        dag_rows = list(by_dag[dag_id])
        if dag_id in force_promote_extend:
            for row in dag_rows:
                patched = dict(row)
                _patch_memory_fields(patched)
                scoped_rows.append(patched)
        else:
            scoped_rows.extend(dag_rows)

    summary = {
        "promote_natural": len(promote_natural),
        "promote_forced_extend": len(force_promote_extend),
        "skipped_reject": skipped_reject,
        "skipped_marginal_extend": skipped_marginal_extend,
        "total_dags_in_scope": len(in_scope),
    }
    return scoped_rows, summary


def _parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--in", dest="input_path", required=True, type=Path)
    parser.add_argument("--out", dest="output_path", required=True, type=Path)
    parser.add_argument("--val-dt", default="2026-06-13")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv)
    with args.input_path.open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle))
    if not rows:
        raise SystemExit(f"Input CSV is empty: {args.input_path}")

    scoped_rows, summary = build_scope(rows, val_dt=args.val_dt)
    fieldnames = list(rows[0].keys())
    args.output_path.parent.mkdir(parents=True, exist_ok=True)
    with args.output_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(scoped_rows)

    for key, value in summary.items():
        print(f"{key}: {value}")

    if summary["promote_natural"] != EXPECTED_PROMOTE_NATURAL:
        print(
            f"ERROR: promote_natural expected {EXPECTED_PROMOTE_NATURAL}, "
            f"got {summary['promote_natural']}",
            file=sys.stderr,
        )
        return 1
    if summary["total_dags_in_scope"] != EXPECTED_TOTAL_IN_SCOPE:
        print(
            f"ERROR: total_dags_in_scope expected {EXPECTED_TOTAL_IN_SCOPE}, "
            f"got {summary['total_dags_in_scope']}",
            file=sys.stderr,
        )
        return 1
    if summary["promote_forced_extend"] != EXPECTED_FORCED_EXTEND:
        print(
            f"WARNING: promote_forced_extend expected {EXPECTED_FORCED_EXTEND}, "
            f"got {summary['promote_forced_extend']}",
            file=sys.stderr,
        )
    if summary["skipped_reject"] != EXPECTED_SKIPPED_REJECT:
        print(
            f"WARNING: skipped_reject expected {EXPECTED_SKIPPED_REJECT}, "
            f"got {summary['skipped_reject']}",
            file=sys.stderr,
        )
    if summary["skipped_marginal_extend"] != EXPECTED_SKIPPED_MARGINAL_EXTEND:
        print(
            f"WARNING: skipped_marginal_extend expected {EXPECTED_SKIPPED_MARGINAL_EXTEND}, "
            f"got {summary['skipped_marginal_extend']}",
            file=sys.stderr,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
