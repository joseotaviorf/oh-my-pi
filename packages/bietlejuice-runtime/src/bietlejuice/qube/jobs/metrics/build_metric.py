"""
Build metric tables by joining dimensions and measures.

This module creates metrics by joining dimension and measure tables,
aggregating counts, and applying k-anonymity privacy protections.
"""

from argparse import Namespace
from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

from pyspark.sql import DataFrame, SparkSession
from pyspark.sql import functions as F

from bietlejuice.pipeline.dataframe_delta_table_loader_pipeline import (
    DataFrameDeltaTableLoaderPipeline,
)
from bietlejuice.qube.jobs.common.conf import Config, parse_common_args
from bietlejuice.qube.jobs.common.data_quality import validate_output
from bietlejuice.qube.jobs.common.logging_config import get_logger, setup_logging
from bietlejuice.qube.jobs.common.path_validator import validate_spec_path
from bietlejuice.qube.jobs.common.privacy import apply_k_anonymity
from bietlejuice.qube.jobs.common.specs_loader import load_spec
from bietlejuice.qube.jobs.common.utils import (
    extract_dimension_value,
    get_spark_session,
    get_window_range,
    load_table,
    timestamp_to_date_string,
)

logger = get_logger("build_metric")


@dataclass
class MetricConfig:
    """Configuration for metric building."""

    entity: str
    name: str
    windows: List[int]
    dim_specs: List[Dict[str, Any]]
    meas_specs: List[Dict[str, Any]]
    k_anonymity: int
    counter_type: str  # "long" or "approx"


def build_metric(args: Namespace) -> None:
    """
    Build metric tables for all configured time windows.

    Args:
        args: Command-line arguments containing spec path, date, env, etc.
    """
    # Setup logging
    setup_logging(level=args.log_level, log_format=args.log_format)
    logger.info("=" * 80)
    logger.info("Starting metric build job")
    logger.info("=" * 80)

    try:
        # Setup configuration
        conf = _setup_configuration(args)
        logger.info(f"Configuration: {conf.to_dict()}")

        # Initialize Spark
        spark = get_spark_session("build_metric", env=args.env)
        logger.info(f"Spark session initialized: {spark.sparkContext.appName}")

        # Load and validate spec
        spec = _load_spec(args)

        # Extract metric configuration
        metric_config = _extract_metric_config(spec, conf)

        logger.info(f"Building metric: {metric_config.entity}.{metric_config.name}")
        logger.info(f"Time windows: {metric_config.windows} days")

        # Check if date is provided
        if not args.date:
            logger.warning(
                "No --date argument provided. Will attempt to infer from dimension tables. "
                "If dimension tables don't exist yet, current date will be used. "
                "For best results, provide --date argument or build dimensions first."
            )

        # Determine target date
        fixed_hi = _determine_target_date(
            args.date,
            spec,
            conf,
            spark,
            metric_config.windows,
            metric_config.entity,
            args.env,
        )
        target_date = datetime.fromtimestamp(fixed_hi).strftime("%Y-%m-%d")
        logger.info(f"Target date: {target_date} (timestamp: {fixed_hi})")

        # Process each window
        for window_days in metric_config.windows:
            logger.info("-" * 80)
            logger.info(f"Processing window: {window_days} days")

            try:
                _process_window(
                    spark=spark,
                    metric_config=metric_config,
                    conf=conf,
                    window_days=window_days,
                    fixed_hi=fixed_hi,
                    env=args.env,
                )
                logger.info(f"Window {window_days}d completed successfully")
            except Exception as e:
                logger.error(
                    f"Failed to process window {window_days}d: {e}", exc_info=True
                )
                raise

        logger.info("=" * 80)
        logger.info("Metric build job completed successfully")
        logger.info("=" * 80)

    except Exception as e:
        logger.error(f"Metric build job failed: {e}", exc_info=True)
        raise


def _setup_configuration(args: Namespace) -> Config:
    """Setup configuration from command-line arguments."""
    return Config(
        env=args.env,
        config_root=args.config_root,
        db_prefix=args.db_prefix,
        warehouse=args.warehouse,
    )


def _load_spec(args: Namespace) -> Dict[str, Any]:
    """Load and validate metric specification."""
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


def _extract_metric_config(spec: Dict[str, Any], conf: Config) -> MetricConfig:
    """Extract metric configuration from spec."""
    entity = spec["entity"]
    name = spec["name"]

    # Determine windows
    raw_windows = spec.get("windows", [1, 7, 28])
    windows = [raw_windows] if isinstance(raw_windows, int) else raw_windows

    # Extract dimension and measure specs
    dim_specs = spec.get("dimensions", [])
    meas_specs = spec.get("measures", [])

    # Extract privacy settings
    k_anonymity = spec.get("privacy", {}).get("k_anonymity", 10)

    # Extract counter type
    counter_type = spec.get("counters", {}).get("type", "long")

    return MetricConfig(
        entity=entity,
        name=name,
        windows=windows,
        dim_specs=dim_specs,
        meas_specs=meas_specs,
        k_anonymity=k_anonymity,
        counter_type=counter_type,
    )


