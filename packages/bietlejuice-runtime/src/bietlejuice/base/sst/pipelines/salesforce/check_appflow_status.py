from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.appflow.marker import (
    ACTIVE_STATUS,
    DEFAULT_MARKER_PREFIX,
    DEFAULT_REGION,
    build_marker_key,
    describe_flow_status,
    extract_flow_name,
    save_status_marker_as_table,
    write_status_marker,
)
from bietlejuice.base.sst.core.utils.common import default_args, retrieve_spark_session

logger = QuintoAndarLogger("sst.pipelines.salesforce_check_appflow_status")


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
            help="S3 Bucket Name where the status marker will be written.",
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
            help="Path to event in S3 bucket (last segment is the AppFlow name).",
        ),
        dict(
            name="region_name",
            flags=["--region_name", "--region-name"],
            type=str,
            required=False,
            default=DEFAULT_REGION,
            help="AWS region for the AppFlow client.",
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
        dict(
            name="marker_prefix",
            flags=["--marker_prefix", "--marker-prefix"],
            type=str,
            required=False,
            default=DEFAULT_MARKER_PREFIX,
            help="S3 key prefix for the AppFlow status marker.",
        ),
        dict(
            name="sync_hive",
            flags=["--sync_hive", "--sync-hive"],
            type=lambda x: x.lower() == "true",
            required=False,
            default=True,
            help="Sync the appflow_status Delta table to the Hive/Trino metastore after writing (default: True).",
        ),
    ]
)
def salesforce_check_appflow_status_pipeline(cfg):
    """Check AppFlow flow status and persist the result as an S3 marker file.

    Always exits successfully so the downstream Airflow branch operator can
    read the marker and route accordingly: Active continues the pipeline,
    any other status or error causes the branch operator to raise and fail.
    """
    job_name = f"{cfg.dag_name}.{cfg.job_name}"
    logger.info(f"m=run, msg=Starting AppFlow status check for {job_name=}")
    logger.info(f"m=run, msg=Config: {cfg=}")

    spark = retrieve_spark_session(job_name=job_name)

    flow_name = extract_flow_name(cfg.event_path)
    marker_key = build_marker_key(
        partition_date=cfg.partition_date,
        partition_hour=cfg.partition_hour,
        target_table=cfg.target_table,
        marker_prefix=cfg.marker_prefix,
    )

    payload = {
        "flow_name": flow_name,
        "event_path": cfg.event_path,
        "target_table": cfg.target_table,
        "partition_date": cfg.partition_date,
        "partition_hour": cfg.partition_hour,
    }

    try:
        status = describe_flow_status(
            flow_name,
            region_name=cfg.region_name,
            assume_role_arn=cfg.appflow_assume_role_arn,
        )
        payload["status"] = status
        payload["error"] = None
        if status == ACTIVE_STATUS:
            logger.info(
                f"m=run, msg=AppFlow {flow_name} is Active for {cfg.target_table}."
            )
        else:
            logger.warning(
                f"m=run, msg=AppFlow {flow_name} status={status!r}, "
                f"branch operator will raise for {cfg.target_table}."
            )
    except Exception as exc:
        logger.error(
            f"m=run, msg=Failed to describe AppFlow flow {flow_name}: {exc}. "
            f"Marker will report the error so the Airflow task can skip and alert."
        )
        payload["status"] = ""
        payload["error"] = f"DescribeFlowError: {exc}"

    try:
        write_status_marker(bucket=cfg.bucket, key=marker_key, payload=payload)
        logger.info(
            f"m=run, msg=Wrote AppFlow status marker to s3://{cfg.bucket}/{marker_key}"
        )
    except Exception as exc:
        logger.error(
            f"m=run, msg=Failed to write AppFlow status marker to S3: {exc}. "
            f"key={marker_key}"
        )
        raise

    try:
        save_status_marker_as_table(spark=spark, payload=payload, bucket=cfg.bucket)
        logger.info(
            "m=run, msg=Wrote AppFlow status to Delta table "
            "datalake_sst_metrics.appflow_status "
        )
    except Exception as exc:
        logger.error(
            f"m=run, msg=Failed to write AppFlow status to Delta table: {exc}. "
        )
        raise


if __name__ == "__main__":
    salesforce_check_appflow_status_pipeline()
