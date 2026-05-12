"""
Build dimension tables with temporal aggregations.

This module processes source data to create dimension tables at multiple
time windows (1d, 7d, 28d by default), applying aggregations and handling
missing values with configurable defaults.
"""

from argparse import Namespace
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from pyspark.sql import DataFrame, SparkSession, Window
from pyspark.sql import functions as F

from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.qube.jobs.common.conf import Config, parse_common_args
from bietlejuice.qube.jobs.common.data_quality import (
    validate_output,
    validate_source_data,
)
from bietlejuice.qube.jobs.common.logging_config import get_logger, setup_logging
from bietlejuice.qube.jobs.common.path_validator import validate_spec_path
from bietlejuice.qube.jobs.common.specs_loader import load_spec
from bietlejuice.qube.jobs.common.utils import (
    get_default_json,
    get_spark_session,
    get_window_range,
    load_table,
    timestamp_to_date_string,
    wrap_dimension_value,
)

logger = get_logger("build_dimension")


@dataclass
class DimensionConfig:
    """Configuration extracted from spec for dimension building."""

    entity: str
    name: str
    windows: List[int]
    source_table: str
    entity_id_col: str
    date_expr_sql: str
    required_cols: List[str]


@dataclass
class LogicConfig:
    """Logic configuration extracted from spec."""

    card: str
    dtype: str
    agg: Optional[str]
    expr_sql: Optional[str]
    value_col: str
    order_by_ts_col: Optional[str]
    extra_cols: List[str]
    include_all_entities: bool
    defaults: Dict[str, Any]


def build_dimension(args: Namespace) -> None:
    """
    Build dimension tables for all configured time windows.

    Args:
        args: Command-line arguments containing spec path, date, env, etc.
    """
    setup_logging(level=args.log_level, log_format=args.log_format)
    logger.info("=" * 80)
    logger.info("Starting dimension build job")
    logger.info("=" * 80)

    try:
        conf = _setup_configuration(args)
        spark = get_spark_session("build_dimension", env=args.env)
        logger.info(f"Spark session initialized: {spark.sparkContext.appName}")

        spec = _load_spec(args)
        dim_config = _extract_dimension_config(spec, conf)
        logic_config = _extract_logic_config(spec)

        logger.info(f"Building dimension: {dim_config.entity}.{dim_config.name}")
        logger.info(f"Time windows: {dim_config.windows} days")
        logger.info(f"Source table: {dim_config.source_table}")
        logger.info(f"Entity ID column: {dim_config.entity_id_col}")

        df_source = _prepare_source_data(spark, dim_config, args.env, conf)

        fixed_hi = _determine_target_date(args.date, df_source)
        target_date = datetime.fromtimestamp(fixed_hi).strftime("%Y-%m-%d")
        logger.info(f"Target date: {target_date} (timestamp: {fixed_hi})")

        core_df_full = _load_core_entity_table(
            spark,
            dim_config.source_table,
            f"core_{dim_config.entity}.{dim_config.entity}",
            df_source,
            args.env,
        )

        for window_days in dim_config.windows:
            logger.info("-" * 80)
            logger.info(f"Processing window: {window_days} days")

            try:
                _process_window(
                    spark=spark,
                    spec=spec,
                    conf=conf,
                    dim_config=dim_config,
                    logic_config=logic_config,
                    df_source=df_source,
                    core_df_full=core_df_full,
                    window_days=window_days,
                    fixed_hi=fixed_hi,
                )
                logger.info(f"Window {window_days}d completed successfully")
            except Exception as e:
                logger.error(
                    f"Failed to process window {window_days}d: {e}", exc_info=True
                )
                raise

        df_source.unpersist()
        logger.info("=" * 80)
        logger.info("Dimension build job completed successfully")
        logger.info("=" * 80)

    except Exception as e:
        logger.error(f"Dimension build job failed: {e}", exc_info=True)
        raise


