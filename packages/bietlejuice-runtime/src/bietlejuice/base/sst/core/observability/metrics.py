from datetime import datetime, timedelta

from pyspark.sql import DataFrame, Window
from pyspark.sql import functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.common import (
    build_metric_dataframe,
    current_write_timestamp,
    save_metric_dataframe,
)
from bietlejuice.base.sst.core.utils.common import validate_and_write
from bietlejuice.base.sst.core.utils.time import standard_now

logger = QuintoAndarLogger("sst.core.observability.metrics")


def _load_latency_df(
    spark,
    target_table,
    partition_date,
    partition_hour,
    source_ts="commit_ts",
    target_ts="ts_load",
):
    """
    Load the latency dataframe from the target table.
    Handles tranformations on the partition column
    """
    return (
        spark.read.table(target_table)
        .where(F.col("partition_date") == partition_date)
        .where(F.col("partition_hour") == partition_hour)
        .withColumn(source_ts, F.to_timestamp(F.from_unixtime(F.col(source_ts) / 1000)))
        .withColumn(target_ts, F.to_timestamp(target_ts, "yyyy-MM-dd HH:mm:ss"))
        .withColumn(
            "diff_seconds",
            F.col(target_ts).cast("long") - F.col(source_ts).cast("long"),
        )
        .select(
            "partition_date",
            "partition_hour",
            "diff_seconds",
        )
    )


def build_latency_metric_dataframe(
    df: DataFrame,
    target_table: str,
    partition_date: str,
    partition_hour: int,
    metric_name: str,
    source_layer: str,
    target_layer: str,
    env: str = "prod",
) -> DataFrame:
    aggregated_df = (
        df.groupBy("partition_date", "partition_hour")
        .agg(
            F.count("*").alias("row_count"),
            F.avg("diff_seconds").alias("average_delay"),
            F.min("diff_seconds").alias("min_value"),
            F.max("diff_seconds").alias("max_value"),
            F.expr("percentile(diff_seconds, 0.5)").alias("p50"),
            F.expr("percentile(diff_seconds, 0.9)").alias("p90"),
            F.expr("percentile(diff_seconds, 0.95)").alias("p95"),
            F.expr("percentile(diff_seconds, 0.99)").alias("p99"),
        )
        .withColumn("unit", F.lit("seconds"))
    )

    metric_values = {
        "metric_category": "latency",
        "metric_name": metric_name,
        "source_layer": source_layer,
        "target_layer": target_layer,
        "target_table": target_table,
        "environment": env,
        "partition_date": partition_date,
        "partition_hour": partition_hour,
        "write_timestamp": current_write_timestamp(),
    }

    select_columns = [
        "metric_category",
        "metric_name",
        "unit",
        "source_layer",
        "target_layer",
        "target_table",
        "environment",
        "partition_date",
        "partition_hour",
        "row_count",
        "average_delay",
        "min_value",
        "max_value",
        "p50",
        "p90",
        "p95",
        "p99",
        "write_timestamp",
    ]

    return build_metric_dataframe(
        df=aggregated_df,
        metric_values=metric_values,
        select_columns=select_columns,
    )


def save_latency_metric(
    spark,
    bucket: str,
    metric_name: str,
    target_table: str,
    metric_table: str,
    partition_date: str,
    partition_hour: int,
    source_layer: str,
    target_layer: str,
    env: str = "prod",
) -> DataFrame:
    df = _load_latency_df(spark, target_table, partition_date, partition_hour)
    results_df = build_latency_metric_dataframe(
        df=df,
        target_table=target_table,
        partition_date=partition_date,
        partition_hour=partition_hour,
        metric_name=metric_name,
        source_layer=source_layer,
        target_layer=target_layer,
        env=env,
    )

    save_metric_dataframe(
        spark=spark,
        df=results_df,
        bucket=bucket,
        metric_table=metric_table,
        partition_cols=["target_table", "partition_date", "partition_hour"],
        partition_filter_values={
            "target_table": target_table,
            "partition_date": partition_date,
            "partition_hour": partition_hour,
        },
    )


def build_stability_base_dataframe(
    spark,
    target_table: str,
    partition_date: str,
    partition_hour: str,
    window_size: int,
) -> DataFrame:
    parsed_partition_date = datetime.strptime(partition_date, "%Y-%m-%d").date()
    window_start_date = parsed_partition_date - timedelta(days=window_size)

    window_spec = Window.partitionBy("partition_hour").orderBy("partition_date")

    return (
        spark.read.table(target_table)
        .filter(
            (F.col("partition_date") >= F.lit(str(window_start_date)))
            & (F.col("partition_hour") == F.lit(partition_hour))
        )
        .groupBy("partition_date", "partition_hour")
        .agg(F.count(F.lit(1)).alias("row_count"))
        .withColumn("window_size", F.lit(window_size))
        .withColumn("history_count", F.count("row_count").over(window_spec))
        .withColumn(
            "has_historical_data",
            F.col("history_count") >= F.lit(window_size),
        )
        .withColumn("moving_avg", F.avg("row_count").over(window_spec))
        .withColumn("stddev", F.stddev("row_count").over(window_spec))
        .withColumn(
            "volume_pct_delta",
            F.when(
                F.col("moving_avg").isNotNull() & (F.col("moving_avg") != 0),
                (F.col("row_count") - F.col("moving_avg")) / F.col("moving_avg"),
            ),
        )
        .withColumn(
            "ratio",
            F.when(
                F.col("moving_avg").isNotNull() & (F.col("moving_avg") != 0),
                F.col("row_count") / F.col("moving_avg"),
            ),
        )
        .withColumn(
            "z_score",
            F.when(
                F.col("stddev").isNotNull() & (F.col("stddev") > 0),
                (F.col("row_count") - F.col("moving_avg")) / F.col("stddev"),
            ),
        )
        .withColumn(
            "cv",
            F.when(
                F.col("moving_avg").isNotNull() & (F.col("moving_avg") > 0),
                F.col("stddev") / F.col("moving_avg"),
            ),
        )
        .filter(F.col("partition_date") == F.lit(partition_date))
    )


