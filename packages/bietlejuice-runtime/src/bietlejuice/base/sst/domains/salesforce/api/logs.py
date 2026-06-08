"""Salesforce API response log conforming and persistence."""

from datetime import datetime, timezone

import pyspark.sql.functions as F

from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    validate_and_write,
)

LOGS_TABLE_LOCATION = "s3a://{bucket}/sst_metrics/salesforce_api_logs"
LOGS_TARGET_TABLE = "datalake_sst_metrics.salesforce_api_logs"


def conform_api_logs(
    df,
    api_entity,
    target_table,
    job_name,
    partition_date,
):

    utc_now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    return (
        df.withColumn("status_code", F.get_json_object("api_logs", "$[0].status_code"))
        .withColumn("entity_type", F.lit(api_entity))
        .withColumn("target_table", F.lit(target_table))
        .withColumn("job_name", F.lit(job_name))
        .withColumn("load_ts", F.lit(utc_now))
        .withColumn("partition_date", F.lit(partition_date))
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
        )
    )


def conform_and_save_api_logs(
    spark,
    df,
    api_entity,
    target_table,
    job_name,
    partition_date,
    bucket,
):
    """
    Conform Salesforce API response logs and write them to ``salesforce_api_logs``.
    """

    logs_df = conform_api_logs(
        df=df,
        api_entity=api_entity,
        target_table=target_table,
        job_name=job_name,
        partition_date=partition_date,
    )
    # Specific for Salesforce, since we have some columns only on salesforce

    partition_filter = {
        "partition_date": partition_date,
        "entity_type": api_entity,
        "job_name": job_name,
    }
    partition_cols = list(partition_filter.keys())
    filter = build_partition_filter(partition_filter)

    table_location = LOGS_TABLE_LOCATION.format(bucket=bucket)
    validate_and_write(
        spark=spark,
        df=logs_df,
        target_table=LOGS_TARGET_TABLE,
        partition_filter=filter,
        partition_cols=partition_cols,
        overwrite_schema=False,
        table_location=table_location,
        sync_hive=True,
        sync_secondary_catalog=True,
    )
