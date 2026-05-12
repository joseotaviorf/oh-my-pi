"""
Data quality checks and validation utilities.
"""

from typing import Any, Dict, List, Optional

from pyspark.sql import DataFrame
from pyspark.sql import functions as F

from bietlejuice.qube.jobs.common.logging_config import get_logger

logger = get_logger("data_quality")


class DataQualityMetrics:
    """Container for data quality metrics."""

    def __init__(
        self,
        row_count: int,
        null_counts: Dict[str, int],
        distinct_counts: Dict[str, int],
        warnings: List[str],
    ):
        self.row_count = row_count
        self.null_counts = null_counts
        self.distinct_counts = distinct_counts
        self.warnings = warnings

    def to_dict(self) -> Dict[str, Any]:
        """Export metrics as dictionary."""
        return {
            "row_count": self.row_count,
            "null_counts": self.null_counts,
            "distinct_counts": self.distinct_counts,
            "warnings": self.warnings,
        }


def validate_output(
    df: DataFrame,
    entity: str,
    name: str,
    window_days: int,
    check_nulls: bool = True,
    null_threshold: float = 0.5,
    warn_empty: bool = True,
) -> DataQualityMetrics:
    """
    Validate output DataFrame and collect quality metrics.

    Args:
        df: DataFrame to validate
        entity: Entity name for logging
        name: Dimension/measure/metric name
        window_days: Window size in days
        check_nulls: Whether to check for high null rates
        null_threshold: Threshold for null rate warnings (0.0-1.0)
        warn_empty: Whether to warn on empty output

    Returns:
        DataQualityMetrics object with validation results
    """
    table_name = f"{entity}_{name}_{window_days}d"
    logger.info(f"Validating output: {table_name}")

    warnings = []

    # Get row count
    row_count = df.count()
    logger.info(f"Row count: {row_count}", extra={"row_count": row_count})

    if warn_empty and row_count == 0:
        warning = f"Empty output detected for {table_name}"
        logger.warning(warning)
        warnings.append(warning)

    # Check nulls if requested and data exists
    null_counts = {}
    distinct_counts = {}

    if row_count > 0:
        # Calculate null counts for each column
        for col_name in df.columns:
            null_count = df.filter(F.col(col_name).isNull()).count()
            null_counts[col_name] = null_count

            if check_nulls and null_count > 0:
                null_rate = null_count / row_count
                if null_rate > null_threshold:
                    warning = (
                        f"High null rate in {table_name}.{col_name}: "
                        f"{null_count}/{row_count} ({null_rate:.1%})"
                    )
                    logger.warning(warning)
                    warnings.append(warning)

        # Calculate distinct counts for key columns
        key_cols = [c for c in df.columns if c not in ["date", "value"]]
        for col_name in key_cols[:5]:  # Limit to first 5 to avoid expensive ops
            try:
                distinct_count = df.select(col_name).distinct().count()
                distinct_counts[col_name] = distinct_count
                logger.debug(f"Distinct values in {col_name}: {distinct_count}")
            except Exception as e:
                logger.debug(f"Could not compute distinct count for {col_name}: {e}")

    metrics = DataQualityMetrics(
        row_count=row_count,
        null_counts=null_counts,
        distinct_counts=distinct_counts,
        warnings=warnings,
    )

    if warnings:
        logger.warning(f"Data quality issues found: {len(warnings)} warnings")
    else:
        logger.info(f"Data quality check passed for {table_name}")

    return metrics


def validate_source_data(
    df: DataFrame,
    entity: str,
    required_columns: List[str],
    date_col: Optional[str] = None,
) -> None:
    """
    Validate source data before processing.

    Args:
        df: Source DataFrame
        entity: Entity name for logging
        required_columns: List of required column names
        date_col: Optional date column to check for valid range

    Raises:
        ValueError: If validation fails
    """
    logger.info(f"Validating source data for entity: {entity}")

    # Check if DataFrame is empty
    if df.rdd.isEmpty():
        raise ValueError(f"Source data is empty for entity: {entity}")

    # Check for required columns
    missing_cols = set(required_columns) - set(df.columns)
    if missing_cols:
        raise ValueError(
            f"Missing required columns in source data for {entity}: {missing_cols}"
        )

    logger.info(f"Source data validation passed for {entity}")

    # Log basic stats
    row_count = df.count()
    logger.info(f"Source row count: {row_count}", extra={"row_count": row_count})

    if date_col and date_col in df.columns:
        date_stats = df.select(
            F.min(date_col).alias("min_date"), F.max(date_col).alias("max_date")
        ).collect()[0]

        logger.info(f"Date range: {date_stats['min_date']} to {date_stats['max_date']}")


def log_processing_stats(
    input_count: int, output_count: int, entity: str, name: str, window_days: int
) -> None:
    """
    Log processing statistics.

    Args:
        input_count: Number of input rows
        output_count: Number of output rows
        entity: Entity name
        name: Dimension/measure/metric name
        window_days: Window size in days
    """
    table_name = f"{entity}_{name}_{window_days}d"

    if input_count > 0:
        reduction_rate = (input_count - output_count) / input_count
        logger.info(
            f"Processing stats for {table_name}: "
            f"input={input_count}, output={output_count}, "
            f"reduction={reduction_rate:.1%}",
            extra={
                "input_count": input_count,
                "output_count": output_count,
                "reduction_rate": reduction_rate,
            },
        )
    else:
        logger.info(
            f"Processing stats for {table_name}: "
            f"input={input_count}, output={output_count}"
        )
