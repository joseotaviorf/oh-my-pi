"""Build and load ``dw_agent_performance.agent_visit_funnel``.

Reads ``datalake_agent_performance.visit_funnel_event`` (visit grain, funnel
flags and timestamps) and ``dw_agent.fact_agent_daily`` (agent-day spine).
Aggregates configured metrics × dimensions to agent-day grain and writes Delta.

File layout (top → bottom):
  Constants     — table names, merge keys, defaults
  Config model  — metric/dimension factories (no business catalog here)
  Catalog       — ``METRIC_DEFINITIONS`` / ``DIMENSION_DEFINITIONS`` (edit here)
  Transform     — window filter, aggregation, spine join, output shaping
  Write         — schema check, Delta merge or partition overwrite
  Entrypoint    — CLI parsing and orchestration
"""

from __future__ import annotations

from argparse import ArgumentParser, Namespace
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Iterable, Literal, Sequence

from pyspark.sql import Column, DataFrame, SparkSession
from pyspark.sql import functions as F
from pyspark.sql.types import (
    DataType,
    DateType,
    DoubleType,
    IntegerType,
    LongType,
    StringType,
    StructField,
    StructType,
)
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.validation.spark_args import (
    add_validation_target_args,
    resolve_datalake_write_target,
)
from bietlejuice.clients.db_clients import SparkClient
from bietlejuice.loaders.delta_loader import DeltaLoader
from bietlejuice.services.metastore_services import MetastoreServiceFactory

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

JOB_NAME = "load_agent_visit_funnel"
VISIT_FUNNEL_EVENT_TABLE = "datalake_agent_performance.visit_funnel_event"
FACT_AGENT_DAILY_TABLE = "dw_agent.fact_agent_daily"
MERGE_KEYS = ["sk_agent_visit_funnel"]
PARTITION_COLS = ["year", "month", "day"]
DEFAULT_WRITE_MODE = "merge"
_SECONDS_PER_HOUR = 3600.0

SliceFn = Callable[[Column], Column]
MetricValueFn = Callable[[], Column]
WriteMode = Literal["merge", "batch"]

logger = QuintoAndarLogger(JOB_NAME)

# ---------------------------------------------------------------------------
# Config model
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class MetricDefinition:
    """One output metric: per-visit value expression + aggregation + output typing."""

    output_base: str
    value: MetricValueFn
    aggregate: Callable[[Column], Column] = F.sum
    output_type: DataType = field(default_factory=LongType)
    missing_value: int | float | None = 0

    @staticmethod
    def _elapsed_hours(start_column: str, end_column: str) -> Column:
        start_ts = F.col(start_column)
        end_ts = F.col(end_column)
        return F.when(
            start_ts.isNotNull() & end_ts.isNotNull() & (end_ts >= start_ts),
            (F.unix_timestamp(end_ts) - F.unix_timestamp(start_ts))
            / F.lit(_SECONDS_PER_HOUR),
        )

    @classmethod
    def sum_column(cls, output_base: str, column: str) -> MetricDefinition:
        """Sum a single enrich column (counts and numeric totals)."""

        def build_value() -> Column:
            return F.col(column)

        return cls(output_base=output_base, value=build_value)

    @classmethod
    def avg_elapsed_hours(
        cls,
        output_base: str,
        start_column: str,
        end_column: str,
        *,
        when_column: str | None = None,
        when_equals: int | str | bool = 1,
    ) -> MetricDefinition:
        """Average elapsed hours between two timestamps; optional qualifying flag."""

        def build_value() -> Column:
            duration = cls._elapsed_hours(start_column, end_column)
            if when_column is None:
                return duration
            return F.when(F.col(when_column) == F.lit(when_equals), duration)

        return cls(
            output_base=output_base,
            value=build_value,
            aggregate=F.avg,
            output_type=DoubleType(),
            missing_value=None,
        )


@dataclass(frozen=True)
class DimensionDefinition:
    """One agent-day cut: attribution column, output suffix, optional visit slice."""

    dimension_id: str
    suffix: str
    person_column: str
    slice: SliceFn | None = None
    join_group: str = "main"

    @staticmethod
    def slice_when_flag(flag_column: str, equals: int | str | bool = 1) -> SliceFn:
        """Keep metric value only when ``flag_column == equals``; else null."""

        def apply_slice(value: Column) -> Column:
            return F.when(F.col(flag_column) == F.lit(equals), value)

        return apply_slice


