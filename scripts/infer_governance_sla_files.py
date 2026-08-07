# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml", "trino", "pandas", "keyring"]
# ///

"""Infer sla/<layer>/<table>.yml for governance DAGs with profiling enabled."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

REPO = Path(__file__).resolve().parents[1]
DAGS = REPO / "dags" / "governance"
PARTITION_COLS = {"year", "month", "day"}
WEEKDAY_NAMES = ("mon", "tue", "wed", "thu", "fri", "sat", "sun")
WEEKDAYS = {0, 1, 2, 3, 4}


def cron_earliest_hour(schedule: str) -> int | None:
    if not schedule or not str(schedule).strip():
        return None
    parts = str(schedule).split()
    if len(parts) < 2:
        return None
    hour_field = parts[1]
    try:
        if "-" in hour_field:
            hour = int(hour_field.split("-", 1)[0])
        elif "," in hour_field:
            hour = int(hour_field.split(",", 1)[0])
        else:
            hour = int(hour_field)
    except ValueError:
        return None
    return min(hour + 2, 23)


def cron_runs_weekdays_only(schedule: str) -> bool:
    if not schedule or len(str(schedule).split()) < 5:
        return False
    dow = str(schedule).split()[4]
    return dow in {"1-5", "MON-FRI", "mon-fri"}


def list_targets() -> list[dict]:
    rows: list[dict] = []
    for decl_path in sorted(DAGS.glob("**/*_declaration.yml")):
        content = yaml.safe_load(decl_path.read_text()) or {}
        wf = content.get("workflow") or {}
        obs = wf.get("observability") or {}
        if obs.get("enabled") is not True:
            continue
        dag = content.get("dag") or {}
        dag_name = dag.get("name") or decl_path.parent.name
        schedule = dag.get("schedule_interval") or ""
        layer = wf.get("layer", "enrich")
        default_partitions = set(wf.get("default_partitions") or [])
        tables_custom = wf.get("tables_customization") or {}
        dag_folder = decl_path.parent

        table_names: set[str] = set(tables_custom)
        queries_dir = dag_folder / "queries" / layer
        if queries_dir.is_dir():
            table_names.update(p.stem for p in queries_dir.glob("*.sql"))

        for table in sorted(table_names):
            meta_path = dag_folder / "metadata" / layer / f"{table}.yml"
            if not meta_path.exists():
                continue
            meta = yaml.safe_load(meta_path.read_text()) or {}
            database_name = meta.get("database_name")
            if not database_name:
                continue
            tc = tables_custom.get(table) or {}
            parts = set(tc.get("partitions") or default_partitions or [])
            cols = set((meta.get("columns") or {}).keys())
            if not PARTITION_COLS.issubset(parts) and not PARTITION_COLS.issubset(cols):
                continue
            sla_path = dag_folder / "sla" / layer / f"{table}.yml"
            if sla_path.exists():
                continue
            rows.append(
                {
                    "dag_folder": dag_folder,
                    "dag_name": dag_name,
                    "layer": layer,
                    "table": table,
                    "database_name": database_name,
                    "schedule": schedule,
                    "sla_path": sla_path,
                }
            )
    return rows


def trino_weekday_histogram(database_name: str, table_name: str) -> dict:
    query = f"""
SELECT day_of_week(
         date_parse(
           CAST(year AS varchar) || '-' ||
           lpad(CAST(month AS varchar), 2, '0') || '-' ||
           lpad(CAST(day AS varchar), 2, '0'),
           '%Y-%m-%d'
         )
       ) AS dow,
       COUNT(DISTINCT date_parse(
         CAST(year AS varchar) || '-' ||
         lpad(CAST(month AS varchar), 2, '0') || '-' ||
         lpad(CAST(day AS varchar), 2, '0'),
         '%Y-%m-%d'
       )) AS partition_days
FROM hive.{database_name}.{table_name}
WHERE date_parse(
        CAST(year AS varchar) || '-' ||
        lpad(CAST(month AS varchar), 2, '0') || '-' ||
        lpad(CAST(day AS varchar), 2, '0'),
        '%Y-%m-%d'
      ) >= current_date - INTERVAL '56' DAY
