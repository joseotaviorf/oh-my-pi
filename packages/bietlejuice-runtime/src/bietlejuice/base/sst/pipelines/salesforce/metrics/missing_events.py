from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.sensors import (
    sensor_table_exists,
)
from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    default_args,
    retrieve_spark_session,
    validate_and_write,
)

logger = QuintoAndarLogger("sst.pipelines.metrics.cdc_pipeline_missing_events")


def salesforce_lost_metrics(
    spark, target_table, bucket, partition_date, partition_hour, env="prod"
):
    """ "
    This is a salesforce CDC specific pipeline, we could change it later if necessary to compare row count from layer to layer
    But for now, let's keep it business specific.
    """

    has_both_tables = sensor_table_exists(
        spark, f"datalake_salesforce_raw.{target_table}", fail=False
    ) and sensor_table_exists(
        spark, f"datalake_salesforce_clean.{target_table}", fail=False
    )
    # This is to avoid failing the job for new events
    if not has_both_tables:
        logger.info("m=run, msg=Missing raw or clean table")
        logger.info("m=run, msg=Skipping missing events metrics")
        return

    raw = (
        spark.read.table(f"datalake_salesforce_raw.{target_table}")
        .where(F.col("partition_date") == partition_date)
        .where(F.col("partition_hour") == partition_hour)
    )

    clean = (
        spark.read.table(f"datalake_salesforce_clean.{target_table}")
        .where(F.col("partition_date") == partition_date)
        .where(F.col("partition_hour") == partition_hour)
    )
    missing_df = raw.join(clean, on="id_record", how="left_anti").agg(
        F.count("*").alias("total_events_missing"),
        F.countDistinct("id_record").alias("unique_id_record_missing"),
    )

    write_timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    # Hardcoding this
    metric_name = "cdc_pipeline_missing_events"
    full_table_name = f"datalake_sst_metrics.{metric_name}"
    table_location = f"s3a://{bucket}/sst_metrics/{metric_name}"
    partition_filter_values = {
        "target_table": target_table,
        "partition_date": partition_date,
        "partition_hour": partition_hour,
    }
    partition_filter = build_partition_filter(partition_filter_values)
    partition_cols = list(partition_filter_values.keys())
    metric_df = missing_df.select(
        F.lit("volume").alias("metric_category"),
        F.lit("missing_cdc_events").alias("metric_name"),
        F.lit(target_table).alias("target_table"),
        F.lit(env).alias("env"),
        F.lit(partition_date).alias("partition_date"),
        F.lit(partition_hour).alias("partition_hour"),
        "unique_id_record_missing",
        "total_events_missing",
        F.lit(write_timestamp).alias("write_timestamp"),
    )
    validate_and_write(
        spark=spark,
        df=metric_df,
        target_table=full_table_name,
        table_location=table_location,
        partition_cols=partition_cols,
        partition_filter=partition_filter,
        overwrite_schema=False,
        append=False,
        sync_hive=True,
    )


@logger(exclude_return=True)
@default_args(
    optional_args=[
        dict(
            name="partition_date",
            flags=["--partition_date", "--partition-date"],
            type=str,
            required=True,
            help="Partition date (YYYY-MM-DD); Required by DAG template.",
        ),
        dict(
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=True,
            help="Partition hour (HH); Required by DAG template.",
        ),
        dict(
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
        ),
        dict(
            name="dag_name",
            flags=["--dag_name", "--dag-name"],
            type=str,
            required=False,
            default="",
            help="DAG name (optional).",
        ),
    ]
)
def run(cfg):
    logger.info(f"m=run, msg={cfg=} received")
    job_name = f"{cfg.dag_name}.{cfg.job_name}"

    logger.info(
        f"m=run, msg=Saving cdc_pipeline_missing_events for {cfg.target_table} CDC PIPELINE"
    )
    logger.info(
        f"m=run, msg=Events: {cfg.target_table}\t {cfg.partition_date}\t{cfg.partition_hour}"
    )
    spark = retrieve_spark_session(job_name=job_name)
    salesforce_lost_metrics(
        spark=spark,
        target_table=cfg.target_table,
        bucket=cfg.bucket,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        env=cfg.env,
    )
    logger.info(
        f"m=run, msg=Saving cdc_pipeline_missing_events for {cfg.target_table} CDC PIPELINE"
    )
    logger.info("m=run, msg=Pipeline completed")


if __name__ == "__main__":
    run()