# ---------------------------------------------------------------------------
# Catalog (edit here to add metrics / dimensions)
# ---------------------------------------------------------------------------

METRIC_DEFINITIONS: tuple[MetricDefinition, ...] = (
    MetricDefinition.sum_column("total_visit", "is_visit_booked"),
    MetricDefinition.sum_column("total_reschedule", "nbr_reschedule"),
    MetricDefinition.sum_column("total_visit_canceled", "is_visit_canceled"),
    MetricDefinition.sum_column("total_visit_completed", "is_visit_completed"),
    MetricDefinition.sum_column("total_visit_unsuccessful", "is_visit_unsuccessful"),
    MetricDefinition.sum_column("total_visit_stalled", "is_visit_stalled"),
    MetricDefinition.sum_column("total_visit_not_finished", "is_visit_not_finished"),
    MetricDefinition.sum_column("total_offer_submitted", "is_offer_submitted"),
    MetricDefinition.sum_column("total_offer_accepted", "is_offer_accepted"),
    MetricDefinition.sum_column("total_agreement_signed", "is_agreement_signed"),
    MetricDefinition.avg_elapsed_hours(
        "avg_hours_booked_to_completed",
        "ts_visit_created",
        "ts_visit_done",
        when_column="is_visit_completed",
    ),
    MetricDefinition.avg_elapsed_hours(
        "avg_hours_completed_to_offer_submitted",
        "ts_visit_done",
        "ts_offer_submitted",
        when_column="is_offer_submitted",
    ),
)

DIMENSION_DEFINITIONS: tuple[DimensionDefinition, ...] = (
    DimensionDefinition(
        dimension_id="overall",
        suffix="",
        person_column="uuid_person_last_associated_agent",
    ),
    DimensionDefinition(
        dimension_id="pfa",
        suffix="_pfa",
        person_column="uuid_person_last_associated_agent",
        slice=DimensionDefinition.slice_when_flag("is_pfa_visit"),
    ),
    DimensionDefinition(
        dimension_id="crcc",
        suffix="_crcc",
        person_column="uuid_person_last_associated_agent",
        slice=DimensionDefinition.slice_when_flag("is_crcc_visit"),
    ),
    DimensionDefinition(
        dimension_id="vbba",
        suffix="_vbba",
        person_column="uuid_person_agent_vbba",
        slice=DimensionDefinition.slice_when_flag("is_vbba_visit"),
        join_group="vbba",
    ),
)

# ---------------------------------------------------------------------------
# Transform
# ---------------------------------------------------------------------------


def metric_output_columns() -> list[str]:
    """Flat list of DW column names (metric × dimension)."""
    return [
        f"{metric.output_base}{dimension.suffix}"
        for dimension in DIMENSION_DEFINITIONS
        for metric in METRIC_DEFINITIONS
    ]


def build_metric_agg_expr(
    metric: MetricDefinition,
    dimension: DimensionDefinition,
) -> Column:
    """Single grouped aggregation for one metric × dimension cell."""
    value = metric.value()
    if dimension.slice is not None:
        value = dimension.slice(value)
    return metric.aggregate(value).alias(f"{metric.output_base}{dimension.suffix}")


def output_schema() -> StructType:
    """Target Delta schema derived from the metric/dimension catalog."""
    fields = [
        StructField("sk_agent_visit_funnel", StringType(), False),
        StructField("uuid_person", StringType(), False),
        StructField("date_ref", DateType(), False),
    ]
    for dimension in DIMENSION_DEFINITIONS:
        for metric in METRIC_DEFINITIONS:
            name = f"{metric.output_base}{dimension.suffix}"
            fields.append(
                StructField(name, metric.output_type, metric.missing_value is None)
            )
    fields.extend(
        [
            StructField("year", IntegerType(), False),
            StructField("month", IntegerType(), False),
            StructField("day", IntegerType(), False),
        ]
    )
    return StructType(fields)


def _visits_in_window(
    visits: DataFrame,
    reprocess_start_date: str,
    load_end_date: str,
) -> DataFrame:
    """Restrict enrich visits to the reprocess lookback ending at load_end_date."""
    return visits.filter(
        F.col("dt_visit_created").between(
            F.lit(reprocess_start_date).cast("date"),
            F.lit(load_end_date).cast("date"),
        )
    )


