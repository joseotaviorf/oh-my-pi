#!/usr/bin/env python3
"""
Run the canonical stale-DAG query against the QuintoAndar Trino cluster.

Usage:
    .cursor/skills/trino/venv/bin/python3 .cursor/skills/find-stale-dags/scripts/run_query.py
    .cursor/skills/trino/venv/bin/python3 .cursor/skills/find-stale-dags/scripts/run_query.py --months 12
    .cursor/skills/trino/venv/bin/python3 .cursor/skills/find-stale-dags/scripts/run_query.py --no-filter
"""

import argparse
import sys
from datetime import datetime

import trino

TRINO_HOST = "trino.apps.data-prd.habitat.zone"
TRINO_PORT = 443
TRINO_USER = "airflow"

# DAG types that are not stale by definition
EXCLUDED_SCHEDULES = {"Dataset", "null", None}
EXCLUDED_PREFIXES = ("quintoml.",)

QUERY_TEMPLATE = """
WITH last_success AS (
    SELECT
        id_dag,
        MAX(ts_started) AS ts_last_success
    FROM datalake_astro_clean.dag_run
    WHERE state = 'success'
    GROUP BY 1
),
last_serialized AS (
    SELECT
        id_dag,
        MAX(ts_last_updated) AS ts_last_serialized
    FROM datalake_astro_clean.serialized_dag
    GROUP BY 1
)
SELECT
    d.id_dag,
    d.owners,
    d.schedule_interval,
    ls.ts_last_success,
    lz.ts_last_serialized,
    date_diff('month', ls.ts_last_success, current_date) AS months_since_last_success,
    date_diff('month', lz.ts_last_serialized, current_date) AS months_since_last_change
FROM datalake_astro_clean.dag d
LEFT JOIN last_success ls ON d.id_dag = ls.id_dag
LEFT JOIN last_serialized lz ON d.id_dag = lz.id_dag
WHERE d.year  = year(current_date)
  AND d.month = month(current_date)
  AND d.day   = day(current_date)
  AND d.is_active  = TRUE
  AND d.is_paused  = FALSE
  AND (
      ls.ts_last_success IS NULL
      OR ls.ts_last_success < date_add('month', ?, current_date)
  )
ORDER BY months_since_last_success DESC NULLS FIRST
LIMIT 200
"""


def parse_args():
    p = argparse.ArgumentParser(description="Find stale Airflow DAGs via Trino")
    p.add_argument(
        "--months",
        type=int,
        default=6,
        metavar="N",
        help="Stale threshold in months (default: 6, allowed: 1–240)",
    )
    p.add_argument("--no-filter", action="store_true", help="Show all stale DAGs incl. manual/event-driven ones")
    p.add_argument("--host", default=TRINO_HOST, help="Trino host")
    return p.parse_args()


def connect(host: str):
    return trino.dbapi.connect(
        host=host,
        port=TRINO_PORT,
        user="airflow",
        http_scheme="https",
        auth=trino.auth.OAuth2Authentication(),
        catalog="hive",
    )


def should_exclude(row: dict) -> bool:
    schedule = str(row["schedule_interval"]).strip('"')
    dag_id = row["id_dag"]
    if schedule in EXCLUDED_SCHEDULES:
        return True
    if any(dag_id.startswith(p) for p in EXCLUDED_PREFIXES):
        return True
    return False


def fmt_date(val) -> str:
    if val is None or str(val) in ("NaT", "None", "nan"):
        return "never"
    if isinstance(val, datetime):
        return val.strftime("%Y-%m-%d")
    return str(val)[:10]


def main():
    args = parse_args()
    if not 1 <= args.months <= 240:
        print("error: --months must be between 1 and 240", file=sys.stderr)
        sys.exit(2)

    print(f"\n🔍 Querying Trino for DAGs with no success in {args.months}+ months …")
    print(f"   Host: {args.host}")

    conn = connect(args.host)
    cur = conn.cursor()
    # Pass negative month delta as a bound parameter (avoids string-built SQL).
    cur.execute(QUERY_TEMPLATE, (-args.months,))

    cols = [d[0] for d in cur.description]
    rows = [dict(zip(cols, r)) for r in cur.fetchall()]

    if not args.no_filter:
        excluded = [r for r in rows if should_exclude(r)]
        rows = [r for r in rows if not should_exclude(r)]
        if excluded:
            print(f"\n   ↳ Filtered out {len(excluded)} event-driven / manual DAG(s) (use --no-filter to see them)")

    if not rows:
        print("\n✅ No stale scheduled DAGs found.\n")
        return

    # Group by owner
    by_owner: dict[str, list] = {}
    for r in rows:
        owner = r["owners"] or "unknown"
        by_owner.setdefault(owner, []).append(r)

    print(f"\n🕸️  {len(rows)} stale DAG(s) found (threshold: {args.months} months)\n")
    print(f"{'DAG ID':<60} {'SCHEDULE':<18} {'LAST SUCCESS':<14} {'MO':>4}")
    print("─" * 100)

    for owner, owner_rows in sorted(by_owner.items()):
        print(f"\n  👤 {owner} ({len(owner_rows)})")
        for r in owner_rows:
            mo = r["months_since_last_success"]
            mo_str = str(int(mo)) if mo and str(mo) not in ("nan", "None") else "∞"
            print(f"    {r['id_dag']:<56} {str(r['schedule_interval']):<18} {fmt_date(r['ts_last_success']):<14} {mo_str:>4}")

    print(f"\n{'─' * 100}")
    print(f"Total: {len(rows)} stale scheduled DAG(s)\n")

    if not args.no_filter and excluded:
        print("Excluded (event-driven / manual):")
        for r in excluded:
            print(f"  • {r['id_dag']}  schedule={r['schedule_interval']}")
        print()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nCancelled.")
        sys.exit(1)