def _setup_configuration(args: Namespace) -> Config:
    """Setup and return configuration object."""
    conf = Config(
        env=args.env,
        config_root=args.config_root,
        db_prefix=args.db_prefix,
        warehouse=args.warehouse,
    )
    logger.info(f"Configuration: {conf.to_dict()}")
    return conf


def _load_spec(args: Namespace) -> Dict[str, Any]:
    """Load and return spec from args."""
    if hasattr(args, "spec_json") and args.spec_json:
        from bietlejuice.qube.jobs.common.specs_loader import load_spec_from_json

        spec = load_spec_from_json(args.spec_json, validate=True)
        logger.info("Spec loaded from JSON string")
    else:
        # Security: Path traversal validation (CWE-23) is handled by validate_spec_path()
        # in specs_loader.load_spec(), which validates against allowed directories
        validated_path = validate_spec_path(args.spec, must_exist=True)
        spec = load_spec(str(validated_path), validate=True)
        logger.info(f"Spec loaded from: {validated_path}")
    return spec


def _extract_dimension_config(spec: Dict[str, Any], conf: Config) -> DimensionConfig:
    """Extract dimension configuration from spec."""
    entity = spec["entity"]
    name = spec["name"]

    raw_windows = spec.get("windows", [1, 7, 28])
    windows = [raw_windows] if isinstance(raw_windows, int) else raw_windows

    source = spec["source"]
    source_table_raw = source.get("table") or f"core_{entity}.{entity}"
    source_table = conf.get_table_path("core", source_table_raw)
    entity_id_col = source.get("entity_id_col") or f"id_{entity}"
    date_expr_sql = source["date_expr"]

    required_cols = [entity_id_col]
    if "select" in source:
        required_cols.extend(source["select"])

    return DimensionConfig(
        entity=entity,
        name=name,
        windows=windows,
        source_table=source_table,
        entity_id_col=entity_id_col,
        date_expr_sql=date_expr_sql,
        required_cols=required_cols,
    )


def _extract_logic_config(spec: Dict[str, Any]) -> LogicConfig:
    """Extract logic configuration from spec."""
    logic = spec["logic"]
    order_by = spec.get("order_by", {})

    return LogicConfig(
        card=logic.get("card", "single"),
        dtype=logic.get("type", "string"),
        agg=logic.get("agg"),
        expr_sql=logic.get("expr_sql"),
        value_col=logic.get("value_col", spec["name"]),
        order_by_ts_col=order_by.get("ts_col") if order_by else None,
        extra_cols=spec.get("extra_cols", []),
        include_all_entities=spec.get("include_all_entities", False),
        defaults=spec.get("defaults", {}),
    )


def _prepare_source_data(
    spark: SparkSession, dim_config: DimensionConfig, env: str, conf: Config
) -> DataFrame:
    """Load, validate, and prepare source data."""
    logger.info("Loading source data...")
    df_source = load_table(spark, dim_config.source_table, env=env)

    validate_source_data(df_source, dim_config.entity, dim_config.required_cols)

    df_source = df_source.withColumn("event_date", F.expr(dim_config.date_expr_sql))

    if env == "prod":
        logger.info("Repartitioning source data by event_date")
        df_source = df_source.repartition(F.col("event_date"))

    df_source.persist()
    source_count = df_source.count()
    logger.info(f"Source data loaded and cached: {source_count} rows")

    return df_source


def _determine_target_date(date_str: str, df_source: DataFrame) -> int:
    """Determine the target date timestamp."""
    if date_str:
        _, fixed_hi = get_window_range(date_str, 0)
        logger.info(f"Using provided date: {date_str}")
    else:
        max_row = df_source.select(F.max("event_date").alias("max_date")).collect()
        max_val = max_row[0]["max_date"]

        if max_val is None:
            dt = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            fixed_hi = int(dt.timestamp())
            logger.warning("No data in source, using current date")
        else:
            fixed_hi = int(max_val)
            logger.info("Using max date from source data")

    return fixed_hi


