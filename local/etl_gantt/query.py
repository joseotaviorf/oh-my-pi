"""Build upstream-lineage + median time-of-day SQL for ETL Gantt."""

from __future__ import annotations

from collections.abc import Mapping, Sequence
from datetime import date, timedelta
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from lineage import Hop

JobHop = tuple[str, str]
SeedJob = tuple[str, str, str]

QUERY_ROW_LIMIT = 100_000
LOOKUP_TASK = "task_id"
LOOKUP_TABLE = "table_name"
MAX_DATE_SPAN_DAYS = 30
DUMP_PARTITION_PAD_DAYS = 1


class QueryError(ValueError):
    """Raised when query parameters are invalid."""


def _sql_string_literal(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def _partition_key(value: date) -> int:
    return value.year * 10000 + value.month * 100 + value.day


def _job_hops_sql(job_hops: Mapping[JobHop, Hop]) -> str:
    rows = [
        (dag, task, hop)
        for (dag, task), hop in sorted(
            job_hops.items(),
            key=lambda item: (item[1].level, item[0][0], item[0][1]),
        )
        if hop.level >= 1
    ]
    if not rows:
        return ""
    values = ",\n            ".join(
        f"({_sql_string_literal(dag)}, {_sql_string_literal(task)}, "
        f"{int(hop.level)}, {'TRUE' if hop.first_run_of_day else 'FALSE'})"
        for dag, task, hop in rows
    )
    return (
        "    UNION\n"
        "    SELECT\n"
        "        tt.table_name,\n"
        "        job_hops.level,\n"
        "        job_hops.first_run_of_day,\n"
        "        job_hops.id_dag,\n"
        "        job_hops.id_task\n"
        "    FROM (\n"
        "        VALUES\n"
        f"            {values}\n"
        "    ) AS job_hops (id_dag, id_task, level, first_run_of_day)\n"
        "    LEFT JOIN task_table_map AS tt\n"
        "        ON job_hops.id_dag = tt.id_dag\n"
        "        AND job_hops.id_task = tt.id_task\n"
    )


def _seed_jobs_sql(seed_jobs: Sequence[SeedJob]) -> str:
    values = ",\n            ".join(
        f"({_sql_string_literal(dag)}, {_sql_string_literal(task)}, "
        f"{_sql_string_literal(table)})"
        for dag, task, table in seed_jobs
    )
    return (
        "    SELECT\n"
        "        seed.table_name,\n"
        "        0 AS level,\n"
        "        FALSE AS first_run_of_day,\n"
        "        seed.id_dag,\n"
        "        seed.id_task\n"
        "    FROM (\n"
        "        VALUES\n"
        f"            {values}\n"
        "    ) AS seed (id_dag, id_task, table_name)\n"
    )


def build_inventory_sql() -> str:
    """Latest DAG inventory snapshot: dag, task, table, files_location."""
    return (
        "WITH latest_inventory_partition AS (\n"
        "    SELECT\n"
        "        MAX(year * 10000 + month * 100 + day) AS partition_key\n"
        '    FROM hive.datalake_dag_inventory_clean."table"\n'
        ")\n"
        "SELECT DISTINCT\n"
        "    inv.dag AS id_dag,\n"
        "    inv.task AS id_task,\n"
        '    inv."table" AS table_name,\n'
        "    inv.files_location\n"
        'FROM hive.datalake_dag_inventory_clean."table" AS inv\n'
        "CROSS JOIN latest_inventory_partition AS part\n"
        "WHERE inv.year = CAST(part.partition_key / 10000 AS INTEGER)\n"
        "    AND inv.month = CAST("
        "(part.partition_key / 100) % 100 AS INTEGER)\n"
        "    AND inv.day = CAST(part.partition_key % 100 AS INTEGER)"
    )


def build_task_seed_tables_sql(id_task: str) -> str:
    """Resolve the tables an Airflow task writes, per the DAG inventory."""
    task = id_task.strip()
    if not task:
        raise QueryError("Lookup value is required.")
    return (
        "WITH latest_inventory_partition AS (\n"
        "    SELECT\n"
        "        MAX(year * 10000 + month * 100 + day) AS partition_key\n"
        '    FROM hive.datalake_dag_inventory_clean."table"\n'
        ")\n"
        "SELECT DISTINCT\n"
        '    inv."table" AS dependent_table_name\n'
        'FROM hive.datalake_dag_inventory_clean."table" AS inv\n'
        "CROSS JOIN latest_inventory_partition AS part\n"
        "WHERE inv.year = CAST(part.partition_key / 10000 AS INTEGER)\n"
        "    AND inv.month = CAST("
        "(part.partition_key / 100) % 100 AS INTEGER)\n"
        "    AND inv.day = CAST(part.partition_key % 100 AS INTEGER)\n"
        f"    AND inv.task = {_sql_string_literal(task)}"
    )


def build_upstream_runtime_sql(
    start: date,
    end: date,
    seed_jobs: Sequence[SeedJob],
    max_hop_level: int | None = None,
    job_hops: Mapping[JobHop, Hop] | None = None,
    include_before_d0: bool = False,
) -> str:
    if not seed_jobs:
        raise QueryError("No DAG inventory row for that lookup.")
    if end < start:
        raise QueryError("End date must be on or after start date.")
    if (end - start).days + 1 > MAX_DATE_SPAN_DAYS:
        raise QueryError(f"Date window must be at most {MAX_DATE_SPAN_DAYS} days.")
    if max_hop_level is not None and max_hop_level < 1:
        raise QueryError("Max hop level must be at least 1.")

    dump_start = start - timedelta(days=DUMP_PARTITION_PAD_DAYS)
    dump_end = end + timedelta(days=DUMP_PARTITION_PAD_DAYS)
    start_lit = f"DATE '{start.isoformat()}'"
    end_lit = f"DATE '{end.isoformat()}'"
    job_hops_sql = _job_hops_sql(job_hops or {})
    seed_jobs_sql = _seed_jobs_sql(seed_jobs)

    # year/month/day on task_instance are the Astro export snapshot, not the
    # UTC day of ts_started. Incremental dumps overlap (d-1 plus today), so
    # prune a one-day pad on each side and rank runs by CAST(ts_started AS DATE).
    date_filters_ti = (
        f"ti.year BETWEEN {dump_start.year} AND {dump_end.year}\n"
        f"    AND (ti.year * 10000 + ti.month * 100 + ti.day) "
        f"BETWEEN {_partition_key(dump_start)} AND {_partition_key(dump_end)}\n"
        f"    AND CAST(ti.ts_started AS DATE) BETWEEN {start_lit} AND {end_lit}\n"
        f"    AND ti.task_state = 'success'"
    )

    return (
        "WITH latest_inventory_partition AS (\n"
        "    SELECT\n"
        "        MAX(year * 10000 + month * 100 + day) AS partition_key\n"
        '    FROM hive.datalake_dag_inventory_clean."table"\n'
        "),\n"
        "task_table_map AS (\n"
        "    SELECT\n"
        '        MIN(inv."table") AS table_name,\n'
        "        inv.dag AS id_dag,\n"
        "        inv.task AS id_task\n"
        '    FROM hive.datalake_dag_inventory_clean."table" AS inv\n'
        "    CROSS JOIN latest_inventory_partition AS part\n"
        "    WHERE inv.year = CAST(part.partition_key / 10000 AS INTEGER)\n"
        "        AND inv.month = CAST("
        "(part.partition_key / 100) % 100 AS INTEGER)\n"
        "        AND inv.day = CAST(part.partition_key % 100 AS INTEGER)\n"
        "    GROUP BY inv.dag, inv.task\n"
        "),\n"
        "upstream_tasks AS (\n"
        f"{seed_jobs_sql}"
        f"{job_hops_sql}"
        "),\n"
        "successes AS (\n"
        "    SELECT\n"
        "        ti.id_dag,\n"
        "        ti.id_task,\n"
        "        ti.id_run,\n"
        "        MIN(ti.ts_started) AS ts_started,\n"
        "        MAX(ti.ts_ended) AS ts_ended,\n"
        "        CAST(MIN(ti.ts_started) AS DATE) AS run_day\n"
        "    FROM hive.datalake_astro_clean.task_instance AS ti\n"
        "    INNER JOIN upstream_tasks AS ut\n"
        "        ON ti.id_dag = ut.id_dag\n"
        "        AND ti.id_task = ut.id_task\n"
        f"    WHERE {date_filters_ti}\n"
        "        AND ti.ts_started IS NOT NULL\n"
        "        AND ti.ts_ended IS NOT NULL\n"
        "    GROUP BY ti.id_dag, ti.id_task, ti.id_run\n"
        "),\n"
        "day_ranked AS (\n"
        "    SELECT\n"
        "        id_dag,\n"
        "        id_task,\n"
        "        id_run,\n"
        "        ts_started,\n"
        "        ts_ended,\n"
        "        run_day,\n"
        "        ROW_NUMBER() OVER (\n"
        "            PARTITION BY id_dag, id_task, run_day\n"
        "            ORDER BY ts_started ASC, id_run ASC\n"
        "        ) AS day_rank\n"
        "    FROM successes\n"
        "),\n"
        "candidates AS (\n"
        "    SELECT\n"
        "        dr.id_dag,\n"
        "        dr.id_task,\n"
        "        dr.id_run,\n"
        "        dr.ts_started,\n"
        "        dr.ts_ended,\n"
        "        dr.run_day,\n"
        "        ut.level\n"
        "    FROM day_ranked AS dr\n"
        "    INNER JOIN upstream_tasks AS ut\n"
        "        ON dr.id_dag = ut.id_dag\n"
        "        AND dr.id_task = ut.id_task\n"
        # A `:first-run-of-day` dataset edge is emitted once per day, by that
        # task's first run, so its later runs never unblock the consumer.
        "    WHERE ut.level = 0\n"
        "        OR NOT ut.first_run_of_day\n"
        "        OR dr.day_rank = 1\n"
        "),\n"
        "seed_days AS (\n"
        "    SELECT\n"
        "        run_day,\n"
        "        MAX(ts_started) AS seed_ts_started\n"
        "    FROM candidates\n"
        "    WHERE level = 0\n"
        "    GROUP BY run_day\n"
        "),\n"
        "scoped AS (\n"
        # One pick per seed day, not one global cutoff: a multi-slot upstream
        # would otherwise contribute its late slot on every day but the seed's,
        # putting the latest bar hours away from the median.
        "    SELECT\n"
        "        c.id_dag,\n"
        "        c.id_task,\n"
        "        c.id_run,\n"
        "        c.ts_started,\n"
        "        c.ts_ended,\n"
        "        sd.run_day AS seed_run_day,\n"
        "        ROW_NUMBER() OVER (\n"
        "            PARTITION BY c.id_dag, c.id_task, sd.run_day\n"
        "            ORDER BY c.ts_started DESC, c.id_run DESC\n"
        "        ) AS rn\n"
        "    FROM candidates AS c\n"
        "    CROSS JOIN seed_days AS sd\n"
        # id_run carries the trigger type as a prefix (scheduled__,
        # dataset_triggered__, manual__), so comparing run ids as strings orders
        # by trigger type before date. Compare instants instead: an upstream run
        # that ended after that day's seed started cannot have fed it.
        "    WHERE (c.level = 0 AND c.run_day = sd.run_day)\n"
        "        OR (c.level > 0 AND c.ts_ended <= sd.seed_ts_started)\n"
        "),\n"
        "daily_pick AS (\n"
        "    SELECT\n"
        "        id_dag,\n"
        "        id_task,\n"
        "        id_run,\n"
        "        ts_started,\n"
        "        ts_ended,\n"
        "        seed_run_day\n"
        "    FROM scoped\n"
        "    WHERE rn = 1\n"
        "),\n"
        "latest_ranked AS (\n"
        "    SELECT\n"
        "        id_dag,\n"
        "        id_task,\n"
        "        ts_started AS latest_ts_started,\n"
        "        ts_ended AS latest_ts_ended,\n"
        "        ROW_NUMBER() OVER (\n"
        "            PARTITION BY id_dag, id_task\n"
        "            ORDER BY ts_started DESC, id_run DESC\n"
        "        ) AS rn\n"
        "    FROM daily_pick\n"
        "),\n"
        "latest_run AS (\n"
        "    SELECT\n"
        "        id_dag,\n"
        "        id_task,\n"
        "        latest_ts_started,\n"
        "        latest_ts_ended\n"
        "    FROM latest_ranked\n"
        "    WHERE rn = 1\n"
        "),\n"
        "median_times AS (\n"
        "    SELECT\n"
        "        id_dag,\n"
        "        id_task,\n"
        "        approx_percentile(\n"
        "            date_diff(\n"
        "                'millisecond',\n"
        "                date_trunc('day', ts_started),\n"
        "                ts_started\n"
        "            ),\n"
        "            0.5\n"
        "        ) AS median_start_ms,\n"
        "        approx_percentile(\n"
        "            date_diff(\n"
        "                'millisecond',\n"
        "                date_trunc('day', ts_ended),\n"
        "                ts_ended\n"
        "            ),\n"
        "            0.5\n"
        "        ) AS median_end_ms\n"
        "    FROM daily_pick\n"
        "    GROUP BY id_dag, id_task\n"
        f"{_seed_anchor_cte(include_before_d0)}"
        "SELECT\n"
        "    ut.level,\n"
        "    ut.table_name,\n"
        "    ut.id_dag,\n"
        "    ut.id_task,\n"
        "    ut.first_run_of_day,\n"
        "    lr.latest_ts_started,\n"
        "    lr.latest_ts_ended,\n"
        "    CAST(\n"
        "        date_add(\n"
        "            'millisecond',\n"
        "            CAST(mt.median_start_ms AS BIGINT),\n"
        "            TIMESTAMP '2000-01-01 00:00:00'\n"
        "        ) AS TIME\n"
        "    ) AS median_start_tod,\n"
        "    CAST(\n"
        "        date_add(\n"
        "            'millisecond',\n"
        "            CAST(mt.median_end_ms AS BIGINT),\n"
        "            TIMESTAMP '2000-01-01 00:00:00'\n"
        "        ) AS TIME\n"
        "    ) AS median_end_tod\n"
        "FROM upstream_tasks AS ut\n"
        "LEFT JOIN latest_run AS lr\n"
        "    ON ut.id_dag = lr.id_dag\n"
        "    AND ut.id_task = lr.id_task\n"
        "LEFT JOIN median_times AS mt\n"
        "    ON ut.id_dag = mt.id_dag\n"
        "    AND ut.id_task = mt.id_task\n"
        f"{_d0_join_and_where(include_before_d0)}"
        "ORDER BY lr.latest_ts_started, table_name\n"
        f"LIMIT {QUERY_ROW_LIMIT}"
    )


def _seed_anchor_cte(include_before_d0: bool) -> str:
    if include_before_d0:
        return ")\n"
    return (
        "),\n"
        "seed_anchor AS (\n"
        "    SELECT CAST(MIN(lr.latest_ts_started) AS DATE) AS d0\n"
        "    FROM latest_run AS lr\n"
        "    INNER JOIN upstream_tasks AS ut\n"
        "        ON lr.id_dag = ut.id_dag\n"
        "        AND lr.id_task = ut.id_task\n"
        "    WHERE ut.level = 0\n"
        ")\n"
    )


def _d0_join_and_where(include_before_d0: bool) -> str:
    if include_before_d0:
        return ""
    return (
        "CROSS JOIN seed_anchor AS sa\n"
        "WHERE ut.level = 0\n"
        "    OR CAST(lr.latest_ts_ended AS DATE) >= sa.d0\n"
    )
