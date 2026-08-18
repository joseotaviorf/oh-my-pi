"""Generic SST API response log conforming and persistence."""

from datetime import datetime, timezone

import pyspark.sql.functions as F

from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    validate_and_write,
)

TRACKSALE_SERVICE_NAME = "tracksale"
LOGS_TABLE_LOCATION = "s3a://{bucket}/sst_metrics/api_logs"
LOGS_TARGET_TABLE = "datalake_sst_metrics.api_logs"


def conform_tracksale_api_logs(
    df,
    api_entity,
    target_table,
    job_name,
    partition_date,
):
    utc_now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return (
        df.withColumn("entity_type", F.lit(api_entity))
        .withColumn("target_table", F.lit(target_table))
        .withColumn("job_name", F.lit(job_name))
        .withColumn("load_ts", F.lit(utc_now))
        .withColumn("partition_date", F.lit(partition_date))
        .withColumn("service_name", F.lit(TRACKSALE_SERVICE_NAME))
        .withColumnRenamed("idx", "query_idx")
        .select(
            "id_record",
            "entity_type",
            "status_code",
            "api_logs",
            "query_idx",
            "success",
            "error",
            "target_table",
            "job_name",
            "load_ts",
            "partition_date",
            "service_name",
        )
    )


def conform_and_save_tracksale_api_logs(
    spark,
    df,
    api_entity,
    target_table,
    job_name,
    partition_date,
    bucket,
):
    """
    Conform Tracksale API response logs and write them to ``api_logs``.
    """

    logs_df = conform_tracksale_api_logs(
        df=df,
        api_entity=api_entity,
        target_table=target_table,
        job_name=job_name,
        partition_date=partition_date,
    )

    # target_table is part of the isolation key because a single Tracksale
    # campaign_code (entity_type) feeds several tables: without it, each table's
    # write would replaceWhere over the previous table's rows for the same day.
    partition_filter = {
        "partition_date": partition_date,
        "entity_type": api_entity,
        "job_name": job_name,
        "service_name": TRACKSALE_SERVICE_NAME,
        "target_table": target_table,
    }
    partition_cols = list(partition_filter.keys())
    filter_expr = build_partition_filter(partition_filter)

    table_location = LOGS_TABLE_LOCATION.format(bucket=bucket)
    validate_and_write(
        spark=spark,
        df=logs_df,
        target_table=LOGS_TARGET_TABLE,
        partition_filter=filter_expr,
        partition_cols=partition_cols,
        overwrite_schema=False,
        table_location=table_location,
        sync_hive=True,
        sync_secondary_catalog=True,
    )