def _load_core_entity_table(
    spark: SparkSession,
    source_table: str,
    core_table: str,
    df_source: DataFrame,
    env: str,
) -> DataFrame:
    """Load core entity table for supported IDs."""
    if source_table == core_table or (
        "." not in source_table
        and source_table.split(".")[-1] == core_table.split(".")[-1]
    ):
        logger.info("Source table is core entity table, reusing")
        return df_source
    else:
        logger.info(f"Loading core entity table: {core_table}")
        core_df = load_table(spark, core_table, env=env)
        core_df.persist()
        return core_df


def _process_window(
    spark: SparkSession,
    spec: Dict[str, Any],
    conf: Config,
    dim_config: DimensionConfig,
    logic_config: LogicConfig,
    df_source: DataFrame,
    core_df_full: DataFrame,
    window_days: int,
    fixed_hi: int,
) -> None:
    """Process a single time window."""
    hi, lo = _calculate_window_range(fixed_hi, window_days)

    df_window = _filter_to_window(df_source, lo, hi)

    df_logic = _select_columns_for_logic(
        df_window, spec, logic_config, dim_config.entity_id_col
    )

    result_df = _apply_aggregation(
        df_logic,
        dim_config.entity_id_col,
        logic_config.value_col,
        logic_config.agg,
        logic_config.expr_sql,
        logic_config.card,
        logic_config.dtype,
        spec,
        logic_config.extra_cols,
    )

    result_df = result_df.withColumn(
        "value",
        wrap_dimension_value("raw_value", logic_config.card, logic_config.dtype),
    )

    final_df = _join_with_supported_entities_if_needed(
        result_df,
        core_df_full,
        dim_config.entity,
        dim_config.entity_id_col,
        logic_config.include_all_entities,
        hi,
    )

    final_df = _apply_defaults(final_df, logic_config)
    final_df = _prepare_output_dataframe(final_df, dim_config, logic_config, hi)

    metrics = validate_output(final_df, dim_config.entity, dim_config.name, window_days)
    logger.info(f"Output metrics: {metrics.to_dict()}")

    _write_output(final_df, conf, dim_config.entity, dim_config.name, window_days, hi)
    logger.info(f"Output written successfully: {metrics.row_count} rows")


def _calculate_window_range(fixed_hi: int, window_days: int) -> Tuple[int, int]:
    """Calculate window range timestamps."""
    hi = fixed_hi
    lo = hi - (window_days * 86400)
    hi_date = timestamp_to_date_string(hi)
    lo_date = timestamp_to_date_string(lo)
    logger.info(f"Window range: {lo_date} to {hi_date} (timestamps: {lo} to {hi})")
    return hi, lo


def _filter_to_window(df_source: DataFrame, lo: int, hi: int) -> DataFrame:
    """Filter source data to window range."""
    df_window = df_source.filter(
        (F.col("event_date") >= lo) & (F.col("event_date") <= hi)
    )
    window_count = df_window.count()
    logger.info(f"Rows in window: {window_count}")

    if window_count == 0:
        hi_date = timestamp_to_date_string(hi)
        logger.warning(
            f"No rows in window! Check if target_date ({hi_date}) overlaps with source data."
        )

    return df_window


def _select_columns_for_logic(
    df_window: DataFrame,
    spec: Dict[str, Any],
    logic_config: LogicConfig,
    entity_id_col: str,
) -> DataFrame:
    """Select columns needed for logic processing."""
    if "select" not in spec["source"]:
        return df_window

    cols = list(spec["source"]["select"])

    # Ensure value_col is included
    if logic_config.value_col not in cols:
        cols.append(logic_config.value_col)

    # Ensure extra_cols are included
    for ec in logic_config.extra_cols:
        if ec not in cols:
            cols.append(ec)

    # Ensure order_by column is included for 'last' aggregation
    if logic_config.agg == "last" and logic_config.order_by_ts_col:
        if logic_config.order_by_ts_col not in cols:
            cols.append(logic_config.order_by_ts_col)

    logger.debug(f"Selecting columns: {cols}")
    return df_window.select(*cols, "event_date")


