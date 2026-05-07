import re
from datetime import datetime

from pyspark.sql import functions as F

from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    default_args,
    normalize_df_columns,
    validate_and_write,
    retrieve_spark_session,
)
from bietlejuice.base.sst.core.quality.checks import basic_quality_checks
from bietlejuice.base.sst.core.observability.sensors import (
    partition_has_data,
    sensor_for_new_columns,
    sensor_partition_hour,
)

from bietlejuice.base.sst.core.observability.metrics import (
    save_table_metadata_metric,
    save_volume_metric,
)
from bietlejuice.base.sst.domains.salesforce.clean.check import check_missing_create
from bietlejuice.base.sst.domains.salesforce.clean.transform import (
    in_memory_cdc_udpate,
    search_for_latest_record,
)


from quintoandar_logger import QuintoAndarLogger


logger = QuintoAndarLogger("sst.pipelines.salesforce_clean")


@default_args(
    optional_args=[
        dict(
            name="dag_name",
            flags=["--dag_name", "--dag-name"],
            type=str,
            required=False,
            default="",
            help="DAG name (optional).",
        ),
        dict(
            name="partition_date",
            flags=["--partition_date", "--partition-date"],
            type=str,
            required=True,
            help="Partition date (YYYY-MM-DD).",
        ),
        dict(
            name="partition_hour",
            flags=["--partition_hour", "--partition-hour"],
            type=str,
            required=True,
            help="Partition hour (HH).",
        ),
        dict(
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
        ),
        dict(
            name="source_schema",
            flags=["--source_schema", "--source-schema"],
            type=str,
            required=True,
            help="Source schema (salesforce_cdc_raw).",
        ),
        dict(
            name="sync_hive",
            flags=["--sync_hive", "--sync-hive"],
            type=lambda x: x.lower() == "true",
            required=False,
            default=False,
            help="When true, calls sync_trino_table_schema from sync_metadata after writing to register or update the table in Trino's Delta catalog. Requires table_location to be set.",
        ),
    ]
)
@logger(exclude_return=True)
def salesforce_clean_pipeline(cfg):

    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=salesforce_clean_pipeline, msg=Starting events for {job_name=}")
    logger.info(f"m=salesforce_clean_pipeline, msg=Config: {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)
    logger.info("m=salesforce_clean_pipeline, msg=Spark session retrieved")
    source_table = f"{cfg.source_schema}.{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    if partition_has_data(spark, target_table, cfg.partition_date, cfg.partition_hour):
        logger.info(
            f"m=salesforce_clean_pipeline, msg=Partition {cfg.partition_date} {cfg.partition_hour} already exists in {target_table}"
        )
        logger.info("m=salesforce_clean_pipeline, msg=Skipping pipeline")
        return

    # spark, table_name, partition_date, partition_hour, fail=True
    # Will skip if no data or upstream table doesn't exist (E.g new events)
    has_data = sensor_partition_hour(
        spark=spark,
        table_name=source_table,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        fail=False,
    )
    if not has_data:
        logger.info(
            f"m=salesforce_clean_pipeline, msg=No data found for {source_table} {cfg.partition_date} {cfg.partition_hour}"
        )
        logger.info("m=salesforce_clean_pipeline, msg=Exiting pipeline")
        return

    event_df = (
        spark.read.table(source_table)
        .where(F.col("partition_date") == cfg.partition_date)
        .where(F.col("partition_hour") == cfg.partition_hour)
    )

    cols = [
        col
        for col in event_df.columns
        if col
        not in [
            "source_file",
            "ts_load",
            "ChangeEventHeader",
            "changed_field",
            "partition_date",
            "partition_hour",
        ]
    ]
    event_df = event_df.select(cols).withColumn(
        "committed_at",
        F.date_format(F.to_timestamp(F.col("commit_ts") / 1000), "yyyy-MM-dd HH:mm:ss"),
    )

    norm_events_df = normalize_df_columns(event_df)
    all_events_df = search_for_latest_record(spark, norm_events_df, target_table)

    passed = check_missing_create(all_events_df, fail=False)
    if not passed:
        # Write only valid event, remove after dev
        invalid_ids = all_events_df.where(
            (~F.col("new_record"))
            & (F.col("event_type") == "HISTORICAL")
            & (F.col("commit_number").isNull())
        ).select("id_record")
        all_events_df = all_events_df.join(
            F.broadcast(invalid_ids), "id_record", "leftanti"
        )

    ts_load = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    cdc_conformed_df = (
        in_memory_cdc_udpate(all_events_df)
        .where(F.col("new_record") == F.lit(True))
        .drop("new_record")
        .withColumn("ts_load", F.lit(ts_load))
        .withColumn("partition_date", F.lit(cfg.partition_date))
        .withColumn("partition_hour", F.lit(cfg.partition_hour))
    )

    basic_quality_checks(
        cdc_conformed_df,
        required_cols=[
            "id_record",
            "transaction_key",
            "sequence_number",
            "commit_number",
        ],
        unique_grain=["id_record", "transaction_key", "sequence_number"],
        fail=True,
    )

    logger.info("m=salesforce_clean_pipeline, msg=Quality checks passed")
    logger.info(
        f"m=salesforce_clean_pipeline, msg=Metadata retrieved: {cfg.target_schema=}"
    )

    new_cols = sensor_for_new_columns(
        spark=spark, df=cdc_conformed_df, table=target_table
    )
    partition_filter = build_partition_filter(
        {
            "partition_date": cfg.partition_date,
            "partition_hour": cfg.partition_hour,
        }
    )
    table_location = f"s3a://{cfg.bucket}/clean/salesforce/{cfg.target_table}"
    validate_and_write(
        spark,
        cdc_conformed_df,
        target_table=target_table,
        partition_filter=partition_filter,
        partition_cols=["partition_date", "partition_hour"],
        overwrite_schema=True,
        table_location=table_location,
        sync_hive=cfg.sync_hive,
    )

    if new_cols:
        logger.info(
            f"m=salesforce_clean_pipeline, msg=New columns detected: {new_cols}"
        )
    else:
        logger.info("m=salesforce_clean_pipeline, msg=No new columns detected")
        new_cols = []

    _metric_grain = {
        "events_volume": ["partition_date", "partition_hour"],
        "events_type_volume": ["partition_date", "partition_hour", "event_type"],
    }
    sanitized_target_table = re.sub(r"\W", "_", target_table).strip("_").lower()
    for _metric, grain in _metric_grain.items():
        logger.info(f"m=salesforce_clean_pipeline, msg=Saving {_metric} metric")
        save_volume_metric(
            spark=spark,
            df=cdc_conformed_df,
            grain=grain,
            metric_name=_metric,
            table_name=target_table,
            env=cfg.env,
            layer="clean",
            partition_cols=["partition_date", "partition_hour"],
            table_location=f"s3a://{cfg.bucket}/sst_metrics/{_metric}",
        )

    logger.info("m=salesforce_clean_pipeline, msg=Saving table_metadata metric")
    save_table_metadata_metric(
        spark=spark,
        df=cdc_conformed_df,
        table_name=target_table,
        new_cols=new_cols,
        env=cfg.env,
        layer="clean",
        table_location=f"s3a://{cfg.bucket}/sst_metrics/{sanitized_target_table}_metadata",
        partition_values={
            "partition_date": cfg.partition_date,
            "partition_hour": cfg.partition_hour,
        },
        partition_cols=["partition_date", "partition_hour"],
    )
    logger.info("m=salesforce_clean_pipeline, msg=Pipeline completed")


if __name__ == "__main__":
    salesforce_clean_pipeline()
