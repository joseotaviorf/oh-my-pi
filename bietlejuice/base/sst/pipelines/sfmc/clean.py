from pyspark.sql import functions as F

from bietlejuice.base.sst.core.observability.sensors import partition_has_data
from bietlejuice.base.sst.core.utils.common import (
    normalize_df_columns,
    validate_and_write,
    validate_partition_readability,
)
from quintoandar_logger import QuintoAndarLogger


logger = QuintoAndarLogger("sst.pipelines.sfmc_clean")


@logger(exclude=["spark"], exclude_return=True)
def sfmc_clean_pipeline(spark, cfg):
    source_table = f"{cfg.source_schema}.{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"
    partition_date = cfg.partition_date

    if partition_has_data(spark, target_table, partition_date):
        logger.info(
            "m=sfmc_clean_pipeline, "
            f"msg=Partition already exists for table={target_table}, "
            f"partition_date={partition_date}. Skipping."
        )
        return

    source_df = normalize_df_columns(
        spark.read.table(source_table).where(
            F.col("partition_date") == F.lit(partition_date)
        )
    )

    cleaned_df = source_df.withColumn("ts_load", F.current_timestamp()).withColumn(
        "partition_date", F.lit(partition_date)
    )

    partition_filter = f"partition_date = '{partition_date}'"
    table_location = f"s3a://{cfg.bucket}/clean/{cfg.target_schema}/{cfg.target_table}"
    validate_and_write(
        spark=spark,
        df=cleaned_df,
        target_table=target_table,
        partition_filter=partition_filter,
        partition_cols=["partition_date"],
        overwrite_schema=True,
        table_location=table_location,
        sync_hive=cfg.sync_hive,
    )
    try:
        validate_partition_readability(
            spark=spark,
            target_table=target_table,
            partition_date=partition_date,
        )
    except Exception as err:
        raise RuntimeError(
            "Clean table write succeeded but post-write readback failed for "
            f"table={target_table}, partition_date={partition_date}. "
        ) from err

    logger.info("m=sfmc_clean_pipeline, msg=Pipeline completed")