def _join_with_supported_entities_if_needed(
    result_df: DataFrame,
    core_df_full: DataFrame,
    entity: str,
    entity_id_col: str,
    include_all_entities: bool,
    hi: int,
) -> DataFrame:
    """Join with supported entities if include_all_entities is True."""
    if not include_all_entities:
        logger.debug("Using aggregated results directly (include_all_entities=False)")
        return result_df.withColumnRenamed("entity_id", entity_id_col)

    sup_id_col = f"id_{entity}"
    sup_df = _get_supported_ids(core_df_full, sup_id_col, entity_id_col, hi)
    logger.debug(f"Joining with {sup_df.count()} supported IDs")
    return sup_df.join(
        result_df, sup_df[entity_id_col] == result_df["entity_id"], "left"
    )


def _apply_defaults(final_df: DataFrame, logic_config: LogicConfig) -> DataFrame:
    """Apply default values to missing/NULL values."""
    default_json = get_default_json(
        logic_config.card, logic_config.dtype, logic_config.defaults
    )
    return final_df.withColumn("value", F.coalesce(F.col("value"), F.lit(default_json)))


def _prepare_output_dataframe(
    final_df: DataFrame, dim_config: DimensionConfig, logic_config: LogicConfig, hi: int
) -> DataFrame:
    """Prepare final output dataframe with correct columns."""
    date_str = timestamp_to_date_string(hi)

    # Select the right entity ID column
    if dim_config.entity_id_col in final_df.columns:
        id_col = F.col(dim_config.entity_id_col)
    else:
        id_col = F.col("entity_id").alias(dim_config.entity_id_col)

    # Build final columns
    final_cols = [F.lit(date_str).alias("date"), id_col, F.col("value")]

    # Add extra columns
    if logic_config.extra_cols:
        logger.debug(
            f"Looking for extra_cols {logic_config.extra_cols} in available columns: {final_df.columns}"
        )

    for ec in logic_config.extra_cols:
        if ec in final_df.columns:
            final_cols.append(F.col(ec))
            logger.debug(f"Added extra column to output: {ec}")
        else:
            logger.warning(
                f"Extra column '{ec}' not found in final dataframe, skipping"
            )

    final_df = final_df.select(*final_cols)

    if logic_config.extra_cols:
        logger.info(f"Output columns: {final_df.columns}")

    return final_df


