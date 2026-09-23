import collections
import logging
import time
from datetime import timedelta
from functools import partial

import pendulum
from airflow import DAG
from airflow.decorators import task
from airflow.exceptions import AirflowException
from airflow.models import Param
from airflow.utils.db_cleanup import config_dict, drop_archived_tables, run_cleanup
from airflow.utils.session import NEW_SESSION, create_session, provide_session
from sqlalchemy import text
from sqlalchemy.exc import DBAPIError
from sqlalchemy.orm.session import Session

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

DAG_NAME = "metadata_db_maintenance"
DAG_ID = f"airflow.{DAG_NAME}"
default_args = {
    "owner": DAGOwnerEnum.DATA_LIFE_CYCLE,
}

# Small tables left to `run_cleanup`. `xcom`, `task_instance_history` and
# `task_fail` have no index on their time column and are purged by the
# `ON DELETE CASCADE` from `task_instance` instead.
RUN_CLEANUP_TABLES = [
    "task_reschedule",
    "dataset_event",
    "sla_miss",
    "callback_request",
    "celery_taskmeta",
    "celery_tasksetmeta",
]
ARCHIVE_SWEEP_TABLES = [
    "dag_run",
    "task_instance",
    "task_instance_history",
    "task_fail",
    "task_reschedule",
    "log",
    "job",
    "xcom",
    "dataset_event",
    "sla_miss",
    "callback_request",
    "celery_taskmeta",
    "celery_tasksetmeta",
]
JOB_TYPES = [
    "LocalTaskJob",
    "SchedulerJob",
    "TriggererJob",
    "DagProcessorJob",
    "BackfillJob",
]
CHUNK_STATEMENT_TIMEOUT = "60s"
CHUNK_LOCK_TIMEOUT = "5s"
DRY_RUN_STATEMENT_TIMEOUT = "300s"
RETRYABLE_PGCODES = {"57014", "55P03"}  # query_canceled, lock_not_available
FAST_CHUNK_SECONDS = 2
SLOW_CHUNK_SECONDS = 15
MAX_DAG_RUNS_PER_CHUNK = 1000
MAX_ROWS_PER_CHUNK = 200_000

TABLE_SIZE_SQL = """
SELECT n.nspname AS schema_name,
       c.relname AS table_name,
       c.reltuples::bigint AS approx_rows,
       pg_total_relation_size(c.oid) AS total_bytes,
       pg_relation_size(c.oid) AS heap_bytes,
       pg_indexes_size(c.oid) AS index_bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND pg_table_is_visible(c.oid)
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY total_bytes DESC
LIMIT 25
"""

# Same rule as `db_cleanup`'s keep_last: the latest scheduled run per DAG
# must survive so the scheduler keeps a continuous data interval.
KEEP_LAST_DAG_RUN_IDS_SQL = """
SELECT dr.id
FROM dag_run dr
JOIN (
    SELECT dag_id, max(start_date) AS max_start_date
    FROM dag_run
    WHERE external_trigger = false
    GROUP BY dag_id
) latest ON latest.dag_id = dr.dag_id AND latest.max_start_date = dr.start_date
"""
DAG_RUN_CHUNK_SQL = """
SELECT id, dag_id, run_id
FROM dag_run
WHERE start_date < :cutoff AND id <> ALL(CAST(:keep_ids AS integer[]))
ORDER BY start_date
LIMIT :size
"""
# Equality on both `ti_dag_run (dag_id, run_id)` columns keeps this an index
# lookup; `task_instance.start_date` has no index.
DELETE_TASK_INSTANCES_SQL = (
    "DELETE FROM task_instance WHERE dag_id = :dag_id AND run_id = :run_id"
)
DELETE_DAG_RUNS_SQL = "DELETE FROM dag_run WHERE id = ANY(CAST(:ids AS integer[]))"
# `id = ANY(ARRAY(...))` rather than `id IN (...)`: with IN, the planner may
# hash-join the chunk against a full scan of the table.
DELETE_LOG_CHUNK_SQL = """
DELETE FROM log WHERE id = ANY(ARRAY(
    SELECT id FROM log WHERE dttm < :cutoff ORDER BY dttm LIMIT :size
))
"""
DELETE_JOB_CHUNK_SQL = """
DELETE FROM job WHERE id = ANY(ARRAY(
    SELECT id FROM job
    WHERE job_type = ANY(CAST(:job_types AS text[])) AND latest_heartbeat < :cutoff
    LIMIT :size
))
"""
COUNT_DAG_RUNS_SQL = (
    "SELECT count(*) FROM dag_run "
    "WHERE start_date < :cutoff AND id <> ALL(CAST(:keep_ids AS integer[]))"
)
COUNT_LOG_SQL = "SELECT count(*) FROM log WHERE dttm < :cutoff"
COUNT_JOB_SQL = (
    "SELECT count(*) FROM job "
    "WHERE job_type = ANY(CAST(:job_types AS text[])) AND latest_heartbeat < :cutoff"
)
TASK_INSTANCE_ESTIMATE_SQL = (
    "SELECT reltuples::bigint FROM pg_class WHERE oid = to_regclass('task_instance')"
)


