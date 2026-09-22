import logging

import pendulum
from airflow import DAG
from airflow.decorators import task
from airflow.models import Param
from airflow.models.log import Log
from airflow.utils.dates import days_ago
from airflow.utils.db_cleanup import drop_archived_tables, run_cleanup
from airflow.utils.session import provide_session
from sqlalchemy import func, text

from bietlejuice.base.airflow.base_dag import BaseDAG
from bietlejuice.base.airflow.dag_owner_enum import DAGOwnerEnum

DAG_NAME = "metadata_db_maintenance"
DAG_ID = f"airflow.{DAG_NAME}"
default_args = {
    "owner": DAGOwnerEnum.DATA_LIFE_CYCLE,
}

CLEANUP_TABLES = [
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

TABLE_SIZE_SQL = """
SELECT c.relname AS table_name,
       pg_total_relation_size(c.oid) AS total_bytes,
       pg_relation_size(c.oid) AS heap_bytes,
       pg_indexes_size(c.oid) AS index_bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY total_bytes DESC
LIMIT 25
"""


@provide_session
def _log_table_sizes(session=None):
    for row in session.execute(text(TABLE_SIZE_SQL)):
        logging.info(
            "table=%s total_bytes=%s heap_bytes=%s index_bytes=%s total=%s",
            row.table_name,
            row.total_bytes,
            row.heap_bytes,
            row.index_bytes,
            row.total_pretty,
        )


@provide_session
def _oldest_log_timestamp(session=None):
    """Earliest `log` row.

    `log` is the batching anchor because it is one of the two largest tables,
    `db_cleanup` has no keep_last rule for it, and nothing holds its rows by
    foreign key — so its minimum advances with every purge. `dag_run` and
    `task_instance` cannot be used: keep_last preserves the most recent
    non-externally-triggered run per dag_id forever, which pins their minimum
    at the oldest abandoned DAG. `idx_log_dttm` makes this an index scan.
    """
    return session.query(func.min(Log.dttm)).scalar()


def _batch_cutoffs(cutoff, batch_size_days, max_batches):
    """Increasing cutoffs ending at `cutoff`, oldest first, capped per run.

    Correctness never depends on where the ladder starts: the last entry is
    always `cutoff`, so any row older than it is deleted by that step or an
    earlier one. The start only bounds how much each step copies and deletes.
    """
    oldest = _oldest_log_timestamp()
    cutoffs = []
    if oldest:
        step = pendulum.instance(oldest).add(days=batch_size_days)
        while step < cutoff:
            cutoffs.append(step)
            step = step.add(days=batch_size_days)
    cutoffs.append(cutoff)
    return cutoffs[:max_batches]


with DAG(
    dag_id=DAG_ID,
    default_args=default_args,
    doc_md=BaseDAG.get_dag_doc(DAG_NAME),
    schedule_interval="0 13 * * 0",
    start_date=days_ago(1),
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
            description=(
                "Absolute cutoff (UTC ISO-8601). Overrides retention_days; "
                "used to walk the historical backfill month by month."
            ),
        ),
        "dry_run": Param(
            False,
            type="boolean",
            description="Log what would be deleted without deleting.",
        ),
        "batch_size_days": Param(
            7,
            type="integer",
            description="Delete in chunks of this many days, oldest first.",
        ),
        "max_batches_per_run": Param(
            10,
            type="integer",
            description=(
                "Maximum chunks in one run. Bounds a single run while the "
                "historical backlog drains; raise it for a manual catch-up."
            ),
        ),
    },
) as dag:

    @task()
    def report_table_sizes():
        _log_table_sizes()

    @task()
    def clean_metadata_db(**context):
        params = context["params"]
        raw_cutoff = params["clean_before_timestamp"]
        cutoff = (
            pendulum.parse(raw_cutoff)
            if raw_cutoff
            else pendulum.now("UTC").subtract(days=params["retention_days"])
        )
        cutoffs = _batch_cutoffs(
            cutoff, params["batch_size_days"], params["max_batches_per_run"]
        )
        logging.info(
            "clean_metadata_db cutoff=%s dry_run=%s batches=%s",
            cutoff,
            params["dry_run"],
            len(cutoffs),
        )
        for index, batch_cutoff in enumerate(cutoffs, start=1):
            logging.info("batch %s/%s up to %s", index, len(cutoffs), batch_cutoff)
            run_cleanup(
                clean_before_timestamp=batch_cutoff,
                table_names=CLEANUP_TABLES,
                dry_run=params["dry_run"],
                verbose=True,
                confirm=False,
                skip_archive=True,
            )

    @task(trigger_rule="all_done")
    def drop_archive_tables():
        """Sweep `_airflow_deleted__*` left behind by a killed cleanup batch."""
        drop_archived_tables(table_names=CLEANUP_TABLES, needs_confirm=False)

    report_table_sizes() >> clean_metadata_db() >> drop_archive_tables()
