"""VACUUM/OPTIMIZE Delta tables.

Optional S3 markers cap maintenance to once per day (``maintenance_once_per_day``,
default true), and a separate per-table cursor lets OPTIMIZE run on a slower,
configurable cadence (``optimize_frequency_days``, e.g. weekly) independently of
VACUUM, which always keeps the once-per-day cadence.
"""

from argparse import ArgumentParser, Namespace
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from multiprocessing.pool import ThreadPool
from typing import Dict, Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    decode_tables_config_from_cli,
)
from bietlejuice.base.db.datalake_metastore_mapping import require_transformation_grade
from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.delta.maintenance_state import (
    build_maintenance_payload,
    build_optimize_cursor_payload,
    is_optimize_due,
    maintenance_already_completed,
    read_maintenance_marker,
    resolve_marker_location,
    resolve_optimize_cursor_location,
    write_maintenance_marker,
)
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.configuration_service import ConfigurationService

JOB_NAME = "optimize_delta_table"
logger = QuintoAndarLogger(JOB_NAME)


@dataclass(frozen=True)
class MaintenanceStateConfig:
    """S3 marker settings for daily maintenance idempotency."""

    state_bucket: Optional[str]
    environment: Optional[str]
    maintenance_date: Optional[str]
    dag_name: Optional[str]
    state_prefix: Optional[str]
    region_name: Optional[str]

    @property
    def is_enabled(self) -> bool:
        return bool(
            self.state_bucket
            and self.environment
            and self.maintenance_date
            and self.dag_name
            and self.state_prefix
            and self.region_name
        )


def main():
    global spark
    if RuntimeDetector.is_emr():
        from bietlejuice.base.spark.spark_session_factory import (
            create_emr_spark_session,
        )

        spark = create_emr_spark_session(JOB_NAME)
    args = parse_arguments()
    loader = DeltaLoader(spark)
    tables = decode_tables_config_from_cli(args.tables)
    partition_predicate = _resolve_partition_predicate(
        args.load_start_date, args.load_end_date
    )
    maintenance_state = _build_maintenance_state_config(args)
    tables = _filter_tables_already_maintained(tables, args.layer, maintenance_state)
    if not tables:
        logger.info(
            "All tables already maintained for this execution date; skipping job."
        )
        return
    tables = _apply_optimize_cadence(tables, args.layer, maintenance_state)

    logger.info(
        f"Starting vacuum and optimize for {len(tables)} tables, "
        f"parallelism = {args.parallelism}."
    )
    # Fail-safe: only the exact string "true" enables it, so an unrendered Jinja
    # template or a typo in the Airflow Variable leaves the behaviour unchanged.
    bootstrap_lite_watermark = args.vacuum_lite_watermark.strip().lower() == "true"
    if bootstrap_lite_watermark:
        logger.info(
            "Vacuum lite watermark bootstrap is enabled; fallback full vacuums will "
            "rewrite _last_vacuum_info so the next run can use VACUUM LITE."
        )
    job_args = [
        (
            loader,
            table_name,
            table_configs,
            args.layer,
            partition_predicate,
            bootstrap_lite_watermark,
        )
        for table_name, table_configs in tables.items()
    ]
    pool = ThreadPool(processes=args.parallelism)
    try:
        async_results = [pool.apply_async(run_job, args) for args in job_args]
        failures = _await_job_results_and_persist_markers(
            tables, async_results, maintenance_state
        )
    finally:
        pool.close()
        pool.join()

    if failures:
        failed_names = ", ".join(table_name for table_name, _ in failures)
        logger.error(
            f"Vacuum and optimize failed for {len(failures)} of {len(tables)} "
            f"table(s): {failed_names}."
        )
        _, first_exc = failures[0]
        raise first_exc

    logger.info("Vacuum and optimize finished for all tables.")


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer", type=str, help="Layer of the tables")
    parser.add_argument(
        "tables",
        type=str,
        help="JSON object with all tables to vacuum and optimize. Each key is a table name, "
        "and each value is an object with the following attributes: schema (string), vacuum_retention_hours (integer), "
        "z_order_by(list), run_optimize(boolean), optimize_frequency_days(integer, default 1), "
        "apply_partition_filter(boolean), and maintenance_once_per_day(boolean).",
    )
    parser.add_argument(
        "parallelism",
        type=int,
        help="Number of parallel table maintenance workers (ThreadPool). S3 marker I/O "
        "runs on the main thread after each table finishes.",
        default=16,
    )
    parser.add_argument(
        "--vacuum-lite-watermark",
        dest="vacuum_lite_watermark",
        type=str,
        default="false",
        help="When 'true', a fallback full vacuum also rewrites the Delta "
        "_last_vacuum_info watermark so the next run is eligible for VACUUM LITE. "
        "Driven by the `vacuum_lite_watermark_enabled` Airflow Variable; any value other "
        "than 'true' (including an unrendered Jinja template) leaves it disabled.",
    )
    parser.add_argument(
        "--load-start-date",
        dest="load_start_date",
        type=str,
        default=None,
        help="Inclusive start date (YYYY-MM-DD) for OPTIMIZE partition filter. "
        "Only used for tables that set apply_partition_filter=true.",
    )
    parser.add_argument(
        "--load-end-date",
        dest="load_end_date",
        type=str,
        default=None,
        help="Inclusive end date (YYYY-MM-DD) for OPTIMIZE partition filter. "
        "Only used for tables that set apply_partition_filter=true.",
    )
    parser.add_argument(
        "--environment",
        dest="environment",
        type=str,
        default=None,
        help="Deployment environment for maintenance markers (e.g. prod, forno).",
    )
    parser.add_argument(
        "--dag-name",
        dest="dag_name",
        type=str,
        default=None,
        help="DAG name recorded in maintenance markers.",
    )
    parser.add_argument(
        "--maintenance-date",
        dest="maintenance_date",
        type=str,
        default=None,
        help="Logical execution date (YYYY-MM-DD) for the daily maintenance cap.",
    )
    parser.add_argument(
        "--state-prefix",
        dest="state_prefix",
        type=str,
        default=None,
        help="Optional override for the S3 key prefix (default from ConfigurationService).",
    )

    return parser.parse_args()