@provide_session
def _log_table_sizes(session: Session = NEW_SESSION):
    rows = session.execute(text(TABLE_SIZE_SQL)).fetchall()
    if not rows:
        logging.warning(
            "report_table_sizes: no tables visible on the current search_path"
        )
    for row in rows:
        logging.info(
            "schema=%s table=%s approx_rows=%s total_bytes=%s heap_bytes=%s "
            "index_bytes=%s total=%s",
            row.schema_name,
            row.table_name,
            row.approx_rows,
            row.total_bytes,
            row.heap_bytes,
            row.index_bytes,
            row.total_pretty,
        )


def _delete_dag_run_chunk(session, size, *, cutoff, keep_ids):
    runs = session.execute(
        text(DAG_RUN_CHUNK_SQL),
        {"cutoff": cutoff, "keep_ids": keep_ids, "size": size},
    ).fetchall()
    if not runs:
        return {"dag_run": 0, "task_instance": 0}
    n_task_instances = 0
    for run in runs:
        n_task_instances += session.execute(
            text(DELETE_TASK_INSTANCES_SQL),
            {"dag_id": run.dag_id, "run_id": run.run_id},
        ).rowcount
    n_dag_runs = session.execute(
        text(DELETE_DAG_RUNS_SQL), {"ids": [run.id for run in runs]}
    ).rowcount
    return {"dag_run": n_dag_runs, "task_instance": n_task_instances}


def _delete_log_chunk(session, size, *, cutoff):
    result = session.execute(
        text(DELETE_LOG_CHUNK_SQL), {"cutoff": cutoff, "size": size}
    )
    return {"log": result.rowcount}


def _delete_job_chunk(session, size, *, cutoff):
    result = session.execute(
        text(DELETE_JOB_CHUNK_SQL),
        {"cutoff": cutoff, "size": size, "job_types": JOB_TYPES},
    )
    return {"job": result.rowcount}