def _determine_target_date(
    date_str: str,
    spec: Dict[str, Any],
    conf: Config,
    spark: SparkSession,
    windows: List[int],
    entity: str,
    env: str,
) -> int:
    """Determine the target date timestamp."""
    if date_str:
        _, fixed_hi = get_window_range(date_str, 0)
        logger.info(f"Using provided date: {date_str}")
    else:
        # Try to infer from first dimension table
        first_dim_spec = spec.get("dimensions", [])[0]
        check_win = windows[0]
        first_dim_table = f"{first_dim_spec['name']}_{check_win}d"
        first_dim_path = conf.get_table_path("dim", first_dim_table)

        logger.info(f"Attempting to infer date from: {first_dim_path}")

        try:
            _, fixed_hi = get_window_range(
                None,
                0,
                spark=spark,
                table_name=first_dim_path,
                date_col="date",
                env=env,
            )
            logger.info("Using max date from dimension table")
        except Exception as e:
            logger.warning(
                f"Could not infer date from dimension table: {e}. "
                "Using current date. Consider providing --date argument."
            )
            from datetime import datetime

            dt = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
            fixed_hi = int(dt.timestamp())
            logger.info(
                f"Using current date: {datetime.fromtimestamp(fixed_hi).strftime('%Y-%m-%d')}"
            )

    return fixed_hi


def _process_window(
    spark: SparkSession,
    metric_config: MetricConfig,
    conf: Config,
    window_days: int,
    fixed_hi: int,
    env: str,
) -> None:
    """Process a single time window."""
    hi = fixed_hi
    lo = hi - (window_days * 86400)
    date_str = timestamp_to_date_string(hi)
    logger.info(f"Window range: {lo} to {hi}")
    logger.info(f"Target date: {date_str}")

    # Load and join dimensions
    logger.info(f"Loading {len(metric_config.dim_specs)} dimensions")
    base_df, dim_cols_info, has_multi, entity_id_col = _load_and_join_dimensions(
        spark, metric_config.dim_specs, metric_config.entity, window_days, conf, env
    )
    if base_df is None:
        logger.warning(f"Window {window_days}d skipped: no dimension data available.")
        return
    logger.info(f"Dimensions loaded, entity_id: {entity_id_col}")
    logger.info(f"Has multi-valued dimensions: {has_multi}")

    # Load and join measures
    logger.info(f"Loading {len(metric_config.meas_specs)} measures")
    full_df, measure_output_cols, loaded_meas_specs = _load_and_join_measures(
        spark,
        metric_config.meas_specs,
        base_df,
        metric_config.entity,
        window_days,
        conf,
        env,
        entity_id_col,
    )
    if len(loaded_meas_specs) < len(metric_config.meas_specs):
        skipped = [
            s["name"] for s in metric_config.meas_specs if s not in loaded_meas_specs
        ]
        logger.warning(
            f"Proceeding with {len(loaded_meas_specs)}/{len(metric_config.meas_specs)} measures. Skipped: {skipped}"
        )

    # Aggregate metrics — use only the measures that were actually loaded
    result_df = _aggregate_metrics(
        full_df,
        dim_cols_info,
        loaded_meas_specs,
        entity_id_col,
        has_multi,
        window_days,
        metric_config.counter_type,
        measure_output_cols,
    )

    # Apply privacy protection
    result_df = _apply_privacy_protection(
        result_df, dim_cols_info, measure_output_cols, metric_config.k_anonymity
    )

    # Validate and write output
    _write_metric_output(
        result_df, conf, metric_config.entity, metric_config.name, window_days, hi
    )


