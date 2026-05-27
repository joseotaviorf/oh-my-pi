"""
Build measure tables with temporal aggregations.

This module processes source data to create measure tables (filtered entity sets)
at multiple time windows (1d, 7d, 28d by default).
"""

from argparse import Namespace
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from bietlejuice.base.validation.target_resolver import validation_database_location
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
    get_spark_session,
    get_window_range,
    load_table,
    timestamp_to_date_string,
)

logger = get_logger("build_measure")


@dataclass
class MeasureConfig:
    """Configuration extracted from spec for measure building."""

    entity: str
    name: str
    windows: List[int]
    source_table: str
    entity_id_col: str
    date_expr_sql: str
    filter_sql: str


def build_measure(args: Namespace) -> None:
    """
    Build measure tables for all configured time windows.

    Args:
        args: Command-line arguments containing spec path, date, env, etc.
    """
    setup_logging(level=args.log_level, log_format=args.log_format)
    logger.info("=" * 80)
    logger.info("Starting measure build job")
    logger.info("=" * 80)

    try:
        conf = _setup_configuration(args)
        spark = get_spark_session("build_measure", env=args.env)
        logger.info(f"Spark session initialized: {spark.sparkContext.appName}")

        spec = _load_spec(args)
        meas_config = _extract_measure_config(spec, conf)

        logger.info(f"Building measure: {meas_config.entity}.{meas_config.name}")
        logger.info(f"Time windows: {meas_config.windows} days")
        logger.info(f"Source table: {meas_config.source_table}")
        logger.info(f"Entity ID column: {meas_config.entity_id_col}")
        logger.info(f"Filter: {meas_config.filter_sql}")

        df_source = _prepare_source_data(spark, meas_config, args.env)

        fixed_hi = _determine_target_date(args.date, df_source)
        target_date = datetime.fromtimestamp(fixed_hi).strftime("%Y-%m-%d")
        logger.info(f"Target date: {target_date} (timestamp: {fixed_hi})")

        for window_days in meas_config.windows:
            logger.info("-" * 80)
            logger.info(f"Processing window: {window_days} days")

            try:
                _process_window(
                    conf=conf,
                    meas_config=meas_config,
                    df_source=df_source,
                    window_days=window_days,
                    fixed_hi=fixed_hi,
                    target_database_name=getattr(args, "target_database_name", None),
                    target_table_name=getattr(args, "target_table_name", None),
                )
                logger.info(f"Window {window_days}d completed successfully")
            except Exception as e:
                logger.error(
                    f"Failed to process window {window_days}d: {e}", exc_info=True
                )
                raise

        df_source.unpersist()
        logger.info("=" * 80)
        logger.info("Measure build job completed successfully")
        logger.info("=" * 80)

    except Exception as e:
        logger.error(f"Measure build job failed: {e}", exc_info=True)
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


def _extract_measure_config(spec: Dict[str, Any], conf: Config) -> MeasureConfig:
    """Extract measure configuration from spec."""
    entity = spec["entity"]
    name = spec["name"]

    raw_windows = spec.get("windows", [1, 7, 28])
    windows = [raw_windows] if isinstance(raw_windows, int) else raw_windows

    source = spec["source"]
    source_table_raw = source.get("table") or f"core_{entity}.{entity}"
    source_table = conf.get_table_path("core", source_table_raw)
    entity_id_col = source.get("entity_id_col") or f"id_{entity}"
    date_expr_sql = source["date_expr"]
    filter_sql = spec["logic"]["filter_sql"]

    return MeasureConfig(
        entity=entity,
        name=name,
        windows=windows,
        source_table=source_table,
        entity_id_col=entity_id_col,
        date_expr_sql=date_expr_sql,
        filter_sql=filter_sql,
    )


def _prepare_source_data(
    spark: SparkSession, meas_config: MeasureConfig, env: str
) -> DataFrame:
    """Load, validate, and prepare source data."""
    logger.info("Loading source data...")
    df_source = load_table(spark, meas_config.source_table, env=env)

    validate_source_data(df_source, meas_config.entity, [meas_config.entity_id_col])

    df_source = df_source.withColumn("event_date", F.expr(meas_config.date_expr_sql))

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


