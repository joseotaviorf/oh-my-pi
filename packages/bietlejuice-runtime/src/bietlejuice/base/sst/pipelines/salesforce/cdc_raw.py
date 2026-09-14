from datetime import datetime

import pyspark.sql.functions as F
from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.appflow.marker import (
    ACTIVE_STATUS,
    appflow_has_completed_hour,
    extract_flow_name,
    format_metric_payload,
    get_latest_appflow_run,
    save_appflow_metrics,
)
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
from bietlejuice.base.sst.core.utils.time import standard_now
from bietlejuice.base.sst.core.utils.transforms import apply_schema_remaps
from bietlejuice.base.sst.domains.salesforce.raw.io import read_sf_cdc_json
from bietlejuice.base.sst.domains.salesforce.raw.transform import (
    sf_cdc_mandatory_fields,
)
from bietlejuice.base.sst.pipelines.salesforce.recovery_flow import events_case_recovery

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
        dict(
            name="api_entity",
            flags=["--api_entity", "--api-entity"],
            type=str,
            required=False,
            default=None,
            help="Salesforce SObject API name (e.g. Case).",
        ),
        dict(
            name="salesforce_endpoint",
            flags=["--salesforce_endpoint", "--salesforce-endpoint"],
            type=str,
            required=False,
            default=None,
            help="Salesforce API base endpoint URL (e.g. https://quintoandar.my.salesforce.com).",
        ),
        dict(
            name="appflow_assume_role_arn",
            flags=["--appflow_assume_role_arn", "--appflow-assume-role-arn"],
            type=str,
            required=False,
            default=None,
            help=(
                "IAM role ARN to assume for the AppFlow client only. Required on EMR "
                "prod, where the cluster runs in the data account and the flows live "
                "in the prod account. Leave empty on Databricks prod and on forno."
            ),
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

    flow_name = extract_flow_name(cfg.event_path)
    try:
        appflow_status = get_latest_appflow_run(
            flow_name, assume_role_arn=cfg.appflow_assume_role_arn
        )
    except Exception as exc:
        logger.warning(
            f"m=salesforce_raw_pipeline, msg=describe_flow failed for {flow_name}: "
            f"{exc}. Treating AppFlow as unavailable for recovery decision."
        )
        appflow_status = {
            "flow_status": "",
            "last_execution_status": None,
            "last_execution_timestamp": None,
            "last_execution_message": str(exc),
            "request_time": standard_now(),
        }

    appflow_completed_hour = appflow_has_completed_hour(
        appflow_status, cfg.partition_date, cfg.partition_hour
    )
    logger.info(f"m=salesforce_raw_pipeline, msg=AppFlow status: {appflow_status}")
    logger.info(
        f"m=salesforce_raw_pipeline, msg=AppFlow completed partition hour: "
        f"{appflow_completed_hour}"
    )

    # Recovery only when AppFlow is down and the last execution timestamp is before the expected end of the partition hour.
    should_run_recovery = (
        appflow_status["flow_status"] != ACTIVE_STATUS and not appflow_completed_hour
    )

    metric_payload = format_metric_payload(
        flow_name=flow_name,
        appflow_payload=appflow_status,
        completed_hour=appflow_completed_hour,
        run_recovery=should_run_recovery,
    )

    logger.info(
        f"m=salesforce_raw_pipeline, msg=Saving Appflow Metrics {metric_payload}"
    )

    save_appflow_metrics(
        spark=spark,
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        job_name=job_name,
        payload=metric_payload,
        bucket=cfg.bucket,
        sync_hive=True,
    )

    if should_run_recovery:
        last_execution_ts = appflow_status.get("last_execution_timestamp")
        last_execution_ts_str = (
            last_execution_ts.isoformat() if last_execution_ts is not None else None
        )
        logger.warning(
            f"m=salesforce_raw_pipeline, msg=AppFlow {flow_name} "
            f"flow_status={appflow_status.get('flow_status')!r} "
            f"last_execution_status={appflow_status.get('last_execution_status')!r} "
            f"last_execution_timestamp={last_execution_ts_str} "
            f"last_execution_message={appflow_status.get('last_execution_message')!r}. "
            f"Running recovery for {target_table}."
        )
        events_case_recovery(
            spark=spark,
            api_entity=cfg.api_entity,
            salesforce_endpoint=cfg.salesforce_endpoint,
            dag_name=cfg.dag_name,
            job_name=cfg.job_name,
            target_schema=cfg.target_schema,
            target_table=cfg.target_table,
            env=cfg.env,
            partition_date=cfg.partition_date,
            partition_hour=cfg.partition_hour,
        )
        return None

    if not has_data:
        logger.info(f"m=salesforce_raw_pipeline, msg=No data found for {s3_file_path}")
        logger.info("m=salesforce_raw_pipeline, msg=Exiting pipeline")
        return

    logger.info(f"m=salesforce_raw_pipeline, msg=Data found for {s3_file_path}")
    logger.info(
        f"m=salesforce_raw_pipeline, msg=Reading Salesforce CDC JSON from {s3_file_path}"
    )

    raw_df = read_sf_cdc_json(spark, s3_file_path)
    raw_df = (
        sf_cdc_mandatory_fields(raw_df)
        .drop_duplicates(["id_record", "transaction_key", "sequence_number"])
        .cache()
    )

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
    )

    raw_final_remapped = apply_schema_remaps(
        spark=spark,
        df=raw_final,
        target_table=target_table,
        skip_new_columns=False,
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
        sync_secondary_catalog=True,
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
    raw_df.unpersist()
    logger.info("m=salesforce_raw_pipeline, msg=Pipeline completed")


if __name__ == "__main__":
    salesforce_raw_pipeline()