def _write_output(
    final_df: DataFrame, conf: Config, entity: str, name: str, window_days: int, hi: int
) -> None:
    """Write output dataframe to table using DataFrameDeltaTableLoaderPipeline."""
    # Remove entity prefix from name if it already starts with it
    # This handles cases where spec has name = "contract_rental_administrator"
    # instead of just "rental_administrator"
    if name.startswith(f"{entity}_"):
        clean_name = name[len(entity) + 1 :]  # Remove "entity_" prefix
        logger.warning(
            f"Dimension name '{name}' already contains entity prefix '{entity}_'. "
            f"Using cleaned name: '{clean_name}'"
        )
        name = clean_name

    output_table_name = f"{entity}_{name}_{window_days}d"
    output_path = conf.get_table_path("dim", output_table_name)
    # date_str = timestamp_to_date_string(hi)

    # Extract database and table name
    # Handle catalog-prefixed table names (e.g., "quintoandar_forno.qube_dimensions.table")
    parts = output_path.split(".")
    if len(parts) == 3:
        # Format: catalog.schema.table
        catalog = parts[0]
        schema = parts[1]
        table_name = parts[2]
    elif len(parts) == 2:
        # Format: schema.table
        schema = parts[0]
        table_name = parts[1]
    else:
        # No dots, just table name
        table_name = output_table_name

    # Use schema-only names to avoid Unity Catalog CREATE DATABASE errors
    database_name = "qube_dimensions"
    target_database_name = "qube_dimensions"

    # Construct database location using schema name (without catalog prefix)
    # schema_name = conf.get_schema_name("dim")
    # Note: database_location should NOT include table name - the pipeline will append it
    database_location = f"{conf.warehouse_path}/qube/dimensions/"

    logger.info(
        f"Writing output to: Catalog{catalog}Schema{schema}Table{table_name} (location: {database_location})"
    )

    # Check if dataframe is empty - skip write if no data
    row_count = final_df.count()
    if row_count == 0:
        logger.warning(f"Skipping write - dataframe is empty for {output_path}")
        return

    logger.info(f"Writing {row_count} rows to {output_path}")

    # Drop table if it has invalid path metadata (from before path fix)
    # This handles tables created with old code that had duplicate table names in path
    try:
        from pyspark.sql import SparkSession
        from pyspark.sql.utils import AnalysisException as SparkAnalysisException

        from bietlejuice.base.spark.runtime_detector import RuntimeDetector

        if RuntimeDetector.is_emr():
            from bietlejuice.base.spark.spark_session_factory import (
                create_emr_spark_session,
            )

            spark = create_emr_spark_session("build_dimension")
        else:
            spark = SparkSession.builder.getOrCreate()
        full_table_name = f"{database_name}.{table_name}"
        expected_location_s3a = f"{database_location}{table_name}"
        expected_location_s3 = expected_location_s3a.replace("s3a://", "s3://")

        try:
            if spark.catalog.tableExists(full_table_name):
                # Get table location from metadata
                table_info = spark.sql(f"DESCRIBE EXTENDED {full_table_name}").collect()
                location_row = [row for row in table_info if row[0] == "Location"]

                if location_row:
                    actual_location = location_row[0][1]

                    # Check if location matches expected (allow both s3:// and s3a://)
                    if actual_location not in [
                        expected_location_s3a,
                        expected_location_s3,
                    ]:
                        logger.warning(
                            f"Table {full_table_name} has incorrect location: {actual_location}. "
                            f"Expected: {expected_location_s3a}. Dropping table to recreate with correct path."
                        )
                        spark.sql(f"DROP TABLE IF EXISTS {full_table_name}")
        except SparkAnalysisException as e:
            # If checking table causes path error, drop it
            if "DELTA_PATH_DOES_NOT_EXIST" in str(e) or "PATH_NOT_FOUND" in str(e):
                logger.warning(
                    f"Table {full_table_name} has invalid path metadata. Dropping table to recreate."
                )
                spark.sql(f"DROP TABLE IF EXISTS {full_table_name}")
    except Exception as e:
        logger.warning(f"Could not check/drop invalid table: {e}. Continuing anyway.")
        # Continue - pipeline will handle it

    # Use DataFrameDeltaTableLoaderPipeline for writing
    pipeline = DataFrameDeltaTableLoaderPipeline(
        database_name=database_name,
        table_name=table_name,
        database_location=database_location,
        layer="enriched",
        dataframe=final_df,
        partitions=["date"],
        target_database_name=target_database_name,
        target_database_location=database_location,
        merge_schema=True,
        spark_session_configs={"udfs": []},
    )

    pipeline.run()
    logger.info(f"Output written successfully to {output_path}")


def _apply_aggregation(
    df: DataFrame,
    entity_id_col: str,
    target_col: str,
    agg: Optional[str],
    expr_sql: Optional[str],
    card: str,
    dtype: str,
    spec: Dict[str, Any],
    extra_cols: List[str] = None,
) -> DataFrame:
    """Apply aggregation logic to DataFrame."""
    extra_cols = extra_cols or []

    if agg == "last" and "order_by" in spec:
        return _apply_last_aggregation(df, entity_id_col, target_col, spec, extra_cols)
    else:
        return _apply_group_by_aggregation(
            df, entity_id_col, target_col, agg, expr_sql, extra_cols
        )