def build_stability_metric_dataframe(
    spark,
    target_table: str,
    partition_date: str,
    partition_hour: str,
    window_size: int,
    env: str,
    layer: str,
) -> DataFrame:
    base_df = build_stability_base_dataframe(
        spark=spark,
        target_table=target_table,
        partition_date=partition_date,
        partition_hour=partition_hour,
        window_size=window_size,
    )

    metric_values = {
        "metric_category": "stability",
        "metric_name": "pipeline_volume_stability",
        "source_table": target_table,
        "environment": env,
        "layer": layer,
        "write_timestamp": current_write_timestamp(),
    }

    select_columns = [
        "metric_category",
        "metric_name",
        "window_size",
        "source_table",
        "environment",
        "layer",
        "partition_date",
        "partition_hour",
        "has_historical_data",
        "row_count",
        "moving_avg",
        "volume_pct_delta",
        "ratio",
        "stddev",
        "z_score",
        "cv",
        "write_timestamp",
    ]

    return build_metric_dataframe(
        df=base_df,
        metric_values=metric_values,
        select_columns=select_columns,
    )


def save_stability_metric(
    spark,
    bucket: str,
    target_table: str,
    partition_date: str,
    partition_hour: int,
    window_size: int,
    env: str,
    layer: str,
) -> DataFrame:
    results_df = build_stability_metric_dataframe(
        spark=spark,
        target_table=target_table,
        partition_date=partition_date,
        partition_hour=partition_hour,
        window_size=window_size,
        env=env,
        layer=layer,
    )

    save_metric_dataframe(
        spark=spark,
        df=results_df,
        bucket=bucket,
        metric_table="pipeline_stability",
        partition_cols=["source_table", "partition_date", "partition_hour"],
        partition_filter_values={
            "source_table": target_table,
            "window_size": window_size,
            "partition_date": partition_date,
            "partition_hour": partition_hour,
        },
    )

    return results_df


@logger(exclude=["spark", "df"], exclude_return=True)
def save_volume_metric(
    spark,
    df,
    grain,
    metric_name,
    table_name,
    env,
    layer,
    partition_cols,
    table_location: str,
):
    write_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    _metric = (
        df.groupby(grain)
        .agg(F.coalesce(F.count("*").cast("bigint"), F.lit(0)).alias("row_count"))
        .withColumn("metric_name", F.lit(metric_name))
        .withColumn("source_table", F.lit(table_name))
        .withColumn("metric_category", F.lit("volume"))
        .withColumn("layer", F.lit(layer))
        .withColumn("environment", F.lit(env))
        .withColumn("_write_timestamp", F.lit(write_timestamp))
        .select(
            "metric_category",
            "metric_name",
            "source_table",
            "environment",
            "layer",
            *grain,
            "row_count",
            "_write_timestamp",
        )
    )

    if _metric.isEmpty():
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
            .withColumn("environment", F.lit(env))
            .withColumn("layer", F.lit(layer))
            .withColumn("row_count", F.lit(0).cast("bigint"))
            .withColumn("_write_timestamp", F.lit(write_timestamp))
            .select(
                "metric_category",
                "metric_name",
                "source_table",
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
        table_location=table_location,
        partition_cols=partition_cols,
        overwrite_schema=False,
        append=True,
        sync_hive=True,
    )


@logger(exclude=["spark"], exclude_return=True)
def save_table_metadata_metric(
    spark,
    table_name,
    new_cols,
    env,
    layer,
    bucket: str,
    partition_date: str,
    partition_hour,
):
    """
    Append one metadata row per source table to the shared
    ``datalake_sst_metrics.table_metadata`` table.

    Each row records, for a given ``source_table`` on a given partition, how many
    new columns showed up (``new_cols_count``) and which columns they are
    (``new_cols``, an array of column names). The table is partitioned by
    ``source_table`` + partition
    keys, so re-running a partition overwrites its own row instead of duplicating
    it, and a single query returns the new-column count for every table.
    """
    new_cols = sorted(new_cols or [])

    metric_values = {
        "metric_category": "metadata",
        "metric_name": "table_metadata",
        "source_table": table_name,
        "new_cols": new_cols,
        "new_cols_count": len(new_cols),
        "environment": env,
        "layer": layer,
        "partition_date": partition_date,
        "partition_hour": partition_hour,
        "write_timestamp": standard_now(),
    }

    select_columns = [
        "metric_category",
        "metric_name",
        "source_table",
        "new_cols",
        "new_cols_count",
        "environment",
        "layer",
        "partition_date",
        "partition_hour",
        "write_timestamp",
    ]

    results_df = build_metric_dataframe(
        df=spark.range(1),
        metric_values=metric_values,
        select_columns=select_columns,
    )

    logger.info(
        f"m=save_table_metadata_metric, msg=Writing table_metadata metric, "
        f"metric_table=datalake_sst_metrics.table_metadata, source_table={table_name}, "
        f"new_cols_count={len(new_cols)}"
    )

    save_metric_dataframe(
        spark=spark,
        df=results_df,
        bucket=bucket,
        metric_table="table_metadata",
        partition_cols=["source_table", "partition_date", "partition_hour"],
        partition_filter_values={
            "source_table": table_name,
            "partition_date": partition_date,
            "partition_hour": partition_hour,
        },
    )
