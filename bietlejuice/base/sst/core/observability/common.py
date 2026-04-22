from datetime import datetime
from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    validate_and_write,
)
from pyspark.sql import DataFrame
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

logger = QuintoAndarLogger("sst.core.observability.common")


def current_write_timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


def add_metric_columns(df: DataFrame, metric_values: dict[str, object]) -> DataFrame:
    """
    Add defautl metrics column to the dataframe
    """
    for column_name, value in metric_values.items():
        df = df.withColumn(column_name, F.lit(value))
    return df


def build_metric_dataframe(
    df: DataFrame,
    metric_values: dict[str, object],
    select_columns: list[str],
) -> DataFrame:
    return add_metric_columns(df, metric_values).select(*select_columns)


def save_metric_dataframe(
    spark,
    df: DataFrame,
    bucket: str,
    metric_table: str,
    partition_cols: list[str],
    partition_filter_values: dict[str, object],
) -> None:
    full_table_name = f"datalake_sst_metrics.{metric_table}"
    table_location = f"s3a://{bucket}/sst_metrics/{metric_table}"
    partition_filter = build_partition_filter(partition_filter_values)

    validate_and_write(
        spark=spark,
        df=df,
        target_table=full_table_name,
        table_location=table_location,
        partition_cols=partition_cols,
        partition_filter=partition_filter,
        overwrite_schema=False,
        append=False,
        sync_hive=True,
    )
