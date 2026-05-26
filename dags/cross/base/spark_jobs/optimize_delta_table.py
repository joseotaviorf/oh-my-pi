from argparse import ArgumentParser, Namespace
from datetime import date, datetime, timedelta
from multiprocessing.pool import ThreadPool
from typing import Optional

from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.airflow.optimize_delta_tables_cli import (
    decode_tables_config_from_cli,
)
from bietlejuice.base.db.metastore_mapping_factory import MetastoreMappingFactory
from bietlejuice.base.pipeline import LayerEnum
from bietlejuice.base.spark.runtime_detector import RuntimeDetector
from bietlejuice.loaders.delta_loader import DeltaLoader

JOB_NAME = "optimize_delta_table"
logger = QuintoAndarLogger(JOB_NAME)


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
    logger.info(
        f"Starting vacuum and optimize for {len(tables)} tables, parallelism = {args.parallelism}."
    )
    pool = ThreadPool(processes=args.parallelism)
    pool.starmap(
        run_job,
        [
            (loader, table_name, table_configs, args.layer, partition_predicate)
            for table_name, table_configs in tables.items()
        ],
    )

    logger.info("Vacuum and optimize finished for all tables.")


def parse_arguments() -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("layer", type=str, help="Layer of the tables")
    parser.add_argument(
        "tables",
        type=str,
        help="JSON object with all tables to vacuum and optimize. Each key is a table name, "
        "and each value is an object with the following attributes: schema (string), vacuum_retention_hours (integer), "
        "z_order_by(list), run_optimize(boolean), and apply_partition_filter(boolean).",
    )
    parser.add_argument(
        "parallelism",
        type=int,
        help="Number of parallel jobs to run. Default is 16.",
        default=16,
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

    return parser.parse_args()


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


def run_job(
    loader: DeltaLoader,
    table_name: str,
    table_configs: dict,
    layer: str,
    partition_predicate: Optional[str] = None,
) -> None:
    """Runs vacuum and, optionally, optimize on a given table."""

    full_table_name = get_full_table_name(
        table_configs.get("schema"), LayerEnum(layer), table_name
    )
    if table_configs.get("run_optimize", True):
        apply_filter = table_configs.get("apply_partition_filter", False)
        where_predicate = partition_predicate if apply_filter else None
        loader.optimize_table(
            full_table_name,
            table_configs.get("z_order_by", []),
            where_predicate=where_predicate,
        )

    if table_configs.get("run_vacuum", True):
        if table_configs.get("vacuum_lite", False):
            loader.vacuum_lite_table(
                full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24)
            )
        else:
            loader.vacuum_table(
                full_table_name, table_configs.get("vacuum_retention_hours", 7 * 24)
            )


def get_full_table_name(schema: str, layer: LayerEnum, table_name: str) -> str:
    """Returns the full table name in the format database_name.table_name."""

    metastore_mapping_factory = MetastoreMappingFactory.get_mapper_by_layer(
        layer, schema, ""
    )
    database_name = metastore_mapping_factory.get_full_database_name(layer)
    return f"{database_name}.{table_name}"


if __name__ == "__main__":
    try:
        main()
    finally:
        try:
            if RuntimeDetector.is_emr():
                spark.stop()
        except NameError:
            pass
