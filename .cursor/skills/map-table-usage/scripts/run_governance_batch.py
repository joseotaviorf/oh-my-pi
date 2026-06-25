#!/usr/bin/env python3
"""Run map-table-usage governance queries on Databricks (Commands API 1.2).

Reuses DatabricksAPI from databricks-emr-migration skill — same pattern as EMR migration
baseline/compare, but for read-only governance SQL against UC tables.

Writes tabular results directly as CSV under {output_dir}/{slug}_raw_data/.
Context (date windows, catalog, cluster) belongs in the analysis/queries markdown — not in CSV.
"""

from __future__ import annotations

import argparse
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPT_DIR.parent
REPO_ROOT = SKILL_DIR.parents[2]
MIGRATION_SKILL = REPO_ROOT / ".cursor" / "skills" / "databricks-emr-migration"
sys.path.insert(0, str(MIGRATION_SKILL))
sys.path.insert(0, str(SCRIPT_DIR))

from csv_utils import count_rows, write_csv  # noqa: E402
from databricks_client import DatabricksAPI  # noqa: E402
from governance_queries import QuerySpec, build_governance_queries  # noqa: E402
from postprocess_csvs import TRINO_DERIVED, postprocess_raw_dir  # noqa: E402


def _windows(end: date) -> tuple[str, str, str]:
    end_s = end.isoformat()
    start_90 = (end - timedelta(days=90)).isoformat()
    start_30 = (end - timedelta(days=30)).isoformat()
    return start_90, end_s, start_30


def _save_query_csv(out_dir: Path, spec: QuerySpec, parsed: Any) -> None:
    csv_path = out_dir / f"{spec.name}.csv"
    rows = parsed.row_dicts if parsed else []
    write_csv(csv_path, rows)


def _csv_has_data(path: Path) -> bool:
    return path.exists() and count_rows(path) > 0


def _trino_bundle_complete(out_csv: Path) -> bool:
    # Only require that derived CSVs exist — empty results (no Superset reasons,
    # no ad-hoc executors, etc.) are legitimate and should not force a re-run.
    return all((out_csv / f"{name}.csv").exists() for name in TRINO_DERIVED)


def _should_skip_spec(out_csv: Path, spec: QuerySpec, *, skip_existing: bool) -> bool:
    if not skip_existing:
        return False
    csv_path = out_csv / f"{spec.name}.csv"
    if spec.name == "trino_usage_bundle":
        return _csv_has_data(csv_path) and _trino_bundle_complete(out_csv)
    return _csv_has_data(csv_path)


def run_batch(
    *,
    schema: str,
    table: str,
    catalog: str,
    cluster: str,
    profile: str,
    output_dir: Path,
    end_date: date,
    timeout_sec: int,
    skip_existing: bool,
) -> dict[str, Any]:
    slug = f"{schema}__{table}"
    start_90d, end_90d, start_30d = _windows(end_date)
    table_full_uc = f"{catalog}.{schema}.{table}"

    specs = build_governance_queries(
        catalog=catalog,
        schema=schema,
        table=table,
        start_90d=start_90d,
        end_90d=end_90d,
        start_30d=start_30d,
    )

    out_csv = output_dir / f"{slug}_raw_data"
    out_csv.mkdir(parents=True, exist_ok=True)

    run_context = {
        "schema": schema,
        "table": table,
        "catalog": catalog,
        "table_full_uc": table_full_uc,
        "window_90d": {"start": start_90d, "end": end_90d},
        "window_30d": {"start": start_30d, "end": end_90d},
        "cluster": cluster,
        "profile": profile,
    }

    print(
        f"Windows: 90d {start_90d} → {end_90d} · 30d {start_30d} → {end_90d}",
        flush=True,
    )

    api = DatabricksAPI(profile, cluster, timeout_sec=timeout_sec)
    if not api.open_context():
        raise RuntimeError("Failed to open Databricks SQL context")

    written: list[str] = []

    try:
        for spec in specs:
            if _should_skip_spec(out_csv, spec, skip_existing=skip_existing):
                print(f"Skipping {spec.name} (existing CSV)", flush=True)
                written.append(spec.name)
                continue

            print(f"Running {spec.name} ...", flush=True)
            parsed = api.execute_sql(spec.sql)
            _save_query_csv(out_dir=out_csv, spec=spec, parsed=parsed)
            written.append(spec.name)

        derived = postprocess_raw_dir(out_csv)
        if derived:
            print(f"Post-processed CSVs: {', '.join(derived)}", flush=True)
            written.extend(derived)
    finally:
        api.close_context()

    print(f"CSV batch written to {out_csv} ({len(written)} files)")
    return {"context": run_context, "written": written}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", required=True, help="Lake schema, e.g. dw_public")
    parser.add_argument("--table", required=True, help="Table name, e.g. fact_house_listings")
    parser.add_argument(
        "--cluster",
        required=True,
        help="Running Databricks all-purpose cluster id (ask the user; do not auto-discover)",
    )
    parser.add_argument("--profile", default="PROD", help="Databricks CLI profile (default: PROD)")
    parser.add_argument("--catalog", default="quintoandar_prod", help="Unity Catalog name")
    parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Output directory, e.g. table_usage_map/dw_public__fact_house_listings/2026-06-16",
    )
    parser.add_argument("--end-date", default=date.today().isoformat(), help="Window end (YYYY-MM-DD)")
    parser.add_argument("--timeout-sec", type=int, default=300, help="Per-query timeout (default 300s)")
    parser.add_argument(
        "--skip-existing",
        action="store_true",
        help="Skip queries whose CSV already exists with data rows",
    )
    args = parser.parse_args()

    end = date.fromisoformat(args.end_date)
    try:
        run_batch(
            schema=args.schema,
            table=args.table,
            catalog=args.catalog,
            cluster=args.cluster,
            profile=args.profile,
            output_dir=args.output_dir.resolve(),
            end_date=end,
            timeout_sec=args.timeout_sec,
            skip_existing=args.skip_existing,
        )
    except Exception as exc:
        print(f"Batch failed: {exc}", flush=True)
        raise SystemExit(1) from exc


if __name__ == "__main__":
    main()
