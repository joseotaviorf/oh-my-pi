from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import save_volume_metric
from bietlejuice.base.sst.core.observability.sensors import (
    partition_has_data,
    sensor_s3_file_exists,
)
from bietlejuice.base.sst.core.quality.checks import basic_quality_checks
from bietlejuice.base.sst.core.utils.common import (
    build_partition_filter,
    default_args,
    retrieve_spark_session,
    validate_and_write,
)
from bietlejuice.base.sst.core.utils.transforms import apply_schema_remaps
from bietlejuice.base.sst.domains.salesforce.raw.io import read_sf_cdc_json
from bietlejuice.base.sst.domains.salesforce.raw.transform import (
    sf_cdc_mandatory_fields,
)

logger = QuintoAndarLogger("sst.pipelines.salesforce_raw")


@logger(exclude_return=True)
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
            name="bucket",
            flags=["--bucket"],
            type=str,
            required=True,
            help="S3 Bucket Name.",
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
            name="event_path",
            flags=["--event_path", "--event-path"],
            type=str,
            required=True,
            help="Path to event in S3 bucket.",
        ),
    ]
)
def salesforce_raw_pipeline(cfg):
    """
    Since most Salesforce pipelines should follow a pattern, this serves as a template
    It can be changed as needed, but let's try to keep it working as needed here
    """
    # Argument breaking logic
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=run, CFG: {cfg}")
    logger.info(f"m=run, msg=Starting events for {job_name=}")
    logger.info(f"m=run, msg=Config: {cfg=}")
    spark = retrieve_spark_session(job_name=job_name)

    partition_path = "/".join(cfg.partition_date.split("-") + [cfg.partition_hour])
    file_key = f"{cfg.event_path}/{partition_path}"
    s3_file_path = f"s3://{cfg.bucket}/{file_key}"
    target_table = f"{cfg.target_schema}.{cfg.target_table}"

    # Due to how QuintoAndar executeCluster works, we need to check if the partition already exists in the target table
    # If it does, we should skip the job to reduce reprocessing.
    if partition_has_data(spark, target_table, cfg.partition_date, cfg.partition_hour):
        logger.info(
            f"m=salesforce_raw_pipeline, msg=Partition {cfg.partition_date} {cfg.partition_hour} already exists in {target_table}"
        )
        logger.info("m=salesforce_raw_pipeline, msg=Skipping pipeline")
        return

    # We're not sure we'll be using sensors now.
    # We'll be passing through if we don't have data in S3 (bad practice)
    # We'll keep an eye on pattern for this pipeline and adjust if needed

    has_data = sensor_s3_file_exists(cfg.bucket, file_key, fail=False)

    if not has_data:
        logger.info(f"m=salesforce_raw_pipeline, msg=No data found for {s3_file_path}")
        logger.info("m=salesforce_raw_pipeline, msg=Exiting pipeline")
        return

    logger.info(f"m=salesforce_raw_pipeline, msg=Data found for {s3_file_path}")
    logger.info(
        f"m=salesforce_raw_pipeline, msg=Reading Salesforce CDC JSON from {s3_file_path}"
    )

    raw_df = read_sf_cdc_json(spark, s3_file_path)
    raw_df = sf_cdc_mandatory_fields(raw_df).drop_duplicates()

    # Quality checks
    # TODO: Transform this into a metric as well
    basic_quality_checks(
        raw_df,
        required_cols=[
            "id_record",
            "transaction_key",
            "sequence_number",
            "commit_number",
        ],
        unique_grain=["id_record", "transaction_key", "sequence_number"],
        fail=True,
    )

    raw_final = (
        raw_df.withColumn("source_file", F.col("_metadata.file_path"))
        .withColumn("ts_load", F.lit(datetime.now().strftime("%Y-%m-%d %H:%M:%S")))
        .withColumn("partition_date", F.lit(cfg.partition_date))
        .withColumn("partition_hour", F.lit(cfg.partition_hour))
        .persist()
    )

    raw_final_remapped = apply_schema_remaps(
        spark=spark, df=raw_final, target_table=target_table, accept_new_cols=True
    )

    logger.info("m=salesforce_raw_pipeline, msg=Quality checks passed")
    logger.info(
        f"m=salesforce_raw_pipeline, msg=Metadata retrieved: {cfg.target_schema=}"
    )

    partition_filter = build_partition_filter(
        {
            "partition_date": cfg.partition_date,
            "partition_hour": cfg.partition_hour,
        }
    )
    partition_cols = ["partition_date", "partition_hour"]
    logger.info(f"m=salesforce_raw_pipeline, msg=Partition columns: {partition_cols}")

    table_location = f"s3a://{cfg.bucket}/raw/salesforce/{cfg.target_table}"
    validate_and_write(
        spark=spark,
        df=raw_final_remapped,
        target_table=target_table,
        partition_filter=partition_filter,
        partition_cols=partition_cols,
        overwrite_schema=True,
        table_location=table_location,
    )

    _metric_grain = {
        "events_volume": ["partition_date", "partition_hour"],
        "events_type_volume": ["partition_date", "partition_hour", "event_type"],
    }
    for _metric, grain in _metric_grain.items():
        logger.info(f"m=salesforce_raw_pipeline, msg=Saving {_metric} metric")
        save_volume_metric(
            spark=spark,
            df=raw_final_remapped,
            grain=grain,
            metric_name=_metric,
            table_name=target_table,
            env=cfg.env,
            layer="raw",
            partition_cols=["partition_date", "partition_hour"],
            table_location=f"s3a://{cfg.bucket}/sst_metrics/{_metric}",
        )
    raw_final.unpersist()
    logger.info("m=salesforce_raw_pipeline, msg=Pipeline completed")


if __name__ == "__main__":
    salesforce_raw_pipeline()