def _process_window(
    conf: Config,
    meas_config: MeasureConfig,
    df_source: DataFrame,
    window_days: int,
    fixed_hi: int,
    target_database_name: Optional[str] = None,
    target_table_name: Optional[str] = None,
) -> None:
    """Process a single time window."""
    hi, lo = _calculate_window_range(fixed_hi, window_days)

    df_window = _filter_to_window(df_source, lo, hi)
    df_filtered = _apply_measure_filter(df_window, meas_config.filter_sql)
    result_df = _extract_distinct_entities(df_filtered, meas_config.entity_id_col, hi)

    metrics = validate_output(
        result_df, meas_config.entity, meas_config.name, window_days
    )
    logger.info(f"Output metrics: {metrics.to_dict()}")

    _write_output(
        result_df,
        conf,
        meas_config.entity,
        meas_config.name,
        window_days,
        hi,
        target_database_name=target_database_name,
        target_table_name=target_table_name,
    )
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


def _apply_measure_filter(df: DataFrame, filter_sql: str) -> DataFrame:
    """Apply filter SQL to dataframe."""
    logger.debug(f"Applying filter: {filter_sql}")
    df_filtered = df.filter(F.expr(filter_sql))
    filtered_count = df_filtered.count()
    logger.info(f"Rows after filter: {filtered_count}")
    return df_filtered


def _extract_distinct_entities(df: DataFrame, entity_id_col: str, hi: int) -> DataFrame:
    """Extract distinct entity IDs and add date column."""
    result_df = df.select(F.col(entity_id_col)).distinct()

    date_str = timestamp_to_date_string(hi)
    result_df = result_df.withColumn("date", F.lit(date_str))

    return result_df


def _write_output(
    result_df: DataFrame,
    conf: Config,
    entity: str,
    name: str,
    window_days: int,
    hi: int,
    target_database_name: Optional[str] = None,
    target_table_name: Optional[str] = None,
) -> None:
    """Write output dataframe to table using DataFrameDeltaTableLoaderPipeline."""
    # Remove entity prefix from name if it already starts with it
    # This handles cases where spec has name = "contract_rental_administrator"
    # instead of just "rental_administrator"
    if name.startswith(f"{entity}_"):
        clean_name = name[len(entity) + 1 :]  # Remove "entity_" prefix
        logger.warning(
            f"Measure name '{name}' already contains entity prefix '{entity}_'. "
            f"Using cleaned name: '{clean_name}'"
        )
        name = clean_name

    output_table_name = f"{entity}_{name}_{window_days}d"
    output_path = conf.get_table_path("meas", output_table_name)
    # date_str = timestamp_to_date_string(hi)

    # Extract database and table name
    # Handle catalog-prefixed table names (e.g., "quintoandar_forno.qube_measures.table")
    parts = output_path.split(".")
    if len(parts) == 3:
        # Format: catalog.schema.table
        # catalog = parts[0]
        # schema = parts[1]
        table_name = parts[2]
    elif len(parts) == 2:
        # Format: schema.table
        # schema = parts[0]
        table_name = parts[1]
    else:
        # No dots, just table name
        table_name = output_table_name

    # Use schema-only names to avoid Unity Catalog CREATE DATABASE errors
    database_name = "qube_measures"
    write_database_name = "qube_measures"

    # Construct database location using schema name (without catalog prefix)
    # schema_name = conf.get_schema_name("meas")
    # Note: database_location should NOT include table name - the pipeline will append it
    database_location = f"{conf.warehouse_path}/qube/measures/"

    # Redirect writes to cluster_validation schema when validation args are provided
    if target_database_name and target_table_name:
        write_database_name = target_database_name
        # Derive per-window validation table name so each window writes to a distinct table
        table_name = f"{database_name}___{output_table_name}"
        # Extract bucket name from warehouse_path (e.g. "s3a://5a-datalake-prod" → "5a-datalake-prod")
        bucket = conf.warehouse_path.split("//", 1)[-1].split("/")[0]
        database_location = validation_database_location(bucket, database_name)
        output_path = f"{write_database_name}.{table_name}"
        logger.info(
            f"Validation mode: redirecting write to {write_database_name}.{table_name}"
        )

    logger.info(f"Writing output to: {output_path} (location: {database_location})")

    # Check if dataframe is empty - skip write if no data
    row_count = result_df.count()
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

            spark = create_emr_spark_session("build_measure")
        else:
            spark = SparkSession.builder.getOrCreate()
        full_table_name = f"{write_database_name}.{table_name}"
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
        database_name=write_database_name,
        table_name=table_name,
        database_location=database_location,
        layer="enriched",
        dataframe=result_df,
        partitions=["date"],
        target_database_name=write_database_name,
        target_database_location=database_location,
        merge_schema=True,
        spark_session_configs={"udfs": []},
    )

    pipeline.run()
    logger.info(f"Output written successfully to {output_path}")


if __name__ == "__main__":
    args = parse_common_args("Build Measure Tables")
    build_measure(args)
