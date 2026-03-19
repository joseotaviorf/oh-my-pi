from datetime import datetime
import json
import re

from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.utils.common import validate_and_write

logger = QuintoAndarLogger("sst.core.observability.metrics")


@logger(exclude=["spark", "df"], exclude_return=True)
def save_volume_metric(
    spark,
    df,
    grain,
    metric_name,
    table_name,
    new_cols,
    env,
    layer,
    partition_cols,
):

    write_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    _metric = (
        df.groupby(grain)
        .agg(F.count("*").alias("row_count"))
        .withColumn("metric_name", F.lit(metric_name))
        .withColumn("source_table", F.lit(table_name))
        .withColumn("new_cols", F.lit(new_cols))
        .withColumn("metric_category", F.lit("volume"))
        .withColumn("layer", F.lit(layer))
        .withColumn("environment", F.lit(env))
        .withColumn("_write_timestamp", F.lit(write_timestamp))
        .select(
            "metric_category",
            "metric_name",
            "source_table",
            "new_cols",
            "environment",
            "layer",
            *grain,
            "row_count",
            "_write_timestamp",
        )
    )

    if _metric.rdd.isEmpty():
        logger.warning(
            f"m=save_volume_metric, msg=No rows found for metric {metric_name}, "
        )
        grain_types = {field.name: field.dataType for field in df.schema.fields}
        _metric = spark.range(1)

        for grain_col in grain:
            col_type = grain_types.get(grain_col)
            grain_col_expr = F.lit(None).cast(col_type) if col_type else F.lit(None)
            _metric = _metric.withColumn(grain_col, grain_col_expr)

        _metric = (
            _metric.withColumn("metric_category", F.lit("volume"))
            .withColumn("metric_name", F.lit(metric_name))
            .withColumn("source_table", F.lit(table_name))
            .withColumn("new_cols", F.lit(new_cols))
            .withColumn("environment", F.lit(env))
            .withColumn("layer", F.lit(layer))
            .withColumn("row_count", F.lit(0))
            .withColumn("_write_timestamp", F.lit(write_timestamp))
            .select(
                "metric_category",
                "metric_name",
                "source_table",
                "new_cols",
                "environment",
                "layer",
                *grain,
                "row_count",
                "_write_timestamp",
            )
        )

    logger.info(f"m=save_volume_metric, msg=Partition columns: {partition_cols}")
    metric_table = f"datalake_sst_metrics.{metric_name}"
    validate_and_write(
        spark=spark,
        df=_metric,
        target_table=metric_table,
        partition_cols=partition_cols,
        overwrite_schema=False,
        append=True,
    )


@logger(exclude=["spark", "df"], exclude_return=True)
def save_table_metadata_metric(
    spark,
    df,
    table_name,
    new_cols,
    env,
    layer,
    partition_values=None,
    partition_cols=None,
):
    write_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    serialized_columns = json.dumps(df.columns)
    serialized_new_cols = json.dumps(sorted(new_cols or []))

    _metric = (
        spark.range(1)
        .withColumn("metric_category", F.lit("metadata"))
        .withColumn("metric_name", F.lit("table_metadata"))
        .withColumn("source_table", F.lit(table_name))
        .withColumn("columns", F.lit(serialized_columns))
        .withColumn("new_cols", F.lit(serialized_new_cols))
        .withColumn("columns_count", F.lit(len(df.columns)))
        .withColumn("environment", F.lit(env))
        .withColumn("layer", F.lit(layer))
        .withColumn("_write_timestamp", F.lit(write_timestamp))
    )

    partition_values = partition_values or {}
    partition_cols = partition_cols or []
    for partition_col, partition_value in partition_values.items():
        _metric = _metric.withColumn(partition_col, F.lit(partition_value))

    selected_cols = [
        "metric_category",
        "metric_name",
        "source_table",
        "columns",
        "new_cols",
        "columns_count",
        "environment",
        "layer",
        *partition_cols,
        "_write_timestamp",
    ]
    _metric = _metric.select(selected_cols)

    sanitized_table_name = re.sub(r"\W", "_", table_name).strip("_").lower()
    metric_table = f"datalake_sst_metrics.{sanitized_table_name}_metadata"

    logger.info(
        f"m=save_table_metadata_metric, msg=Writing metadata metric, "
        f"metric_table={metric_table}, source_table={table_name}, partition_cols={partition_cols}"
    )
    validate_and_write(
        spark=spark,
        df=_metric,
        target_table=metric_table,
        partition_cols=partition_cols,
        overwrite_schema=False,
        append=True,
    )