GROUP BY 1
ORDER BY 1
LIMIT 20
""".strip()
    user = os.environ.get("TRINO_USER", "")
    cmd = [
        "uv",
        "run",
        "--script",
        str(REPO / ".cursor/skills/trino/scripts/execute_trino.py"),
        "--host",
        os.environ.get("TRINO_HOST", "trino.apps.data-prd.habitat.zone"),
        "--catalog",
        "hive",
        "--query",
        query,
        "--external-auth",
    ]
    if user:
        cmd.extend(["--user", user])
    proc = subprocess.run(cmd, cwd=REPO, capture_output=True, text=True)
    if proc.returncode != 0:
        return {"error": proc.stderr or proc.stdout}
    try:
        payload = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return {"error": proc.stdout[-500:]}
    if payload.get("status") != "success":
        return {"error": payload.get("message", "unknown trino error")}
    hist: dict[int, int] = {}
    for row in payload.get("data") or []:
        hist[int(row[0])] = int(row[1])
    return {"histogram": hist, "total_days": sum(hist.values())}


def dow_to_days_of_week(hist: dict[int, int]) -> tuple[object, set[int]]:
    """Trino dow 1=Mon..7=Sun -> our weekday indices 0..6."""
    observed = {d - 1 for d in hist if hist[d] > 0}
    if not observed:
        return "all", set()
    if observed == set(range(7)):
        return "all", observed
    if observed == WEEKDAYS:
        return "weekdays", observed
    return [WEEKDAY_NAMES[i] for i in sorted(observed)], observed


def build_sla(target: dict, hist_result: dict) -> dict:
    reviews: list[str] = []
    schedule = target["schedule"]
    earliest_hour = cron_earliest_hour(schedule)
    if earliest_hour is None:
        earliest_hour = 9
        reviews.append("no schedule_interval in declaration; earliest_hour defaulted to 09")

    if "error" in hist_result:
        days_of_week: object = "all"
        reviews.append(f"trino history unavailable: {hist_result['error'][:120]}")
    else:
        total_days = hist_result.get("total_days", 0)
        days_of_week, observed = dow_to_days_of_week(hist_result.get("histogram", {}))
        if total_days < 28:
            reviews.append(f"sparse history ({total_days} partition-days in 56d lookback)")
        if cron_runs_weekdays_only(schedule) and observed - WEEKDAYS:
            reviews.append("observed weekend partitions but cron is weekdays-only")
        if isinstance(days_of_week, list) and not days_of_week:
            days_of_week = "all"

    reason_bits = []
    if schedule:
        reason_bits.append(f"{target['dag_name']} runs {schedule}")
    else:
        reason_bits.append(f"{target['dag_name']} has no cron (upstream-triggered)")
    if "histogram" in hist_result:
        reason_bits.append("observed cadence from Trino 56d lookback")
    for note in reviews:
        reason_bits.append(f"note: {note}")

    arrival: dict = {
        "days_of_week": days_of_week,
        "earliest_hour": earliest_hour,
        "reason": "; ".join(reason_bits),
        "source": "inferred",
    }
    content = {
        "database_name": target["database_name"],
        "table_name": target["table"],
        "arrival": arrival,
    }
    return content


def render_yaml(content: dict) -> str:
    return yaml.safe_dump(content, sort_keys=False, allow_unicode=True)


def main() -> int:
    targets = list_targets()
    print(f"Generating SLA files for {len(targets)} tables...")
    created = 0
    for target in targets:
        print(f"  infer {target['database_name']}.{target['table']} ...", flush=True)
        hist = trino_weekday_histogram(target["database_name"], target["table"])
        content = build_sla(target, hist)
        target["sla_path"].parent.mkdir(parents=True, exist_ok=True)
        target["sla_path"].write_text(render_yaml(content), encoding="utf-8")
        created += 1
    print(f"Created {created} SLA file(s).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