def _build_maintenance_state_config(args: Namespace) -> MaintenanceStateConfig:
    """Resolve maintenance marker settings from ConfigurationService (and optional CLI override)."""
    state_bucket = None
    state_prefix = None
    region_name = None
    if args.dag_name:
        config_service = ConfigurationService(args.dag_name)
        state_bucket = config_service.get_config("artifacts_bucket")
        state_prefix = config_service.get_config("delta_maintenance_state_prefix")
        region_name = config_service.get_config("aws_s3_region")
    if args.state_prefix:
        state_prefix = args.state_prefix
    return MaintenanceStateConfig(
        state_bucket=state_bucket,
        environment=args.environment,
        maintenance_date=args.maintenance_date,
        dag_name=args.dag_name,
        state_prefix=state_prefix,
        region_name=region_name,
    )


def _resolve_partition_predicate(
    load_start_date: Optional[str], load_end_date: Optional[str]
) -> Optional[str]:
    """Return the year/month/day OPTIMIZE WHERE clause for [start, end], or None when dates are missing."""
    if not load_start_date or not load_end_date:
        return None
    return build_year_month_day_predicate(load_start_date, load_end_date)


def build_year_month_day_predicate(start_date: str, end_date: str) -> str:
    """Build a partition predicate over year/month/day for every day in [start_date, end_date].

    Iterating day-by-day keeps the expression a disjunction of equality predicates,
    which Delta's OPTIMIZE WHERE clause supports for pruning files by partition.
    """
    start = _parse_iso_date(start_date)
    end = _parse_iso_date(end_date)
    if end < start:
        raise ValueError(
            f"load_end_date ({end_date}) must be on or after load_start_date ({start_date})."
        )

    clauses = []
    current = start
    while current <= end:
        clauses.append(
            f"(year = {current.year} AND month = {current.month} AND day = {current.day})"
        )
        current += timedelta(days=1)
    if len(clauses) == 1:
        # Strip the wrapping parens so single-day predicates read naturally in logs.
        return clauses[0][1:-1]
    return " OR ".join(clauses)