class _ChunkPurger:
    def __init__(self, name, run_chunk, size, max_size):
        self.name = name
        self.run_chunk = run_chunk
        self.size = size
        self.max_size = max_size
        self.totals = collections.Counter()

    def step(self, session) -> int:
        """Delete one chunk in its own transaction; return rows removed from `name` (0 = done)."""
        while True:
            started = time.monotonic()
            try:
                session.execute(
                    text(f"SET LOCAL statement_timeout = '{CHUNK_STATEMENT_TIMEOUT}'")
                )
                session.execute(
                    text(f"SET LOCAL lock_timeout = '{CHUNK_LOCK_TIMEOUT}'")
                )
                counts = self.run_chunk(session, self.size)
                session.commit()
            except DBAPIError as exc:
                session.rollback()
                pgcode = getattr(exc.orig, "pgcode", None)
                if pgcode not in RETRYABLE_PGCODES:
                    raise
                if self.size == 1:
                    raise AirflowException(
                        f"{self.name} chunk of size 1 failed with pgcode {pgcode}"
                    ) from exc
                logging.warning(
                    "%s chunk hit pgcode %s at size %s; retrying with %s",
                    self.name,
                    pgcode,
                    self.size,
                    max(self.size // 2, 1),
                )
                self.size = max(self.size // 2, 1)
                continue
            elapsed = time.monotonic() - started
            self.totals.update(counts)
            logging.info(
                "%s chunk: %s in %.1fs (size %s)", self.name, counts, elapsed, self.size
            )
            if elapsed < FAST_CHUNK_SECONDS:
                self.size = min(self.size * 2, self.max_size)
            elif elapsed > SLOW_CHUNK_SECONDS:
                self.size = max(self.size // 2, 1)
            return counts[self.name]


def _explain(session, sql, params, label) -> str:
    plan = "\n".join(row[0] for row in session.execute(text("EXPLAIN " + sql), params))
    logging.info("plan for %s:\n%s", label, plan)
    return plan


def _find_leftovers(cutoff):
    failures = []
    with create_session() as session:
        for table in RUN_CLEANUP_TABLES:
            if (
                session.execute(text("SELECT to_regclass(:t)"), {"t": table}).scalar()
                is None
            ):
                continue
            column = config_dict[table].recency_column_name
            leftover = session.execute(
                text(f"SELECT EXISTS (SELECT 1 FROM {table} WHERE {column} < :cutoff)"),
                {"cutoff": cutoff},
            ).scalar()
            if leftover:
                failures.append(f"run_cleanup left rows older than cutoff in {table}")
    return failures


def _purge_large_tables(params, cutoff, deadline, failures):
    with create_session() as session:
        keep_ids = [row[0] for row in session.execute(text(KEEP_LAST_DAG_RUN_IDS_SQL))]
        logging.info("keeping %s latest scheduled dag_runs", len(keep_ids))
        session.commit()

        dag_run_purger = _ChunkPurger(
            "dag_run",
            partial(_delete_dag_run_chunk, cutoff=cutoff, keep_ids=keep_ids),
            params["dag_runs_per_chunk"],
            MAX_DAG_RUNS_PER_CHUNK,
        )
        log_purger = _ChunkPurger(
            "log",
            partial(_delete_log_chunk, cutoff=cutoff),
            params["rows_per_chunk"],
            MAX_ROWS_PER_CHUNK,
        )
        job_purger = _ChunkPurger(
            "job",
            partial(_delete_job_chunk, cutoff=cutoff),
            params["rows_per_chunk"],
            MAX_ROWS_PER_CHUNK,
        )
        all_purgers = [dag_run_purger, log_purger, job_purger]
        purgers = list(all_purgers)

        candidate = session.execute(
            text(DAG_RUN_CHUNK_SQL), {"cutoff": cutoff, "keep_ids": keep_ids, "size": 1}
        ).first()
        if candidate is None:
            purgers.remove(dag_run_purger)
            logging.info("dag_run: nothing older than cutoff remains")
        else:
            plan = _explain(
                session,
                DELETE_TASK_INSTANCES_SQL,
                {"dag_id": candidate.dag_id, "run_id": candidate.run_id},
                "task_instance delete",
            )
            if "Seq Scan on task_instance" in plan:
                purgers.remove(dag_run_purger)
                failures.append("task_instance delete plan uses a sequential scan")
        plan = _explain(
            session,
            DELETE_LOG_CHUNK_SQL,
            {"cutoff": cutoff, "size": params["rows_per_chunk"]},
            "log delete",
        )
        if "Seq Scan on log" in plan:
            purgers.remove(log_purger)
            failures.append("log delete plan uses a sequential scan")
        _explain(
            session,
            DELETE_JOB_CHUNK_SQL,
            {
                "cutoff": cutoff,
                "size": params["rows_per_chunk"],
                "job_types": JOB_TYPES,
            },
            "job delete",
        )
        _explain(
            session,
            DAG_RUN_CHUNK_SQL,
            {
                "cutoff": cutoff,
                "keep_ids": keep_ids,
                "size": params["dag_runs_per_chunk"],
            },
            "dag_run chunk select",
        )
        session.commit()

        if params["dry_run"]:
            session.execute(
                text(f"SET LOCAL statement_timeout = '{DRY_RUN_STATEMENT_TIMEOUT}'")
            )
            logging.info(
                "dry run: dag_runs=%s log=%s job=%s task_instance_estimate=%s",
                session.execute(
                    text(COUNT_DAG_RUNS_SQL), {"cutoff": cutoff, "keep_ids": keep_ids}
                ).scalar(),
                session.execute(text(COUNT_LOG_SQL), {"cutoff": cutoff}).scalar(),
                session.execute(
                    text(COUNT_JOB_SQL), {"cutoff": cutoff, "job_types": JOB_TYPES}
                ).scalar(),
                session.execute(text(TASK_INSTANCE_ESTIMATE_SQL)).scalar(),
            )
            session.commit()
            return all_purgers

        while purgers:
            if time.monotonic() >= deadline:
                logging.info("time budget reached; stopping")
                break
            for purger in list(purgers):
                if purger.step(session) == 0:
                    purgers.remove(purger)
                    logging.info("%s: nothing older than cutoff remains", purger.name)
            time.sleep(params["pause_seconds"])
    return all_purgers


with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
    schedule_interval="0 13 * * *",
    start_date=pendulum.datetime(2026, 9, 1, tz="UTC"),
    catchup=False,
    max_active_runs=1,
    params={
        "retention_days": Param(
            90,
            type="integer",
            description="Delete metadata rows whose timestamp is older than this many days.",
        ),
        "clean_before_timestamp": Param(
            None,
            type=["null", "string"],
            format="date-time",
            description="Absolute cutoff (UTC ISO-8601). Overrides retention_days.",
        ),
        "dry_run": Param(
            False,
            type="boolean",
            description="Log what would be deleted without deleting.",
        ),
        "max_runtime_minutes": Param(
            45,
            type="integer",
            minimum=1,
            maximum=170,
            description=(
                "Stop starting new delete chunks after this many minutes; "
                "the next run continues."
            ),
        ),
        "dag_runs_per_chunk": Param(
            50,
            type="integer",
            minimum=1,
            maximum=1000,
            description=(
                "Initial DAG runs per delete transaction; their task instances and "
                "dependents go with them. Adapts to chunk duration."
            ),
        ),
        "rows_per_chunk": Param(
            20000,
            type="integer",
            minimum=1000,
            maximum=200000,
            description="Initial log/job rows per delete transaction. Adapts to chunk duration.",
        ),
        "pause_seconds": Param(
            1,
            type="integer",
            minimum=0,
            maximum=60,
            description="Sleep between chunk rounds to leave database headroom.",
        ),
    },
) as dag:

    @task()
    def report_table_sizes():
        _log_table_sizes()

    @task(execution_timeout=timedelta(hours=3))
    def clean_metadata_db(**context):
        params = context["params"]
        raw_cutoff = params["clean_before_timestamp"]
        if raw_cutoff:
            cutoff = pendulum.parse(raw_cutoff)
            if not isinstance(cutoff, pendulum.DateTime):
                raise AirflowException(
                    f"clean_before_timestamp must be a date-time, got {raw_cutoff!r}"
                )
        else:
            cutoff = pendulum.now("UTC").subtract(days=params["retention_days"])
        started = time.monotonic()
        deadline = started + params["max_runtime_minutes"] * 60
        logging.info(
            "clean_metadata_db cutoff=%s dry_run=%s max_runtime_minutes=%s "
            "dag_runs_per_chunk=%s rows_per_chunk=%s",
            cutoff,
            params["dry_run"],
            params["max_runtime_minutes"],
            params["dag_runs_per_chunk"],
            params["rows_per_chunk"],
        )
        failures: list[str] = []

        run_cleanup(
            clean_before_timestamp=cutoff,
            table_names=RUN_CLEANUP_TABLES,
            dry_run=params["dry_run"],
            verbose=True,
            confirm=False,
            skip_archive=True,
        )
        if not params["dry_run"]:
            failures.extend(_find_leftovers(cutoff))

        all_purgers = _purge_large_tables(params, cutoff, deadline, failures)

        totals = collections.Counter()
        for purger in all_purgers:
            totals.update(purger.totals)
        logging.info(
            "totals dag_run=%s task_instance=%s log=%s job=%s elapsed=%.0fs",
            totals["dag_run"],
            totals["task_instance"],
            totals["log"],
            totals["job"],
            time.monotonic() - started,
        )
        if failures:
            raise AirflowException("; ".join(failures))

    @task(trigger_rule="all_done")
    def drop_archive_tables():
        """Sweep `_airflow_deleted__*` left behind by a killed `run_cleanup` call."""
        with create_session() as session:
            drop_archived_tables(
                table_names=ARCHIVE_SWEEP_TABLES, needs_confirm=False, session=session
            )

    report_table_sizes() >> clean_metadata_db() >> drop_archive_tables()