def build_agent_day_base(
    spark: SparkSession,
    start_date: str,
    end_date: str,
) -> DataFrame:
    """Agent-day spine: every (uuid_person, dt_ref) in fact_agent_daily for the window."""
    return (
        spark.table(FACT_AGENT_DAILY_TABLE)
        .filter(
            F.col("dt_ref").between(
                F.lit(start_date).cast("date"),
                F.lit(end_date).cast("date"),
            )
        )
        .select(
            F.col("uuid_person"),
            F.col("dt_ref").alias("date_ref"),
        )
        .distinct()
    )


def _aggregate_dimension_group(
    visits: DataFrame,
    person_column: str,
    dimensions: Sequence[DimensionDefinition],
) -> DataFrame:
    """Aggregate visits for dimensions sharing the same person column and join group."""
    agg_exprs = [
        build_metric_agg_expr(metric, dimension)
        for dimension in dimensions
        for metric in METRIC_DEFINITIONS
    ]
    return (
        visits.where(F.col(person_column).isNotNull())
        .groupBy(
            F.col(person_column).alias("uuid_person"),
            F.col("dt_visit_created").alias("date_ref"),
        )
        .agg(*agg_exprs)
    )


def build_agent_visit_funnel(
    spark: SparkSession,
    reprocess_start_date: str,
    load_start_date: str,
    load_end_date: str,
) -> DataFrame:
    """Main transform: agent-day spine left-joined to visit aggregations."""
    visits_in_window = _visits_in_window(
        spark.table(VISIT_FUNNEL_EVENT_TABLE),
        reprocess_start_date,
        load_end_date,
    )
    agent_days = build_agent_day_base(spark, reprocess_start_date, load_end_date)

    dimensions_by_group: dict[tuple[str, str], list[DimensionDefinition]] = {}
    for dimension in DIMENSION_DEFINITIONS:
        key = (dimension.person_column, dimension.join_group)
        dimensions_by_group.setdefault(key, []).append(dimension)

    metric_frames = [
        _aggregate_dimension_group(visits_in_window, person_column, dimensions)
        for (person_column, _join_group), dimensions in dimensions_by_group.items()
    ]

    result = agent_days
    for metrics_df in metric_frames:
        result = result.join(metrics_df, ["uuid_person", "date_ref"], "left")

    for dimension in DIMENSION_DEFINITIONS:
        for metric in METRIC_DEFINITIONS:
            column_name = f"{metric.output_base}{dimension.suffix}"
            if metric.missing_value is None:
                result = result.withColumn(
                    column_name, F.col(column_name).cast(metric.output_type)
                )
            else:
                result = result.withColumn(
                    column_name,
                    F.coalesce(F.col(column_name), F.lit(metric.missing_value)).cast(
                        metric.output_type
                    ),
                )

    return (
        result.withColumn(
            "sk_agent_visit_funnel",
            F.md5(
                F.concat(
                    F.col("uuid_person"),
                    F.col("date_ref").cast(StringType()),
                )
            ),
        )
        .withColumn("year", F.year("date_ref").cast(IntegerType()))
        .withColumn("month", F.month("date_ref").cast(IntegerType()))
        .withColumn("day", F.dayofmonth("date_ref").cast(IntegerType()))
        .select(
            "sk_agent_visit_funnel",
            "uuid_person",
            "date_ref",
            *metric_output_columns(),
            *PARTITION_COLS,
        )
    )


# ---------------------------------------------------------------------------
# Write
# ---------------------------------------------------------------------------


def resolve_delta_write_mode(write_mode: str) -> list[str] | None:
    """``merge`` upserts on ``MERGE_KEYS``; ``batch`` overwrites output partitions."""
    normalized = write_mode.strip().lower()
    aliases = {"overwrite_partitions": "batch", "overwrite": "batch"}
    normalized = aliases.get(normalized, normalized)
    if normalized == "merge":
        return list(MERGE_KEYS)
    if normalized == "batch":
        return None
    raise ValueError(
        f"Unsupported write_mode={write_mode!r}; expected merge or batch "
        f"(aliases: overwrite_partitions, overwrite)"
    )


def validate_before_write(result_df: DataFrame) -> int | None:
    """Assert output schema; return row count, or None when the batch is empty."""
    row_count = result_df.count()
    if row_count == 0:
        return None

    expected = {field.name: field.dataType for field in output_schema().fields}
    actual = {field.name: field.dataType for field in result_df.schema.fields}
    if set(expected) != set(actual):
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        raise ValueError(
            f"agent_visit_funnel schema mismatch missing={missing} extra={extra}"
        )
    for name, expected_type in expected.items():
        if actual[name] != expected_type:
            raise ValueError(
                f"agent_visit_funnel column {name}: expected {expected_type}, got {actual[name]}"
            )
    return row_count


