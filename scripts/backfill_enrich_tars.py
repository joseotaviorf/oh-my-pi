#!/usr/bin/env python3
# /// script
# dependencies = ["httpx"]
# ///
"""
One-shot backfill for enrich_tars.

Triggers one DAG run per calendar day from START_DATE to END_DATE (inclusive),
passing load_start_date + load_end_date = that day, run_type = test_run so
downstream dataset events are NOT emitted during the catch-up.

Usage:
  uv run --script scripts/backfill_enrich_tars.py
"""

import asyncio
import os
from datetime import date, timedelta

import httpx

AIRFLOW_API_URL = os.environ["AIRFLOW_API_URL"].rstrip("/")
AIRFLOW_AUTH_TOKEN = os.environ["AIRFLOW_AUTH_TOKEN"]
DAG_ID = "bietlejuice.enrich_tars"

# Vector sink started 2026-08-12. Do NOT backfill query_annotations before that
# date — S3 has no earlier objects and re-runs would wipe Trino-derived history.
START_DATE = date(2026, 8, 12)
END_DATE = date(2026, 8, 12)

HEADERS = {
    "Authorization": f"Bearer {AIRFLOW_AUTH_TOKEN}",
    "Content-Type": "application/json",
}


def date_range(start: date, end: date):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)


async def trigger(client: httpx.AsyncClient, d: date) -> tuple[date, str, str]:
    ds = d.isoformat()
    payload = {
        "dag_run_id": f"manual_catchup__{ds}",
        "conf": {
            "load_start_date": ds,
            "load_end_date": ds,
            "run_type": "test_run",
        },
        "logical_date": f"{ds}T06:00:00+00:00",
        "note": "cursor backfill enrich_tars 2026-06-18 → 2026-07-04",
    }
    try:
        r = await client.post(
            f"{AIRFLOW_API_URL}/dags/{DAG_ID}/dagRuns",
            json=payload,
            timeout=30,
        )
        if r.status_code == 200:
            state = r.json().get("state", "queued")
            return d, "TRIGGERED", state
        elif r.status_code == 409:
            return d, "SKIPPED", "already exists"
        else:
            return d, "ERROR", f"HTTP {r.status_code}: {r.text[:120]}"
    except Exception as exc:
        return d, "ERROR", str(exc)


async def main() -> None:
    days = list(date_range(START_DATE, END_DATE))
    print(f"Backfilling {len(days)} days: {START_DATE} → {END_DATE}")
    print(f"DAG: {DAG_ID}  |  run_type: test_run\n")

    async with httpx.AsyncClient(headers=HEADERS) as client:
        # Trigger in batches of 5 to avoid overwhelming Airflow
        for i in range(0, len(days), 5):
            batch = days[i : i + 5]
            results = await asyncio.gather(*[trigger(client, d) for d in batch])
            for d, status, detail in results:
                print(f"  {d}  {status:<10} {detail}")
            await asyncio.sleep(1)

    print("\nDone — check the Airflow UI to monitor progress.")


if __name__ == "__main__":
    asyncio.run(main())
