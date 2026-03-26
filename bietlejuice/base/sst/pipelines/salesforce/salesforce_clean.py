from datetime import datetime

from pyspark.sql import functions as F

from bietlejuice.base.sst.core.utils.common import (
    normalize_df_columns,
    validate_and_write,
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


@logger(exclude_return=True)
def salesforce_clean_pipeline(spark, cfg):

    source_table = f"{cfg.source_schema}.{cfg.target_table}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    if partition_has_data(spark, target_table, cfg.partition_date, cfg.partition_hour):
        logger.info(
            f"m=salesforce_clean_pipeline, msg=Partition {cfg.partition_date} {cfg.partition_hour} already exists in {target_table}"
        )
        logger.info("m=salesforce_clean_pipeline, msg=Skipping pipeline")
        return

    # spark, table_name, partition_date, partition_hour, fail=True
    sensor_partition_hour(
        spark=spark,
        table_name=source_table,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        fail=False,
    )

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
    snapshot = (
        in_memory_cdc_udpate(all_events_df)
        .where(F.col("new_record") == F.lit(True))
        .drop("new_record")
        .withColumn("ts_load", F.lit(ts_load))
        .withColumn("partition_date", F.lit(cfg.partition_date))
        .withColumn("partition_hour", F.lit(cfg.partition_hour))
    )

    basic_quality_checks(
        snapshot,
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
    partition_filter = f"partition_date='{cfg.partition_date}' AND partition_hour='{cfg.partition_hour}'"
    validate_and_write(
        spark,
        snapshot,
        target_table=target_table,  # "datalake_salesforce_test_cdc.events_case_clean",
        partition_filter=partition_filter,
        partition_cols=["partition_date", "partition_hour"],
        overwrite_schema=True,
    )

    new_cols = sensor_for_new_columns(spark=spark, df=snapshot, table=target_table)
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
    for _metric, grain in _metric_grain.items():
        logger.info(f"m=salesforce_clean_pipeline, msg=Saving {_metric} metric")
        save_volume_metric(
            spark=spark,
            df=snapshot,
            grain=grain,
            metric_name=_metric,
            table_name=target_table,
            env=cfg.env,
            layer="clean",
            partition_cols=["partition_date", "partition_hour"],
        )

    logger.info("m=salesforce_clean_pipeline, msg=Saving table_metadata metric")
    save_table_metadata_metric(
        spark=spark,
        df=snapshot,
        table_name=target_table,
        new_cols=new_cols,
        env=cfg.env,
        layer="clean",
        partition_values={
            "partition_date": cfg.partition_date,
            "partition_hour": cfg.partition_hour,
        },
        partition_cols=["partition_date", "partition_hour"],
    )
    logger.info("m=salesforce_clean_pipeline, msg=Pipeline completed")
