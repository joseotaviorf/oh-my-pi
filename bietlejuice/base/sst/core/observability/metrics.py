from datetime import datetime

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

    metric_rows = _metric.collect()
    if len(metric_rows) == 0:
        logger.warning(
            f"m=save_volume_metric, msg=No rows found for metric {metric_name}, "
        )
        return None

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
