"""Post-load profiling Spark job (A0.4).

Runs on the DAG's shared job cluster right after the load task, reads the just
-loaded table's Delta metadata, and appends fresh-tier observability metrics to
``datalake_observability``. Gated by the ``observability`` declaration block and
the runtime kill-switch; fail-open so it never breaks the host DAG (NFR1).
"""

import json
import logging
from argparse import ArgumentParser

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.observability.profiling.profiling_pipeline import ProfilingPipeline

JOB_NAME = "profiling"
logging.getLogger("py4j").setLevel(logging.ERROR)
logger = QuintoAndarLogger(JOB_NAME)


def parse_args():
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("env", type=str, help="Environment where the task is executing")
    parser.add_argument(
        "run_logical_date", type=str, help="Airflow logical date (YYYY-MM-DD)"
    )
    parser.add_argument("database", type=str, help="Hive schema of the profiled table")
    parser.add_argument("table", type=str, help="Name of the profiled table")
    parser.add_argument("layer", type=str, help="Medallion layer of the profiled table")
    parser.add_argument(
        "partitions",
        type=str,
        nargs="?",
        default="[]",
        help="JSON list of the profiled table's partition columns",
    )
    parser.add_argument(
        "column_checks",
        type=str,
        nargs="?",
        default="false",
        help="Whether the optional column tier is enabled (reserved; unused in fresh tier)",
    )
    parser.add_argument(
        "dag_enabled",
        type=str,
        nargs="?",
        default="",
        help="Per-DAG observability.enabled ('true'/'false'); empty means undeclared",
    )
    return parser.parse_args()


def _parse_bool(value: str) -> bool:
    return str(value).strip().lower() in {"true", "1", "yes"}


def _parse_dag_enabled(value: str):
    if value is None or str(value).strip() == "":
        return None
    return _parse_bool(value)


def _parse_partitions(value: str) -> list:
    try:
        parsed = json.loads(value) if value else []
    except (TypeError, ValueError):
        return []
    return parsed if isinstance(parsed, list) else []


def main() -> None:
    global spark
    spark = None
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session(JOB_NAME)

    args = parse_args()
    logger.info(
        f"m={JOB_NAME}, env={args.env}, database={args.database}, table={args.table}, "
        f"layer={args.layer}, run_logical_date={args.run_logical_date}, "
        f"msg=Profiling job started."
    )

    pipeline = ProfilingPipeline(
        environment=args.env,
        run_logical_date=args.run_logical_date,
        database=args.database,
        table=args.table,
        layer=args.layer,
        partitions=_parse_partitions(args.partitions),
        column_checks=_parse_bool(args.column_checks),
        dag_enabled=_parse_dag_enabled(args.dag_enabled),
        spark=spark,
    )
    # ProfilingPipeline.run() is fail-open (NFR1): it never raises, so the host
    # DAG cannot be broken by profiling.
    pipeline.run()


if __name__ == "__main__":
    try:
        main()
    finally:
        try:
            if RuntimeDetector.is_emr():
                spark.sparkContext._gateway.shutdown_callback_server()
                spark.stop()
        except Exception:
            pass