def _parse_iso_date(value: str) -> date:
    try:
        return datetime.strptime(value, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError(f"Expected date in YYYY-MM-DD format, got {value!r}.") from exc


def _table_performs_maintenance(table_configs: dict) -> bool:
    return table_configs.get("run_optimize", True) or table_configs.get(
        "run_vacuum", True
    )


def _should_use_daily_maintenance_cap(
    table_configs: dict, maintenance_state: MaintenanceStateConfig
) -> bool:
    if not table_configs.get("maintenance_once_per_day", True):
        return False
    if not _table_performs_maintenance(table_configs):
        return False
    return maintenance_state.is_enabled


def _filter_tables_already_maintained(
    tables: Dict[str, dict],
    layer: str,
    maintenance_state: MaintenanceStateConfig,
) -> Dict[str, dict]:
    if not maintenance_state.is_enabled:
        return tables

    remaining = {}
    for table_name, table_configs in tables.items():
        if not _should_use_daily_maintenance_cap(table_configs, maintenance_state):
            remaining[table_name] = table_configs
            continue
        full_table_name = get_full_table_name(
            table_configs.get("schema"),
            LayerEnum(layer),
            table_name,
            transformation_grade=table_configs.get("transformation_grade"),
        )
        if _maintenance_marker_exists(full_table_name, maintenance_state):
            logger.info(
                f"Skipping {full_table_name}: maintenance already completed for "
                f"{maintenance_state.maintenance_date}."
            )
            continue
        remaining[table_name] = table_configs
    return remaining


def _apply_optimize_cadence(
    tables: Dict[str, dict],
    layer: str,
    maintenance_state: MaintenanceStateConfig,
) -> Dict[str, dict]:
    """Suppress OPTIMIZE (only) for tables not yet due per ``optimize_frequency_days``.

    Decoupled from the daily marker cap above: VACUUM (and OPTIMIZE on tables
    using the historical once-per-day cadence, i.e. ``optimize_frequency_days <= 1``)
    is untouched here. Tables whose OPTIMIZE cursor shows fewer days elapsed than
    their configured frequency get a copy of their config with ``run_optimize``
    forced to ``False`` for this run only; VACUUM still proceeds per its own flag.

    No-op when maintenance state isn't fully configured (no bucket/region to
    read a cursor from), preserving today's behavior for DAGs without markers set up.
    """
    if not maintenance_state.is_enabled:
        return tables

    today = _parse_iso_date(maintenance_state.maintenance_date)
    resolved = {}
    for table_name, table_configs in tables.items():
        optimize_frequency_days = table_configs.get("optimize_frequency_days", 1)
        if not table_configs.get("run_optimize", True) or optimize_frequency_days <= 1:
            resolved[table_name] = table_configs
            continue

        full_table_name = get_full_table_name(
            table_configs.get("schema"),
            LayerEnum(layer),
            table_name,
            transformation_grade=table_configs.get("transformation_grade"),
        )
        cursor_payload = _read_optimize_cursor(full_table_name, maintenance_state)
        if is_optimize_due(cursor_payload, today, optimize_frequency_days):
            resolved[table_name] = table_configs
            continue

        logger.info(
            f"Skipping OPTIMIZE for {full_table_name}: last ran "
            f"{cursor_payload.get('last_optimize_date') if cursor_payload else 'never'}, "
            f"due again every {optimize_frequency_days} day(s). VACUUM (if enabled) still runs."
        )
        resolved[table_name] = {**table_configs, "run_optimize": False}
    return resolved


def _read_optimize_cursor(
    full_table_name: str, maintenance_state: MaintenanceStateConfig
) -> Optional[dict]:
    bucket, key = resolve_optimize_cursor_location(
        state_bucket=maintenance_state.state_bucket,
        environment=maintenance_state.environment,
        full_table_name=full_table_name,
        state_prefix=maintenance_state.state_prefix,
    )
    return read_maintenance_marker(
        bucket, key, region_name=maintenance_state.region_name
    )


def _persist_optimize_cursor(
    full_table_name: str, maintenance_state: MaintenanceStateConfig
) -> None:
    """Overwrite the table's OPTIMIZE cursor with today's date after a successful run."""
    bucket, key = resolve_optimize_cursor_location(
        state_bucket=maintenance_state.state_bucket,
        environment=maintenance_state.environment,
        full_table_name=full_table_name,
        state_prefix=maintenance_state.state_prefix,
    )
    payload = build_optimize_cursor_payload(
        full_table_name=full_table_name,
        last_optimize_date=maintenance_state.maintenance_date,
        environment=maintenance_state.environment,
        dag_name=maintenance_state.dag_name,
    )
    write_maintenance_marker(
        bucket, key, payload, region_name=maintenance_state.region_name
    )
    logger.info(f"Updated OPTIMIZE cursor for {full_table_name} at s3://{bucket}/{key}")


def _maintenance_marker_exists(
    full_table_name: str, maintenance_state: MaintenanceStateConfig
) -> bool:
    bucket, key = resolve_marker_location(
        state_bucket=maintenance_state.state_bucket,
        environment=maintenance_state.environment,
        full_table_name=full_table_name,
        maintenance_date=maintenance_state.maintenance_date,
        state_prefix=maintenance_state.state_prefix,
    )
    return maintenance_already_completed(
        bucket, key, region_name=maintenance_state.region_name
    )


def _await_job_results_and_persist_markers(
    tables: Dict[str, dict],
    async_results,
    maintenance_state: MaintenanceStateConfig,
) -> list:
    """Collect worker results, persist markers for successes, defer failures.

    Returns a list of (table_name, exception) for each failed table so the caller
    can fail the job after every successful table has recorded its S3 marker.
    """
    failures = []
    for (table_name, table_configs), async_result in zip(tables.items(), async_results):
        try:
            full_table_name = async_result.get()
        except Exception as exc:
            logger.exception(f"Vacuum/optimize failed for table {table_name}.")
            failures.append((table_name, exc))
            continue
        _persist_maintenance_marker(table_configs, full_table_name, maintenance_state)
        if (
            full_table_name
            and table_configs.get("run_optimize", True)
            and maintenance_state.is_enabled
        ):
            _persist_optimize_cursor(full_table_name, maintenance_state)
    return failures


def _persist_maintenance_marker(
    table_configs: dict,
    full_table_name: Optional[str],
    maintenance_state: MaintenanceStateConfig,
) -> None:
    """Write the daily S3 marker on the driver main thread after Spark work finishes."""
    if not full_table_name:
        return
    if not _should_use_daily_maintenance_cap(table_configs, maintenance_state):
        return
    run_optimize = table_configs.get("run_optimize", True)
    run_vacuum = table_configs.get("run_vacuum", True)
    bucket, key = resolve_marker_location(
        state_bucket=maintenance_state.state_bucket,
        environment=maintenance_state.environment,
        full_table_name=full_table_name,
        maintenance_date=maintenance_state.maintenance_date,
        state_prefix=maintenance_state.state_prefix,
    )
    payload = build_maintenance_payload(
        full_table_name=full_table_name,
        maintenance_date=maintenance_state.maintenance_date,
        environment=maintenance_state.environment,
        dag_name=maintenance_state.dag_name,
        run_vacuum=run_vacuum,
        run_optimize=run_optimize,
    )
    write_maintenance_marker(
        bucket, key, payload, region_name=maintenance_state.region_name
    )
    logger.info(
        f"Wrote maintenance marker for {full_table_name} at s3://{bucket}/{key}"
    )


def run_job(
    loader: DeltaLoader,
    table_name: str,
    table_configs: dict,
    layer: str,
    partition_predicate: Optional[str] = None,
    bootstrap_lite_watermark: bool = False,
) -> Optional[str]:
    """Run OPTIMIZE/VACUUM for one table. Returns full table name when maintenance ran."""

    full_table_name = get_full_table_name(
        table_configs.get("schema"),
        LayerEnum(layer),
        table_name,
        transformation_grade=table_configs.get("transformation_grade"),
    )

    run_optimize = table_configs.get("run_optimize", True)
    run_vacuum = table_configs.get("run_vacuum", True)
    if not run_optimize and not run_vacuum:
        return None

    if run_optimize:
        apply_filter = table_configs.get("apply_partition_filter", False)
        where_predicate = partition_predicate if apply_filter else None
        loader.optimize_table(
            full_table_name,
            table_configs.get("z_order_by", []),
            where_predicate=where_predicate,
        )

    if run_vacuum:
        if table_configs.get("vacuum_lite", True):
            loader.vacuum_lite_table(
                full_table_name,
                table_configs.get("vacuum_retention_hours", 7 * 24),
                bootstrap_watermark=bootstrap_lite_watermark,
            )
        else:
            loader.vacuum_table(
                full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24)
            )

    return full_table_name


def get_full_table_name(
    schema: str,
    layer: LayerEnum,
    table_name: str,
    transformation_grade: Optional[str] = None,
) -> str:
    """Returns the full table name in the format database_name.table_name."""

    metastore_mapping_factory = MetastoreMappingFactory.get_mapper_by_layer(
        layer, schema, ""
    )
    name_kwargs = {}
    if layer == LayerEnum.TRANSFORMATION:
        name_kwargs["transformation_grade"] = require_transformation_grade(
            transformation_grade
        )
    database_name = metastore_mapping_factory.get_full_database_name(
        layer, **name_kwargs
    )
    return f"{database_name}.{table_name}"


if __name__ == "__main__":
    from bietlejuice.base.spark.spark_session_factory import run_spark_entrypoint

    run_spark_entrypoint(main)