def _load_and_join_dimensions(
    spark: SparkSession,
    dim_specs: List[Dict[str, Any]],
    entity: str,
    window_days: int,
    conf: Config,
    env: str,
) -> Tuple[DataFrame, List[Tuple[str, str]], bool, str]:
    """Load and join all dimension tables, skipping any that do not exist yet."""
    base_df = None
    dim_cols_info = []
    has_multi = False
    join_keys = ["date"]
    entity_id_col = None

    for d_spec in dim_specs:
        d_name = d_spec["name"]
        d_card = d_spec.get("card", "single")
        d_type = d_spec.get("type", "string")

        d_df = _load_single_dimension(spark, entity, d_name, window_days, conf, env)
        if d_df is None:
            logger.warning(
                f"Skipping dimension '{d_name}' for window {window_days}d: table not available"
            )
            continue

        # Identify entity_id column
        if entity_id_col is None:
            entity_id_col = _identify_entity_id_column(d_df)
            join_keys.append(entity_id_col)

        # Parse dimension value
        parsed_col_name = f"dim_{d_name}"
        d_df = _parse_dimension_value(d_df, parsed_col_name, d_card, d_type)

        # Handle multi-valued dimensions
        if d_card == "multi":
            has_multi = True
            d_df = _handle_multi_valued_dimension(d_df, parsed_col_name)

        # Project relevant columns
        d_df = d_df.select(*join_keys, parsed_col_name)
        dim_cols_info.append((parsed_col_name, d_type))

        # Join
        if base_df is None:
            base_df = d_df
        else:
            base_df = base_df.join(d_df, on=join_keys, how="inner")

    if base_df is None:
        logger.warning(
            f"No dimension tables available for window {window_days}d — skipping window."
        )
        return None, [], False, None

    return base_df, dim_cols_info, has_multi, entity_id_col


def _load_and_join_measures(
    spark: SparkSession,
    meas_specs: List[Dict[str, Any]],
    base_df: DataFrame,
    entity: str,
    window_days: int,
    conf: Config,
    env: str,
    entity_id_col: str,
) -> Tuple[DataFrame, List[str], List[Dict[str, Any]]]:
    """Load and join all measure tables, skipping any that do not exist yet.

    Returns the joined DataFrame, output column names, and the subset of
    measure specs that were actually loaded (so downstream aggregation only
    references columns that exist in the DataFrame).
    """
    full_df = base_df
    measure_output_cols = []
    loaded_meas_specs = []
    join_keys = ["date", entity_id_col]

    for m_spec in meas_specs:
        m_name = m_spec["name"]

        m_df = _load_single_measure(spark, entity, m_name, window_days, conf, env)
        if m_df is None:
            logger.warning(
                f"Skipping measure '{m_name}' for window {window_days}d: table not available"
            )
            continue

        loaded_meas_specs.append(m_spec)

        # Add flag column
        m_df = _prepare_measure_flag_column(m_df, join_keys, m_name)

        # Left join
        full_df = full_df.join(m_df, on=join_keys, how="left")

        # Fill nulls
        col_name = f"m_{m_name}"
        full_df = full_df.withColumn(col_name, F.coalesce(F.col(col_name), F.lit(0)))

    return full_df, measure_output_cols, loaded_meas_specs


def _aggregate_metrics(
    full_df: DataFrame,
    dim_cols_info: List[Tuple[str, str]],
    meas_specs: List[Dict[str, Any]],
    entity_id_col: str,
    has_multi: bool,
    window_days: int,
    counter_type: str,
    measure_output_cols: List[str],
) -> DataFrame:
    """Aggregate metrics by dimensions."""
    logger.info("Aggregating metrics")
    group_cols = ["date"] + [c[0] for c in dim_cols_info]

    agg_exprs = _build_agg_exprs(
        meas_specs,
        entity_id_col,
        has_multi,
        window_days,
        counter_type,
        measure_output_cols,
    )

    result_df = full_df.groupBy(*group_cols).agg(*agg_exprs)

    agg_count = result_df.count()
    logger.info(f"Aggregated rows: {agg_count}")

    return result_df


def _apply_privacy_protection(
    result_df: DataFrame,
    dim_cols_info: List[Tuple[str, str]],
    measure_output_cols: List[str],
    k_anonymity: int,
) -> DataFrame:
    """Apply k-anonymity privacy protection."""
    logger.info(f"Applying k-anonymity with k={k_anonymity}")
    return apply_k_anonymity(result_df, dim_cols_info, measure_output_cols, k_anonymity)


def _write_metric_output(
    result_df: DataFrame,
    conf: Config,
    entity: str,
    name: str,
    window_days: int,
    hi: int,
) -> None:
    """Write metric output to table using DataFrameDeltaTableLoaderPipeline."""
    # Validate output
    metrics = validate_output(result_df, entity, name, window_days)
    logger.info(f"Output metrics: {metrics.to_dict()}")

    # Remove entity prefix from name if it already starts with it
    # This handles cases where spec has name = "contract_rental_administrator"
    # instead of just "rental_administrator"
    if name.startswith(f"{entity}_"):
        clean_name = name[len(entity) + 1 :]  # Remove "entity_" prefix
        logger.warning(
            f"Metric name '{name}' already contains entity prefix ''. "
            f"Using cleaned name: '{clean_name}'"
        )
        name = clean_name

    # Prepare output paths
    output_table_name = f"{entity}_{name}_{window_days}d"
    output_path = conf.get_table_path("met", output_table_name)

    # Extract database and table name
    # Handle catalog-prefixed table names (e.g., "quintoandar_forno.qube_metrics.table")
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
    database_name = "qube_metrics"
    target_database_name = "qube_metrics"

    # Construct database location using schema name (without catalog prefix)
    # schema_name = conf.get_schema_name("met")
    # Note: database_location should NOT include table name - the pipeline will append it
    database_location = f"{conf.warehouse_path}/qube/metrics/"

    logger.info(f"Writing output to: {output_path} (location: {database_location})")
    # date_str = timestamp_to_date_string(hi)
    logger.info(result_df.printSchema())

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

            spark = create_emr_spark_session("build_metric")
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
        dataframe=result_df,
        partitions=["date"],
        target_database_name=target_database_name,
        target_database_location=database_location,
        merge_schema=True,
        spark_session_configs={"udfs": []},
    )

    pipeline.run()
    logger.info(f"Output written successfully: {metrics.row_count} rows")


