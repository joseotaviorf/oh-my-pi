from quintoandar_logger import QuintoAndarLogger

from bietlejuice.base.sst.core.observability.metrics import save_latency_metric
from bietlejuice.base.sst.core.observability.sensors import (
    sensor_table_exists,
)
from bietlejuice.base.sst.core.utils.common import (
    default_args,
    retrieve_spark_session,
)

# TODO: Add core_models, dw and other layers when available if needed

LAYERS = ["raw", "clean"]
logger = QuintoAndarLogger("sst.pipelines.metrics.latency")


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
    ]
)
def run(cfg):
    job_name = f"{cfg.dag_name}.{cfg.job_name}" if cfg.dag_name != "" else cfg.job_name
    spark = retrieve_spark_session(job_name=job_name)
    source_layer = "salesforce"
    metric_name = "pipeline_events_latency"
    for layer in LAYERS:
        target_table = f"datalake_salesforce_{layer}.{cfg.target_table}"
        logger.info(
            f"m=run, msg=Saving latency metric for {layer=} at {cfg.target_table}"
        )
        # This is to avoid failing the job for new events
        if not sensor_table_exists(spark, target_table, fail=False):
            logger.info(f"m=run, msg=Table {target_table} does not exist")
            logger.info(f"m=run, msg=Skipping latency metrics for {layer=}")
            continue

        save_latency_metric(
            spark=spark,
            bucket=cfg.bucket,
            metric_name=metric_name,
            target_table=target_table,
            metric_table=metric_name,
            partition_date=cfg.partition_date,
            partition_hour=cfg.partition_hour,
            source_layer=source_layer,
            target_layer=layer,
            env=cfg.env,
        )
        logger.info(
            f"m=run, msg=Latency metric saved for {layer=} at {cfg.target_table}"
        )
    logger.info("m=run, msg=Pipeline completed")


if __name__ == "__main__":
    run()