def write_agent_visit_funnel(
    spark: SparkSession,
    spark_client: SparkClient,
    result_df: DataFrame,
    args: Namespace,
    row_count: int,
) -> None:
    """Resolve write target, load Delta (merge or batch), refresh metastore."""
    database_name = f"dw_{args.database_name}"
    prod_location = (
        f"s3://{args.datalake_bucket}/{args.database_name}/{args.table_name}"
    )
    write_database_name, write_table_name, write_location = (
        resolve_datalake_write_target(
            prod_database=database_name,
            prod_table=args.table_name,
            prod_location=prod_location,
            bucket=args.datalake_bucket,
            target_database=args.target_database_name,
            target_table=args.target_table_name,
        )
    )

    MetastoreServiceFactory.create_loader_metastore_service(
        spark_client
    ).create_database(write_database_name)

    full_table_name = f"{write_database_name}.{write_table_name}"
    s3_path = (
        f"{write_location}{write_table_name}"
        if write_location.endswith("/")
        else write_location
    )

    merge_on = resolve_delta_write_mode(args.write_mode)
    if merge_on is None:
        spark.conf.set("spark.sql.sources.partitionOverwriteMode", "dynamic")

    DeltaLoader(spark).load_table(
        table_name=full_table_name,
        path=s3_path,
        source_df=result_df,
        partition_by=PARTITION_COLS,
        merge_on=merge_on,
    )
    MetastoreServiceFactory.create_loader_metastore_service(spark_client).refresh_table(
        write_database_name, write_table_name
    )
    logger.info(
        f"m=write_agent_visit_funnel, table={full_table_name}, rows={row_count:,}, "
        f"write_mode={args.write_mode}, msg=Load completed"
    )


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------


def parse_args(argv: Iterable[str] | None = None) -> Namespace:
    parser = ArgumentParser(description=JOB_NAME)
    parser.add_argument("environment", help="Environment: forno/prod")
    parser.add_argument("datalake_bucket", help="Datalake bucket")
    parser.add_argument("database_name", help="Database base name (agent_performance)")
    parser.add_argument("dag_name", help="DAG name")
    parser.add_argument("table_name", help="Target table name")
    parser.add_argument("load_start_date", help="Load start date (YYYY-MM-DD)")
    parser.add_argument("load_end_date", help="Load end date (YYYY-MM-DD)")
    parser.add_argument("run_mode", help="Run mode: prod/dev")
    parser.add_argument(
        "reprocess_start_date",
        help="Visit reprocess window start (YYYY-MM-DD), typically ds-90",
    )
    parser.add_argument(
        "write_mode",
        nargs="?",
        default=DEFAULT_WRITE_MODE,
        help="Delta write mode: merge (upsert) or batch (partition overwrite)",
    )
    add_validation_target_args(parser)
    return parser.parse_args(argv)


def main(args: Namespace | None = None) -> None:
    """Transform → validate → dev temp view or production Delta write."""
    if args is None:
        args = parse_args()

    logger.info(
        f"m=main, environment={args.environment}, database_name={args.database_name}, "
        f"table_name={args.table_name}, load_start_date={args.load_start_date}, "
        f"load_end_date={args.load_end_date}, "
        f"reprocess_start_date={args.reprocess_start_date}, "
        f"write_mode={args.write_mode}, msg=Starting {JOB_NAME}"
    )

    spark_client = SparkClient()
    spark = spark_client.conn
    result_df = build_agent_visit_funnel(
        spark,
        reprocess_start_date=args.reprocess_start_date,
        load_start_date=args.load_start_date,
        load_end_date=args.load_end_date,
    )
    row_count = validate_before_write(result_df)
    if row_count is None:
        logger.warning(
            "m=main, msg=No agent_visit_funnel rows in load window, skipping write"
        )
        return

    if getattr(args, "run_mode", "prod") != "prod":
        view_name = f"dev_{args.table_name}"
        result_df.createOrReplaceTempView(view_name)
        logger.info(f"m=main, msg=Dev mode registered temp view {view_name}")
        return

    write_agent_visit_funnel(spark, spark_client, result_df, args, row_count)


if __name__ == "__main__":
    main()