def _load_single_dimension(
    spark: SparkSession,
    entity: str,
    dim_name: str,
    window_days: int,
    conf: Config,
    env: str,
) -> Optional[DataFrame]:
    """Load a single dimension table, returning None if it does not exist yet."""
    table_name = f"{dim_name}_{window_days}d"
    path = conf.get_table_path("dim", table_name)

    logger.debug(f"Loading dimension: {table_name}")
    try:
        return load_table(spark, path, env=env)
    except Exception as e:
        logger.warning(f"Dimension table not found, skipping: {path}\n" f"Error: {e}")
        return None


def _identify_entity_id_column(df: DataFrame) -> str:
    """Identify the entity_id column from the DataFrame."""
    for col_name in df.columns:
        if col_name not in ["date", "value"]:
            return col_name
    raise ValueError("Could not identify entity_id column in dimension table")


def _parse_dimension_value(
    df: DataFrame,
    parsed_col_name: str,
    card: str,
    dtype: str,
) -> DataFrame:
    """Parse dimension value based on cardinality and type."""
    return df.withColumn(
        parsed_col_name, extract_dimension_value(F.col("value"), card, dtype)
    )


def _handle_multi_valued_dimension(
    df: DataFrame,
    parsed_col_name: str,
) -> DataFrame:
    """Explode multi-valued dimension into separate rows."""
    return df.withColumn(parsed_col_name, F.explode(F.col(parsed_col_name)))


def _load_single_measure(
    spark: SparkSession,
    entity: str,
    meas_name: str,
    window_days: int,
    conf: Config,
    env: str,
) -> Optional[DataFrame]:
    """Load a single measure table, returning None if it does not exist yet."""
    table_name = f"{meas_name}_{window_days}d"
    path = conf.get_table_path("meas", table_name)

    logger.debug(f"Loading measure: {table_name}")
    try:
        return load_table(spark, path, env=env)
    except Exception as e:
        logger.warning(f"Measure table not found, skipping: {path}\n" f"Error: {e}")
        return None


def _prepare_measure_flag_column(
    df: DataFrame,
    join_keys: List[str],
    meas_name: str,
) -> DataFrame:
    """Add flag column to measure DataFrame."""
    return df.select(*join_keys).withColumn(f"m_{meas_name}", F.lit(1))


def _build_agg_exprs(
    meas_specs: List[Dict[str, Any]],
    entity_id_col: str,
    has_multi: bool,
    window_days: int,
    counter_type: str,
    measure_output_cols: List[str],
) -> List:
    """Build aggregation expressions for measures."""
    agg_exprs = []

    for m_spec in meas_specs:
        m_name = m_spec["name"]
        expr, out_col = _build_measure_aggregation(
            m_name, entity_id_col, has_multi, window_days, counter_type
        )
        agg_exprs.append(expr)
        measure_output_cols.append(out_col)

    return agg_exprs


def _build_measure_aggregation(
    meas_name: str,
    entity_id_col: str,
    has_multi: bool,
    window_days: int,
    counter_type: str,
) -> Tuple[F.Column, str]:
    """Build aggregation expression for a single measure."""
    flag_col = f"m_{meas_name}"
    target_id = F.when(F.col(flag_col) == 1, F.col(entity_id_col))

    use_approx = _determine_use_approx_counter(has_multi, counter_type)

    if use_approx:
        out_col = f"measure_{meas_name}_{window_days}d_counter_approx"
        expr = F.approx_count_distinct(target_id).alias(out_col)
    else:
        out_col = f"measure_{meas_name}_{window_days}d_counter"
        expr = F.countDistinct(target_id).alias(out_col)

    return expr, out_col


def _determine_use_approx_counter(has_multi: bool, counter_type: str) -> bool:
    """Determine whether to use approximate or exact counter."""
    return has_multi or counter_type == "approx"


if __name__ == "__main__":
    args = parse_common_args("Build Metric Tables")
    build_metric(args)