def _apply_last_aggregation(
    df: DataFrame,
    entity_id_col: str,
    target_col: str,
    spec: Dict[str, Any],
    extra_cols: List[str],
) -> DataFrame:
    """Apply window-based last value aggregation."""
    ts_col = spec["order_by"]["ts_col"]
    w = Window.partitionBy(entity_id_col).orderBy(F.col(ts_col).desc())

    df_ranked = df.withColumn("__rank", F.row_number().over(w))
    df_latest = df_ranked.filter(F.col("__rank") == 1)

    select_cols = [
        F.col(entity_id_col).alias("entity_id"),
        F.col(target_col).alias("raw_value"),
    ]
    select_cols.extend(_build_extra_column_expressions(df, extra_cols))

    return df_latest.select(*select_cols)


def _apply_group_by_aggregation(
    df: DataFrame,
    entity_id_col: str,
    target_col: str,
    agg: Optional[str],
    expr_sql: Optional[str],
    extra_cols: List[str],
) -> DataFrame:
    """Apply group-by aggregation."""
    agg_expr = _build_aggregation_expression(target_col, agg, expr_sql)

    agg_exprs = [agg_expr.alias("raw_value")]
    agg_exprs.extend(_build_extra_column_aggregations(df, extra_cols))

    return (
        df.groupBy(entity_id_col)
        .agg(*agg_exprs)
        .withColumnRenamed(entity_id_col, "entity_id")
    )


def _build_aggregation_expression(
    target_col: str, agg: Optional[str], expr_sql: Optional[str]
) -> F.Column:
    """Build aggregation expression based on agg type or expr_sql."""
    if expr_sql:
        return F.expr(expr_sql)

    agg_map = {
        "count": lambda: F.count(target_col),
        "sum": lambda: F.sum(target_col),
        "avg": lambda: F.avg(target_col),
        "min": lambda: F.min(target_col),
        "max": lambda: F.max(target_col),
        "collect_set": lambda: F.collect_set(target_col),
        "mode": lambda: F.expr(f"mode({target_col})"),
    }

    if agg in agg_map:
        return agg_map[agg]()

    return F.first(target_col)


def _build_extra_column_expressions(
    df: DataFrame, extra_cols: List[str]
) -> List[F.Column]:
    """Build column expressions for extra columns in select."""
    df_columns = df.columns
    select_cols = []

    for ec in extra_cols:
        if ec in df_columns:
            select_cols.append(F.col(ec))
        else:
            logger.warning(f"Extra column '{ec}' not found in dataframe, skipping")

    return select_cols


def _build_extra_column_aggregations(
    df: DataFrame, extra_cols: List[str]
) -> List[F.Column]:
    """Build aggregation expressions for extra columns (use first value)."""
    df_columns = df.columns
    agg_exprs = []

    for ec in extra_cols:
        if ec in df_columns:
            agg_exprs.append(F.first(ec).alias(ec))
        else:
            logger.warning(f"Extra column '{ec}' not found in dataframe, skipping")

    return agg_exprs


def _get_supported_ids(
    core_df: DataFrame, sup_id_col: str, entity_id_col: str, hi: int
) -> DataFrame:
    """Get supported entity IDs filtered by creation time."""
    if "ts_created" in core_df.columns:
        sup_df_filtered = core_df.filter(
            F.col("ts_created").cast("timestamp").cast("long") <= hi
        )
    else:
        sup_df_filtered = core_df

    date_str = timestamp_to_date_string(hi)
    return sup_df_filtered.select(
        F.lit(date_str).alias("date"), F.col(sup_id_col).alias(entity_id_col)
    ).distinct()


if __name__ == "__main__":
    args = parse_common_args("Build Dimension Tables")
    build_dimension(args)
